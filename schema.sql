-- Quản lý trạm sạc xe điện và bãi đỗ thông minh  |  Nhóm M3B
-- PostgreSQL 14+
-- Đặt tên: hậu tố theo ISO/IEC 11179
--   _identifier  _code  _text  _count  _datetime  _time  _kw  _kwh  _value
-- Múi giờ dùng cho khung giá: Asia/Ho_Chi_Minh (xem fn_select_tariff)

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. user_account

CREATE TABLE user_account (
    account_identifier   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name_text       VARCHAR(100) NOT NULL,
    contact_phone_number VARCHAR(15)  NOT NULL,
    email_address        VARCHAR(255) NOT NULL,
    password_hash_text   VARCHAR(255) NOT NULL,
    role_code            VARCHAR(20)  NOT NULL DEFAULT 'CUSTOMER',
    created_datetime     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_datetime     TIMESTAMPTZ,
    purged_datetime      TIMESTAMPTZ,          -- đã xóa vĩnh viễn thông tin cá nhân
    -- mật khẩu gốc để quản trị viên xem (lựa chọn của nhóm để demo; đăng nhập vẫn kiểm bản băm)
    password_plain_text  VARCHAR(255),
    CONSTRAINT ck_user_account_role
        CHECK (role_code IN ('CUSTOMER', 'MANAGER', 'ADMIN')),
    CONSTRAINT ck_user_account_phone
        CHECK (contact_phone_number ~ '^\+?[0-9]{8,14}$'),
    CONSTRAINT ck_user_account_name CHECK (btrim(full_name_text) <> ''),
    CONSTRAINT ck_user_account_email
        CHECK (email_address ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

-- Chỉ mục duy nhất từng phần: tài khoản đã xóa mềm sẽ nhả số điện thoại/email.
CREATE UNIQUE INDEX ux_user_account_phone
    ON user_account (contact_phone_number) WHERE deleted_datetime IS NULL;
CREATE UNIQUE INDEX ux_user_account_email
    ON user_account (lower(email_address)) WHERE deleted_datetime IS NULL;


-- 2. vehicle

CREATE TABLE vehicle (
    vehicle_identifier   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    account_identifier   UUID          NOT NULL
        REFERENCES user_account (account_identifier) ON DELETE CASCADE,
    license_plate_text   VARCHAR(20)   NOT NULL,
    battery_capacity_kwh DECIMAL(10,2) NOT NULL,
    deleted_datetime     TIMESTAMPTZ,
    CONSTRAINT ck_vehicle_battery
        CHECK (battery_capacity_kwh > 0 AND battery_capacity_kwh <> 'NaN')
);

CREATE UNIQUE INDEX ux_vehicle_license_plate
    ON vehicle (license_plate_text) WHERE deleted_datetime IS NULL;
CREATE INDEX ix_vehicle_account ON vehicle (account_identifier);


-- 3. parking_facility

CREATE TABLE parking_facility (
    facility_identifier  UUID                  PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_name_text   VARCHAR(100)          NOT NULL,
    geographic_location  GEOMETRY(Point, 4326) NOT NULL,
    address_text         VARCHAR(255)          NOT NULL,
    total_capacity_count INT                   NOT NULL,
    CONSTRAINT ck_parking_facility_capacity CHECK (total_capacity_count > 0)
);

CREATE INDEX ix_parking_facility_location
    ON parking_facility USING gist (geographic_location);


-- 4. facility_manager  (quan hệ N:M giữa tài khoản MANAGER và bãi đỗ)

CREATE TABLE facility_manager (
    manager_identifier  UUID NOT NULL
        REFERENCES user_account (account_identifier) ON DELETE CASCADE,
    facility_identifier UUID NOT NULL
        REFERENCES parking_facility (facility_identifier) ON DELETE CASCADE,
    PRIMARY KEY (manager_identifier, facility_identifier)
);

CREATE INDEX ix_facility_manager_facility ON facility_manager (facility_identifier);


-- 5. parking_space

CREATE TABLE parking_space (
    space_identifier         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    facility_identifier      UUID        NOT NULL
        REFERENCES parking_facility (facility_identifier) ON DELETE CASCADE,
    space_code               VARCHAR(10) NOT NULL,
    availability_status_code VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',
    deleted_datetime         TIMESTAMPTZ,
    CONSTRAINT ck_parking_space_status
        CHECK (availability_status_code IN
               ('AVAILABLE', 'RESERVED', 'OCCUPIED', 'OUTOFSERVICE'))
);

CREATE UNIQUE INDEX ux_parking_space_code
    ON parking_space (facility_identifier, space_code)
    WHERE deleted_datetime IS NULL;
CREATE INDEX ix_parking_space_facility ON parking_space (facility_identifier);


-- 6. charging_equipment  (mở rộng 1:1 của parking_space)

CREATE TABLE charging_equipment (
    equipment_identifier  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    space_identifier      UUID          NOT NULL
        REFERENCES parking_space (space_identifier) ON DELETE CASCADE,
    evse_identifier       VARCHAR(50)   NOT NULL,
    connector_type_code   VARCHAR(50)   NOT NULL,
    max_power_kw          DECIMAL(10,2) NOT NULL,
    equipment_status_code VARCHAR(20)   NOT NULL DEFAULT 'READY',
    deleted_datetime      TIMESTAMPTZ,
    CONSTRAINT ck_charging_equipment_connector
        CHECK (connector_type_code IN ('FAST_DC', 'STANDARD_AC')),
    CONSTRAINT ck_charging_equipment_power
        CHECK (max_power_kw > 0 AND max_power_kw <> 'NaN'),
    CONSTRAINT ck_charging_equipment_status
        CHECK (equipment_status_code IN
               ('READY', 'CHARGING', 'FAULT', 'MAINTENANCE'))
);

CREATE UNIQUE INDEX ux_charging_equipment_space
    ON charging_equipment (space_identifier) WHERE deleted_datetime IS NULL;
CREATE UNIQUE INDEX ux_charging_equipment_evse
    ON charging_equipment (evse_identifier) WHERE deleted_datetime IS NULL;
CREATE INDEX ix_charging_equipment_space ON charging_equipment (space_identifier);


-- 7. Biểu giá: time_band, time_band_window, power_tier, tariff_rate, parking_rate
-- Lịch khung giờ khai báo MỘT lần cho cả hệ thống (time_band_window), dải công
-- suất khai báo một lần cho mỗi loại cổng (power_tier); bảng giá chỉ lưu giá theo
-- (dải công suất, khung). Khung không vắt qua nửa đêm: 22:00-05:00 lưu thành
-- 22:00-24:00 và 00:00-05:00. Dải công suất là nửa mở [min, max).
-- Giá có lịch sử: mỗi dòng giá là một PHIÊN BẢN có hiệu lực
-- [effective_from, effective_to); đổi giá = đóng phiên bản cũ và thêm phiên bản
-- mới (fn_change_tariff), không sửa đè. Phiên sạc trỏ tới phiên bản đã áp dụng.

CREATE TABLE time_band (
    time_band_code  VARCHAR(20)  PRIMARY KEY,
    time_band_name  VARCHAR(50)  NOT NULL,
    CONSTRAINT ck_time_band_code
        CHECK (time_band_code IN ('PEAK', 'STANDARD', 'OFF_PEAK'))
);

CREATE TABLE time_band_window (
    start_time      TIME         PRIMARY KEY,
    end_time        TIME         NOT NULL,
    time_band_code  VARCHAR(20)  NOT NULL
        REFERENCES time_band (time_band_code) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_time_band_window_time CHECK (end_time > start_time),
    -- hai khoảng giờ không được chồng nhau
    CONSTRAINT ex_time_band_window_no_overlap EXCLUDE USING gist (
        int4range(extract(epoch FROM start_time)::INT,
                  extract(epoch FROM end_time)::INT) WITH &&
    )
);

CREATE INDEX ix_time_band_window_band ON time_band_window (time_band_code);

CREATE TABLE power_tier (
    connector_type_code  VARCHAR(50)   NOT NULL,
    min_power_kw         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    max_power_kw         DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (connector_type_code, min_power_kw),
    CONSTRAINT ck_power_tier_connector
        CHECK (connector_type_code IN ('FAST_DC', 'STANDARD_AC')),
    CONSTRAINT ck_power_tier_power
        CHECK (min_power_kw >= 0 AND max_power_kw > min_power_kw),
    -- các dải của cùng một loại cổng không chồng nhau
    CONSTRAINT ex_power_tier_no_overlap EXCLUDE USING gist (
        connector_type_code WITH =,
        numrange(min_power_kw, max_power_kw) WITH &&
    )
);

CREATE TABLE tariff_rate (
    rate_identifier             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    connector_type_code         VARCHAR(50)   NOT NULL,
    min_power_kw                DECIMAL(10,2) NOT NULL,
    time_band_code              VARCHAR(20)   NOT NULL
        REFERENCES time_band (time_band_code) ON DELETE RESTRICT ON UPDATE CASCADE,
    price_per_kwh_value         DECIMAL(10,2) NOT NULL,
    overtime_fee_per_hour_value DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    effective_from              TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to                TIMESTAMPTZ,
    CONSTRAINT fk_tariff_rate_power_tier
        FOREIGN KEY (connector_type_code, min_power_kw)
        REFERENCES power_tier (connector_type_code, min_power_kw)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_tariff_rate_price
        CHECK (price_per_kwh_value >= 0 AND price_per_kwh_value <> 'NaN'),
    CONSTRAINT ck_tariff_rate_overtime
        CHECK (overtime_fee_per_hour_value >= 0 AND overtime_fee_per_hour_value <> 'NaN'),
    CONSTRAINT ck_tariff_rate_period
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    -- khóa ứng viên nghiệp vụ: một phiên bản giá bắt đầu tại một thời điểm
    CONSTRAINT uq_tariff_rate_key
        UNIQUE (connector_type_code, min_power_kw, time_band_code, effective_from),
    -- cùng (dải công suất, khung) thì các phiên bản không chồng thời gian hiệu lực
    CONSTRAINT ex_tariff_rate_no_overlap EXCLUDE USING gist (
        connector_type_code WITH =,
        min_power_kw WITH =,
        time_band_code WITH =,
        tstzrange(effective_from, effective_to) WITH &&
    )
);

CREATE INDEX ix_tariff_rate_band ON tariff_rate (time_band_code);

-- Giá đỗ xe theo giờ cho ô không có trụ sạc, cũng có lịch sử như tariff_rate
CREATE TABLE parking_rate (
    parking_rate_identifier  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    time_band_code           VARCHAR(20)   NOT NULL
        REFERENCES time_band (time_band_code) ON DELETE RESTRICT ON UPDATE CASCADE,
    price_per_hour_value     DECIMAL(10,2) NOT NULL,
    effective_from           TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to             TIMESTAMPTZ,
    CONSTRAINT ck_parking_rate_price
        CHECK (price_per_hour_value >= 0 AND price_per_hour_value <> 'NaN'),
    CONSTRAINT ck_parking_rate_period
        CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT uq_parking_rate_key UNIQUE (time_band_code, effective_from),
    CONSTRAINT ex_parking_rate_no_overlap EXCLUDE USING gist (
        time_band_code WITH =,
        tstzrange(effective_from, effective_to) WITH &&
    )
);


-- 8. reservation

CREATE TABLE reservation (
    reservation_identifier  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_identifier      UUID        NOT NULL
        REFERENCES vehicle (vehicle_identifier) ON DELETE RESTRICT,
    space_identifier        UUID        NOT NULL
        REFERENCES parking_space (space_identifier) ON DELETE RESTRICT,
    start_datetime          TIMESTAMPTZ NOT NULL,
    end_datetime            TIMESTAMPTZ NOT NULL,
    reservation_status_code VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_datetime        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_datetime        TIMESTAMPTZ,
    CONSTRAINT ck_reservation_time CHECK (end_datetime > start_datetime),
    CONSTRAINT ck_reservation_duration
        CHECK (end_datetime - start_datetime <= INTERVAL '24 hours'),
    CONSTRAINT ck_reservation_status
        CHECK (reservation_status_code IN
               ('PENDING', 'CONFIRMED', 'FULFILLED', 'CANCELLED', 'EXPIRED')),
    -- Chỉ lượt đặt còn đang giữ chỗ mới chặn lượt đặt khác;
    -- dòng CANCELLED / EXPIRED / đã xóa mềm sẽ trả lại khung giờ.
    CONSTRAINT ex_reservation_no_overlap EXCLUDE USING gist (
        space_identifier WITH =,
        tstzrange(start_datetime, end_datetime) WITH &&
    ) WHERE (reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
             AND deleted_datetime IS NULL),
    -- một xe không thể giữ hai ô trong các khung giờ chồng nhau
    CONSTRAINT ex_reservation_vehicle_no_overlap EXCLUDE USING gist (
        vehicle_identifier WITH =,
        tstzrange(start_datetime, end_datetime) WITH &&
    ) WHERE (reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
             AND deleted_datetime IS NULL)
);

CREATE INDEX ix_reservation_vehicle ON reservation (vehicle_identifier);
CREATE INDEX ix_reservation_space ON reservation (space_identifier);
CREATE INDEX ix_reservation_timeout
    ON reservation (start_datetime)
    WHERE reservation_status_code IN ('PENDING', 'CONFIRMED');


-- 9. service_session
-- Phiên sử dụng: phiên SẠC (equipment_identifier, giá tariff_rate) hoặc phiên
-- CHỈ ĐỖ XE ở ô không có trụ (space_identifier, giá parking_rate); đúng một trong
-- hai (ràng buộc loại trừ). Ô của phiên sạc suy ra qua thiết bị, không lưu lặp.
-- Tài khoản sở hữu được suy ra qua vehicle.account_identifier.

CREATE TABLE service_session (
    session_identifier     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_identifier UUID          UNIQUE
        REFERENCES reservation (reservation_identifier) ON DELETE SET NULL,
    vehicle_identifier     UUID          NOT NULL
        REFERENCES vehicle (vehicle_identifier) ON DELETE RESTRICT,
    equipment_identifier   UUID
        REFERENCES charging_equipment (equipment_identifier) ON DELETE RESTRICT,
    space_identifier       UUID
        REFERENCES parking_space (space_identifier) ON DELETE RESTRICT,
    start_datetime         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_datetime           TIMESTAMPTZ,
    fully_charged_datetime TIMESTAMPTZ,
    peak_charging_power_kw DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    consumed_energy_kwh    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    -- phiên bản giá chốt lúc bắt đầu (trigger tự ghi, không sửa được)
    rate_identifier        UUID
        REFERENCES tariff_rate (rate_identifier) ON DELETE RESTRICT,
    parking_rate_identifier UUID
        REFERENCES parking_rate (parking_rate_identifier) ON DELETE RESTRICT,
    -- % pin lúc cắm sạc do quản lý nhập; điện năng và giờ đầy pin tự tính (fn_session_estimate)
    start_battery_percent  DECIMAL(5,2),
    CONSTRAINT ck_service_session_kind
        CHECK ((equipment_identifier IS NOT NULL AND space_identifier IS NULL
                AND rate_identifier IS NOT NULL AND parking_rate_identifier IS NULL)
            OR (equipment_identifier IS NULL AND space_identifier IS NOT NULL
                AND rate_identifier IS NULL AND parking_rate_identifier IS NOT NULL
                AND consumed_energy_kwh = 0 AND peak_charging_power_kw = 0
                AND fully_charged_datetime IS NULL AND start_battery_percent IS NULL)),
    CONSTRAINT ck_service_session_battery_percent
        CHECK (start_battery_percent IS NULL
               OR (start_battery_percent >= 0 AND start_battery_percent < 100)),
    CONSTRAINT ck_service_session_end
        CHECK (end_datetime IS NULL OR end_datetime >= start_datetime),
    CONSTRAINT ck_service_session_full
        CHECK (fully_charged_datetime IS NULL
               OR (fully_charged_datetime >= start_datetime
                   AND (end_datetime IS NULL
                        OR fully_charged_datetime <= end_datetime))),
    CONSTRAINT ck_service_session_peak
        CHECK (peak_charging_power_kw >= 0 AND peak_charging_power_kw <> 'NaN'),
    CONSTRAINT ck_service_session_energy
        CHECK (consumed_energy_kwh >= 0 AND consumed_energy_kwh <> 'NaN')
);

-- mỗi trụ sạc chỉ có một phiên đang mở tại một thời điểm
CREATE UNIQUE INDEX ux_service_session_open_equipment
    ON service_session (equipment_identifier) WHERE end_datetime IS NULL;
-- mỗi xe cũng chỉ có một phiên đang mở
CREATE UNIQUE INDEX ux_service_session_open_vehicle
    ON service_session (vehicle_identifier) WHERE end_datetime IS NULL;
-- mỗi ô chỉ đỗ xe chỉ có một phiên đang mở
CREATE UNIQUE INDEX ux_service_session_open_space
    ON service_session (space_identifier) WHERE end_datetime IS NULL;
CREATE INDEX ix_service_session_vehicle ON service_session (vehicle_identifier);
CREATE INDEX ix_service_session_equipment ON service_session (equipment_identifier);
CREATE INDEX ix_service_session_space ON service_session (space_identifier);
CREATE INDEX ix_service_session_rate ON service_session (rate_identifier);
CREATE INDEX ix_service_session_parking_rate ON service_session (parking_rate_identifier);


-- 10. payment_transaction

CREATE TABLE payment_transaction (
    transaction_identifier       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    session_identifier           UUID          NOT NULL UNIQUE
        REFERENCES service_session (session_identifier) ON DELETE RESTRICT,
    energy_amount_value          DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    overtime_amount_value        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    parking_amount_value         DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    transaction_amount_value     DECIMAL(12,2) NOT NULL,
    currency_code                CHAR(3)       NOT NULL DEFAULT 'VND',
    payment_method_code          VARCHAR(50),
    gateway_reference_identifier VARCHAR(100),
    transaction_status_code      VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    created_datetime             TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- người được lập hóa đơn, chụp lại lúc lập (trg_payment_snapshot) để còn
    -- nguyên khi tài khoản bị xóa
    customer_name_text           VARCHAR(100)  NOT NULL,
    customer_phone_number        VARCHAR(15)   NOT NULL,
    customer_email_address       VARCHAR(255)  NOT NULL,
    license_plate_text           VARCHAR(20)   NOT NULL,
    -- quản lý bãi xác nhận (SUCCESS) hoặc từ chối (FAILED) khoản khách đã trả
    confirmed_by_identifier      UUID
        REFERENCES user_account (account_identifier) ON DELETE RESTRICT,
    confirmed_datetime           TIMESTAMPTZ,
    CONSTRAINT ck_payment_confirmed
        CHECK (transaction_status_code IN ('PENDING', 'PROCESSING')
               OR (confirmed_by_identifier IS NOT NULL AND confirmed_datetime IS NOT NULL)),
    CONSTRAINT ck_payment_amounts
        CHECK (energy_amount_value >= 0 AND overtime_amount_value >= 0
               AND parking_amount_value >= 0
               AND transaction_amount_value
                   = energy_amount_value + overtime_amount_value + parking_amount_value),
    CONSTRAINT ck_payment_currency CHECK (currency_code IN ('VND', 'USD')),
    CONSTRAINT ck_payment_method
        CHECK (payment_method_code IS NULL
               OR payment_method_code IN
                  ('CREDIT_CARD', 'E_WALLET', 'BANK_TRANSFER')),
    CONSTRAINT ck_payment_status
        CHECK (transaction_status_code IN
               ('PENDING', 'PROCESSING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    -- PROCESSING: khách đã trả, chờ quản lý bãi xác nhận
    CONSTRAINT ck_payment_success_needs_method
        CHECK (transaction_status_code NOT IN ('PROCESSING', 'SUCCESS')
               OR (payment_method_code IS NOT NULL
                   AND gateway_reference_identifier IS NOT NULL))
);

CREATE INDEX ix_payment_transaction_confirmed_by
    ON payment_transaction (confirmed_by_identifier);


-- HÀM VÀ TRIGGER


-- Tra biểu giá: chọn phiên bản giá có hiệu lực tại giờ BẮT ĐẦU phiên;
-- khung giờ theo giờ địa phương, dải công suất theo công suất định mức của trụ
CREATE OR REPLACE FUNCTION fn_select_tariff(
    p_equipment_identifier UUID,
    p_start_datetime       TIMESTAMPTZ
) RETURNS UUID
LANGUAGE sql STABLE AS $$
    SELECT t.rate_identifier
    FROM charging_equipment AS ce
    JOIN time_band_window AS w
      ON (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME >= w.start_time
     AND (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME <  w.end_time
    JOIN power_tier AS pt
      ON pt.connector_type_code = ce.connector_type_code
     AND ce.max_power_kw >= pt.min_power_kw
     AND ce.max_power_kw <  pt.max_power_kw
    JOIN tariff_rate AS t
      ON t.connector_type_code = pt.connector_type_code
     AND t.min_power_kw = pt.min_power_kw
     AND t.time_band_code = w.time_band_code
     AND p_start_datetime >= t.effective_from
     AND (t.effective_to IS NULL OR p_start_datetime < t.effective_to)
    WHERE ce.equipment_identifier = p_equipment_identifier
$$;

-- Giá đỗ xe theo giờ có hiệu lực tại giờ bắt đầu phiên chỉ đỗ xe
CREATE OR REPLACE FUNCTION fn_select_parking_rate(p_start_datetime TIMESTAMPTZ)
RETURNS UUID
LANGUAGE sql STABLE AS $$
    SELECT pr.parking_rate_identifier
    FROM time_band_window AS w
    JOIN parking_rate AS pr
      ON pr.time_band_code = w.time_band_code
     AND p_start_datetime >= pr.effective_from
     AND (pr.effective_to IS NULL OR p_start_datetime < pr.effective_to)
    WHERE (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME >= w.start_time
      AND (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME <  w.end_time
$$;

-- Đổi giá: đóng phiên bản đang hiệu lực tại p_at và thêm phiên bản mới từ p_at.
-- SECURITY DEFINER: web chỉ được gọi hàm, không sửa trực tiếp bảng giá.
CREATE OR REPLACE FUNCTION fn_change_tariff(
    p_rate_identifier UUID,
    p_price_per_kwh   DECIMAL(10,2),
    p_overtime_fee    DECIMAL(10,2),
    p_at              TIMESTAMPTZ DEFAULT clock_timestamp()
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_old tariff_rate%ROWTYPE;
    v_new UUID;
BEGIN
    SELECT * INTO v_old FROM tariff_rate
    WHERE rate_identifier = p_rate_identifier FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Price version % does not exist', p_rate_identifier
            USING ERRCODE = 'no_data_found';
    END IF;
    IF v_old.effective_to IS NOT NULL THEN
        RAISE EXCEPTION 'Only the current price version can be changed'
            USING ERRCODE = 'restrict_violation';
    END IF;
    UPDATE tariff_rate SET effective_to = p_at WHERE rate_identifier = p_rate_identifier;
    INSERT INTO tariff_rate (connector_type_code, min_power_kw, time_band_code,
                             price_per_kwh_value, overtime_fee_per_hour_value, effective_from)
    VALUES (v_old.connector_type_code, v_old.min_power_kw, v_old.time_band_code,
            p_price_per_kwh, p_overtime_fee, p_at)
    RETURNING rate_identifier INTO v_new;
    RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION fn_change_parking_rate(
    p_parking_rate_identifier UUID,
    p_price_per_hour          DECIMAL(10,2),
    p_at                      TIMESTAMPTZ DEFAULT clock_timestamp()
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_old parking_rate%ROWTYPE;
    v_new UUID;
BEGIN
    SELECT * INTO v_old FROM parking_rate
    WHERE parking_rate_identifier = p_parking_rate_identifier FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Price version % does not exist', p_parking_rate_identifier
            USING ERRCODE = 'no_data_found';
    END IF;
    IF v_old.effective_to IS NOT NULL THEN
        RAISE EXCEPTION 'Only the current price version can be changed'
            USING ERRCODE = 'restrict_violation';
    END IF;
    UPDATE parking_rate SET effective_to = p_at
    WHERE parking_rate_identifier = p_parking_rate_identifier;
    INSERT INTO parking_rate (time_band_code, price_per_hour_value, effective_from)
    VALUES (v_old.time_band_code, p_price_per_hour, p_at)
    RETURNING parking_rate_identifier INTO v_new;
    RETURN v_new;
END $$;

REVOKE ALL ON FUNCTION fn_change_tariff(UUID, DECIMAL, DECIMAL, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_change_parking_rate(UUID, DECIMAL, TIMESTAMPTZ) FROM PUBLIC;

-- ---- T0: phiên bản giá không sửa đè; chỉ được đóng (ghi effective_to) một lần
CREATE OR REPLACE FUNCTION fn_rate_version_fixed() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.effective_to IS NOT NULL OR NEW.effective_to IS NULL
       OR to_jsonb(NEW) - 'effective_to' <> to_jsonb(OLD) - 'effective_to' THEN
        RAISE EXCEPTION 'A price version is never edited; add a new version instead'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_tariff_rate_fixed
    BEFORE UPDATE ON tariff_rate
    FOR EACH ROW EXECUTE FUNCTION fn_rate_version_fixed();
CREATE TRIGGER trg_parking_rate_fixed
    BEFORE UPDATE ON parking_rate
    FOR EACH ROW EXECUTE FUNCTION fn_rate_version_fixed();

-- ---- T0b: lịch khung giờ phải phủ kín 24 giờ (kiểm tra cuối giao dịch, để
-- sửa nhiều dòng trong một giao dịch, ví dụ dời giờ cao điểm). Các khoảng
-- không chồng nhau (EXCLUDE) nên tổng độ dài 24 giờ nghĩa là không có khe hở.
CREATE OR REPLACE FUNCTION fn_time_band_window_coverage() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT coalesce(sum(extract(epoch FROM end_time - start_time)), 0)
        FROM time_band_window) <> 86400 THEN
        RAISE EXCEPTION 'Time band windows must cover the whole day'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_time_band_window_coverage';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_time_band_window_coverage
    AFTER INSERT OR UPDATE OR DELETE ON time_band_window
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_time_band_window_coverage();

-- Ô đang có phiên mở (phiên sạc qua trụ của ô, hoặc phiên chỉ đỗ xe)
CREATE OR REPLACE FUNCTION fn_space_has_open_session(p_space_identifier UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM service_session AS s
                   WHERE s.space_identifier = p_space_identifier AND s.end_datetime IS NULL)
        OR EXISTS (SELECT 1 FROM service_session AS s
                   JOIN charging_equipment AS ce ON ce.equipment_identifier = s.equipment_identifier
                   WHERE ce.space_identifier = p_space_identifier AND s.end_datetime IS NULL)
$$;

-- ---- T1: chỉ tài khoản MANAGER mới được phân công quản lý bãi --------------
CREATE OR REPLACE FUNCTION fn_facility_manager_role() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_account
                   WHERE account_identifier = NEW.manager_identifier
                     AND role_code = 'MANAGER'
                     AND deleted_datetime IS NULL) THEN
        RAISE EXCEPTION 'Account % is not an active MANAGER', NEW.manager_identifier
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_facility_manager_role
    BEFORE INSERT OR UPDATE ON facility_manager
    FOR EACH ROW EXECUTE FUNCTION fn_facility_manager_role();

-- ---- T1b: chỉ tài khoản CUSTOMER còn hoạt động mới được sở hữu xe ----------
CREATE OR REPLACE FUNCTION fn_vehicle_owner_role() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_account
                   WHERE account_identifier = NEW.account_identifier
                     AND role_code = 'CUSTOMER'
                     AND deleted_datetime IS NULL) THEN
        RAISE EXCEPTION 'Account % is not an active CUSTOMER', NEW.account_identifier
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_vehicle_owner_role
    BEFORE INSERT OR UPDATE OF account_identifier ON vehicle
    FOR EACH ROW EXECUTE FUNCTION fn_vehicle_owner_role();

-- ---- T2: số ô đỗ không được vượt total_capacity_count ----------------------
CREATE OR REPLACE FUNCTION fn_space_capacity() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_capacity INT;
    v_count    INT;
BEGIN
    SELECT total_capacity_count INTO v_capacity
    FROM parking_facility
    WHERE facility_identifier = NEW.facility_identifier
    FOR UPDATE;   -- tuần tự hóa các lệnh thêm đồng thời vào cùng một bãi

    SELECT count(*) INTO v_count
    FROM parking_space
    WHERE facility_identifier = NEW.facility_identifier
      AND deleted_datetime IS NULL
      AND space_identifier IS DISTINCT FROM NEW.space_identifier;

    IF NEW.deleted_datetime IS NULL AND v_count + 1 > v_capacity THEN
        RAISE EXCEPTION 'Facility % is full (capacity %)',
            NEW.facility_identifier, v_capacity
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_space_capacity
    BEFORE INSERT OR UPDATE OF facility_identifier, deleted_datetime
    ON parking_space
    FOR EACH ROW EXECUTE FUNCTION fn_space_capacity();

-- ---- T2b: không được giảm sức chứa xuống dưới số ô đang có ------------------
CREATE OR REPLACE FUNCTION fn_facility_capacity() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.total_capacity_count < (SELECT count(*) FROM parking_space
                                   WHERE facility_identifier = NEW.facility_identifier
                                     AND deleted_datetime IS NULL) THEN
        RAISE EXCEPTION 'Capacity % is below the number of existing spaces',
            NEW.total_capacity_count
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_facility_capacity
    BEFORE UPDATE OF total_capacity_count ON parking_facility
    FOR EACH ROW EXECUTE FUNCTION fn_facility_capacity();

-- ---- T3: lượt đặt mới cần ô đỗ dùng được và xe còn hoạt động ---------------
CREATE OR REPLACE FUNCTION fn_reservation_validate() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_status  VARCHAR(20);
    v_deleted TIMESTAMPTZ;
BEGIN
    SELECT availability_status_code, deleted_datetime
      INTO v_status, v_deleted
    FROM parking_space WHERE space_identifier = NEW.space_identifier;

    IF v_deleted IS NOT NULL OR v_status = 'OUTOFSERVICE' THEN
        RAISE EXCEPTION 'Space % is out of service', NEW.space_identifier
            USING ERRCODE = 'check_violation';
    END IF;

    IF EXISTS (SELECT 1 FROM vehicle AS v
               JOIN user_account AS u ON u.account_identifier = v.account_identifier
               WHERE v.vehicle_identifier = NEW.vehicle_identifier
                 AND (v.deleted_datetime IS NOT NULL OR u.deleted_datetime IS NOT NULL)) THEN
        RAISE EXCEPTION 'Vehicle % or its owner has been removed', NEW.vehicle_identifier
            USING ERRCODE = 'check_violation';
    END IF;

    -- ô đang có xe sạc: không nhận lượt đặt bắt đầu trong 30 phút tới
    IF NEW.reservation_status_code IN ('PENDING', 'CONFIRMED')
       AND NEW.start_datetime < CURRENT_TIMESTAMP + INTERVAL '30 minutes'
       AND NEW.end_datetime > CURRENT_TIMESTAMP
       AND fn_space_has_open_session(NEW.space_identifier) THEN
        RAISE EXCEPTION 'Space is occupied by an open session'
            USING ERRCODE = 'exclusion_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reservation_validate
    BEFORE INSERT ON reservation
    FOR EACH ROW EXECUTE FUNCTION fn_reservation_validate();

-- ---- T3b: lượt đặt chỉ đi một chiều; trạng thái cuối không đổi được ---------
CREATE OR REPLACE FUNCTION fn_reservation_status_flow() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT ((OLD.reservation_status_code = 'PENDING'
             AND NEW.reservation_status_code IN
                 ('CONFIRMED', 'FULFILLED', 'CANCELLED', 'EXPIRED'))
         OR (OLD.reservation_status_code = 'CONFIRMED'
             AND NEW.reservation_status_code IN
                 ('FULFILLED', 'CANCELLED', 'EXPIRED'))) THEN
        RAISE EXCEPTION 'Reservation cannot change from % to %',
            OLD.reservation_status_code, NEW.reservation_status_code
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.reservation_status_code = 'CONFIRMED'
       AND (NEW.end_datetime <= CURRENT_TIMESTAMP
            OR NEW.start_datetime + INTERVAL '30 minutes' < CURRENT_TIMESTAMP) THEN
        RAISE EXCEPTION 'An overdue booking cannot be confirmed'
            USING ERRCODE = 'check_violation';
    END IF;

    -- FULFILLED chỉ khi đã mở phiên (phiên sạc hoặc phiên chỉ đỗ xe)
    IF NEW.reservation_status_code = 'FULFILLED'
       AND NOT EXISTS (SELECT 1 FROM service_session
                       WHERE reservation_identifier = NEW.reservation_identifier) THEN
        RAISE EXCEPTION 'A booking is used by opening a session'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reservation_status_flow
    BEFORE UPDATE OF reservation_status_code ON reservation
    FOR EACH ROW
    WHEN (OLD.reservation_status_code IS DISTINCT FROM NEW.reservation_status_code)
    EXECUTE FUNCTION fn_reservation_status_flow();

-- ---- T3c: cờ RESERVED cập nhật ngay khi lượt đặt thay đổi -------------------
CREATE OR REPLACE FUNCTION fn_reservation_refresh() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_refresh_reserved_spaces();
    RETURN NULL;
END $$;

CREATE TRIGGER trg_reservation_refresh
    AFTER INSERT OR UPDATE ON reservation
    FOR EACH STATEMENT EXECUTE FUNCTION fn_reservation_refresh();

-- ---- T4: thiết bị FAULT/MAINTENANCE  <->  ô đỗ OUTOFSERVICE ----------------
CREATE OR REPLACE FUNCTION fn_equipment_status_sync() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.equipment_status_code IN ('FAULT', 'MAINTENANCE') THEN
        UPDATE parking_space SET availability_status_code = 'OUTOFSERVICE'
        WHERE space_identifier = NEW.space_identifier
          AND availability_status_code <> 'OUTOFSERVICE';
        -- các lượt đặt chưa dùng trên ô này được hủy
        UPDATE reservation SET reservation_status_code = 'CANCELLED'
        WHERE space_identifier = NEW.space_identifier
          AND reservation_status_code IN ('PENDING', 'CONFIRMED')
          AND end_datetime > CURRENT_TIMESTAMP;
    ELSIF NEW.equipment_status_code = 'READY' THEN
        UPDATE parking_space SET availability_status_code = 'AVAILABLE'
        WHERE space_identifier = NEW.space_identifier
          AND availability_status_code = 'OUTOFSERVICE';
        PERFORM fn_refresh_reserved_spaces();
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_equipment_status_sync
    AFTER UPDATE OF equipment_status_code ON charging_equipment
    FOR EACH ROW
    WHEN (OLD.equipment_status_code IS DISTINCT FROM NEW.equipment_status_code)
    EXECUTE FUNCTION fn_equipment_status_sync();

-- ---- T5: kiểm tra phiên trước khi bắt đầu và chốt phiên bản giá -------------
CREATE OR REPLACE FUNCTION fn_session_validate() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_space      UUID;
    v_eq_status  VARCHAR(20);
    v_res        reservation%ROWTYPE;
BEGIN
    IF num_nonnulls(NEW.equipment_identifier, NEW.space_identifier) <> 1 THEN
        RAISE EXCEPTION 'A session uses either a charger or a parking-only space'
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_service_session_kind';
    END IF;

    IF NEW.equipment_identifier IS NOT NULL THEN
        SELECT space_identifier, equipment_status_code
          INTO v_space, v_eq_status
        FROM charging_equipment
        WHERE equipment_identifier = NEW.equipment_identifier;

        IF v_eq_status IN ('FAULT', 'MAINTENANCE') THEN
            RAISE EXCEPTION 'Charger % is not available (%)',
                NEW.equipment_identifier, v_eq_status
                USING ERRCODE = 'check_violation';
        END IF;
    ELSE
        v_space := NEW.space_identifier;
        IF EXISTS (SELECT 1 FROM charging_equipment
                   WHERE space_identifier = v_space AND deleted_datetime IS NULL) THEN
            RAISE EXCEPTION 'A charging space is used through its charger'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM vehicle AS v
               JOIN user_account AS u ON u.account_identifier = v.account_identifier
               WHERE v.vehicle_identifier = NEW.vehicle_identifier
                 AND (v.deleted_datetime IS NOT NULL OR u.deleted_datetime IS NOT NULL))
       OR EXISTS (SELECT 1 FROM charging_equipment AS ce
                  WHERE ce.equipment_identifier = NEW.equipment_identifier
                    AND ce.deleted_datetime IS NOT NULL)
       OR EXISTS (SELECT 1 FROM parking_space AS s
                  WHERE s.space_identifier = v_space
                    AND (s.deleted_datetime IS NOT NULL
                         OR s.availability_status_code = 'OUTOFSERVICE')) THEN
        RAISE EXCEPTION 'Vehicle, charger or space has been removed or is out of service'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.reservation_identifier IS NOT NULL THEN
        SELECT * INTO v_res FROM reservation
        WHERE reservation_identifier = NEW.reservation_identifier;

        IF v_res.space_identifier <> v_space
           OR v_res.vehicle_identifier <> NEW.vehicle_identifier THEN
            RAISE EXCEPTION 'Session does not match its reservation'
                USING ERRCODE = 'check_violation';
        END IF;
        IF v_res.reservation_status_code NOT IN ('PENDING', 'CONFIRMED') THEN
            RAISE EXCEPTION 'Reservation is %', v_res.reservation_status_code
                USING ERRCODE = 'check_violation';
        END IF;
        -- được đến sớm tối đa 15 phút, và phải trước khi khung giờ kết thúc
        IF NEW.start_datetime > v_res.start_datetime + INTERVAL '30 minutes' THEN
            RAISE EXCEPTION 'Booking is more than 30 minutes overdue'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_session_late_arrival';
        END IF;
        IF v_res.deleted_datetime IS NOT NULL
           OR NEW.start_datetime < v_res.start_datetime - INTERVAL '15 minutes'
           OR NEW.start_datetime >= v_res.end_datetime THEN
            RAISE EXCEPTION 'Session starts outside its reservation window'
                USING ERRCODE = 'check_violation';
        END IF;
    ELSE
        -- lượt đặt đang giữ ô: từ 30 phút trước giờ bắt đầu đến hết hạn ân hạn
        SELECT * INTO v_res FROM reservation
        WHERE space_identifier = v_space
          AND reservation_status_code IN ('PENDING', 'CONFIRMED')
          AND deleted_datetime IS NULL
          AND NEW.start_datetime >= start_datetime - INTERVAL '30 minutes'
          AND NEW.start_datetime <= start_datetime + INTERVAL '30 minutes'
          AND NEW.start_datetime <  end_datetime
        ORDER BY (vehicle_identifier = NEW.vehicle_identifier) DESC, start_datetime
        LIMIT 1;
        IF FOUND AND v_res.vehicle_identifier = NEW.vehicle_identifier THEN
            RAISE EXCEPTION 'Own booking: arrival is allowed at most 15 minutes early'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_session_early_arrival';
        ELSIF FOUND THEN
            RAISE EXCEPTION 'Space is reserved by another customer'
                USING ERRCODE = 'exclusion_violation';
        END IF;
    END IF;

    -- chốt phiên bản giá có hiệu lực lúc bắt đầu (bỏ qua giá trị người gọi gửi lên)
    IF NEW.equipment_identifier IS NOT NULL THEN
        NEW.rate_identifier := fn_select_tariff(NEW.equipment_identifier, NEW.start_datetime);
        NEW.parking_rate_identifier := NULL;
    ELSE
        NEW.parking_rate_identifier := fn_select_parking_rate(NEW.start_datetime);
        NEW.rate_identifier := NULL;
    END IF;
    IF NEW.rate_identifier IS NULL AND NEW.parking_rate_identifier IS NULL THEN
        RAISE EXCEPTION 'No price covers this session at %', NEW.start_datetime
            USING ERRCODE = 'no_data_found';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_validate
    BEFORE INSERT ON service_session
    FOR EACH ROW EXECUTE FUNCTION fn_session_validate();

-- ---- T6: bắt đầu phiên -> ô OCCUPIED, trụ CHARGING, lượt đặt FULFILLED
CREATE OR REPLACE FUNCTION fn_session_start() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.equipment_identifier IS NOT NULL THEN
        UPDATE charging_equipment SET equipment_status_code = 'CHARGING'
        WHERE equipment_identifier = NEW.equipment_identifier;
    END IF;

    UPDATE parking_space SET availability_status_code = 'OCCUPIED'
    WHERE space_identifier = coalesce(NEW.space_identifier,
                                      (SELECT space_identifier FROM charging_equipment
                                       WHERE equipment_identifier = NEW.equipment_identifier));

    IF NEW.reservation_identifier IS NOT NULL THEN
        UPDATE reservation SET reservation_status_code = 'FULFILLED'
        WHERE reservation_identifier = NEW.reservation_identifier;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_start
    AFTER INSERT ON service_session
    FOR EACH ROW EXECUTE FUNCTION fn_session_start();

-- ---- T6b: phiên đã kết thúc là chỉ đọc ---------------------------------------
CREATE OR REPLACE FUNCTION fn_session_immutable() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'A finished session cannot be changed'
        USING ERRCODE = 'restrict_violation';
END $$;

CREATE TRIGGER trg_session_immutable
    BEFORE UPDATE OF vehicle_identifier, equipment_identifier, space_identifier,
                     start_datetime, end_datetime, fully_charged_datetime,
                     peak_charging_power_kw, consumed_energy_kwh
    ON service_session
    FOR EACH ROW
    WHEN (OLD.end_datetime IS NOT NULL)
    EXECUTE FUNCTION fn_session_immutable();

-- ---- T7: kết thúc phiên -> giải phóng thiết bị + tự động lập hóa đơn -------
CREATE OR REPLACE FUNCTION fn_session_finish() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_rate     tariff_rate%ROWTYPE;
    v_hourly   DECIMAL(10,2);
    v_energy   DECIMAL(12,2) := 0;
    v_overtime DECIMAL(12,2) := 0;
    v_parking  DECIMAL(12,2) := 0;
BEGIN
    -- giải phóng thiết bị (không ghi đè FAULT / MAINTENANCE / OUTOFSERVICE)
    IF NEW.equipment_identifier IS NOT NULL THEN
        UPDATE charging_equipment SET equipment_status_code = 'READY'
        WHERE equipment_identifier = NEW.equipment_identifier
          AND equipment_status_code = 'CHARGING';
    END IF;

    UPDATE parking_space SET availability_status_code = 'AVAILABLE'
    WHERE space_identifier = coalesce(NEW.space_identifier,
                                      (SELECT space_identifier FROM charging_equipment
                                       WHERE equipment_identifier = NEW.equipment_identifier))
      AND availability_status_code = 'OCCUPIED';

    -- lập hóa đơn theo phiên bản giá đã chốt lúc bắt đầu
    IF NEW.equipment_identifier IS NOT NULL THEN
        SELECT * INTO v_rate FROM tariff_rate WHERE rate_identifier = NEW.rate_identifier;
        v_energy := round(NEW.consumed_energy_kwh * v_rate.price_per_kwh_value, 2);
        IF NEW.fully_charged_datetime IS NOT NULL THEN
            v_overtime := round(
                greatest(0, extract(epoch FROM (NEW.end_datetime
                                                - NEW.fully_charged_datetime)) / 3600.0)
                * v_rate.overtime_fee_per_hour_value, 2);
        END IF;
    ELSE
        -- chỉ đỗ xe: số giờ đỗ x giá theo giờ
        SELECT price_per_hour_value INTO v_hourly
        FROM parking_rate WHERE parking_rate_identifier = NEW.parking_rate_identifier;
        v_parking := round(extract(epoch FROM (NEW.end_datetime - NEW.start_datetime))
                           / 3600.0 * v_hourly, 2);
    END IF;

    INSERT INTO payment_transaction
        (session_identifier, energy_amount_value, overtime_amount_value,
         parking_amount_value, transaction_amount_value)
    VALUES
        (NEW.session_identifier, v_energy, v_overtime,
         v_parking, v_energy + v_overtime + v_parking);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_finish
    AFTER UPDATE OF end_datetime ON service_session
    FOR EACH ROW
    WHEN (OLD.end_datetime IS NULL AND NEW.end_datetime IS NOT NULL)
    EXECUTE FUNCTION fn_session_finish();

-- ---- T8: hồ sơ tài chính là bất biến ---------------------------------------
CREATE OR REPLACE FUNCTION fn_payment_immutable() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'payment_transaction rows cannot be deleted'
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.session_identifier <> OLD.session_identifier
       OR NEW.energy_amount_value <> OLD.energy_amount_value
       OR NEW.overtime_amount_value <> OLD.overtime_amount_value
       OR NEW.parking_amount_value <> OLD.parking_amount_value
       OR NEW.transaction_amount_value <> OLD.transaction_amount_value
       OR NEW.currency_code <> OLD.currency_code
       OR (NEW.customer_name_text, NEW.customer_phone_number,
           NEW.customer_email_address, NEW.license_plate_text)
          IS DISTINCT FROM
          (OLD.customer_name_text, OLD.customer_phone_number,
           OLD.customer_email_address, OLD.license_plate_text) THEN
        RAISE EXCEPTION 'Invoice amounts and billed customer are immutable'
            USING ERRCODE = 'restrict_violation';
    END IF;
    -- Luồng: khách trả  PENDING/FAILED -> PROCESSING;
    --       quản lý bãi PROCESSING -> SUCCESS (xác nhận) / FAILED (từ chối);
    --       hoàn tiền   SUCCESS -> REFUNDED.
    IF NEW.transaction_status_code <> OLD.transaction_status_code
       AND NOT ((OLD.transaction_status_code IN ('PENDING', 'FAILED')
                 AND NEW.transaction_status_code = 'PROCESSING')
             OR (OLD.transaction_status_code = 'PROCESSING'
                 AND NEW.transaction_status_code IN ('SUCCESS', 'FAILED'))
             OR (OLD.transaction_status_code = 'SUCCESS'
                 AND NEW.transaction_status_code = 'REFUNDED')) THEN
        RAISE EXCEPTION 'Payment cannot change from % to %',
            OLD.transaction_status_code, NEW.transaction_status_code
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.transaction_status_code = 'PROCESSING'
       AND OLD.transaction_status_code <> 'PROCESSING' THEN
        -- lần trả mới: bỏ kết quả xác nhận cũ (nếu từng bị từ chối)
        NEW.confirmed_by_identifier := NULL;
        NEW.confirmed_datetime := NULL;
    ELSIF OLD.transaction_status_code = 'PROCESSING'
          AND NEW.transaction_status_code IN ('SUCCESS', 'FAILED') THEN
        -- chỉ quản lý (chưa xóa) đang phụ trách bãi nơi khách sạc mới xác nhận được
        IF NEW.confirmed_by_identifier IS NULL OR NOT EXISTS (
               SELECT 1
               FROM service_session AS ss
               LEFT JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
               JOIN parking_space AS s
                 ON s.space_identifier = coalesce(ss.space_identifier, ce.space_identifier)
               JOIN facility_manager AS fm ON fm.facility_identifier = s.facility_identifier
               JOIN user_account AS u ON u.account_identifier = fm.manager_identifier
               WHERE ss.session_identifier = NEW.session_identifier
                 AND u.account_identifier = NEW.confirmed_by_identifier
                 AND u.role_code = 'MANAGER' AND u.deleted_datetime IS NULL) THEN
            RAISE EXCEPTION 'Only a manager of the facility can confirm this payment'
                USING ERRCODE = 'check_violation',
                      CONSTRAINT = 'ck_payment_confirmed_by_manager';
        END IF;
        IF NEW.confirmed_datetime IS NOT DISTINCT FROM OLD.confirmed_datetime THEN
            NEW.confirmed_datetime := CURRENT_TIMESTAMP;
        END IF;
    END IF;
    IF OLD.transaction_status_code IN ('SUCCESS', 'REFUNDED')
       AND (NEW.payment_method_code IS DISTINCT FROM OLD.payment_method_code
            OR NEW.gateway_reference_identifier
               IS DISTINCT FROM OLD.gateway_reference_identifier
            OR NEW.confirmed_by_identifier IS DISTINCT FROM OLD.confirmed_by_identifier
            OR NEW.confirmed_datetime IS DISTINCT FROM OLD.confirmed_datetime) THEN
        RAISE EXCEPTION 'Paid invoice details are immutable'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_immutable
    BEFORE UPDATE OR DELETE ON payment_transaction
    FOR EACH ROW EXECUTE FUNCTION fn_payment_immutable();

-- ---- T8b: hóa đơn ghi lại người được lập hóa đơn ----------------------------
CREATE OR REPLACE FUNCTION fn_payment_snapshot() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    SELECT u.full_name_text, u.contact_phone_number, u.email_address, v.license_plate_text
      INTO NEW.customer_name_text, NEW.customer_phone_number,
           NEW.customer_email_address, NEW.license_plate_text
    FROM service_session AS ss
    JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
    JOIN user_account AS u ON u.account_identifier = v.account_identifier
    WHERE ss.session_identifier = NEW.session_identifier;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_snapshot
    BEFORE INSERT ON payment_transaction
    FOR EACH ROW EXECUTE FUNCTION fn_payment_snapshot();

-- ---- T9: vai trò và xóa mềm tài khoản --------------------------------------
CREATE OR REPLACE FUNCTION fn_account_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.role_code <> OLD.role_code THEN
        IF OLD.role_code = 'CUSTOMER' AND EXISTS (
               SELECT 1 FROM vehicle WHERE account_identifier = OLD.account_identifier) THEN
            RAISE EXCEPTION 'A customer who owns vehicles cannot change role'
                USING ERRCODE = 'check_violation';
        END IF;
        IF OLD.role_code = 'MANAGER' AND EXISTS (
               SELECT 1 FROM facility_manager
               WHERE manager_identifier = OLD.account_identifier) THEN
            RAISE EXCEPTION 'A manager with assigned facilities cannot change role'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    IF OLD.deleted_datetime IS NULL AND NEW.deleted_datetime IS NOT NULL THEN
        IF OLD.role_code = 'ADMIN' THEN
            RAISE EXCEPTION 'Administrator accounts cannot be removed'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_account_admin';
        END IF;
        -- đang sạc hoặc còn nợ vẫn xóa được (web cảnh báo trước); phiên đang mở
        -- vẫn kết thúc và lập hóa đơn bình thường
        UPDATE reservation SET reservation_status_code = 'CANCELLED'
        WHERE reservation_status_code IN ('PENDING', 'CONFIRMED')
          AND end_datetime > CURRENT_TIMESTAMP
          AND vehicle_identifier IN (SELECT vehicle_identifier FROM vehicle
                                     WHERE account_identifier = OLD.account_identifier);
        DELETE FROM facility_manager WHERE manager_identifier = OLD.account_identifier;
        -- xe ngừng theo chủ, biển số được nhả cho người khác đăng ký
        UPDATE vehicle SET deleted_datetime = NEW.deleted_datetime
        WHERE account_identifier = OLD.account_identifier AND deleted_datetime IS NULL;
    END IF;
    IF OLD.deleted_datetime IS NOT NULL AND NEW.deleted_datetime IS NOT NULL
       AND NEW.deleted_datetime <> OLD.deleted_datetime THEN
        RAISE EXCEPTION 'The removal time of an account cannot be changed'
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF OLD.deleted_datetime IS NOT NULL AND NEW.deleted_datetime IS NULL THEN
        IF OLD.purged_datetime IS NOT NULL THEN
            RAISE EXCEPTION 'The account has been deleted permanently'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_account_purged';
        END IF;
        IF OLD.deleted_datetime <= CURRENT_TIMESTAMP - INTERVAL '30 minutes' THEN
            RAISE EXCEPTION 'The 30 minute restore window has passed'
                USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_account_restore_expired';
        END IF;
        -- chỉ khôi phục các xe bị ngừng cùng lúc với tài khoản
        UPDATE vehicle SET deleted_datetime = NULL
        WHERE account_identifier = OLD.account_identifier
          AND deleted_datetime = OLD.deleted_datetime;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_account_guard
    BEFORE UPDATE OF role_code, deleted_datetime ON user_account
    FOR EACH ROW EXECUTE FUNCTION fn_account_guard();

CREATE OR REPLACE FUNCTION fn_admin_keep() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Administrator accounts cannot be removed'
        USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_account_admin';
END $$;

CREATE TRIGGER trg_admin_keep
    BEFORE DELETE ON user_account
    FOR EACH ROW WHEN (OLD.role_code = 'ADMIN')
    EXECUTE FUNCTION fn_admin_keep();

-- Xóa vĩnh viễn các tài khoản đã xóa quá 30 phút (web gọi định kỳ).
-- Chưa có lịch sử thì xóa hẳn; có lịch sử thì xóa thông tin cá nhân, giữ phiên
-- sạc và hóa đơn (hóa đơn đã ghi sẵn người được lập). Đang sạc thì chờ.
-- SECURITY DEFINER: web chỉ được gọi hàm này, không có quyền xóa trực tiếp.
CREATE OR REPLACE FUNCTION fn_purge_deleted_accounts() RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    a       RECORD;
    v_count INT := 0;
BEGIN
    FOR a IN
        SELECT u.account_identifier FROM user_account AS u
        WHERE u.deleted_datetime <= CURRENT_TIMESTAMP - INTERVAL '30 minutes'
          AND u.purged_datetime IS NULL AND u.role_code <> 'ADMIN'
          AND NOT EXISTS (SELECT 1 FROM service_session AS ss
                          JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
                          WHERE v.account_identifier = u.account_identifier
                            AND ss.end_datetime IS NULL)
        FOR UPDATE SKIP LOCKED
    LOOP
        IF EXISTS (SELECT 1 FROM vehicle AS v
                   WHERE v.account_identifier = a.account_identifier
                     AND (EXISTS (SELECT 1 FROM service_session AS ss
                                  WHERE ss.vehicle_identifier = v.vehicle_identifier)
                          OR EXISTS (SELECT 1 FROM reservation AS r
                                     WHERE r.vehicle_identifier = v.vehicle_identifier)))
           -- quản lý đã xác nhận thanh toán: giữ dòng để hóa đơn còn người xác nhận
           OR EXISTS (SELECT 1 FROM payment_transaction AS p
                      WHERE p.confirmed_by_identifier = a.account_identifier) THEN
            UPDATE vehicle SET license_plate_text = 'DA-XOA'
            WHERE account_identifier = a.account_identifier;
            UPDATE user_account
            SET full_name_text = 'Tài khoản đã xóa', contact_phone_number = '00000000',
                email_address = 'da-xoa@invalid.local', password_hash_text = '!',
                password_plain_text = NULL, purged_datetime = CURRENT_TIMESTAMP
            WHERE account_identifier = a.account_identifier;
        ELSE
            DELETE FROM user_account WHERE account_identifier = a.account_identifier;
        END IF;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

REVOKE ALL ON FUNCTION fn_purge_deleted_accounts() FROM PUBLIC;

-- ---- Ước tính phiên sạc: điện năng, giờ đầy pin, % pin tại một thời điểm ----
-- Sạc với công suất định mức của trụ x hiệu suất 90 %, dừng khi pin đầy.
-- Thiếu % pin lúc cắm (phiên cũ) thì coi là 20 %.
CREATE OR REPLACE FUNCTION fn_session_estimate(p_session UUID, p_at TIMESTAMPTZ)
RETURNS TABLE (energy_kwh DECIMAL(10,2), full_at TIMESTAMPTZ,
               battery_percent DECIMAL(5,2), power_kw DECIMAL(10,2))
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT ss.start_datetime AS t0,
               coalesce(ss.start_battery_percent, 20) AS pct,
               v.battery_capacity_kwh AS cap,
               ce.max_power_kw AS kw,
               ce.max_power_kw * 0.9 AS rate,
               v.battery_capacity_kwh * (100 - coalesce(ss.start_battery_percent, 20)) / 100 AS need,
               greatest(extract(epoch FROM (p_at - ss.start_datetime)), 0) / 3600.0 AS hours
        FROM service_session AS ss
        JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
        JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
        WHERE ss.session_identifier = p_session
    ), e AS (
        SELECT x.*, round(least(x.rate * x.hours, x.need), 2) AS kwh,
               x.t0 + make_interval(secs => x.need / x.rate * 3600) AS full_time
        FROM x
    )
    SELECT e.kwh::DECIMAL(10,2),
           CASE WHEN e.full_time <= p_at THEN e.full_time END,
           least(100, round(e.pct + e.kwh / e.cap * 100, 2))::DECIMAL(5,2),
           CASE WHEN e.kwh > 0 THEN e.kw ELSE 0 END::DECIMAL(10,2)
    FROM e
$$;

-- ---- T10: xe, ô, giờ của lượt đặt không sửa được (muốn đổi thì hủy và đặt lại)
CREATE OR REPLACE FUNCTION fn_reservation_fixed() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.vehicle_identifier, NEW.space_identifier, NEW.start_datetime, NEW.end_datetime)
       IS DISTINCT FROM
       (OLD.vehicle_identifier, OLD.space_identifier, OLD.start_datetime, OLD.end_datetime) THEN
        RAISE EXCEPTION 'Vehicle, space and time of a booking cannot be changed'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reservation_fixed
    BEFORE UPDATE OF vehicle_identifier, space_identifier, start_datetime, end_datetime
    ON reservation
    FOR EACH ROW EXECUTE FUNCTION fn_reservation_fixed();

-- ---- T11: phiên không xóa được; xe, trụ/ô, giờ bắt đầu, phiên bản giá cố định
CREATE OR REPLACE FUNCTION fn_session_fixed() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (NEW.vehicle_identifier, NEW.equipment_identifier, NEW.space_identifier,
            NEW.start_datetime, NEW.rate_identifier, NEW.parking_rate_identifier,
            NEW.start_battery_percent)
           IS NOT DISTINCT FROM
           (OLD.vehicle_identifier, OLD.equipment_identifier, OLD.space_identifier,
            OLD.start_datetime, OLD.rate_identifier, OLD.parking_rate_identifier,
            OLD.start_battery_percent) THEN
            RETURN NEW;
        END IF;
    END IF;
    -- phiên có hóa đơn đã được khóa ngoại RESTRICT bảo vệ, ở đây chặn mọi phiên
    RAISE EXCEPTION 'Session records cannot be deleted or re-pointed'
        USING ERRCODE = 'restrict_violation';
END $$;

CREATE TRIGGER trg_session_fixed
    BEFORE DELETE OR UPDATE OF vehicle_identifier, equipment_identifier, space_identifier,
                     start_datetime, rate_identifier, parking_rate_identifier,
                     start_battery_percent
    ON service_session
    FOR EACH ROW EXECUTE FUNCTION fn_session_fixed();

-- ---- T12: điện năng phải khả thi --------------------------------------------
-- tối đa 110 % dung lượng pin (hao hụt khi sạc) và công suất trụ x thời gian
-- (cộng 5 phút sai số đồng hồ)
CREATE OR REPLACE FUNCTION fn_session_energy_limit() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_battery DECIMAL(10,2);
    v_power   DECIMAL(10,2);
BEGIN
    IF NEW.equipment_identifier IS NULL THEN
        RETURN NEW;          -- phiên chỉ đỗ xe không có điện năng (ck_service_session_kind)
    END IF;
    SELECT battery_capacity_kwh INTO v_battery
    FROM vehicle WHERE vehicle_identifier = NEW.vehicle_identifier;
    SELECT max_power_kw INTO v_power
    FROM charging_equipment WHERE equipment_identifier = NEW.equipment_identifier;

    IF NEW.consumed_energy_kwh > v_battery * 1.10 THEN
        RAISE EXCEPTION 'Energy % kWh exceeds the battery capacity', NEW.consumed_energy_kwh
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_session_energy_battery';
    END IF;
    IF NEW.consumed_energy_kwh > v_power
       * (extract(epoch FROM (NEW.end_datetime - NEW.start_datetime)) + 300) / 3600.0 THEN
        RAISE EXCEPTION 'Energy % kWh exceeds charger power x charging time',
            NEW.consumed_energy_kwh
            USING ERRCODE = 'check_violation', CONSTRAINT = 'ck_session_energy_power';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_energy_limit
    BEFORE UPDATE OF end_datetime ON service_session
    FOR EACH ROW
    WHEN (OLD.end_datetime IS NULL AND NEW.end_datetime IS NOT NULL)
    EXECUTE FUNCTION fn_session_energy_limit();

-- ---- T13: trạng thái CHARGING phải khớp với phiên đang mở -------------------
CREATE OR REPLACE FUNCTION fn_equipment_charging_guard() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_open BOOLEAN;
BEGIN
    v_open := EXISTS (SELECT 1 FROM service_session
                      WHERE equipment_identifier = NEW.equipment_identifier
                        AND end_datetime IS NULL);
    IF (NEW.equipment_status_code = 'CHARGING' AND NOT v_open)
       OR (OLD.equipment_status_code = 'CHARGING' AND v_open) THEN
        RAISE EXCEPTION 'CHARGING status must follow the open charging session'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_equipment_charging_guard
    BEFORE UPDATE OF equipment_status_code ON charging_equipment
    FOR EACH ROW
    WHEN (OLD.equipment_status_code IS DISTINCT FROM NEW.equipment_status_code)
    EXECUTE FUNCTION fn_equipment_charging_guard();

-- ---- T14: chỉ lập hóa đơn cho phiên đã kết thúc -----------------------------
CREATE OR REPLACE FUNCTION fn_payment_requires_end() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM service_session
               WHERE session_identifier = NEW.session_identifier
                 AND end_datetime IS NULL) THEN
        RAISE EXCEPTION 'Cannot invoice a session that is still open'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_requires_end
    BEFORE INSERT ON payment_transaction
    FOR EACH ROW EXECUTE FUNCTION fn_payment_requires_end();

-- ---- T15: xóa mềm ô đỗ -------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_space_removal() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF fn_space_has_open_session(OLD.space_identifier) THEN
        RAISE EXCEPTION 'A space with an open session cannot be removed'
            USING ERRCODE = 'check_violation';
    END IF;
    UPDATE reservation SET reservation_status_code = 'CANCELLED'
    WHERE space_identifier = OLD.space_identifier
      AND reservation_status_code IN ('PENDING', 'CONFIRMED')
      AND end_datetime > CURRENT_TIMESTAMP;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_space_removal
    BEFORE UPDATE OF deleted_datetime ON parking_space
    FOR EACH ROW
    WHEN (OLD.deleted_datetime IS NULL AND NEW.deleted_datetime IS NOT NULL)
    EXECUTE FUNCTION fn_space_removal();

-- ---- Tác vụ định kỳ (gọi từ pg_cron mỗi phút) ------------------------------
-- Tùy chọn, cần extension pg_cron (không tạo trong file này):
--   SELECT cron.schedule('expire_reservations', '* * * * *',
--                        'SELECT fn_expire_overdue_reservations()');
-- Không có pg_cron thì gọi hàm bằng trình lập lịch bất kỳ (cron, Task Scheduler).
-- Thời gian ân hạn 30 phút: cho hết hạn lượt đặt không được kích hoạt.
CREATE OR REPLACE FUNCTION fn_expire_overdue_reservations() RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE reservation AS r
    SET reservation_status_code = 'EXPIRED'
    WHERE r.reservation_status_code IN ('PENDING', 'CONFIRMED')
      AND r.start_datetime + INTERVAL '30 minutes' < CURRENT_TIMESTAMP
      AND NOT EXISTS (SELECT 1 FROM service_session s
                      WHERE s.reservation_identifier = r.reservation_identifier);
    GET DIAGNOSTICS v_count = ROW_COUNT;

    PERFORM fn_refresh_reserved_spaces();
    RETURN v_count;
END $$;

-- Giữ cờ RESERVED khớp với bảng reservation.
CREATE OR REPLACE FUNCTION fn_refresh_reserved_spaces() RETURNS VOID
LANGUAGE sql AS $$
    UPDATE parking_space AS p SET availability_status_code = 'RESERVED'
    WHERE p.availability_status_code = 'AVAILABLE'
      AND EXISTS (SELECT 1 FROM reservation r
                  WHERE r.space_identifier = p.space_identifier
                    AND r.reservation_status_code = 'CONFIRMED'
                    AND CURRENT_TIMESTAMP >= r.start_datetime
                    AND r.deleted_datetime IS NULL
                    AND CURRENT_TIMESTAMP <  r.end_datetime);

    UPDATE parking_space AS p SET availability_status_code = 'AVAILABLE'
    WHERE p.availability_status_code = 'RESERVED'
      AND NOT EXISTS (SELECT 1 FROM reservation r
                      WHERE r.space_identifier = p.space_identifier
                        AND r.reservation_status_code = 'CONFIRMED'
                        AND CURRENT_TIMESTAMP >= r.start_datetime
                        AND r.deleted_datetime IS NULL
                        AND CURRENT_TIMESTAMP <  r.end_datetime);
$$;

-- Kiểm tra còn trống trong khung giờ yêu cầu (thay cho kiểm tra trạng thái tức thời).
CREATE OR REPLACE FUNCTION fn_is_space_available(
    p_space_identifier UUID,
    p_start_datetime   TIMESTAMPTZ,
    p_end_datetime     TIMESTAMPTZ
) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
               SELECT 1 FROM parking_space
               WHERE space_identifier = p_space_identifier
                 AND (deleted_datetime IS NOT NULL
                      OR availability_status_code = 'OUTOFSERVICE'))
       AND NOT (
               p_start_datetime < CURRENT_TIMESTAMP + INTERVAL '30 minutes'
               AND p_end_datetime > CURRENT_TIMESTAMP
               AND fn_space_has_open_session(p_space_identifier))
       AND NOT EXISTS (
               SELECT 1 FROM reservation
               WHERE space_identifier = p_space_identifier
                 AND reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
                 AND deleted_datetime IS NULL
                 AND tstzrange(start_datetime, end_datetime)
                     && tstzrange(p_start_datetime, p_end_datetime))
$$;

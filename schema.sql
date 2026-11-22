-- =============================================================================
-- Smart City EV Charging & Parking Management  |  Group M3B  |  v0.3.1
-- PostgreSQL 14+  (PostGIS + btree_gist required)
-- Style: SQLStyle.guide (lowercase snake_case identifiers, UPPERCASE keywords)
-- Naming: ISO/IEC 11179 suffixes
--   _identifier  _code  _text  _count  _datetime  _time  _kw  _kwh  _value
-- Time zone for tariff bands: Asia/Ho_Chi_Minh (see fn_select_tariff)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- -----------------------------------------------------------------------------
-- 1. user_account
-- -----------------------------------------------------------------------------
CREATE TABLE user_account (
    account_identifier   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name_text       VARCHAR(100) NOT NULL,
    contact_phone_number VARCHAR(15)  NOT NULL,
    email_address        VARCHAR(255) NOT NULL,
    password_hash_text   VARCHAR(255) NOT NULL,
    role_code            VARCHAR(20)  NOT NULL DEFAULT 'CUSTOMER',
    created_datetime     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_datetime     TIMESTAMPTZ,
    CONSTRAINT ck_user_account_role
        CHECK (role_code IN ('CUSTOMER', 'MANAGER', 'ADMIN')),
    CONSTRAINT ck_user_account_phone
        CHECK (contact_phone_number ~ '^\+?[0-9]{8,14}$')
);

-- Partial unique indexes: a soft-deleted account releases its phone/email.
CREATE UNIQUE INDEX ux_user_account_phone
    ON user_account (contact_phone_number) WHERE deleted_datetime IS NULL;
CREATE UNIQUE INDEX ux_user_account_email
    ON user_account (lower(email_address)) WHERE deleted_datetime IS NULL;

-- -----------------------------------------------------------------------------
-- 2. vehicle
-- -----------------------------------------------------------------------------
CREATE TABLE vehicle (
    vehicle_identifier   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    account_identifier   UUID          NOT NULL
        REFERENCES user_account (account_identifier) ON DELETE CASCADE,
    license_plate_text   VARCHAR(20)   NOT NULL,
    battery_capacity_kwh DECIMAL(10,2) NOT NULL,
    deleted_datetime     TIMESTAMPTZ,
    CONSTRAINT ck_vehicle_battery CHECK (battery_capacity_kwh > 0)
);

CREATE UNIQUE INDEX ux_vehicle_license_plate
    ON vehicle (license_plate_text) WHERE deleted_datetime IS NULL;
CREATE INDEX ix_vehicle_account ON vehicle (account_identifier);

-- -----------------------------------------------------------------------------
-- 3. parking_facility
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 4. facility_manager  (N:M between MANAGER accounts and facilities)
-- -----------------------------------------------------------------------------
CREATE TABLE facility_manager (
    manager_identifier  UUID NOT NULL
        REFERENCES user_account (account_identifier) ON DELETE CASCADE,
    facility_identifier UUID NOT NULL
        REFERENCES parking_facility (facility_identifier) ON DELETE CASCADE,
    PRIMARY KEY (manager_identifier, facility_identifier)
);

-- -----------------------------------------------------------------------------
-- 5. parking_space
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 6. charging_equipment  (1:1 extension of parking_space)
-- -----------------------------------------------------------------------------
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
    CONSTRAINT ck_charging_equipment_power CHECK (max_power_kw > 0),
    CONSTRAINT ck_charging_equipment_status
        CHECK (equipment_status_code IN
               ('READY', 'CHARGING', 'FAULT', 'MAINTENANCE'))
);

CREATE UNIQUE INDEX ux_charging_equipment_space
    ON charging_equipment (space_identifier) WHERE deleted_datetime IS NULL;
CREATE UNIQUE INDEX ux_charging_equipment_evse
    ON charging_equipment (evse_identifier) WHERE deleted_datetime IS NULL;

-- -----------------------------------------------------------------------------
-- 7. tariff_rate
-- Bands never cross midnight: 22:00-05:00 is stored as two rows
-- (22:00-24:00 and 00:00-05:00). Power range is half-open [min, max) and is
-- compared with charging_equipment.max_power_kw (rated power).
-- -----------------------------------------------------------------------------
CREATE TABLE tariff_rate (
    rate_identifier             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    connector_type_code         VARCHAR(50)   NOT NULL,
    time_band_code              VARCHAR(20)   NOT NULL,
    start_time                  TIME          NOT NULL,
    end_time                    TIME          NOT NULL,
    min_power_kw                DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    max_power_kw                DECIMAL(10,2) NOT NULL,
    price_per_kwh_value         DECIMAL(10,2) NOT NULL,
    overtime_fee_per_hour_value DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT ck_tariff_rate_connector
        CHECK (connector_type_code IN ('FAST_DC', 'STANDARD_AC')),
    CONSTRAINT ck_tariff_rate_band
        CHECK (time_band_code IN ('PEAK', 'STANDARD', 'OFF_PEAK')),
    CONSTRAINT ck_tariff_rate_time CHECK (end_time > start_time),
    CONSTRAINT ck_tariff_rate_power
        CHECK (min_power_kw >= 0 AND max_power_kw > min_power_kw),
    CONSTRAINT ck_tariff_rate_price CHECK (price_per_kwh_value >= 0),
    CONSTRAINT ck_tariff_rate_overtime CHECK (overtime_fee_per_hour_value >= 0),
    -- no two rows of the same connector type may overlap in time AND power
    CONSTRAINT ex_tariff_rate_no_overlap EXCLUDE USING gist (
        connector_type_code WITH =,
        int4range(extract(epoch FROM start_time)::INT,
                  extract(epoch FROM end_time)::INT) WITH &&,
        numrange(min_power_kw, max_power_kw) WITH &&
    )
);

-- -----------------------------------------------------------------------------
-- 8. reservation
-- -----------------------------------------------------------------------------
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
    CONSTRAINT ck_reservation_status
        CHECK (reservation_status_code IN
               ('PENDING', 'CONFIRMED', 'FULFILLED', 'CANCELLED', 'EXPIRED')),
    -- Only reservations that still hold the slot block other bookings;
    -- CANCELLED / EXPIRED / soft-deleted rows free the time window.
    CONSTRAINT ex_reservation_no_overlap EXCLUDE USING gist (
        space_identifier WITH =,
        tstzrange(start_datetime, end_datetime) WITH &&
    ) WHERE (reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
             AND deleted_datetime IS NULL)
);

CREATE INDEX ix_reservation_vehicle ON reservation (vehicle_identifier);
CREATE INDEX ix_reservation_timeout
    ON reservation (start_datetime)
    WHERE reservation_status_code IN ('PENDING', 'CONFIRMED');

-- -----------------------------------------------------------------------------
-- 9. service_session
-- The owning account is reached through vehicle.account_identifier
-- (no duplicated account column -> no transitive dependency).
-- -----------------------------------------------------------------------------
CREATE TABLE service_session (
    session_identifier     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_identifier UUID          UNIQUE
        REFERENCES reservation (reservation_identifier) ON DELETE SET NULL,
    vehicle_identifier     UUID          NOT NULL
        REFERENCES vehicle (vehicle_identifier) ON DELETE RESTRICT,
    equipment_identifier   UUID          NOT NULL
        REFERENCES charging_equipment (equipment_identifier) ON DELETE RESTRICT,
    start_datetime         TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_datetime           TIMESTAMPTZ,
    fully_charged_datetime TIMESTAMPTZ,
    peak_charging_power_kw DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    consumed_energy_kwh    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT ck_service_session_end
        CHECK (end_datetime IS NULL OR end_datetime >= start_datetime),
    CONSTRAINT ck_service_session_full
        CHECK (fully_charged_datetime IS NULL
               OR (fully_charged_datetime >= start_datetime
                   AND (end_datetime IS NULL
                        OR fully_charged_datetime <= end_datetime))),
    CONSTRAINT ck_service_session_peak CHECK (peak_charging_power_kw >= 0),
    CONSTRAINT ck_service_session_energy CHECK (consumed_energy_kwh >= 0)
);

-- one open session per charger at a time
CREATE UNIQUE INDEX ux_service_session_open_equipment
    ON service_session (equipment_identifier) WHERE end_datetime IS NULL;
CREATE INDEX ix_service_session_vehicle ON service_session (vehicle_identifier);

-- -----------------------------------------------------------------------------
-- 10. payment_transaction
-- -----------------------------------------------------------------------------
CREATE TABLE payment_transaction (
    transaction_identifier       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    session_identifier           UUID          NOT NULL UNIQUE
        REFERENCES service_session (session_identifier) ON DELETE RESTRICT,
    rate_identifier              UUID          NOT NULL
        REFERENCES tariff_rate (rate_identifier) ON DELETE RESTRICT,
    energy_amount_value          DECIMAL(12,2) NOT NULL,
    overtime_amount_value        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    transaction_amount_value     DECIMAL(12,2) NOT NULL,
    currency_code                CHAR(3)       NOT NULL DEFAULT 'VND',
    payment_method_code          VARCHAR(50),
    gateway_reference_identifier VARCHAR(100),
    transaction_status_code      VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    created_datetime             TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_payment_amounts
        CHECK (energy_amount_value >= 0 AND overtime_amount_value >= 0
               AND transaction_amount_value
                   = energy_amount_value + overtime_amount_value),
    CONSTRAINT ck_payment_currency CHECK (currency_code IN ('VND', 'USD')),
    CONSTRAINT ck_payment_method
        CHECK (payment_method_code IS NULL
               OR payment_method_code IN
                  ('CREDIT_CARD', 'E_WALLET', 'BANK_TRANSFER')),
    CONSTRAINT ck_payment_status
        CHECK (transaction_status_code IN
               ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    CONSTRAINT ck_payment_success_needs_method
        CHECK (transaction_status_code <> 'SUCCESS'
               OR (payment_method_code IS NOT NULL
                   AND gateway_reference_identifier IS NOT NULL))
);

-- =============================================================================
-- FUNCTIONS & TRIGGERS
-- =============================================================================

-- ---- Tariff lookup: rate is chosen by the session START time (local time) ----
CREATE OR REPLACE FUNCTION fn_select_tariff(
    p_equipment_identifier UUID,
    p_start_datetime       TIMESTAMPTZ
) RETURNS UUID
LANGUAGE sql STABLE AS $$
    SELECT t.rate_identifier
    FROM charging_equipment AS ce
    JOIN tariff_rate AS t
      ON t.connector_type_code = ce.connector_type_code
     AND ce.max_power_kw >= t.min_power_kw
     AND ce.max_power_kw <  t.max_power_kw
     AND (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME >= t.start_time
     AND (p_start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIME <  t.end_time
    WHERE ce.equipment_identifier = p_equipment_identifier
$$;

-- ---- T1: only MANAGER accounts may be assigned to facilities ----------------
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

-- ---- T2: number of spaces must not exceed total_capacity_count --------------
CREATE OR REPLACE FUNCTION fn_space_capacity() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_capacity INT;
    v_count    INT;
BEGIN
    SELECT total_capacity_count INTO v_capacity
    FROM parking_facility
    WHERE facility_identifier = NEW.facility_identifier
    FOR UPDATE;   -- serialises concurrent inserts into one facility

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

-- ---- T3: a new booking needs a usable space and an active vehicle -----------
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

    IF EXISTS (SELECT 1 FROM vehicle
               WHERE vehicle_identifier = NEW.vehicle_identifier
                 AND deleted_datetime IS NOT NULL) THEN
        RAISE EXCEPTION 'Vehicle % has been removed', NEW.vehicle_identifier
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_reservation_validate
    BEFORE INSERT ON reservation
    FOR EACH ROW EXECUTE FUNCTION fn_reservation_validate();

-- ---- T4: equipment FAULT/MAINTENANCE  <->  space OUTOFSERVICE ---------------
CREATE OR REPLACE FUNCTION fn_equipment_status_sync() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.equipment_status_code IN ('FAULT', 'MAINTENANCE') THEN
        UPDATE parking_space SET availability_status_code = 'OUTOFSERVICE'
        WHERE space_identifier = NEW.space_identifier
          AND availability_status_code <> 'OUTOFSERVICE';
    ELSIF NEW.equipment_status_code = 'READY' THEN
        UPDATE parking_space SET availability_status_code = 'AVAILABLE'
        WHERE space_identifier = NEW.space_identifier
          AND availability_status_code = 'OUTOFSERVICE';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_equipment_status_sync
    AFTER UPDATE OF equipment_status_code ON charging_equipment
    FOR EACH ROW
    WHEN (OLD.equipment_status_code IS DISTINCT FROM NEW.equipment_status_code)
    EXECUTE FUNCTION fn_equipment_status_sync();

-- ---- T5: validate a session before it starts --------------------------------
CREATE OR REPLACE FUNCTION fn_session_validate() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_space      UUID;
    v_eq_status  VARCHAR(20);
    v_res        reservation%ROWTYPE;
BEGIN
    SELECT space_identifier, equipment_status_code
      INTO v_space, v_eq_status
    FROM charging_equipment
    WHERE equipment_identifier = NEW.equipment_identifier;

    IF v_eq_status IN ('FAULT', 'MAINTENANCE') THEN
        RAISE EXCEPTION 'Charger % is not available (%)',
            NEW.equipment_identifier, v_eq_status
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
    ELSIF EXISTS (SELECT 1 FROM reservation
                  WHERE space_identifier = v_space
                    AND reservation_status_code IN ('PENDING', 'CONFIRMED')
                    AND deleted_datetime IS NULL
                    AND NEW.start_datetime >= start_datetime
                    AND NEW.start_datetime <  end_datetime) THEN
        RAISE EXCEPTION 'Space is reserved by another customer'
            USING ERRCODE = 'exclusion_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_validate
    BEFORE INSERT ON service_session
    FOR EACH ROW EXECUTE FUNCTION fn_session_validate();

-- ---- T6: session start -> space OCCUPIED, charger CHARGING, reservation FULFILLED
CREATE OR REPLACE FUNCTION fn_session_start() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE charging_equipment SET equipment_status_code = 'CHARGING'
    WHERE equipment_identifier = NEW.equipment_identifier;

    UPDATE parking_space SET availability_status_code = 'OCCUPIED'
    WHERE space_identifier = (SELECT space_identifier FROM charging_equipment
                              WHERE equipment_identifier = NEW.equipment_identifier);

    IF NEW.reservation_identifier IS NOT NULL THEN
        UPDATE reservation SET reservation_status_code = 'FULFILLED'
        WHERE reservation_identifier = NEW.reservation_identifier;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_start
    AFTER INSERT ON service_session
    FOR EACH ROW EXECUTE FUNCTION fn_session_start();

-- ---- T7: session end -> free hardware + issue invoice automatically ----------
CREATE OR REPLACE FUNCTION fn_session_finish() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_rate     tariff_rate%ROWTYPE;
    v_rate_id  UUID;
    v_energy   DECIMAL(12,2);
    v_overtime DECIMAL(12,2) := 0;
BEGIN
    -- release hardware (never overwrite FAULT / MAINTENANCE / OUTOFSERVICE)
    UPDATE charging_equipment SET equipment_status_code = 'READY'
    WHERE equipment_identifier = NEW.equipment_identifier
      AND equipment_status_code = 'CHARGING';

    UPDATE parking_space SET availability_status_code = 'AVAILABLE'
    WHERE space_identifier = (SELECT space_identifier FROM charging_equipment
                              WHERE equipment_identifier = NEW.equipment_identifier)
      AND availability_status_code = 'OCCUPIED';

    -- invoice
    v_rate_id := fn_select_tariff(NEW.equipment_identifier, NEW.start_datetime);
    IF v_rate_id IS NULL THEN
        RAISE EXCEPTION 'No tariff covers charger % at %',
            NEW.equipment_identifier, NEW.start_datetime
            USING ERRCODE = 'no_data_found';
    END IF;
    SELECT * INTO v_rate FROM tariff_rate WHERE rate_identifier = v_rate_id;

    v_energy := round(NEW.consumed_energy_kwh * v_rate.price_per_kwh_value, 2);
    IF NEW.fully_charged_datetime IS NOT NULL THEN
        v_overtime := round(
            greatest(0, extract(epoch FROM (NEW.end_datetime
                                            - NEW.fully_charged_datetime)) / 3600.0)
            * v_rate.overtime_fee_per_hour_value, 2);
    END IF;

    INSERT INTO payment_transaction
        (session_identifier, rate_identifier, energy_amount_value,
         overtime_amount_value, transaction_amount_value)
    VALUES
        (NEW.session_identifier, v_rate_id, v_energy,
         v_overtime, v_energy + v_overtime);
    RETURN NEW;
END $$;

CREATE TRIGGER trg_session_finish
    AFTER UPDATE OF end_datetime ON service_session
    FOR EACH ROW
    WHEN (OLD.end_datetime IS NULL AND NEW.end_datetime IS NOT NULL)
    EXECUTE FUNCTION fn_session_finish();

-- ---- T8: financial records are immutable ------------------------------------
CREATE OR REPLACE FUNCTION fn_payment_immutable() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'payment_transaction rows cannot be deleted'
            USING ERRCODE = 'restrict_violation';
    END IF;
    IF NEW.session_identifier <> OLD.session_identifier
       OR NEW.rate_identifier <> OLD.rate_identifier
       OR NEW.energy_amount_value <> OLD.energy_amount_value
       OR NEW.overtime_amount_value <> OLD.overtime_amount_value
       OR NEW.transaction_amount_value <> OLD.transaction_amount_value
       OR NEW.currency_code <> OLD.currency_code THEN
        RAISE EXCEPTION 'Invoice amounts are immutable'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_immutable
    BEFORE UPDATE OR DELETE ON payment_transaction
    FOR EACH ROW EXECUTE FUNCTION fn_payment_immutable();

-- ---- Scheduled jobs (call from pg_cron every minute) -------------------------
-- Optional, needs the pg_cron extension (not created here):
--   SELECT cron.schedule('expire_reservations', '* * * * *',
--                        'SELECT fn_expire_overdue_reservations()');
-- Without pg_cron, run the function from any scheduler (cron, Task Scheduler).
-- 30-minute grace period: expire reservations that were never activated.
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

-- Keep the RESERVED flag consistent with the reservation table.
CREATE OR REPLACE FUNCTION fn_refresh_reserved_spaces() RETURNS VOID
LANGUAGE sql AS $$
    UPDATE parking_space AS p SET availability_status_code = 'RESERVED'
    WHERE p.availability_status_code = 'AVAILABLE'
      AND EXISTS (SELECT 1 FROM reservation r
                  WHERE r.space_identifier = p.space_identifier
                    AND r.reservation_status_code = 'CONFIRMED'
                    AND r.deleted_datetime IS NULL
                    AND CURRENT_TIMESTAMP >= r.start_datetime
                    AND CURRENT_TIMESTAMP <  r.end_datetime);

    UPDATE parking_space AS p SET availability_status_code = 'AVAILABLE'
    WHERE p.availability_status_code = 'RESERVED'
      AND NOT EXISTS (SELECT 1 FROM reservation r
                      WHERE r.space_identifier = p.space_identifier
                        AND r.reservation_status_code = 'CONFIRMED'
                        AND r.deleted_datetime IS NULL
                        AND CURRENT_TIMESTAMP >= r.start_datetime
                        AND CURRENT_TIMESTAMP <  r.end_datetime);
$$;

-- Requested-window availability (replaces the point-in-time status check).
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
       AND NOT EXISTS (
               SELECT 1 FROM reservation
               WHERE space_identifier = p_space_identifier
                 AND reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
                 AND deleted_datetime IS NULL
                 AND tstzrange(start_datetime, end_datetime)
                     && tstzrange(p_start_datetime, p_end_datetime))
$$;

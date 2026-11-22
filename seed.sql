-- =============================================================================
-- Smart City EV Charging & Parking Management - mock data (DML) - v0.3.1
-- Run AFTER schema.sql on an EMPTY database:
--     psql -d evt -v ON_ERROR_STOP=1 -f schema.sql
--     psql -d evt -v ON_ERROR_STOP=1 -f seed.sql
-- Do not run on the same database as tests.sql (tests.sql inserts its own
-- tariff rows, which would overlap with the ones below; tests.sql ROLLBACKs
-- by itself, so run it BEFORE seed.sql or on a separate database).
--
-- All history is generated through the real triggers (no trigger is disabled),
-- so the data set itself demonstrates the integrity rules:
--   * sessions are inserted open, then closed with UPDATE ... end_datetime,
--     which makes trg_session_finish issue the invoice automatically;
--   * reservations are inserted as CONFIRMED and become FULFILLED through
--     trg_session_start.
-- History is deterministic (md5 of plate + session start, no random() and no
-- generated UUIDs in any digest): 2026-09-01 .. 2026-10-26.
-- A few rows relative to now() (open sessions, upcoming bookings) are added
-- at the end so that "current state" queries return something.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. user_account: 1 ADMIN, 4 MANAGER, 25 CUSTOMER
-- -----------------------------------------------------------------------------
INSERT INTO user_account
    (full_name_text, contact_phone_number, email_address, password_hash_text,
     role_code, created_datetime)
SELECT n.full_name,
       '09' || lpad(n.seq::TEXT, 8, '0'),
       'user' || lpad(n.seq::TEXT, 2, '0') || '@example.com',
       '$2b$12$' || rpad(md5('pw' || n.seq::TEXT), 53, 'x'),
       CASE WHEN n.seq = 1 THEN 'ADMIN'
            WHEN n.seq BETWEEN 2 AND 5 THEN 'MANAGER'
            ELSE 'CUSTOMER' END,
       TIMESTAMPTZ '2026-08-01 08:00:00+07' + (n.seq || ' hours')::INTERVAL
FROM (
    SELECT row_number() OVER () AS seq, full_name
    FROM unnest(ARRAY[
        'Nguyễn Văn An', 'Trần Thị Bình', 'Lê Hoàng Cường', 'Phạm Minh Dũng',
        'Võ Thị Em', 'Đặng Quốc Phong', 'Bùi Thu Giang', 'Hoàng Gia Huy',
        'Ngô Thanh Khoa', 'Dương Mỹ Linh', 'Lý Hữu Minh', 'Phan Ngọc Nga',
        'Vũ Đức Oanh', 'Đỗ Thị Phương', 'Trương Quang Quý', 'Huỳnh Thanh Sơn',
        'Mai Thị Thảo', 'Lâm Văn Út', 'Đinh Công Vinh', 'Tạ Thị Xuân',
        'Châu Minh Yên', 'Cao Bảo Anh', 'Hồ Thế Bảo', 'Lương Diệu Chi',
        'Kiều Anh Đức', 'Thái Quốc Hưng', 'Quách Thị Kim', 'Từ Văn Long',
        'Tôn Nữ Mai', 'Giang Hải Nam'
    ]) AS t(full_name)
) AS n;

-- -----------------------------------------------------------------------------
-- 2. vehicle: 48 vehicles for the 25 customers (accounts 6..30)
-- -----------------------------------------------------------------------------
INSERT INTO vehicle (account_identifier, license_plate_text, battery_capacity_kwh)
SELECT c.account_identifier,
       (50 + (g.n % 9)) || CASE g.n % 3 WHEN 0 THEN 'A' WHEN 1 THEN 'B' ELSE 'F' END
           || '-' || lpad((100 + g.n * 37 % 900)::TEXT, 3, '0')
           || '.' || lpad((g.n * 11 % 100)::TEXT, 2, '0'),
       (ARRAY[42.0, 59.6, 64.8, 75.0, 82.5, 87.7, 100.0])[1 + g.n % 7]
FROM generate_series(1, 48) AS g(n)
JOIN (
    SELECT account_identifier, row_number() OVER (ORDER BY created_datetime) AS rn
    FROM user_account
    WHERE role_code = 'CUSTOMER'
) AS c ON c.rn = 1 + (g.n - 1) % 25;

-- -----------------------------------------------------------------------------
-- 3. parking_facility: 5 facilities, capacity 12 each
-- (coordinates are approximate points in Ho Chi Minh City: longitude, latitude)
-- -----------------------------------------------------------------------------
INSERT INTO parking_facility
    (facility_name_text, geographic_location, address_text, total_capacity_count)
VALUES
    ('EV Hub Quận 1 - Đồng Khởi', ST_SetSRID(ST_MakePoint(106.7019, 10.7769), 4326),
     'Đồng Khởi, Quận 1, TP.HCM', 12),
    ('EV Hub Bình Thạnh - Landmark', ST_SetSRID(ST_MakePoint(106.7218, 10.7950), 4326),
     'Nguyễn Hữu Cảnh, Bình Thạnh, TP.HCM', 12),
    ('EV Hub Quận 7 - Phú Mỹ Hưng', ST_SetSRID(ST_MakePoint(106.7219, 10.7298), 4326),
     'Nguyễn Văn Linh, Quận 7, TP.HCM', 12),
    ('EV Hub Thủ Đức - Khu Công nghệ cao', ST_SetSRID(ST_MakePoint(106.7840, 10.8412), 4326),
     'Xa lộ Hà Nội, TP. Thủ Đức, TP.HCM', 12),
    ('EV Hub Tân Bình - Sân bay', ST_SetSRID(ST_MakePoint(106.6600, 10.8180), 4326),
     'Trường Sơn, Tân Bình, TP.HCM', 12);

-- -----------------------------------------------------------------------------
-- 4. facility_manager (M:N): 4 managers over 5 facilities
-- -----------------------------------------------------------------------------
INSERT INTO facility_manager (manager_identifier, facility_identifier)
SELECT m.account_identifier, f.facility_identifier
FROM (
    SELECT account_identifier, row_number() OVER (ORDER BY created_datetime) AS rn
    FROM user_account WHERE role_code = 'MANAGER'
) AS m
JOIN (
    SELECT facility_identifier, row_number() OVER (ORDER BY facility_name_text) AS rn
    FROM parking_facility
) AS f ON (m.rn, f.rn) IN ((1, 1), (1, 2), (2, 3), (3, 4), (4, 5), (1, 5));

-- -----------------------------------------------------------------------------
-- 5. parking_space: 12 per facility (A-01 .. A-12)
-- -----------------------------------------------------------------------------
INSERT INTO parking_space (facility_identifier, space_code)
SELECT f.facility_identifier, 'A-' || lpad(g.n::TEXT, 2, '0')
FROM parking_facility AS f
CROSS JOIN generate_series(1, 12) AS g(n);

-- -----------------------------------------------------------------------------
-- 6. charging_equipment: spaces A-01..A-08 of each facility have a charger
--    A-01, A-02 : FAST_DC 120 kW      A-03 : FAST_DC 60 kW
--    A-04..A-08 : STANDARD_AC 22 kW (A-07, A-08: 11 kW)
-- -----------------------------------------------------------------------------
INSERT INTO charging_equipment
    (space_identifier, evse_identifier, connector_type_code, max_power_kw)
SELECT s.space_identifier,
       'VN*EVH*' || f.fac_no || '*' || replace(s.space_code, '-', ''),
       CASE WHEN s.num <= 3 THEN 'FAST_DC' ELSE 'STANDARD_AC' END,
       CASE WHEN s.num <= 2 THEN 120.00
            WHEN s.num = 3 THEN 60.00
            WHEN s.num <= 6 THEN 22.00
            ELSE 11.00 END
FROM (
    SELECT facility_identifier, row_number() OVER (ORDER BY facility_name_text) AS fac_no
    FROM parking_facility
) AS f
JOIN (
    SELECT space_identifier, facility_identifier, space_code,
           substr(space_code, 3)::INT AS num
    FROM parking_space
) AS s ON s.facility_identifier = f.facility_identifier
WHERE s.num <= 8;

-- -----------------------------------------------------------------------------
-- 7. tariff_rate: 3 bands x (AC + 2 DC power tiers) = 15 rows, 24 h covered
--    FAST_DC [0,100) kW and [100,1000) kW; STANDARD_AC [0,1000) kW
--    price columns: AC, DC<100, DC>=100  (VND per kWh)
-- -----------------------------------------------------------------------------
INSERT INTO tariff_rate
    (connector_type_code, time_band_code, start_time, end_time,
     min_power_kw, max_power_kw, price_per_kwh_value, overtime_fee_per_hour_value)
SELECT t.connector, b.band, b.s::TIME, b.e::TIME, t.min_kw, t.max_kw,
       b.base_price + t.surcharge, b.overtime
FROM (VALUES
    ('STANDARD_AC',    0.00, 1000.00,    0),
    ('FAST_DC',        0.00,  100.00,  700),
    ('FAST_DC',      100.00, 1000.00, 1500)
) AS t(connector, min_kw, max_kw, surcharge)
CROSS JOIN (VALUES
    ('OFF_PEAK', '00:00', '05:00', 1500, 30000),
    ('STANDARD', '05:00', '17:00', 2000, 45000),
    ('PEAK',     '17:00', '20:00', 2600, 60000),
    ('STANDARD', '20:00', '22:00', 2000, 45000),
    ('OFF_PEAK', '22:00', '24:00', 1500, 30000)
) AS b(band, s, e, base_price, overtime);

-- -----------------------------------------------------------------------------
-- 8. History 2026-09-01 .. 2026-10-26 (56 days) generated through the triggers
--    One slot per charger per day at most; a slot is skipped when the previous
--    one (booking or session) is not over yet, so slots never overlap.
--    Slot kinds (by hash):
--      0-5 reserved + charged   6 walk-in   7 reservation CANCELLED
--      8   reservation EXPIRED  9 reserved + charged + long idle (overtime)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_vehicles   UUID[];
    eq           RECORD;
    v_day        DATE;
    di           INT;
    k            INT;
    h            INT;
    v_kind       INT;
    v_start      TIMESTAMPTZ;
    v_res_hours  NUMERIC;
    v_vehicle    UUID;
    v_battery    NUMERIC;
    v_res        UUID;
    v_session    UUID;
    v_charge_h   NUMERIC;
    v_idle_h     NUMERIC;
    v_full       TIMESTAMPTZ;
    v_end        TIMESTAMPTZ;
    v_energy     NUMERIC;
    v_peak       NUMERIC;
    v_busy_until TIMESTAMPTZ;
    v_hours      INT[];
    v_hour       INT;
BEGIN
    SELECT array_agg(vehicle_identifier ORDER BY license_plate_text)
      INTO v_vehicles
    FROM vehicle;

    -- start-hour distribution (weights for hours 0..23): morning and evening
    -- peaks, quiet at night
    SELECT array_agg(w.hr)
      INTO v_hours
    FROM unnest(ARRAY[1,1,1,1,1,1, 3,5,6,4,3,3, 4,3,3,3,5,8, 9,8,6,4,3,2])
         WITH ORDINALITY AS t(weight, pos)
    CROSS JOIN LATERAL (SELECT t.pos - 1 AS hr FROM generate_series(1, t.weight)) AS w;

    FOR eq IN
        SELECT row_number() OVER (ORDER BY evse_identifier) AS ei,
               equipment_identifier, space_identifier, max_power_kw, evse_identifier
        FROM charging_equipment
        ORDER BY evse_identifier
    LOOP
        v_busy_until := '-infinity';
        FOR di IN 0 .. 55 LOOP
            v_day := DATE '2026-09-01' + di;
            h := ('x' || substr(md5(eq.ei || ':' || di), 1, 7))::BIT(28)::INT;

            -- about 70 % of charger-days have an event
            CONTINUE WHEN h % 100 >= 70;

            -- chargers that are out of order now were already idle for the
            -- last 30 days of history
            CONTINUE WHEN eq.evse_identifier IN ('VN*EVH*3*A04', 'VN*EVH*5*A08',
                                                 'VN*EVH*2*A06')
                      AND v_day >= DATE '2026-09-27';

            v_kind      := (h / 100) % 10;
            v_hour      := v_hours[1 + (h / 1000) % array_length(v_hours, 1)];
            v_start     := (v_day + v_hour * INTERVAL '1 hour'
                            + ((h / 20000) % 4) * INTERVAL '15 minutes')
                           AT TIME ZONE 'Asia/Ho_Chi_Minh';
            v_res_hours := 1 + (h / 80000) % 3;      -- booked window 1..3 h

            -- a charger is never booked again before its previous slot is over
            CONTINUE WHEN v_start < v_busy_until + INTERVAL '30 minutes';
            v_busy_until := v_start + v_res_hours * INTERVAL '1 hour';

            -- a vehicle is never in two places at once: take the first vehicle
            -- (starting from a deterministic preference) with no booking or
            -- session within the next 6 hours
            v_vehicle := NULL;
            FOR k IN 0 .. 47 LOOP
                v_vehicle := v_vehicles[1 + (eq.ei * 7 + di * 13 + k) % 48];
                EXIT WHEN NOT EXISTS (
                    SELECT 1 FROM reservation AS r
                    WHERE r.vehicle_identifier = v_vehicle
                      AND tstzrange(r.start_datetime, r.end_datetime)
                          && tstzrange(v_start - INTERVAL '3 hours',
                                       v_start + INTERVAL '6 hours'))
                AND NOT EXISTS (
                    SELECT 1 FROM service_session AS x
                    WHERE x.vehicle_identifier = v_vehicle
                      AND tstzrange(x.start_datetime,
                                    coalesce(x.end_datetime, 'infinity'))
                          && tstzrange(v_start - INTERVAL '3 hours',
                                       v_start + INTERVAL '6 hours'));
                v_vehicle := NULL;
            END LOOP;
            CONTINUE WHEN v_vehicle IS NULL;

            -- ---- reservation (not for walk-ins) --------------------------------
            v_res := NULL;
            IF v_kind <> 6 THEN
                INSERT INTO reservation
                    (vehicle_identifier, space_identifier, start_datetime,
                     end_datetime, reservation_status_code, created_datetime)
                VALUES
                    (v_vehicle, eq.space_identifier, v_start,
                     v_start + v_res_hours * INTERVAL '1 hour',
                     CASE v_kind WHEN 7 THEN 'CANCELLED'
                                 WHEN 8 THEN 'EXPIRED'
                                 ELSE 'CONFIRMED' END,
                     v_start - ((2 + (h / 500) % 70) * INTERVAL '1 hour'))
                RETURNING reservation_identifier INTO v_res;
            END IF;

            CONTINUE WHEN v_kind IN (7, 8);

            -- ---- session ----------------------------------------------------------
            SELECT battery_capacity_kwh INTO v_battery
            FROM vehicle WHERE vehicle_identifier = v_vehicle;

            v_start := v_start + ((h / 3000) % 9) * INTERVAL '1 minute';
            INSERT INTO service_session
                (reservation_identifier, vehicle_identifier, equipment_identifier,
                 start_datetime)
            VALUES (v_res, v_vehicle, eq.equipment_identifier, v_start)
            RETURNING session_identifier INTO v_session;

            -- energy needed ~ 30..80 % of the battery, limited by charger power
            v_energy   := round(v_battery * (30 + (h / 7000) % 51) / 100.0, 2);
            v_peak     := round(eq.max_power_kw * (80 + (h / 11000) % 16) / 100.0, 2);
            v_charge_h := round(greatest(0.4,
                                         v_energy / (v_peak * 0.75)), 2);
            v_charge_h := least(v_charge_h, 5.0);
            v_energy   := round(least(v_energy, v_peak * 0.75 * v_charge_h), 2);

            -- 70 % of sessions reach full charge; kind 9 stays plugged-in long
            IF v_kind = 9 THEN
                v_idle_h := 1.0 + (h / 13000) % 8 / 4.0;      -- 1.0 .. 2.75 h
            ELSE
                v_idle_h := (h / 13000) % 4 * 0.05;           -- 0 .. 0.15 h
            END IF;

            IF v_kind = 9 OR (h / 17000) % 10 < 7 THEN
                v_full := v_start + v_charge_h * INTERVAL '1 hour';
                v_end  := v_full + v_idle_h * INTERVAL '1 hour';
            ELSE
                v_full := NULL;
                v_end  := v_start + v_charge_h * INTERVAL '1 hour';
            END IF;

            v_busy_until := greatest(v_busy_until, v_end);

            UPDATE service_session
            SET end_datetime           = v_end,
                fully_charged_datetime = v_full,
                peak_charging_power_kw = v_peak,
                consumed_energy_kwh    = v_energy
            WHERE session_identifier = v_session;
        END LOOP;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 9. Payments: invoices were created PENDING by trg_session_finish.
--    Only status / method / gateway reference / created time are updated
--    (amounts are immutable by trg_payment_immutable).
-- -----------------------------------------------------------------------------
UPDATE payment_transaction AS p
SET created_datetime = x.end_datetime + INTERVAL '1 minute',
    transaction_status_code = x.status,
    payment_method_code = CASE WHEN x.status IN ('SUCCESS', 'REFUNDED')
                               THEN x.method END,
    gateway_reference_identifier = CASE WHEN x.status IN ('SUCCESS', 'REFUNDED')
                               THEN 'GW-' || upper(substr(x.digest, 1, 12)) END
FROM (
    SELECT q.transaction_identifier, q.end_datetime, q.digest,
           (ARRAY['E_WALLET', 'CREDIT_CARD', 'E_WALLET', 'BANK_TRANSFER'])
               [1 + ('x' || substr(q.digest, 1, 5))::BIT(20)::INT % 4] AS method,
           CASE
               WHEN q.end_datetime > TIMESTAMPTZ '2026-10-24 00:00:00+07'
                    THEN 'PENDING'
               WHEN ('x' || substr(q.digest, 6, 5))::BIT(20)::INT % 100 < 4
                    THEN 'FAILED'
               WHEN ('x' || substr(q.digest, 6, 5))::BIT(20)::INT % 100 < 8
                    THEN 'REFUNDED'
               ELSE 'SUCCESS'
           END AS status
    FROM (
        SELECT t.transaction_identifier, s.end_datetime,
               md5(v.license_plate_text || ':'
                   || extract(epoch FROM s.start_datetime)::TEXT) AS digest
        FROM payment_transaction AS t
        JOIN service_session AS s ON s.session_identifier = t.session_identifier
        JOIN vehicle AS v ON v.vehicle_identifier = s.vehicle_identifier
    ) AS q
) AS x
WHERE p.transaction_identifier = x.transaction_identifier;

-- -----------------------------------------------------------------------------
-- 10. Current state (relative to now()): open sessions, upcoming bookings,
--     one overdue PENDING booking, faulty / maintenance chargers
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_vehicles UUID[];
    eq         RECORD;
    k          INT := 0;
BEGIN
    SELECT array_agg(vehicle_identifier ORDER BY license_plate_text DESC)
      INTO v_vehicles
    FROM vehicle;

    -- 7 walk-in sessions currently running (chargers 3,9,15,21,27,33,39 by evse order)
    FOR eq IN
        SELECT row_number() OVER (ORDER BY evse_identifier) AS ei,
               equipment_identifier, space_identifier, max_power_kw
        FROM charging_equipment ORDER BY evse_identifier
    LOOP
        IF eq.ei % 6 = 3 THEN
            k := k + 1;
            INSERT INTO service_session
                (vehicle_identifier, equipment_identifier, start_datetime,
                 peak_charging_power_kw, consumed_energy_kwh)
            VALUES
                (v_vehicles[k], eq.equipment_identifier,
                 now() - (15 + k * 12) * INTERVAL '1 minute',
                 round(eq.max_power_kw * 0.85, 2), 0);

            -- the next customer already booked this space shortly after
            IF k <= 3 THEN
                INSERT INTO reservation
                    (vehicle_identifier, space_identifier, start_datetime,
                     end_datetime, reservation_status_code, created_datetime)
                VALUES
                    (v_vehicles[30 + k], eq.space_identifier,
                     now() + (30 + k * 20) * INTERVAL '1 minute',
                     now() + (150 + k * 20) * INTERVAL '1 minute',
                     'CONFIRMED', now() - INTERVAL '1 day');
            END IF;
        END IF;
    END LOOP;

    -- upcoming CONFIRMED bookings on charger spaces that are not in use
    FOR eq IN
        SELECT row_number() OVER (ORDER BY evse_identifier) AS ei, space_identifier
        FROM charging_equipment ORDER BY evse_identifier
    LOOP
        IF eq.ei % 6 = 5 THEN
            INSERT INTO reservation
                (vehicle_identifier, space_identifier, start_datetime, end_datetime,
                 reservation_status_code, created_datetime)
            VALUES
                (v_vehicles[10 + eq.ei / 6], eq.space_identifier,
                 now() + (1 + eq.ei % 5) * INTERVAL '1 hour',
                 now() + (3 + eq.ei % 5) * INTERVAL '1 hour',
                 CASE WHEN eq.ei % 12 = 5 THEN 'CONFIRMED' ELSE 'PENDING' END,
                 now() - INTERVAL '30 minutes');
        END IF;
    END LOOP;

    -- one PENDING booking already 45 minutes late (will be EXPIRED by the job)
    INSERT INTO reservation
        (vehicle_identifier, space_identifier, start_datetime, end_datetime,
         reservation_status_code, created_datetime)
    SELECT v_vehicles[48], s.space_identifier,
           now() - INTERVAL '45 minutes', now() + INTERVAL '75 minutes',
           'PENDING', now() - INTERVAL '3 hours'
    FROM parking_space AS s
    JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
    WHERE s.space_code = 'A-11'
    ORDER BY f.facility_name_text
    LIMIT 1;

    -- parking-only bookings on spaces without a charger (A-10)
    INSERT INTO reservation
        (vehicle_identifier, space_identifier, start_datetime, end_datetime,
         reservation_status_code, created_datetime)
    SELECT v_vehicles[20 + n.rn::INT], s.space_identifier,
           now() + (1 + n.rn) * INTERVAL '1 day',
           now() + (1 + n.rn) * INTERVAL '1 day' + INTERVAL '4 hours',
           'CONFIRMED', now() - INTERVAL '2 hours'
    FROM (SELECT space_identifier, row_number() OVER (ORDER BY space_identifier) AS rn
          FROM parking_space WHERE space_code = 'A-10') AS s
    JOIN (SELECT generate_series(1, 5) AS rn) AS n ON n.rn = s.rn;
END $$;

-- chargers out of order (trg_equipment_status_sync marks their spaces OUTOFSERVICE)
UPDATE charging_equipment SET equipment_status_code = 'FAULT'
WHERE evse_identifier = 'VN*EVH*3*A04';
UPDATE charging_equipment SET equipment_status_code = 'MAINTENANCE'
WHERE evse_identifier IN ('VN*EVH*5*A08', 'VN*EVH*2*A06');

-- one customer account and one of their vehicles are soft-deleted (history kept)
UPDATE vehicle SET deleted_datetime = TIMESTAMPTZ '2026-10-20 09:00:00+07'
WHERE vehicle_identifier = (SELECT vehicle_identifier FROM vehicle
                            ORDER BY license_plate_text LIMIT 1 OFFSET 30)
  AND NOT EXISTS (SELECT 1 FROM service_session s
                  WHERE s.vehicle_identifier = vehicle.vehicle_identifier
                    AND s.end_datetime IS NULL);

-- refresh RESERVED flags from the reservation table
SELECT fn_refresh_reserved_spaces();

COMMIT;

-- Summary of what was loaded
SELECT 'user_account' AS table_name, count(*) AS row_count FROM user_account
UNION ALL SELECT 'vehicle', count(*) FROM vehicle
UNION ALL SELECT 'parking_facility', count(*) FROM parking_facility
UNION ALL SELECT 'facility_manager', count(*) FROM facility_manager
UNION ALL SELECT 'parking_space', count(*) FROM parking_space
UNION ALL SELECT 'charging_equipment', count(*) FROM charging_equipment
UNION ALL SELECT 'tariff_rate', count(*) FROM tariff_rate
UNION ALL SELECT 'reservation', count(*) FROM reservation
UNION ALL SELECT 'service_session', count(*) FROM service_session
UNION ALL SELECT 'payment_transaction', count(*) FROM payment_transaction;

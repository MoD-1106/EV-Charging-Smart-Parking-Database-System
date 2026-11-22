-- =============================================================================
-- Self-checking tests for schema.sql  (run: psql -v ON_ERROR_STOP=1 -f tests.sql)
-- Each test raises an exception when the expectation fails.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE t_ids (k TEXT PRIMARY KEY, id UUID);

-- helper: statement must fail with the given SQLSTATE (several allowed, comma-separated)
CREATE FUNCTION pg_temp.expect_error(p_sql TEXT, p_state TEXT, p_name TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = ANY (string_to_array(p_state, ',')) THEN
            RAISE NOTICE 'PASS  %  (got %)', p_name, SQLSTATE;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL  %: expected %, got % (%)', p_name, p_state, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL  %: statement succeeded but should fail', p_name;
END $$;

CREATE FUNCTION pg_temp.expect_true(p_cond BOOLEAN, p_name TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL  %', p_name; END IF;
    RAISE NOTICE 'PASS  %', p_name;
END $$;

-- ---- seed -------------------------------------------------------------------
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number,
                          email_address, password_hash_text, role_code) VALUES
 ('00000000-0000-0000-0000-0000000000a1','Nguyen Van A','+84901000001','a@x.vn','h','CUSTOMER'),
 ('00000000-0000-0000-0000-0000000000a2','Tran Thi B',  '+84901000002','b@x.vn','h','MANAGER'),
 ('00000000-0000-0000-0000-0000000000a3','Admin',        '+84901000003','c@x.vn','h','ADMIN'),
 ('00000000-0000-0000-0000-0000000000a4','Le Van D',     '+84901000004','d@x.vn','h','CUSTOMER');

INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','51H-123.45',82.00),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a4','51K-999.99',60.00);

INSERT INTO parking_facility (facility_identifier, facility_name_text, geographic_location,
                              address_text, total_capacity_count) VALUES
 ('00000000-0000-0000-0000-0000000000c1','Vincom Dong Khoi',
  ST_SetSRID(ST_MakePoint(106.7019, 10.7769), 4326),'72 Le Thanh Ton, Q1',2);

INSERT INTO parking_space (space_identifier, facility_identifier, space_code) VALUES
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000c1','A-01'),
 ('00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000c1','A-02');

INSERT INTO charging_equipment (equipment_identifier, space_identifier, evse_identifier,
                                connector_type_code, max_power_kw) VALUES
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000d1','VN*EVSE*E00001','FAST_DC',120),
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000d2','VN*EVSE*E00002','STANDARD_AC',22);

-- Tariff: PEAK 17-20, OFF_PEAK 22-05 (split at midnight), STANDARD elsewhere
INSERT INTO tariff_rate (connector_type_code, time_band_code, start_time, end_time,
                         min_power_kw, max_power_kw, price_per_kwh_value, overtime_fee_per_hour_value)
SELECT c.code, b.band, b.s::TIME, b.e::TIME, 0, 1000,
       CASE c.code WHEN 'FAST_DC' THEN b.fast ELSE b.ac END, b.ot
FROM (VALUES ('FAST_DC'), ('STANDARD_AC')) AS c(code)
CROSS JOIN (VALUES
    ('OFF_PEAK','00:00','05:00', 2500, 1500, 30000),
    ('STANDARD','05:00','17:00', 3200, 2000, 45000),
    ('PEAK',    '17:00','20:00', 4000, 2600, 60000),
    ('STANDARD','20:00','22:00', 3200, 2000, 45000),
    ('OFF_PEAK','22:00','24:00', 2500, 1500, 30000)
) AS b(band, s, e, fast, ac, ot);

-- ---- constraints --------------------------------------------------------------
SELECT pg_temp.expect_true((SELECT count(*) FROM tariff_rate) = 10, 'tariff seed: 24h fully covered per connector (5 bands x 2)');

SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,time_band_code,start_time,end_time,
    min_power_kw,max_power_kw,price_per_kwh_value) VALUES ('FAST_DC','PEAK','18:00','19:00',0,50,1)$$,
    '23P01','tariff overlap (time AND power) rejected');

SELECT pg_temp.expect_error($$INSERT INTO user_account (full_name_text,contact_phone_number,email_address,password_hash_text)
    VALUES ('dup','+84901000009','A@X.VN','h')$$,'23505','email unique, case-insensitive');

SELECT pg_temp.expect_error($$INSERT INTO parking_space (facility_identifier,space_code)
    VALUES ('00000000-0000-0000-0000-0000000000c1','A-03')$$,'23514','capacity trigger (3rd space in capacity-2 facility)');

SELECT pg_temp.expect_error($$INSERT INTO facility_manager VALUES
    ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000c1')$$,'23514','CUSTOMER cannot manage a facility');
INSERT INTO facility_manager VALUES ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000c1');

SELECT pg_temp.expect_error($$INSERT INTO charging_equipment (space_identifier,evse_identifier,connector_type_code,max_power_kw)
    VALUES ('00000000-0000-0000-0000-0000000000d1','VN*EVSE*E00003','FAST_DC',50)$$,'23505','1:1 space-equipment');

-- ---- reservations -------------------------------------------------------------
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000d1',
        now() + INTERVAL '2 hours', now() + INTERVAL '3 hours', 'CONFIRMED');

SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d1',
            now() + INTERVAL '150 minutes', now() + INTERVAL '4 hours')$$,'23P01','overlapping booking rejected');

SELECT pg_temp.expect_true(NOT fn_is_space_available('00000000-0000-0000-0000-0000000000d1', now()+INTERVAL '150 minutes', now()+INTERVAL '4 hours'),
    'fn_is_space_available false inside booked window');
SELECT pg_temp.expect_true(fn_is_space_available('00000000-0000-0000-0000-0000000000d1', now()+INTERVAL '3 hours', now()+INTERVAL '4 hours'),
    'fn_is_space_available true on adjacent window');

SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d1', now(), now())$$,'23514','end must be after start');

-- cancelled booking frees the window
UPDATE reservation SET reservation_status_code = 'CANCELLED'
WHERE reservation_identifier = '00000000-0000-0000-0000-0000000000f1';
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d1',
        now() + INTERVAL '2 hours', now() + INTERVAL '3 hours', 'CONFIRMED');
SELECT pg_temp.expect_true(true, 'cancelled booking releases the time window');

-- 30-minute grace period
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f3','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000d2',
        now() - INTERVAL '45 minutes', now() + INTERVAL '1 hour', 'CONFIRMED'),
       ('00000000-0000-0000-0000-0000000000f4','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d2',
        now() + INTERVAL '5 hours', now() + INTERVAL '6 hours', 'CONFIRMED');
SELECT pg_temp.expect_true(fn_expire_overdue_reservations() = 1, 'only the booking older than 30 min expires');
SELECT pg_temp.expect_true((SELECT reservation_status_code FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000000f3')='EXPIRED', 'status = EXPIRED');
SELECT pg_temp.expect_true((SELECT reservation_status_code FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000000f4')='CONFIRMED', 'future booking untouched');

-- ---- equipment <-> space sync --------------------------------------------------
UPDATE charging_equipment SET equipment_status_code='FAULT' WHERE equipment_identifier='00000000-0000-0000-0000-0000000000e2';
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d2')='OUTOFSERVICE', 'FAULT -> space OUTOFSERVICE');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d2', now()+INTERVAL '9 hours', now()+INTERVAL '10 hours')$$,
    '23514','cannot book OUTOFSERVICE space');
UPDATE charging_equipment SET equipment_status_code='READY' WHERE equipment_identifier='00000000-0000-0000-0000-0000000000e2';
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d2')='AVAILABLE', 'READY -> space AVAILABLE again');

-- ---- sessions, invoice, walk-in conflict --------------------------------------
-- walk-in at A-01 while f2 (other customer) holds the slot now+2h..+3h : start inside window => rejected
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier,start_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000e1', now()+INTERVAL '150 minutes')$$,
    '23P01','walk-in cannot start inside someone else''s booking');

-- Session with reservation: 2026-10-28 18:00 +07 (PEAK), 45.5 kWh, full at 19:00, unplug 19:30
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f5','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000d1',
        '2020-01-01 18:00+07','2020-01-01 19:30+07','CONFIRMED');
INSERT INTO service_session (session_identifier, reservation_identifier, vehicle_identifier, equipment_identifier, start_datetime)
VALUES ('00000000-0000-0000-0000-000000000051','00000000-0000-0000-0000-0000000000f5','00000000-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-0000000000e1','2020-01-01 18:00+07');
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d1')='OCCUPIED', 'session start -> OCCUPIED');
SELECT pg_temp.expect_true((SELECT equipment_status_code FROM charging_equipment WHERE equipment_identifier='00000000-0000-0000-0000-0000000000e1')='CHARGING', 'session start -> CHARGING');
SELECT pg_temp.expect_true((SELECT reservation_status_code FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000000f5')='FULFILLED', 'reservation -> FULFILLED');

SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier,start_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000e1','2020-01-01 18:05+07')$$,
    '23505','one open session per charger');

UPDATE service_session SET consumed_energy_kwh=45.50, peak_charging_power_kw=110,
       fully_charged_datetime='2020-01-01 19:00+07', end_datetime='2020-01-01 19:30+07'
WHERE session_identifier='00000000-0000-0000-0000-000000000051';

SELECT pg_temp.expect_true((SELECT energy_amount_value FROM payment_transaction)=182000.00, 'energy = 45.5 x 4000 = 182,000 (doc example)');
SELECT pg_temp.expect_true((SELECT overtime_amount_value FROM payment_transaction)=30000.00, 'overtime = 0.5 h x 60,000');
SELECT pg_temp.expect_true((SELECT transaction_amount_value FROM payment_transaction)=212000.00, 'total = energy + overtime');
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d1')='AVAILABLE', 'session end -> AVAILABLE');

-- off-peak midnight-crossing band: 23:30 local on the AC charger
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime)
VALUES ('00000000-0000-0000-0000-000000000052','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000e2','2020-01-02 23:30+07');
UPDATE service_session SET consumed_energy_kwh=10, end_datetime='2020-01-03 01:00+07' WHERE session_identifier='00000000-0000-0000-0000-000000000052';
SELECT pg_temp.expect_true((SELECT energy_amount_value FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000052')=15000.00, 'AC off-peak 23:30 -> 1,500/kWh');

-- ---- immutability / audit ------------------------------------------------------
SELECT pg_temp.expect_error($$DELETE FROM payment_transaction$$,'23001','payment cannot be deleted');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET energy_amount_value=1, transaction_amount_value=1$$,'23001','invoice amounts immutable');
-- ON DELETE RESTRICT: PostgreSQL 17 and older report 23503 (foreign_key_violation),
-- PostgreSQL 18 reports 23001 (restrict_violation).
SELECT pg_temp.expect_error($$DELETE FROM service_session$$,'23503,23001','session with invoice cannot be deleted (FK RESTRICT)');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='SUCCESS'$$,'23514','SUCCESS requires method + gateway reference');
UPDATE payment_transaction SET transaction_status_code='SUCCESS', payment_method_code='E_WALLET', gateway_reference_identifier='MOMO-123'
WHERE session_identifier='00000000-0000-0000-0000-000000000051';
SELECT pg_temp.expect_true(true, 'payment status can move to SUCCESS');

-- ---- soft delete frees unique keys ---------------------------------------------
UPDATE vehicle SET deleted_datetime=now() WHERE vehicle_identifier='00000000-0000-0000-0000-0000000000b2';
INSERT INTO vehicle (account_identifier, license_plate_text, battery_capacity_kwh)
VALUES ('00000000-0000-0000-0000-0000000000a4','51K-999.99',60);
SELECT pg_temp.expect_true(true, 'soft-deleted plate can be re-registered');

DO $$ BEGIN RAISE NOTICE 'ALL TESTS PASSED'; END $$;
ROLLBACK;

-- =============================================================================
-- Kiểm thử tự đối chiếu cho schema.sql  (chạy: psql -v ON_ERROR_STOP=1 -f tests.sql)
-- Mỗi kiểm thử ném ngoại lệ khi kết quả không như mong đợi.
-- =============================================================================
BEGIN;

CREATE TEMP TABLE t_ids (k TEXT PRIMARY KEY, id UUID);

-- hàm phụ: câu lệnh phải lỗi với SQLSTATE cho trước (cho phép nhiều mã, cách nhau bằng dấu phẩy)
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

-- ---- dữ liệu mồi ------------------------------------------------------------
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

-- Biểu giá: khung giờ khai báo một lần (time_band, time_band_window),
-- giá theo (loại cổng, dải công suất, khung). PEAK 17-20, OFF_PEAK 22-05, còn lại STANDARD
INSERT INTO time_band (time_band_code, time_band_name) VALUES
 ('OFF_PEAK','Thấp điểm'), ('STANDARD','Bình thường'), ('PEAK','Cao điểm');
INSERT INTO time_band_window (start_time, end_time, time_band_code) VALUES
 ('00:00','05:00','OFF_PEAK'), ('05:00','17:00','STANDARD'), ('17:00','20:00','PEAK'),
 ('20:00','22:00','STANDARD'), ('22:00','24:00','OFF_PEAK');
INSERT INTO power_tier (connector_type_code, min_power_kw, max_power_kw) VALUES
 ('FAST_DC', 0, 1000), ('STANDARD_AC', 0, 1000);
INSERT INTO tariff_rate (connector_type_code, min_power_kw, time_band_code,
                         price_per_kwh_value, overtime_fee_per_hour_value, effective_from)
SELECT c.code, 0, b.band, CASE c.code WHEN 'FAST_DC' THEN b.fast ELSE b.ac END, b.ot, '2000-01-01'
FROM (VALUES ('FAST_DC'), ('STANDARD_AC')) AS c(code)
CROSS JOIN (VALUES ('OFF_PEAK', 2500, 1500, 30000), ('STANDARD', 3200, 2000, 45000),
                   ('PEAK', 4000, 2600, 60000)) AS b(band, fast, ac, ot);
INSERT INTO parking_rate (time_band_code, price_per_hour_value, effective_from) VALUES
 ('OFF_PEAK', 10000, '2000-01-01'), ('STANDARD', 15000, '2000-01-01'), ('PEAK', 20000, '2000-01-01');

-- ---- ràng buộc ----------------------------------------------------------------
SELECT pg_temp.expect_true((SELECT sum(extract(epoch FROM end_time - start_time)) FROM time_band_window) = 86400,
    'time band windows cover 24 hours exactly once');
SELECT pg_temp.expect_true((SELECT count(*) FROM tariff_rate) = 6, 'one price per connector and band (2 x 3)');
SELECT pg_temp.expect_error($$INSERT INTO time_band_window VALUES ('18:00','23:00','PEAK')$$,
    '23P01','overlapping time band windows rejected');
SELECT pg_temp.expect_error($$INSERT INTO time_band_window VALUES ('23:00','21:00','PEAK')$$,
    '23514','time band window must end after it starts');
SELECT pg_temp.expect_error($$INSERT INTO time_band VALUES ('NIGHT','Đêm')$$,
    '23514','unknown time band code rejected');
SELECT pg_temp.expect_error($$UPDATE time_band_window SET time_band_code='NIGHT' WHERE start_time='17:00'$$,
    '23503','time band window must reference a time band');
SELECT pg_temp.expect_error($$DELETE FROM time_band WHERE time_band_code='PEAK'$$,
    '23503','time band in use cannot be deleted');
SELECT pg_temp.expect_error($$INSERT INTO power_tier VALUES ('FAST_DC',500,2000)$$,
    '23P01','power tiers of one connector type cannot overlap');
SELECT pg_temp.expect_error($$INSERT INTO power_tier VALUES ('CHADEMO',0,10)$$,
    '23514','unknown connector type rejected');
SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,
    price_per_kwh_value,effective_from) VALUES ('FAST_DC',0,'PEAK',1,'2026-06-01')$$,
    '23P01','two price versions of one cell cannot overlap in time');
SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,
    price_per_kwh_value,effective_from) VALUES ('FAST_DC',0,'NIGHT',1,'2026-06-01')$$,
    '23503','tariff must reference a time band');
SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,
    price_per_kwh_value,effective_from) VALUES ('FAST_DC',5,'PEAK',1,'2026-06-01')$$,
    '23503','tariff must reference a power tier');
SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,
    price_per_kwh_value,effective_from,effective_to) VALUES ('FAST_DC',0,'PEAK',1,'2026-06-01','2026-05-01')$$,
    '23514','a price version must end after it starts');
SELECT pg_temp.expect_error($$UPDATE tariff_rate SET price_per_kwh_value = 1$$,
    '23001','a price version is never edited in place');
SELECT pg_temp.expect_error($$INSERT INTO parking_rate (time_band_code,price_per_hour_value,effective_from)
    VALUES ('PEAK',1,'2026-06-01')$$,'23P01','two parking price versions of one band cannot overlap');
SELECT pg_temp.expect_true(NOT EXISTS (
    SELECT 1 FROM pg_constraint AS c
    WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace
      AND NOT EXISTS (SELECT 1 FROM pg_index AS i
                      WHERE i.indrelid = c.conrelid AND i.indpred IS NULL
                        AND i.indkey[0] = c.conkey[1])),
    'every foreign key has a full index on its leading column');
-- lịch khung giờ phải phủ kín 24 giờ (kiểm tra khi kết thúc giao dịch)
SET CONSTRAINTS trg_time_band_window_coverage IMMEDIATE;
SELECT pg_temp.expect_error($$DELETE FROM time_band_window WHERE start_time='20:00'$$,
    '23514','a gap in the time band schedule is rejected');
SET CONSTRAINTS trg_time_band_window_coverage DEFERRED;

SELECT pg_temp.expect_error($$INSERT INTO user_account (full_name_text,contact_phone_number,email_address,password_hash_text)
    VALUES ('dup','+84901000009','A@X.VN','h')$$,'23505','email unique, case-insensitive');

SELECT pg_temp.expect_error($$INSERT INTO parking_space (facility_identifier,space_code)
    VALUES ('00000000-0000-0000-0000-0000000000c1','A-03')$$,'23514','capacity trigger (3rd space in capacity-2 facility)');

SELECT pg_temp.expect_error($$INSERT INTO facility_manager VALUES
    ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000c1')$$,'23514','CUSTOMER cannot manage a facility');
INSERT INTO facility_manager VALUES ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000c1');

SELECT pg_temp.expect_error($$INSERT INTO charging_equipment (space_identifier,evse_identifier,connector_type_code,max_power_kw)
    VALUES ('00000000-0000-0000-0000-0000000000d1','VN*EVSE*E00003','FAST_DC',50)$$,'23505','1:1 space-equipment');

-- ---- đặt chỗ ------------------------------------------------------------------
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

-- lượt đặt đã hủy trả lại khung giờ
UPDATE reservation SET reservation_status_code = 'CANCELLED'
WHERE reservation_identifier = '00000000-0000-0000-0000-0000000000f1';
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d1',
        now() + INTERVAL '2 hours', now() + INTERVAL '3 hours', 'CONFIRMED');
SELECT pg_temp.expect_true(true, 'cancelled booking releases the time window');

-- thời gian ân hạn 30 phút
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code)
VALUES ('00000000-0000-0000-0000-0000000000f3','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000d2',
        now() - INTERVAL '45 minutes', now() + INTERVAL '1 hour', 'CONFIRMED'),
       ('00000000-0000-0000-0000-0000000000f4','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d2',
        now() + INTERVAL '5 hours', now() + INTERVAL '6 hours', 'CONFIRMED');
SELECT pg_temp.expect_true(fn_expire_overdue_reservations() = 1, 'only the booking older than 30 min expires');
SELECT pg_temp.expect_true((SELECT reservation_status_code FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000000f3')='EXPIRED', 'status = EXPIRED');
SELECT pg_temp.expect_true((SELECT reservation_status_code FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000000f4')='CONFIRMED', 'future booking untouched');

-- ---- đồng bộ thiết bị <-> ô đỗ -------------------------------------------------
UPDATE charging_equipment SET equipment_status_code='FAULT' WHERE equipment_identifier='00000000-0000-0000-0000-0000000000e2';
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d2')='OUTOFSERVICE', 'FAULT -> space OUTOFSERVICE');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000d2', now()+INTERVAL '9 hours', now()+INTERVAL '10 hours')$$,
    '23514','cannot book OUTOFSERVICE space');
UPDATE charging_equipment SET equipment_status_code='READY' WHERE equipment_identifier='00000000-0000-0000-0000-0000000000e2';
SELECT pg_temp.expect_true((SELECT availability_status_code FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000000d2')='AVAILABLE', 'READY -> space AVAILABLE again');

-- ---- phiên sạc, hóa đơn, xung đột khách vãng lai ------------------------------
-- vãng lai tại A-01 khi f2 (khách khác) giữ khung now+2h..+3h : bắt đầu trong khung => bị từ chối
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier,start_datetime)
    VALUES ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000e1', now()+INTERVAL '150 minutes')$$,
    '23P01','walk-in cannot start inside someone else''s booking');

-- Phiên có đặt chỗ: 2026-10-28 18:00 +07 (PEAK), 45.5 kWh, đầy lúc 19:00, rút sạc 19:30
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

-- khung thấp điểm vắt qua nửa đêm: 23:30 giờ địa phương trên trụ AC
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime)
VALUES ('00000000-0000-0000-0000-000000000052','00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000e2','2020-01-02 23:30+07');
UPDATE service_session SET consumed_energy_kwh=10, end_datetime='2020-01-03 01:00+07' WHERE session_identifier='00000000-0000-0000-0000-000000000052';
SELECT pg_temp.expect_true((SELECT energy_amount_value FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000052')=15000.00, 'AC off-peak 23:30 -> 1,500/kWh');

-- ---- bất biến / kiểm toán ------------------------------------------------------
SELECT pg_temp.expect_error($$DELETE FROM payment_transaction$$,'23001','payment cannot be deleted');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET energy_amount_value=1, transaction_amount_value=1$$,'23001','invoice amounts immutable');
-- ON DELETE RESTRICT: PostgreSQL 17 trở xuống báo 23503 (foreign_key_violation),
-- PostgreSQL 18 báo 23001 (restrict_violation).
SELECT pg_temp.expect_error($$DELETE FROM service_session$$,'23503,23001','session with invoice cannot be deleted (FK RESTRICT)');
-- thanh toán: khách trả (PROCESSING) rồi quản lý bãi xác nhận
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='SUCCESS', payment_method_code='E_WALLET', gateway_reference_identifier='MOMO-0'
  WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23001','invoice cannot jump to SUCCESS without manager confirmation');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='PROCESSING' WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23514','payment requires method + gateway reference');
UPDATE payment_transaction SET transaction_status_code='PROCESSING', payment_method_code='E_WALLET', gateway_reference_identifier='MOMO-123'
WHERE session_identifier='00000000-0000-0000-0000-000000000051';
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='SUCCESS' WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23514','confirmation must name the manager');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='SUCCESS', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a1' WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23514','a customer cannot confirm a payment');
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text, role_code) VALUES
 ('00000000-0000-0000-0000-0000000000a5','Quan Ly Bai Khac','+84901000005','e@x.vn','h','MANAGER');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='SUCCESS', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23514','manager of another facility cannot confirm');
UPDATE payment_transaction SET transaction_status_code='SUCCESS', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a2' WHERE session_identifier='00000000-0000-0000-0000-000000000051';
SELECT pg_temp.expect_true((SELECT transaction_status_code='SUCCESS' AND confirmed_by_identifier='00000000-0000-0000-0000-0000000000a2' AND confirmed_datetime IS NOT NULL
   FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000051'), 'manager of the facility confirms the payment');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET confirmed_by_identifier=NULL WHERE session_identifier='00000000-0000-0000-0000-000000000051'$$,'23001','who confirmed a paid invoice is fixed');

-- ---- xóa mềm giải phóng khóa duy nhất ------------------------------------------
UPDATE vehicle SET deleted_datetime=now() WHERE vehicle_identifier='00000000-0000-0000-0000-0000000000b2';
INSERT INTO vehicle (account_identifier, license_plate_text, battery_capacity_kwh)
VALUES ('00000000-0000-0000-0000-0000000000a4','51K-999.99',60);
SELECT pg_temp.expect_true(true, 'soft-deleted plate can be re-registered');

-- ---- quy tắc bổ sung ----------------------------------------------------------
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text) VALUES
 ('00000000-0000-0000-0000-0000000009a1','Khach Bo Sung','+84901000091','bs@x.vn','h');
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES
 ('00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009a1','59A-000.01',60),
 ('00000000-0000-0000-0000-0000000009b2','00000000-0000-0000-0000-0000000009a1','59A-000.02',60),
 ('00000000-0000-0000-0000-0000000009b3','00000000-0000-0000-0000-0000000009a1','59A-000.03',60);
INSERT INTO parking_facility (facility_identifier, facility_name_text, geographic_location, address_text, total_capacity_count) VALUES
 ('00000000-0000-0000-0000-0000000009c1','Bai kiem thu',ST_SetSRID(ST_MakePoint(106.70, 10.77), 4326),'Q1',4);
INSERT INTO parking_space (space_identifier, facility_identifier, space_code)
SELECT ('00000000-0000-0000-0000-0000000009d' || n)::uuid, '00000000-0000-0000-0000-0000000009c1', 'T-0' || n FROM generate_series(1,4) n;
INSERT INTO charging_equipment (equipment_identifier, space_identifier, evse_identifier, connector_type_code, max_power_kw)
SELECT ('00000000-0000-0000-0000-0000000009e' || n)::uuid, ('00000000-0000-0000-0000-0000000009d' || n)::uuid, 'VN*TEST*' || n, 'FAST_DC', 60 FROM generate_series(1,4) n;

SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,price_per_kwh_value,effective_from,effective_to)
 VALUES ('FAST_DC',0,'PEAK','NaN','1980-01-01','1980-02-01')$$,'23514','price NaN rejected');
SELECT pg_temp.expect_error($$INSERT INTO tariff_rate (connector_type_code,min_power_kw,time_band_code,price_per_kwh_value,overtime_fee_per_hour_value,effective_from,effective_to)
 VALUES ('FAST_DC',0,'PEAK',1,'NaN','1980-01-01','1980-02-01')$$,'23514','overtime NaN rejected');
SELECT pg_temp.expect_error($$UPDATE parking_facility SET total_capacity_count=3 WHERE facility_identifier='00000000-0000-0000-0000-0000000009c1'$$,'23514','capacity cannot drop below existing spaces');

INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code) VALUES
 ('00000000-0000-0000-0000-0000000009f1','00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009d1', now()+INTERVAL '5 days', now()+INTERVAL '5 days 1 hour','PENDING');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
 VALUES ('00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009d2', now()+INTERVAL '5 days', now()+INTERVAL '5 days 1 hour')$$,'23P01','one vehicle cannot hold two overlapping bookings');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
 VALUES ('00000000-0000-0000-0000-0000000009b2','00000000-0000-0000-0000-0000000009d2', now()+INTERVAL '10 days', now()+INTERVAL '11 days 1 minute')$$,'23514','booking longer than 24h rejected');
SELECT pg_temp.expect_error($$INSERT INTO service_session (reservation_identifier,vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-0000000009f1','00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009e1')$$,'23514','booked session cannot start days early');
UPDATE reservation SET reservation_status_code='CANCELLED' WHERE reservation_identifier='00000000-0000-0000-0000-0000000009f1';
SELECT pg_temp.expect_error($$UPDATE reservation SET reservation_status_code='CONFIRMED' WHERE reservation_identifier='00000000-0000-0000-0000-0000000009f1'$$,'23514','cancelled booking cannot be revived');

-- lượt đặt sắp đến chặn khách vãng lai
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code) VALUES
 ('00000000-0000-0000-0000-0000000009f2','00000000-0000-0000-0000-0000000009b2','00000000-0000-0000-0000-0000000009d2', now()+INTERVAL '10 minutes', now()+INTERVAL '2 hours','CONFIRMED');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-0000000009b3','00000000-0000-0000-0000-0000000009e2')$$,'23P01','walk-in blocked shortly before a booking');

-- cờ RESERVED tự khớp
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime) VALUES
 ('00000000-0000-0000-0000-0000000009f3','00000000-0000-0000-0000-0000000009b3','00000000-0000-0000-0000-0000000009d3', now()-INTERVAL '1 minute', now()+INTERVAL '1 hour');
UPDATE reservation SET reservation_status_code='CONFIRMED' WHERE reservation_identifier='00000000-0000-0000-0000-0000000009f3';
SELECT pg_temp.expect_true((SELECT availability_status_code='RESERVED' FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000009d3'),'space shows RESERVED right after confirm');
UPDATE reservation SET reservation_status_code='CANCELLED' WHERE reservation_identifier='00000000-0000-0000-0000-0000000009f3';
SELECT pg_temp.expect_true((SELECT availability_status_code='AVAILABLE' FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-0000000009d3'),'space freed right after cancel');

-- phiên đang mở
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime) VALUES
 ('00000000-0000-0000-0000-000000000951','00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009e3', now()-INTERVAL '10 minutes');
SELECT pg_temp.expect_true(NOT fn_is_space_available('00000000-0000-0000-0000-0000000009d3', now()+INTERVAL '1 minute', now()+INTERVAL '1 hour'),'charging space is not available now');
SELECT pg_temp.expect_true(fn_is_space_available('00000000-0000-0000-0000-0000000009d3', now()+INTERVAL '3 hours', now()+INTERVAL '4 hours'),'charging space still bookable later');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
 VALUES ('00000000-0000-0000-0000-0000000009b3','00000000-0000-0000-0000-0000000009d3', now()+INTERVAL '1 minute', now()+INTERVAL '1 hour')$$,'23P01','cannot book a space that is charging right now');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-0000000009b1','00000000-0000-0000-0000-0000000009e4')$$,'23505','one vehicle cannot charge at two chargers');
UPDATE service_session SET consumed_energy_kwh=5, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000951';
SELECT pg_temp.expect_error($$UPDATE service_session SET consumed_energy_kwh=50 WHERE session_identifier='00000000-0000-0000-0000-000000000951'$$,'23001','finished session is read-only');

-- trạng thái thanh toán
INSERT INTO facility_manager VALUES ('00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-0000000009c1');
UPDATE payment_transaction SET transaction_status_code='PROCESSING', payment_method_code='CREDIT_CARD', gateway_reference_identifier='R0' WHERE session_identifier='00000000-0000-0000-0000-000000000951';
UPDATE payment_transaction SET transaction_status_code='FAILED', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000951';
UPDATE payment_transaction SET transaction_status_code='PROCESSING', payment_method_code='E_WALLET', gateway_reference_identifier='R1', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000951';
SELECT pg_temp.expect_true((SELECT confirmed_by_identifier IS NULL AND confirmed_datetime IS NULL FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000951'),'paying again clears the earlier rejection');
UPDATE payment_transaction SET transaction_status_code='SUCCESS', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000951';
SELECT pg_temp.expect_true(true,'rejected invoice can be paid again and confirmed');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='PENDING' WHERE session_identifier='00000000-0000-0000-0000-000000000951'$$,'23001','paid invoice cannot return to PENDING');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET gateway_reference_identifier='X' WHERE session_identifier='00000000-0000-0000-0000-000000000951'$$,'23001','paid invoice reference is fixed');
UPDATE payment_transaction SET transaction_status_code='REFUNDED' WHERE session_identifier='00000000-0000-0000-0000-000000000951';

-- trụ hỏng hủy các lượt đặt chưa dùng
UPDATE charging_equipment SET equipment_status_code='FAULT' WHERE equipment_identifier='00000000-0000-0000-0000-0000000009e2';
SELECT pg_temp.expect_true((SELECT reservation_status_code='CANCELLED' FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-0000000009f2'),'fault cancels upcoming booking');

-- ---- toàn vẹn khi vận hành ------------------------------------------------------
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text, role_code) VALUES
 ('00000000-0000-0000-0000-000000000aa1','Khach Van Hanh','+84901000171','vh@x.vn','h','CUSTOMER'),
 ('00000000-0000-0000-0000-000000000aa2','Quan Ly Van Hanh','+84901000172','ql@x.vn','h','MANAGER'),
 ('00000000-0000-0000-0000-000000000aa3','Khach Se Xoa','+84901000173','xoa@x.vn','h','CUSTOMER');
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh)
SELECT ('00000000-0000-0000-0000-000000000ab' || n)::uuid, '00000000-0000-0000-0000-000000000aa1', '60A-000.0' || n, 40 FROM generate_series(1,6) n;
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES
 ('00000000-0000-0000-0000-000000000ab9','00000000-0000-0000-0000-000000000aa3','60A-000.09',40);
INSERT INTO parking_facility (facility_identifier, facility_name_text, geographic_location, address_text, total_capacity_count) VALUES
 ('00000000-0000-0000-0000-000000000ac1','Bai van hanh',ST_SetSRID(ST_MakePoint(106.70, 10.77), 4326),'Q3',8);
INSERT INTO facility_manager VALUES ('00000000-0000-0000-0000-000000000aa2','00000000-0000-0000-0000-000000000ac1');
INSERT INTO parking_space (space_identifier, facility_identifier, space_code)
SELECT ('00000000-0000-0000-0000-000000000ad' || n)::uuid, '00000000-0000-0000-0000-000000000ac1', 'V-0' || n FROM generate_series(1,8) n;
-- ô 1..6 có trụ 22 kW, ô 7 và 8 chỉ đỗ xe
INSERT INTO charging_equipment (equipment_identifier, space_identifier, evse_identifier, connector_type_code, max_power_kw)
SELECT ('00000000-0000-0000-0000-000000000ae' || n)::uuid, ('00000000-0000-0000-0000-000000000ad' || n)::uuid, 'VN*VH*' || n, 'STANDARD_AC', 22 FROM generate_series(1,6) n;

INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime) VALUES
 ('00000000-0000-0000-0000-000000000a51','00000000-0000-0000-0000-000000000ab1','00000000-0000-0000-0000-000000000ae1', now()-INTERVAL '3 hours'),
 ('00000000-0000-0000-0000-000000000a52','00000000-0000-0000-0000-000000000ab2','00000000-0000-0000-0000-000000000ae2', now()-INTERVAL '1 minute');

SELECT pg_temp.expect_error($$UPDATE service_session SET consumed_energy_kwh=60, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000a51'$$,'23514','energy cannot exceed battery capacity');
SELECT pg_temp.expect_error($$UPDATE service_session SET consumed_energy_kwh=30, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000a52'$$,'23514','energy cannot exceed charger power x time');
SELECT pg_temp.expect_error($$UPDATE service_session SET vehicle_identifier='00000000-0000-0000-0000-000000000ab6' WHERE session_identifier='00000000-0000-0000-0000-000000000a51'$$,'23001','open session keeps its vehicle');
SELECT pg_temp.expect_error($$UPDATE service_session SET start_datetime=now()-INTERVAL '9 hours' WHERE session_identifier='00000000-0000-0000-0000-000000000a51'$$,'23001','open session start cannot be moved');
SELECT pg_temp.expect_error($$UPDATE service_session SET rate_identifier=NULL WHERE session_identifier='00000000-0000-0000-0000-000000000a51'$$,'23001','locked price version cannot be changed');
SELECT pg_temp.expect_error($$DELETE FROM service_session WHERE session_identifier='00000000-0000-0000-0000-000000000a51'$$,'23001','open session cannot be deleted');
SELECT pg_temp.expect_error($$UPDATE charging_equipment SET equipment_status_code='READY' WHERE equipment_identifier='00000000-0000-0000-0000-000000000ae1'$$,'23514','charger stays CHARGING while a session is open');
SELECT pg_temp.expect_error($$UPDATE charging_equipment SET equipment_status_code='CHARGING' WHERE equipment_identifier='00000000-0000-0000-0000-000000000ae6'$$,'23514','charger cannot be CHARGING without a session');
SELECT pg_temp.expect_error($$INSERT INTO payment_transaction (session_identifier,energy_amount_value,transaction_amount_value)
 VALUES ('00000000-0000-0000-0000-000000000a51', 1, 1)$$,'23514','no invoice for an open session');

-- giá chốt lúc bắt đầu sạc
CREATE TEMP TABLE t_price AS SELECT t.price_per_kwh_value AS p, t.rate_identifier AS r
 FROM service_session AS ss JOIN tariff_rate AS t USING (rate_identifier)
 WHERE ss.session_identifier='00000000-0000-0000-0000-000000000a51';
-- đổi giá = đóng phiên bản cũ, thêm phiên bản mới (lịch sử giá được giữ)
SELECT fn_change_tariff(rate_identifier, price_per_kwh_value * 10, overtime_fee_per_hour_value)
FROM tariff_rate WHERE effective_to IS NULL AND connector_type_code = 'STANDARD_AC';
SELECT pg_temp.expect_true((SELECT count(*) = 2 AND count(effective_to) = 1 FROM tariff_rate AS t, t_price
   WHERE (t.connector_type_code, t.min_power_kw, t.time_band_code)
       = (SELECT connector_type_code, min_power_kw, time_band_code FROM tariff_rate WHERE rate_identifier = t_price.r)),
   'a price change keeps the old version and adds a new one');
SELECT pg_temp.expect_true(fn_select_tariff('00000000-0000-0000-0000-000000000ae1', now() - INTERVAL '3 hours') = (SELECT r FROM t_price)
   AND fn_select_tariff('00000000-0000-0000-0000-000000000ae1', clock_timestamp() + INTERVAL '1 second') <> (SELECT r FROM t_price),
   'tariff lookup returns the version valid at the given time');
SELECT pg_temp.expect_error($$SELECT fn_change_tariff((SELECT r FROM t_price), 1, 1)$$,'23001','a closed price version cannot be changed again');
UPDATE service_session SET consumed_energy_kwh=10, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000a51';
SELECT pg_temp.expect_true((SELECT energy_amount_value FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000a51') = (SELECT 10*p FROM t_price), 'price change mid-session does not affect the bill');

-- vai trò và xóa mềm tài khoản
SELECT pg_temp.expect_error($$UPDATE user_account SET role_code='ADMIN' WHERE account_identifier='00000000-0000-0000-0000-000000000aa1'$$,'23514','customer with vehicles keeps the role');
SELECT pg_temp.expect_error($$UPDATE user_account SET role_code='CUSTOMER' WHERE account_identifier='00000000-0000-0000-0000-000000000aa2'$$,'23514','assigned manager keeps the role');
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime) VALUES
 ('00000000-0000-0000-0000-000000000af9','00000000-0000-0000-0000-000000000ab9','00000000-0000-0000-0000-000000000ad6', now()+INTERVAL '3 days', now()+INTERVAL '3 days 1 hour');
UPDATE user_account SET deleted_datetime=now() WHERE account_identifier IN ('00000000-0000-0000-0000-000000000aa3','00000000-0000-0000-0000-000000000aa2');
SELECT pg_temp.expect_true((SELECT reservation_status_code='CANCELLED' FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-000000000af9'),'removing an account cancels its bookings');
SELECT pg_temp.expect_true(NOT EXISTS (SELECT 1 FROM facility_manager WHERE manager_identifier='00000000-0000-0000-0000-000000000aa2'),'removing a manager drops assignments');
SELECT pg_temp.expect_error($$INSERT INTO reservation (vehicle_identifier,space_identifier,start_datetime,end_datetime)
 VALUES ('00000000-0000-0000-0000-000000000ab9','00000000-0000-0000-0000-000000000ad6', now()+INTERVAL '4 days', now()+INTERVAL '4 days 1 hour')$$,'23514','removed account cannot book');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-000000000ab9','00000000-0000-0000-0000-000000000ae6')$$,'23514','removed account cannot charge');

-- lượt đặt không sửa được ô, xe, giờ
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime) VALUES
 ('00000000-0000-0000-0000-000000000af1','00000000-0000-0000-0000-000000000ab3','00000000-0000-0000-0000-000000000ad3', now()+INTERVAL '20 minutes', now()+INTERVAL '2 hours');
SELECT pg_temp.expect_error($$UPDATE reservation SET start_datetime=now()-INTERVAL '400 days', end_datetime=now()-INTERVAL '399 days 23 hours' WHERE reservation_identifier='00000000-0000-0000-0000-000000000af1'$$,'23001','booking time is fixed');
SELECT pg_temp.expect_error($$UPDATE reservation SET space_identifier='00000000-0000-0000-0000-000000000ad6' WHERE reservation_identifier='00000000-0000-0000-0000-000000000af1'$$,'23001','booking space is fixed');

-- đến sớm / đến trễ
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-000000000ab3','00000000-0000-0000-0000-000000000ae3')$$,'23514','own booking 20 min ahead: told to wait, not "taken"');
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime) VALUES
 ('00000000-0000-0000-0000-000000000af4','00000000-0000-0000-0000-000000000ab4','00000000-0000-0000-0000-000000000ad4', now()-INTERVAL '45 minutes', now()+INTERVAL '1 hour');
SELECT pg_temp.expect_error($$INSERT INTO service_session (reservation_identifier,vehicle_identifier,equipment_identifier)
 VALUES ('00000000-0000-0000-0000-000000000af4','00000000-0000-0000-0000-000000000ab4','00000000-0000-0000-0000-000000000ae4')$$,'23514','booking cannot be used 45 minutes late');
SELECT pg_temp.expect_error($$UPDATE reservation SET reservation_status_code='CONFIRMED' WHERE reservation_identifier='00000000-0000-0000-0000-000000000af4'$$,'23514','overdue booking cannot be confirmed');
INSERT INTO service_session (vehicle_identifier, equipment_identifier) VALUES ('00000000-0000-0000-0000-000000000ab5','00000000-0000-0000-0000-000000000ae4');
SELECT pg_temp.expect_true(true,'overdue booking no longer blocks a walk-in');

-- ô chỉ đỗ xe: khách đến thì mở phiên đỗ xe, khách đi thì tính tiền theo giờ
INSERT INTO reservation (reservation_identifier, vehicle_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code) VALUES
 ('00000000-0000-0000-0000-000000000af7','00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ad7', now()-INTERVAL '5 minutes', now()+INTERVAL '1 hour','CONFIRMED'),
 ('00000000-0000-0000-0000-000000000af8','00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ad8', now()+INTERVAL '2 days', now()+INTERVAL '2 days 1 hour','CONFIRMED');
SELECT pg_temp.expect_error($$INSERT INTO service_session (reservation_identifier,vehicle_identifier,space_identifier)
 VALUES ('00000000-0000-0000-0000-000000000af8','00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ad8')$$,'23514','cannot check in days early');
SELECT pg_temp.expect_error($$UPDATE reservation SET reservation_status_code='FULFILLED' WHERE reservation_identifier='00000000-0000-0000-0000-000000000af7'$$,'23514','a booking is used only by opening a session');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,space_identifier)
 VALUES ('00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ad5')$$,'23514','a charging space is used through its charger');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier,equipment_identifier,space_identifier)
 VALUES ('00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ae5','00000000-0000-0000-0000-000000000ad7')$$,'23514','a session uses a charger or a parking-only space, not both');
INSERT INTO service_session (session_identifier, reservation_identifier, vehicle_identifier, space_identifier) VALUES
 ('00000000-0000-0000-0000-000000000a57','00000000-0000-0000-0000-000000000af7','00000000-0000-0000-0000-000000000ab6','00000000-0000-0000-0000-000000000ad7');
SELECT pg_temp.expect_true((SELECT r.reservation_status_code='FULFILLED' AND s.availability_status_code='OCCUPIED'
   AND ss.parking_rate_identifier IS NOT NULL AND ss.rate_identifier IS NULL
   FROM service_session AS ss JOIN reservation AS r USING (reservation_identifier)
   JOIN parking_space AS s ON s.space_identifier = ss.space_identifier
   WHERE ss.session_identifier='00000000-0000-0000-0000-000000000a57'),'parking session: booking used, space occupied, hourly price locked');
SELECT pg_temp.expect_error($$UPDATE service_session SET consumed_energy_kwh=5 WHERE session_identifier='00000000-0000-0000-0000-000000000a57'$$,'23514','a parking session has no energy');
UPDATE service_session SET end_datetime = start_datetime + INTERVAL '90 minutes' WHERE session_identifier='00000000-0000-0000-0000-000000000a57';
SELECT pg_temp.expect_true((SELECT p.parking_amount_value = 1.5 * pr.price_per_hour_value AND p.energy_amount_value = 0
     AND p.overtime_amount_value = 0 AND p.transaction_amount_value = p.parking_amount_value
   FROM payment_transaction AS p JOIN service_session AS ss USING (session_identifier)
   JOIN parking_rate AS pr ON pr.parking_rate_identifier = ss.parking_rate_identifier
   WHERE p.session_identifier='00000000-0000-0000-0000-000000000a57'),'parking is billed per hour: 1.5 h x hourly price');
SELECT pg_temp.expect_true((SELECT availability_status_code='AVAILABLE' FROM parking_space WHERE space_identifier='00000000-0000-0000-0000-000000000ad7'),'parking-only space is released when the car leaves');

-- xóa mềm ô đỗ
SELECT pg_temp.expect_error($$UPDATE parking_space SET deleted_datetime=now() WHERE space_identifier='00000000-0000-0000-0000-000000000ad2'$$,'23514','charging space cannot be removed');
UPDATE parking_space SET deleted_datetime=now() WHERE space_identifier='00000000-0000-0000-0000-000000000ad8';
SELECT pg_temp.expect_true((SELECT reservation_status_code='CANCELLED' FROM reservation WHERE reservation_identifier='00000000-0000-0000-0000-000000000af8'),'removing a space cancels its bookings');

-- định dạng tài khoản
SELECT pg_temp.expect_error($$INSERT INTO user_account (full_name_text,contact_phone_number,email_address,password_hash_text) VALUES ('A','+84901000181','khongphaiemail','h')$$,'23514','email format checked');
SELECT pg_temp.expect_error($$INSERT INTO user_account (full_name_text,contact_phone_number,email_address,password_hash_text) VALUES ('   ','+84901000182','trong@x.vn','h')$$,'23514','blank name rejected');

-- Admin xóa tài khoản: xóa mềm, khôi phục trong 30 phút, sau đó xóa vĩnh viễn
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text) VALUES
 ('00000000-0000-0000-0000-000000000bb1','Khach Dang Sac','+84901000191','dangsac@x.vn','h'),
 ('00000000-0000-0000-0000-000000000bb4','Khach Chua Dung','+84901000194','chuadung@x.vn','h'),
 ('00000000-0000-0000-0000-000000000bb5','Khach Vua Xoa','+84901000195','vuaxoa@x.vn','h');
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES
 ('00000000-0000-0000-0000-000000000bb2','00000000-0000-0000-0000-000000000bb1','60A-111.11',40),
 ('00000000-0000-0000-0000-000000000bb8','00000000-0000-0000-0000-000000000bb4','60A-444.44',40);
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime) VALUES
 ('00000000-0000-0000-0000-000000000bb3','00000000-0000-0000-0000-000000000bb2','00000000-0000-0000-0000-000000000ae1', now()-INTERVAL '2 hours');

UPDATE user_account SET deleted_datetime=now() WHERE account_identifier='00000000-0000-0000-0000-000000000bb1';
SELECT pg_temp.expect_true((SELECT deleted_datetime IS NOT NULL FROM vehicle WHERE vehicle_identifier='00000000-0000-0000-0000-000000000bb2'),'a charging account can be removed and its vehicle is retired');
UPDATE service_session SET consumed_energy_kwh=5, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000bb3';
SELECT pg_temp.expect_true((SELECT (customer_name_text,customer_phone_number,customer_email_address,license_plate_text)
   = ('Khach Dang Sac','+84901000191','dangsac@x.vn','60A-111.11') FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000bb3'),'invoice records who was billed');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET customer_name_text='x' WHERE session_identifier='00000000-0000-0000-0000-000000000bb3'$$,'23001','billed customer details are fixed');

UPDATE user_account SET deleted_datetime=NULL WHERE account_identifier='00000000-0000-0000-0000-000000000bb1';
SELECT pg_temp.expect_true((SELECT deleted_datetime IS NULL FROM vehicle WHERE vehicle_identifier='00000000-0000-0000-0000-000000000bb2'),'restoring an account restores its vehicles');

UPDATE user_account SET deleted_datetime=now()-INTERVAL '31 minutes' WHERE account_identifier IN ('00000000-0000-0000-0000-000000000bb1','00000000-0000-0000-0000-000000000bb4');
UPDATE user_account SET deleted_datetime=now() WHERE account_identifier='00000000-0000-0000-0000-000000000bb5';
SELECT pg_temp.expect_error($$UPDATE user_account SET deleted_datetime=NULL WHERE account_identifier='00000000-0000-0000-0000-000000000bb1'$$,'23514','no restore after 30 minutes');
SELECT pg_temp.expect_error($$UPDATE user_account SET deleted_datetime=now() WHERE account_identifier='00000000-0000-0000-0000-000000000bb1'$$,'23001','deletion time cannot be pushed forward');

SELECT fn_purge_deleted_accounts();
SELECT pg_temp.expect_true((SELECT purged_datetime IS NOT NULL AND full_name_text='Tài khoản đã xóa' AND email_address<>'dangsac@x.vn' AND contact_phone_number<>'+84901000191' AND password_hash_text='!'
   FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bb1'),'personal data of an account with history is erased');
SELECT pg_temp.expect_true((SELECT license_plate_text<>'60A-111.11' FROM vehicle WHERE vehicle_identifier='00000000-0000-0000-0000-000000000bb2'),'plate is erased from the retired vehicle');
SELECT pg_temp.expect_true((SELECT (customer_name_text,license_plate_text)=('Khach Dang Sac','60A-111.11') FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000bb3'),'invoice keeps the information after purge');
SELECT pg_temp.expect_true(NOT EXISTS (SELECT 1 FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bb4')
   AND NOT EXISTS (SELECT 1 FROM vehicle WHERE vehicle_identifier='00000000-0000-0000-0000-000000000bb8'),'account without history is removed completely');
SELECT pg_temp.expect_true((SELECT purged_datetime IS NULL AND full_name_text='Khach Vua Xoa' FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bb5'),'recently removed account is not purged yet');
SELECT pg_temp.expect_error($$UPDATE user_account SET deleted_datetime=NULL WHERE account_identifier='00000000-0000-0000-0000-000000000bb1'$$,'23514','purged account cannot be restored');

-- đang sạc thì chờ phiên kết thúc rồi mới xóa vĩnh viễn (để hóa đơn còn đủ thông tin)
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text) VALUES
 ('00000000-0000-0000-0000-000000000bb6','Khach Sac Lau','+84901000196','saclau@x.vn','h');
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES ('00000000-0000-0000-0000-000000000bb9','00000000-0000-0000-0000-000000000bb6','60A-666.66',40);
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime) VALUES ('00000000-0000-0000-0000-000000000bba','00000000-0000-0000-0000-000000000bb9','00000000-0000-0000-0000-000000000ae1', now()-INTERVAL '1 hour');
UPDATE user_account SET deleted_datetime=now()-INTERVAL '31 minutes' WHERE account_identifier='00000000-0000-0000-0000-000000000bb6';
SELECT fn_purge_deleted_accounts();
SELECT pg_temp.expect_true((SELECT purged_datetime IS NULL FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bb6'),'purge waits while the account is charging');
UPDATE service_session SET consumed_energy_kwh=2, end_datetime=now() WHERE session_identifier='00000000-0000-0000-0000-000000000bba';
SELECT fn_purge_deleted_accounts();
SELECT pg_temp.expect_true((SELECT purged_datetime IS NOT NULL FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bb6'),'purge runs once the session has ended');

-- email đã được người khác đăng ký lại thì không khôi phục được
INSERT INTO user_account (full_name_text, contact_phone_number, email_address, password_hash_text) VALUES ('Nguoi Moi','+84901000197','vuaxoa@x.vn','h');
SELECT pg_temp.expect_error($$UPDATE user_account SET deleted_datetime=NULL WHERE account_identifier='00000000-0000-0000-0000-000000000bb5'$$,'23505','restore refused when the email was taken again');

INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text, role_code) VALUES
 ('00000000-0000-0000-0000-000000000bbb','Quan Tri Thu','+84901000198','qt@x.vn','h','ADMIN');
SELECT pg_temp.expect_error($$UPDATE user_account SET deleted_datetime=now() WHERE account_identifier='00000000-0000-0000-0000-000000000bbb'$$,'23514','admin account cannot be removed');
SELECT pg_temp.expect_error($$DELETE FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000bbb'$$,'23514','admin account cannot be deleted outright');

-- Tự tính điện năng: quản lý chỉ nhập % pin lúc cắm sạc, hiệu suất sạc 90 %
INSERT INTO parking_facility (facility_identifier, facility_name_text, geographic_location, address_text, total_capacity_count) VALUES
 ('00000000-0000-0000-0000-000000000cc1','Bai tu tinh',ST_SetSRID(ST_MakePoint(106.71, 10.78), 4326),'Q5',2);
INSERT INTO parking_space (space_identifier, facility_identifier, space_code) VALUES
 ('00000000-0000-0000-0000-000000000cd1','00000000-0000-0000-0000-000000000cc1','T-01');
INSERT INTO charging_equipment (equipment_identifier, space_identifier, evse_identifier, connector_type_code, max_power_kw) VALUES
 ('00000000-0000-0000-0000-000000000ce1','00000000-0000-0000-0000-000000000cd1','VN*TT*1','FAST_DC',60);
INSERT INTO user_account (account_identifier, full_name_text, contact_phone_number, email_address, password_hash_text, password_plain_text) VALUES
 ('00000000-0000-0000-0000-000000000ca1','Khach Tu Tinh','+84901000301','tutinh@x.vn','h','matkhau123');
INSERT INTO vehicle (vehicle_identifier, account_identifier, license_plate_text, battery_capacity_kwh) VALUES
 ('00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ca1','60C-100.01',82);
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier, equipment_identifier, start_battery_percent) VALUES ('00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ce1',100)$$,'23514','battery percent at plug-in must be below 100');
SELECT pg_temp.expect_error($$INSERT INTO service_session (vehicle_identifier, equipment_identifier, start_battery_percent) VALUES ('00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ce1',-1)$$,'23514','battery percent cannot be negative');
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime, start_battery_percent) VALUES
 ('00000000-0000-0000-0000-000000000cf1','00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ce1', now()-INTERVAL '2 hours', 20);
SELECT pg_temp.expect_true((SELECT e.energy_kwh = 27.00 AND e.full_at IS NULL AND round(e.battery_percent, 1) = 52.9
   FROM service_session AS ss, fn_session_estimate(ss.session_identifier, ss.start_datetime + INTERVAL '30 minutes') AS e
   WHERE ss.session_identifier='00000000-0000-0000-0000-000000000cf1'),'30 minutes at 60 kW x 90 % = 27 kWh, battery 52.9 %');
SELECT pg_temp.expect_true((SELECT e.energy_kwh = 65.60 AND e.battery_percent = 100
     AND abs(extract(epoch FROM e.full_at - ss.start_datetime) - 65.6 / 54 * 3600) < 1
   FROM service_session AS ss, fn_session_estimate(ss.session_identifier, now()) AS e
   WHERE ss.session_identifier='00000000-0000-0000-0000-000000000cf1'),'energy stops at a full battery and the full time is computed');
SELECT pg_temp.expect_error($$UPDATE service_session SET start_battery_percent=50 WHERE session_identifier='00000000-0000-0000-0000-000000000cf1'$$,'23001','battery percent at plug-in cannot be changed');
UPDATE service_session SET end_datetime = now(),
       (consumed_energy_kwh, fully_charged_datetime, peak_charging_power_kw) =
       (SELECT e.energy_kwh, e.full_at, e.power_kw FROM fn_session_estimate('00000000-0000-0000-0000-000000000cf1', now()) AS e)
 WHERE session_identifier='00000000-0000-0000-0000-000000000cf1';
SELECT pg_temp.expect_true((SELECT p.overtime_amount_value > 0 AND p.energy_amount_value = 65.60 * t.price_per_kwh_value
   FROM payment_transaction AS p JOIN service_session AS ss USING (session_identifier)
   JOIN tariff_rate AS t ON t.rate_identifier = ss.rate_identifier
   WHERE p.session_identifier='00000000-0000-0000-0000-000000000cf1'),'computed session is billed with energy and overtime');
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime) VALUES
 ('00000000-0000-0000-0000-000000000cf2','00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ce1', now()-INTERVAL '10 minutes');
SELECT pg_temp.expect_true((SELECT e.energy_kwh = 9.00 AND round(e.battery_percent, 1) = 31.0
   FROM service_session AS ss, fn_session_estimate(ss.session_identifier, ss.start_datetime + INTERVAL '10 minutes') AS e
   WHERE ss.session_identifier='00000000-0000-0000-0000-000000000cf2'),'without a plug-in percent the estimate assumes 20 %');
UPDATE service_session SET end_datetime = now(), consumed_energy_kwh = 1 WHERE session_identifier='00000000-0000-0000-0000-000000000cf2';

-- Khách bấm thanh toán thì hóa đơn chờ quản lý xác nhận (PROCESSING)
INSERT INTO service_session (session_identifier, vehicle_identifier, equipment_identifier, start_datetime, start_battery_percent) VALUES
 ('00000000-0000-0000-0000-000000000cf3','00000000-0000-0000-0000-000000000cb1','00000000-0000-0000-0000-000000000ce1', now()-INTERVAL '20 minutes', 50);
UPDATE service_session SET end_datetime = now(), consumed_energy_kwh = 3 WHERE session_identifier='00000000-0000-0000-0000-000000000cf3';
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='PROCESSING' WHERE session_identifier='00000000-0000-0000-0000-000000000cf3'$$,'23514','waiting for confirmation needs a method and a reference');
UPDATE payment_transaction SET transaction_status_code='PROCESSING', payment_method_code='E_WALLET', gateway_reference_identifier='DEMO-1'
 WHERE session_identifier='00000000-0000-0000-0000-000000000cf3';
SELECT pg_temp.expect_true((SELECT transaction_status_code='PROCESSING' FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000cf3'),'customer payment waits for the manager');
SELECT pg_temp.expect_error($$UPDATE payment_transaction SET transaction_status_code='PENDING' WHERE session_identifier='00000000-0000-0000-0000-000000000cf3'$$,'23001','waiting payment cannot go back to unpaid');
INSERT INTO facility_manager VALUES ('00000000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-000000000cc1');
UPDATE payment_transaction SET transaction_status_code='FAILED', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000cf3';
UPDATE payment_transaction SET transaction_status_code='PROCESSING', gateway_reference_identifier='DEMO-2' WHERE session_identifier='00000000-0000-0000-0000-000000000cf3';
UPDATE payment_transaction SET transaction_status_code='SUCCESS', confirmed_by_identifier='00000000-0000-0000-0000-0000000000a5' WHERE session_identifier='00000000-0000-0000-0000-000000000cf3';
SELECT pg_temp.expect_true((SELECT transaction_status_code='SUCCESS' AND gateway_reference_identifier='DEMO-2' FROM payment_transaction WHERE session_identifier='00000000-0000-0000-0000-000000000cf3'),'rejected payment can be paid again and then confirmed');

-- Chuẩn hóa biểu giá: dời giờ cao điểm ở MỘT dòng time_band_window thì mọi loại cổng đổi theo
UPDATE time_band_window SET end_time='16:00' WHERE start_time='05:00';
UPDATE time_band_window SET start_time='16:00' WHERE start_time='17:00';
SELECT pg_temp.expect_true((SELECT bool_and(t.time_band_code = 'PEAK')
   FROM charging_equipment AS ce
   JOIN tariff_rate AS t ON t.rate_identifier = fn_select_tariff(ce.equipment_identifier,
                                  TIMESTAMPTZ '2026-12-01 16:30:00+07')
   WHERE ce.equipment_identifier IN ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e2')),
   'moving the peak start in one row re-prices both connector types');
UPDATE time_band_window SET start_time='17:00' WHERE start_time='16:00';
UPDATE time_band_window SET end_time='17:00' WHERE start_time='05:00';

-- mật khẩu xem được bị xóa cùng thông tin cá nhân
UPDATE user_account SET deleted_datetime=now()-INTERVAL '31 minutes' WHERE account_identifier='00000000-0000-0000-0000-000000000ca1';
SELECT fn_purge_deleted_accounts();
SELECT pg_temp.expect_true((SELECT purged_datetime IS NOT NULL AND password_plain_text IS NULL FROM user_account WHERE account_identifier='00000000-0000-0000-0000-000000000ca1'),'purge also erases the viewable password');

-- quản lý đã xác nhận thanh toán: xóa vĩnh viễn chỉ ẩn thông tin, không xóa hẳn
DELETE FROM facility_manager WHERE manager_identifier='00000000-0000-0000-0000-0000000000a5';
UPDATE user_account SET deleted_datetime=now()-INTERVAL '31 minutes' WHERE account_identifier='00000000-0000-0000-0000-0000000000a5';
SELECT fn_purge_deleted_accounts();
SELECT pg_temp.expect_true((SELECT purged_datetime IS NOT NULL FROM user_account WHERE account_identifier='00000000-0000-0000-0000-0000000000a5'),'manager who confirmed payments is anonymised, not deleted');

DO $$ BEGIN RAISE NOTICE 'ALL TESTS PASSED'; END $$;
ROLLBACK;

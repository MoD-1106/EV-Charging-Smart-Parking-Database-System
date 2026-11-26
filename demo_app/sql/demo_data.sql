-- Chạy sau demo_accounts.sql (chạy lại nhiều lần không tạo trùng).
BEGIN;

-- Vài phiên sạc gần đây cho xe demo (tính theo now()) để trang khách có hóa đơn
-- và báo cáo 30 ngày của quản trị có số liệu. Chỉ tạo khi xe demo chưa có phiên.
DO $$
DECLARE
    v_vehicle UUID;
    v_charger UUID;
    v_session UUID;
    v_start   TIMESTAMPTZ;
    d         INT;
BEGIN
    SELECT vehicle_identifier INTO v_vehicle FROM vehicle
    WHERE license_plate_text = '51Z-888.88' AND deleted_datetime IS NULL;
    IF v_vehicle IS NULL OR EXISTS (SELECT 1 FROM service_session
                                    WHERE vehicle_identifier = v_vehicle) THEN
        RETURN;
    END IF;
    SELECT ce.equipment_identifier INTO v_charger
    FROM charging_equipment AS ce
    WHERE ce.equipment_status_code = 'READY' AND ce.deleted_datetime IS NULL
      AND NOT EXISTS (SELECT 1 FROM reservation AS r
                      WHERE r.space_identifier = ce.space_identifier
                        AND r.reservation_status_code IN ('PENDING', 'CONFIRMED'))
    ORDER BY ce.evse_identifier LIMIT 1;
    IF v_charger IS NULL THEN
        RETURN;
    END IF;
    FOR d IN REVERSE 3 .. 1 LOOP
        v_start := now() - d * INTERVAL '1 day';
        INSERT INTO service_session (vehicle_identifier, equipment_identifier, start_datetime)
        VALUES (v_vehicle, v_charger, v_start)
        RETURNING session_identifier INTO v_session;
        UPDATE service_session
        SET end_datetime = v_start + INTERVAL '1 hour', consumed_energy_kwh = 20 + d
        WHERE session_identifier = v_session;
        IF d > 1 THEN   -- phiên mới nhất để chờ thanh toán
            UPDATE payment_transaction
            SET transaction_status_code = 'SUCCESS', payment_method_code = 'E_WALLET',
                gateway_reference_identifier = 'DEMO-SEED-' || d,
                created_datetime = v_start + INTERVAL '1 hour'
            WHERE session_identifier = v_session;
        END IF;
    END LOOP;
END $$;

COMMIT;

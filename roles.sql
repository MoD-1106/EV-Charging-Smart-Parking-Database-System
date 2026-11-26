-- Tài khoản CSDL quyền tối thiểu cho ứng dụng web.
-- Chạy bằng postgres, sau schema.sql, ngay trên CSDL của đồ án (chạy lại được).
-- Sau đó tự đặt mật khẩu:   ALTER ROLE evc_app PASSWORD '<mat khau cua ban>';
-- rồi cho web dùng:         DATABASE_URL=postgresql://evc_app:<mat khau>@localhost:5432/<ten CSDL>
-- Role này không được sửa cấu trúc, không xóa dữ liệu nghiệp vụ (trừ phân công
-- quản lý bãi). Phân quyền CUSTOMER / MANAGER / ADMIN vẫn do ứng dụng kiểm soát.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'evc_app') THEN
        CREATE ROLE evc_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO evc_app;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM evc_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO evc_app;

GRANT INSERT ON user_account, vehicle, reservation, service_session,
                payment_transaction, facility_manager TO evc_app;
-- gồm cả cột do trigger cập nhật (trigger chạy bằng quyền của người gọi)
GRANT UPDATE (reservation_status_code) ON reservation TO evc_app;
GRANT UPDATE (end_datetime, consumed_energy_kwh, fully_charged_datetime, peak_charging_power_kw)
    ON service_session TO evc_app;
GRANT UPDATE (equipment_status_code) ON charging_equipment TO evc_app;
GRANT UPDATE (availability_status_code) ON parking_space TO evc_app;
GRANT UPDATE (transaction_status_code, payment_method_code, gateway_reference_identifier,
                confirmed_by_identifier, confirmed_datetime)
    ON payment_transaction TO evc_app;
GRANT UPDATE (price_per_kwh_value, overtime_fee_per_hour_value) ON tariff_rate TO evc_app;
-- admin xóa tài khoản là xóa mềm; trigger ngừng luôn xe của tài khoản đó
GRANT UPDATE (deleted_datetime) ON user_account, vehicle TO evc_app;
-- admin đặt lại mật khẩu; lần đăng nhập đầu sau khi nâng cấp ghi lại mật khẩu để admin xem
GRANT UPDATE (password_hash_text, password_plain_text) ON user_account TO evc_app;
GRANT DELETE ON facility_manager TO evc_app;
-- xóa vĩnh viễn chỉ qua hàm này (chạy bằng quyền chủ sở hữu, có kiểm tra 30 phút)
GRANT EXECUTE ON FUNCTION fn_purge_deleted_accounts() TO evc_app;

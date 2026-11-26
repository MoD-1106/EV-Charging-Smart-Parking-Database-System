-- Tài khoản demo: chỉ chứa mật khẩu đã băm (mật khẩu gốc xem DEMO_ACCOUNTS.md).
BEGIN;
INSERT INTO user_account (full_name_text, contact_phone_number, email_address, password_hash_text, role_code)
VALUES ('Quản trị demo', '0988000001', 'admin.demo@evcharge.test', 'scrypt:32768:8:1$swRqItEp0I6dDceZ$721036679520e195979067bc04976bfa6f647868991b6dfa902fb3bcfbf57b0ffd7172012d8551ca69425a32729de5cb1d916e5b5d42d51696b9e249761f8e88', 'ADMIN')
ON CONFLICT DO NOTHING;
INSERT INTO user_account (full_name_text, contact_phone_number, email_address, password_hash_text, role_code)
VALUES ('Quản lý demo', '0988000002', 'quanly.demo@evcharge.test', 'scrypt:32768:8:1$jmVnGGpwc1Onuuyz$c8c8c1a13a84c3441a1e2e2e3dd7a7b59192c4ecbf5ac8ecf61c07c10e32d9648121f47d7c67c4aa1d00d00a68cd064d5b4b6fabcf16d162dbac514516285f98', 'MANAGER')
ON CONFLICT DO NOTHING;
INSERT INTO user_account (full_name_text, contact_phone_number, email_address, password_hash_text, role_code)
VALUES ('Khách hàng demo', '0988000003', 'khach.demo@evcharge.test', 'scrypt:32768:8:1$hkLvZyS2nIcj2WI7$6ff300a2aa14b8995a8bad097956ec80ecb3df601f591e4d5662cebf2caef7853a22da49e31341b1c2f89d597c3c84e299f42316f66d24fc3d07fc7f9f1c5489', 'CUSTOMER')
ON CONFLICT DO NOTHING;
INSERT INTO facility_manager (manager_identifier, facility_identifier)
SELECT u.account_identifier, f.facility_identifier
FROM user_account AS u CROSS JOIN parking_facility AS f
WHERE u.email_address = 'quanly.demo@evcharge.test' AND f.facility_name_text IN ('EV Hub Quận 1 - Đồng Khởi', 'EV Hub Bình Thạnh - Landmark')
ON CONFLICT DO NOTHING;
INSERT INTO vehicle (account_identifier, license_plate_text, battery_capacity_kwh)
SELECT account_identifier, '51Z-888.88', 75.00 FROM user_account
WHERE email_address = 'khach.demo@evcharge.test'
ON CONFLICT DO NOTHING;
COMMIT;

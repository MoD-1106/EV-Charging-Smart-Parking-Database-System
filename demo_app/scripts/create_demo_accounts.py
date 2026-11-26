"""Generate demo accounts (ADMIN, MANAGER, CUSTOMER) with random passwords.

Writes two files next to the app:
  sql/demo_accounts.sql   - INSERT statements with password HASHES only
  DEMO_ACCOUNTS.md        - the plaintext passwords, for local demo use
Load the SQL into a database that already has schema.sql + seed.sql:
  psql -d evt -v ON_ERROR_STOP=1 -f sql/demo_accounts.sql
Run again to rotate: it overwrites both files with new passwords.
"""
import pathlib
import secrets

from werkzeug.security import generate_password_hash

ROOT = pathlib.Path(__file__).resolve().parent.parent
ACCOUNTS = [
    ("ADMIN", "Quản trị demo", "0988000001", "admin.demo@evcharge.test"),
    ("MANAGER", "Quản lý demo", "0988000002", "quanly.demo@evcharge.test"),
    ("CUSTOMER", "Khách hàng demo", "0988000003", "khach.demo@evcharge.test"),
]
FACILITIES_FOR_MANAGER = ("EV Hub Quận 1 - Đồng Khởi", "EV Hub Bình Thạnh - Landmark")


def main():
    sql = ["-- Demo accounts: password hashes only (see DEMO_ACCOUNTS.md for passwords).",
           "BEGIN;"]
    md = ["# Tài khoản demo", "",
          "Chỉ dùng cho môi trường thử trên máy cá nhân. Đổi hoặc xóa trước khi triển khai thật.", "",
          "| Vai trò | Email | Mật khẩu |", "|---|---|---|"]
    for role, name, phone, email in ACCOUNTS:
        password = secrets.token_urlsafe(9)
        digest = generate_password_hash(password)
        sql.append(
            "INSERT INTO user_account (full_name_text, contact_phone_number, email_address, "
            "password_hash_text, role_code)\n"
            f"VALUES ('{name}', '{phone}', '{email}', '{digest}', '{role}')\n"
            "ON CONFLICT DO NOTHING;")
        md.append(f"| {role} | {email} | `{password}` |")
    names = ", ".join(f"'{n}'" for n in FACILITIES_FOR_MANAGER)
    sql.append(
        "INSERT INTO facility_manager (manager_identifier, facility_identifier)\n"
        "SELECT u.account_identifier, f.facility_identifier\n"
        "FROM user_account AS u CROSS JOIN parking_facility AS f\n"
        f"WHERE u.email_address = 'quanly.demo@evcharge.test' AND f.facility_name_text IN ({names})\n"
        "ON CONFLICT DO NOTHING;")
    sql.append(
        "INSERT INTO vehicle (account_identifier, license_plate_text, battery_capacity_kwh)\n"
        "SELECT account_identifier, '51Z-888.88', 75.00 FROM user_account\n"
        "WHERE email_address = 'khach.demo@evcharge.test'\n"
        "ON CONFLICT DO NOTHING;")
    sql.append("COMMIT;")
    (ROOT / "sql").mkdir(exist_ok=True)
    (ROOT / "sql" / "demo_accounts.sql").write_text("\n".join(sql) + "\n", encoding="utf-8")
    (ROOT / "DEMO_ACCOUNTS.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print("Wrote sql/demo_accounts.sql and DEMO_ACCOUNTS.md")


if __name__ == "__main__":
    main()

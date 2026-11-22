#!/usr/bin/env bash
# Chạy một lần khi tạo Codespace: cài thư viện, tạo tài khoản demo.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v psql >/dev/null 2>&1; then
  sudo apt-get update -qq && sudo apt-get install -y -qq postgresql-client
fi
pip install --quiet -r demo_app/requirements.txt pytest

echo "Đợi CSDL sẵn sàng..."
until pg_isready -q; do sleep 2; done

# Tài khoản demo: chỉ tạo khi chưa có (mật khẩu ngẫu nhiên, ghi vào demo_app/DEMO_ACCOUNTS.md, file này nằm trong .gitignore)
EXISTS=$(psql -Atc "SELECT count(*) FROM user_account WHERE email_address = 'admin.demo@evcharge.test'")
if [ "$EXISTS" = "0" ]; then
  python demo_app/scripts/create_demo_accounts.py
  psql -v ON_ERROR_STOP=1 -q -f demo_app/sql/demo_accounts.sql
  git checkout -- demo_app/sql/demo_accounts.sql   # giữ file SQL đã commit, không làm bẩn working tree
fi
echo "Xong. Mật khẩu demo: demo_app/DEMO_ACCOUNTS.md"

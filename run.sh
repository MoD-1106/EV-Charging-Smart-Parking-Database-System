#!/usr/bin/env bash
# Một lệnh chạy hết: bash run.sh
# Tự cài thư viện, đợi CSDL, tạo tài khoản demo (nếu chưa có), bật lại Flask và in đường link mở web.
set -uo pipefail
cd "$(dirname "$0")"

# 1. Cài đặt (idempotent): thư viện, tài khoản demo
bash .devcontainer/setup.sh || { echo "Setup lỗi, xem thông báo phía trên."; exit 1; }

# 2. Tắt Flask cũ rồi bật mới, tách khỏi terminal để không bị tắt theo
pkill -f "flask --app app" 2>/dev/null || true
sleep 1
(cd demo_app && setsid nohup flask --app app run --host 0.0.0.0 --port 5000 > /tmp/flask.log 2>&1 < /dev/null &)

# 3. Đợi Flask trả lời
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' localhost:5000/login)" = "200" ] && break
  sleep 1
done
if [ "$(curl -s -o /dev/null -w '%{http_code}' localhost:5000/login)" != "200" ]; then
  echo "Flask chưa lên được. Log:"; tail -20 /tmp/flask.log; exit 1
fi

# 4. Đảm bảo cổng 5000 được chuyển tiếp lại (tránh lỗi 502 do trạng thái cũ)
if command -v gh >/dev/null 2>&1 && [ -n "${CODESPACE_NAME:-}" ]; then
  gh codespace ports visibility 5000:private -c "$CODESPACE_NAME" >/dev/null 2>&1 || true
fi

URL="https://${CODESPACE_NAME:-localhost}-5000.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
echo
echo "Đã chạy xong. Mở: $URL"
echo "Tài khoản demo: demo_app/DEMO_ACCOUNTS.md"
[ -n "${BROWSER:-}" ] && "$BROWSER" "$URL" >/dev/null 2>&1 || true

# Chay web cho nhieu nguoi test qua Cloudflare Quick Tunnel.
# Cua so 1 chay khoi lenh tren (web); cua so 2 chay lenh cloudflared o cuoi.
# Thay MAT_KHAU bang mat khau PostgreSQL; khong dua mat khau that len GitHub.

cd "C:\Users\Truong Nghi\Downloads\Database_EV_Charging\demo_app"
$env:DATABASE_URL="postgresql://postgres:MAT_KHAU@localhost:5432/EV_Charging_Management"
$env:SECRET_KEY="mot-chuoi-dai-ngau-nhien-bat-ky"
waitress-serve --listen=127.0.0.1:5000 --threads=8 app:app


cloudflared tunnel --url http://localhost:5000
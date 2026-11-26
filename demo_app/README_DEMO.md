# Demo web (Flask + PostgreSQL) cho Phase 4

Ứng dụng nối trực tiếp vào CSDL của đồ án (schema.sql, seed.sql ở thư mục cha). Mọi quy tắc nghiệp vụ (chống đặt chỗ chồng giờ, đồng bộ trạng thái thiết bị, hóa đơn tự lập, phân công chỉ cho MANAGER) vẫn do CSDL thực thi; lớp web chỉ gọi và dịch lỗi sang tiếng Việt.

## Chạy thử

```bash
# 1. CSDL (một lần): thư mục cha chứa schema.sql, seed.sql
createdb evt
psql -d evt -v ON_ERROR_STOP=1 -f ../schema.sql
psql -d evt -v ON_ERROR_STOP=1 -f ../seed.sql
psql -d evt -v ON_ERROR_STOP=1 -f sql/demo_accounts.sql   # tạo tài khoản admin, quản lý, khách
psql -d evt -v ON_ERROR_STOP=1 -f sql/demo_data.sql       # vài phiên sạc gần đây cho tài khoản khách demo

# (nên làm) tài khoản CSDL quyền tối thiểu cho web
psql -d evt -v ON_ERROR_STOP=1 -f ../roles.sql
psql -d evt -c "ALTER ROLE evc_app PASSWORD 'MAT_KHAU_APP'"   # rồi dùng evc_app trong DATABASE_URL

# 2. Ứng dụng
python -m venv .venv
.venv\Scripts\activate            # Windows (Linux/macOS: source .venv/bin/activate)
pip install -r requirements.txt
set DATABASE_URL=postgresql://postgres:MAT_KHAU@localhost:5432/evt   # PowerShell: $env:DATABASE_URL="..."
set SECRET_KEY=doi-chuoi-nay                                         # PowerShell: $env:SECRET_KEY="..."
flask --app app run
```

Mở http://127.0.0.1:5000. Email và mật khẩu demo nằm trong `DEMO_ACCOUNTS.md` (file này không có trên GitHub; chạy `python scripts/create_demo_accounts.py` để sinh lại).

## Vai trò và chức năng

| Vai trò | Trang | Chức năng |
|---|---|---|
| CUSTOMER | `/register`, `/customer` | Tự đăng ký; xem ô trống theo khung giờ (`fn_is_space_available`), giá theo giờ bắt đầu (`fn_select_tariff`), đặt chỗ, hủy chỗ, xem và thanh toán hóa đơn (cổng thanh toán mô phỏng). Đặt trước tối đa 30 ngày, giữ tối đa 3 lượt, phải trả hết hóa đơn mới đặt tiếp |
| MANAGER | `/manager` | Chỉ thấy bãi được phân công: sơ đồ ô, báo lỗi/bảo trì/sẵn sàng thiết bị, xác nhận đặt chỗ, hủy đặt chỗ quá 30 phút, ghi nhận khách đến ô chỉ đỗ xe, bắt đầu và kết thúc phiên sạc |
| ADMIN | `/admin` | Doanh thu, sửa biểu giá, phân công quản lý cho bãi, tạo tài khoản MANAGER/ADMIN, đối soát hóa đơn |

## Diễn thử luồng sạc

Tài khoản khách demo có sẵn một hóa đơn chờ thanh toán: hãy thanh toán trước rồi mới đặt được chỗ.

1. Khách đặt một ô có trụ sạc, giờ bắt đầu trong vòng 15 phút tới.
2. Quản lý xác nhận, nhập biển số (được điền sẵn khi đã tới giờ nhận chỗ) rồi bấm "Bắt đầu sạc".
3. Quản lý nhập số kWh rồi bấm "Kết thúc sạc"; hóa đơn được lập tự động. Số kWh phải phù hợp thời gian đã sạc (công suất × (thời gian + 5 phút)) và dung lượng pin, nên phiên vừa bắt đầu chỉ nhập được số nhỏ; muốn nhập số lớn hãy dùng một phiên đang mở sẵn.
4. Khách thanh toán hóa đơn.

## API giờ và đồng hồ

`GET /api/time` (không cần đăng nhập) trả giờ của CSDL (`now()`, múi giờ `Asia/Ho_Chi_Minh`) kèm khung giá đang áp dụng:

```json
{"epoch_ms": 1793862040000, "local_iso": "2026-11-05T14:00:40", "tz": "Asia/Ho_Chi_Minh",
 "band": "STANDARD", "band_name": "Bình thường",
 "next_band": "PEAK", "next_band_name": "Cao điểm", "change_epoch_ms": 1793872800000}
```

Khung giá được suy ra từ bảng `tariff_rate` (không hard-code giờ). Nếu bảng giá trống, API vẫn trả giờ, chỉ thiếu các trường `band`.

`static/live.js` (nạp trong `base.html`, nên có ở mọi trang) lấy giờ server khi tải trang, tự chạy mỗi giây và đồng bộ lại mỗi 60 giây. Nếu gọi API lỗi, đồng hồ dùng giờ máy. Nguyên tắc: **trình duyệt chỉ hiển thị và chặn sớm, CSDL mới quyết định** (kiểm tra `> now()`, ràng buộc `EXCLUDE`, trigger hóa đơn).

| # | Tính năng | Vị trí |
|---|---|---|
| 1 | Chặn khung giờ đã qua: ngày và giờ tối thiểu theo giờ server, khóa nút "Đặt" khi giờ bắt đầu đã qua | `/customer`, form tìm và đặt chỗ |
| 2 | Đếm ngược tới giờ nhận chỗ rồi tới hạn giữ chỗ (30 phút); số phút trễ và "đặt kế tiếp" ở manager chạy theo thời gian thực | `/customer` (Đặt chỗ của tôi), `/manager` |
| 3 | Nhãn khung giá hiện tại và thời gian tới lần đổi khung | Đồng hồ góc phải dưới, mọi trang |
| 4 | Xem trước giờ kết thúc, thời lượng, kWh và tiền ước tính (công suất × thời gian, không vượt dung lượng pin xe đã chọn) | Từng ô trống ở `/customer` |
| 5 | Phiên đang sạc: thời gian đã sạc và chi phí tạm tính chạy mỗi giây | `/customer` (khung "Phiên đang sạc"), `/manager` (sơ đồ ô) |

Số tiền ở mục 4 và 5 chỉ là ước tính để xem trước. Hóa đơn chính thức do trigger `trg_session_finish` lập khi phiên kết thúc.

Khung "Phiên đang sạc" chỉ hiện khi tài khoản có phiên chưa kết thúc (`service_session.end_datetime IS NULL`).

## Tài khoản
- `sql/demo_accounts.sql` chỉ chứa mật khẩu đã băm (scrypt). Mật khẩu gốc ở `DEMO_ACCOUNTS.md`.
- Tạo lại với mật khẩu mới: `python scripts/create_demo_accounts.py` rồi nạp lại file SQL (tài khoản đã tồn tại sẽ được giữ, nên xóa dòng cũ trước khi nạp).
- Tài khoản trong `seed.sql` dùng mật khẩu băm giả, không đăng nhập được. Đây là chủ ý của dữ liệu mẫu.
- Admin tạo tài khoản MANAGER/ADMIN trong tab Tài khoản và **tự nhập mật khẩu** (tối thiểu 8 ký tự, nhập lại để xác nhận). Hệ thống chỉ lưu bản băm và không hiển thị lại mật khẩu.
- Khách hàng tự đăng ký tại `/register` (liên kết ở trang đăng nhập): họ tên, email, số điện thoại, mật khẩu và xe đầu tiên (biển số, dung lượng pin). Vai trò luôn là `CUSTOMER`; tài khoản và xe được tạo trong một câu SQL nên không có tài khoản thiếu xe. Email, số điện thoại và biển số trùng sẽ báo lỗi riêng. Đăng ký xong quay về trang đăng nhập.
- Đăng nhập sai 5 lần (theo địa chỉ máy và email) bị khóa 5 phút. Demo chưa giới hạn số lần đăng ký; trang đăng ký công khai và thông báo trùng email cho biết email đã tồn tại.

## Lưu ý
- Ứng dụng không dùng PostGIS, nên chạy được cả khi CSDL dùng `GEOMETRY` lẫn `POINT`.
- Các form POST có mã CSRF; phân quyền kiểm tra ở từng route và trong câu SQL (quản lý chỉ sửa được thiết bị thuộc bãi mình phụ trách).
- Đây là bản demo: chưa có HTTPS hay cổng thanh toán thật. Không đặt `SECRET_KEY` thì khóa được sinh ngẫu nhiên, khởi động lại là phải đăng nhập lại.
- Danh sách phiên đăng xuất được giữ trong bộ nhớ: khi chạy nhiều tiến trình hoặc khởi động lại mà vẫn dùng cùng `SECRET_KEY`, cookie đã đăng xuất chưa bị chặn.
- Đặt chỗ quá hạn được hủy khi có người mở trang khách, quản lý hoặc admin (tối đa mỗi phút một lần).
- Hạn chế của lược đồ đã nêu trong phần review (chưa có biểu giá cho ô chỉ đỗ xe, chưa có chỉ số sạc theo thời gian) thể hiện trực tiếp trên giao diện.

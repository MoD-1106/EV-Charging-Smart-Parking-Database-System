# CHANGELOG — v0.3 → v0.3.1

Sửa theo đợt rà soát đối chiếu báo cáo với mã nguồn.

## Sửa lỗi
| # | Vấn đề ở v0.3 | Cách sửa ở v0.3.1 |
|---|---|---|
| 1 | `seed.sql` chia trạng thái thanh toán theo `md5(session_identifier)`, mà UUID phiên sinh ngẫu nhiên nên mỗi lần nạp cho số khác nhau (báo cáo ghi 1.057/49/36 không tái lập) | Digest lấy từ `md5(biển số xe \|\| epoch(start_datetime))`. Nạp hai lần cho cùng kết quả: SUCCESS 1.070, PENDING 71, FAILED 37, REFUNDED 35; báo cáo cập nhật theo |
| 2 | `run_tests.ps1` truyền `--junitxml=(Join-Path ...)` nên PowerShell tách tham số, pytest báo thiếu `ket_qua.xml` và không chạy test | Dựng đường dẫn thành chuỗi `"--junitxml=$xmlPath"`, `"--html=$htmlPath"` |
| 3 | `demo_app`: nút "hủy quá hạn" của manager không kiểm tra lượt đặt đã có phiên sạc như `fn_expire_overdue_reservations` | Thêm `NOT EXISTS (service_session ...)` vào câu UPDATE |
| 4 | `data_dictionary.md` tiêu đề cột chưa đúng mẫu đề | Đổi thành Attribute Name, Data Type, Key Type, Nullable?, Default Value, Business Rules / Constraints |
| 5 | `queries.sql` Q2 ghi dùng FILTER nhưng không có | Bỏ khỏi dòng Features |
| 6 | `schema.sql` nhắc pg_cron nhưng không có lệnh lập lịch | Thêm ví dụ `cron.schedule` (chú thích) |

## Báo cáo Word (`database_report_v0.3.1.docx`)
- Cập nhật số liệu thanh toán; ghi rõ schema cần PostGIS (PostgreSQL 16 thử bằng `POINT`); mô tả đúng cách sinh dữ liệu tất định.
- Sửa lỗi gõ trong bảng bao đóng khóa (`contact_phone_number`, `space_identifier`, `license_plate_text`).
- Ví dụ giá trong từ điển ghi rõ là minh họa, kèm bảng giá thật trong `seed.sql`.
- Thêm mục F "Tích hợp giao diện và backend (Phase 4)".

## Đồng bộ tài liệu
- Tiêu đề `schema.sql`, `seed.sql`, `queries.sql` và các file `.md` (`business_rule`, `normalization_proof`, `data_dictionary`, `relational_schema_mapping`) ghi v0.3.1; báo cáo Word cập nhật chú thích ERD và mục hạn chế.
- `business_rule.md`: bỏ dòng "Thời hạn dự án" (CHANGELOG v0.3 đã ghi là bỏ).
- `data_dictionary.md` và báo cáo Word: mật khẩu băm bằng scrypt (`werkzeug`), đúng với `demo_app`, thay cho "bcrypt/argon2".
- `README.md`: mô tả CHANGELOG là lịch sử v0.2.1 → v0.3 → v0.3.1; `README_DEMO.md` và `run_tests.ps1` bỏ tham chiếu tới thư mục `revised_v0.3`.

## Chưa làm
- Chưa chạy lại pytest trên máy Windows: cần chạy `.\run_tests.ps1` để có kết quả thật cho 38 hàm kiểm thử trong `tests/test_app.py`.
- Chưa đo hiệu năng (`EXPLAIN ANALYZE`) cho NFR-01, NFR-02, NFR-05.

---

# CHANGELOG — v0.2.1 → v0.3

## Sửa lỗi thiết kế
| # | Vấn đề ở v0.2.1 | Cách sửa ở v0.3 |
|---|---|---|
| 1 | `EXCLUDE` dùng `tsrange` trên `TIMESTAMPTZ` (PostgreSQL từ chối: hàm không IMMUTABLE) | Dùng `tstzrange` |
| 2 | `EXCLUDE` tính cả lượt `CANCELLED`/đã xóa ⇒ tự hủy sau 30 phút không trả lại khung giờ | Thêm `WHERE status IN (PENDING, CONFIRMED, FULFILLED) AND deleted_datetime IS NULL` |
| 3 | Khách vãng lai có thể đè lên lịch đã đặt | Trigger `trg_session_validate` + chỉ mục một phiên mở / thiết bị |
| 4 | Một `rate_identifier` cho cả phiên nhưng giờ cao/thấp điểm có khoảng trống và không có quy tắc phiên vắt qua khung giờ | Bảng giá phủ kín 24h (PEAK / STANDARD / OFF_PEAK), chọn giá theo giờ bắt đầu phiên, `EXCLUDE` chống chồng ô giá |
| 5 | Hóa đơn chỉ có tổng tiền | Thêm `energy_amount_value`, `overtime_amount_value`, CHECK tổng; trigger tự lập và bất biến hóa đơn |
| 6 | Rule "ô `AVAILABLE` trong cả khung giờ" không kiểm tra được bằng cột trạng thái hiện tại | Khả dụng theo khung giờ = `fn_is_space_available`; trạng thái ô chỉ là trạng thái hiện tại, có trigger đồng bộ |
| 7 | `service_session`/`reservation` lưu `account_identifier` trùng với dữ liệu suy ra được (vi phạm 3NF khi có reservation) | Bỏ cột, tài khoản suy ra từ `vehicle` |
| 8 | `vehicle` không nối vào luồng đặt chỗ/phiên sạc | Thêm `vehicle_identifier` NOT NULL vào `reservation`, `service_session` |
| 9 | `service_session.reservation_identifier` không UNIQUE | Thêm UNIQUE |
| 10 | `COMPLETED` đặt lúc bắt đầu phiên; không phân biệt khách hủy / hệ thống hủy | `FULFILLED`, `CANCELLED`, `EXPIRED` |
| 11 | Ràng buộc UNIQUE thường chặn đăng ký lại sau xóa mềm | Partial unique index `WHERE deleted_datetime IS NULL` |
| 12 | `gateway_reference_id` vừa `NOT NULL` vừa `DEFAULT NULL`; `payment_method_code` không có CHECK | Cho phép NULL khi `PENDING`; thêm CHECK; `SUCCESS` yêu cầu đủ method + gateway |
| 13 | Thiếu mật khẩu cho xác thực | Thêm `password_hash_text`, `created_datetime` |
| 14 | Chỉ MANAGER mới được phân công; sức chứa; đồng bộ thiết bị chỉ mô tả bằng lời | Trigger `trg_facility_manager_role`, `trg_space_capacity`, `trg_equipment_status_sync` |

## Sửa tài liệu
- ERD vẽ lại bằng **IE Crow's Foot**; sửa 1:1 `parking_space`–`charging_equipment`, 1:N `owns`, vị trí FK ô giá, thêm các thuộc tính thiếu, bỏ thực thể `ADMIN`/`SUPERVISES` không có trong schema.
- Thống nhất tên: `_amount` → `_value`; `deleted_at → deleted_datetime`; `license_plate → license_plate_text`; `gateway_reference_id → gateway_reference_identifier`; thêm hậu tố `_time`.
- README dùng snake_case, bỏ PascalCase, sửa công thức hóa đơn (theo kWh, không theo giờ), sửa "Admin/Staff" thành MANAGER do ADMIN phân công.
- `business_rule.md`: thêm mục 5 (yêu cầu người dùng, FR, NFR, ánh xạ chuyên biệt hóa); bỏ LaTeX hiển thị thô.
- `normalization_proof.md`: viết lại mục BCNF, bổ sung các FD ngầm đã loại và mục "dư thừa có kiểm soát".

## Báo cáo Word
- `database_report_v0.3.docx` là bản sao của `database_report_v.0.2.1.docx` đã đồng bộ: quy tắc nghiệp vụ, mục FR/NFR mới, ERD Crow's Foot, lược đồ quan hệ, bảng FK, bảng bao đóng khóa, các khối mã (EXCLUDE, partial index), mục trigger/kiểm thử và 10 bảng từ điển dữ liệu (426 ô khớp `data_dictionary.md`). Công thức toán và định dạng gốc được giữ nguyên, trừ các ô của bảng bao đóng khóa cho tariff_rate, reservation, service_session, payment_transaction được viết lại bằng văn bản thường.

## Ánh xạ lược đồ quan hệ
- Thêm `relational_schema_mapping.md`: trình bày ánh xạ ERD → 10 quan hệ theo các bước (thực thể mạnh, 1:1, 1:N, M:N, chuyên biệt hóa, thuộc tính suy diễn), danh mục 12 khóa ngoại kèm chính sách ON DELETE, ràng buộc cài bằng EXCLUDE/trigger và ánh xạ kiểu dữ liệu. Đồng thời thêm file vào bảng trong `README.md`.

## Phase 3: dữ liệu mẫu và truy vấn
- Thêm `seed.sql`: dữ liệu mẫu tất định (30 tài khoản, 48 xe, 5 bãi, 60 ô, 40 thiết bị, 15 ô giá, 1.381 lượt đặt, 1.220 phiên sạc, 1.213 hóa đơn). Nạp qua đúng các trigger, không tắt trigger nào; hóa đơn do `trg_session_finish` tự lập.
- Thêm `queries.sql`: 13 truy vấn (Q1-Q12 chạy trên PostgreSQL thuần, Q13 cần PostGIS).
- Báo cáo Word: thêm mục E "Triển khai và truy vấn (Phase 3)" và cập nhật dòng phiên bản.
- `tests.sql`: từ khóa `interval` viết hoa theo SQLStyle.guide. `data_dictionary.md`: tiêu đề cột theo đúng mẫu (Attribute Name, Nullable?, Default Value, Business Rules / Constraints).
- Bỏ dòng ngày nộp (`business_rule.md`, báo cáo Word) và mục Đầu vào/Đầu ra ở tiêu đề `relational_schema_mapping.md`.

## Kiểm chứng trên PostgreSQL 18.6 + PostGIS (Windows)
- `schema.sql`, `seed.sql`, `queries.sql` (Q1-Q13, gồm Q13 dùng PostGIS) chạy không lỗi: cột `GEOMETRY(Point, 4326)`, chỉ mục GiST và hàm `ST_...` hoạt động, 5 bãi đỗ có SRID 4326.
- `tests.sql` đạt 33/33 (`ALL TESTS PASSED`) trên PostgreSQL 18.6 với PostGIS thật, và trên PostgreSQL 16 (không PostGIS, dùng kiểu `POINT` thay thế).
- Sửa `tests.sql` để tương thích PostgreSQL 18: ràng buộc `ON DELETE RESTRICT` báo SQLSTATE `23001` (`restrict_violation`) ở bản 18, còn bản 17 trở xuống báo `23503`. Hàm `expect_error` nay nhận nhiều mã, phân tách bằng dấu phẩy.

## Phase 4: giao diện và API giờ (`demo_app`)
- Thêm `GET /api/time`: giờ của CSDL (`Asia/Ho_Chi_Minh`) và khung giá đang áp dụng, suy ra từ `tariff_rate`.
- Thêm đồng hồ góc phải dưới ở mọi trang (`static/live.js`), đồng bộ với giờ server.
- Dùng giờ server trong luồng đặt xe: chặn khung giờ đã qua, đếm ngược tới giờ nhận chỗ và hạn giữ chỗ 30 phút, nhãn khung giá, xem trước giờ kết thúc và chi phí ước tính, khung "Phiên đang sạc" với chi phí tạm tính.
- Sửa kiểm tra CSRF: trước đây POST không có phiên (không có mã CSRF trong session) vẫn lọt qua vì so sánh `None == None`; nay bị từ chối với HTTP 400.
- Thêm `/register`: khách hàng tự đăng ký ở trang đăng nhập, kèm xe đầu tiên; vai trò luôn `CUSTOMER`, tài khoản và xe tạo trong một câu SQL, báo riêng lỗi trùng email, số điện thoại, biển số.
- Admin tạo MANAGER/ADMIN với mật khẩu **do admin tự nhập** (tối thiểu 8 ký tự), thay cho mật khẩu tạm ngẫu nhiên hiện một lần.
- `tests/test_app.py`: thêm 29 kiểm thử (API giờ, tính khung giá, trang khách/quản lý, đăng ký khách hàng, tạo tài khoản admin). Không đổi schema, quy tắc nghiệp vụ hay chuẩn hóa nên các tài liệu thiết kế giữ nguyên.

## Chưa thay đổi
- Chưa đo hiệu năng thực tế (`EXPLAIN ANALYZE`) cho NFR-01, NFR-02 và NFR-05; đây vẫn là mục tiêu thiết kế.

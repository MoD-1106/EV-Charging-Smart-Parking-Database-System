# Smart City EV Charging & Parking Management System — v0.3

Cơ sở dữ liệu quan hệ trên **PostgreSQL** để quản lý bãi đỗ xe tích hợp trạm sạc xe điện trong thành phố thông minh: đặt chỗ theo khung giờ, phiên sạc, tính giá động theo loại cổng / công suất / giờ và hóa đơn bất biến.

## Thành viên — Nhóm M3B
* **Nguyễn Trường Nghị** - n24dccn142@student.ptithcm.edu.vn (Project Owner) — truongnghi1106@gmail.com
* **Phạm Công Đang** - n24dccn102@student.ptithcm.edu.vn
* **Mai Văn Công** - n24dccn100@student.ptithcm.edu.vn

**Lớp:** D24CQCN02-N  **Giảng viên:** Lê Hà Thanh
**Trường:** Học viện Công nghệ Bưu chính Viễn thông (cơ sở TP.HCM)

## Cấu trúc thư mục
| File | Nội dung |
|---|---|
| `docs/business_rule.md` | Quy tắc nghiệp vụ, RBAC, đặc tả yêu cầu FR/NFR (ISO 29148) |
| `docs/ERD_Diagram.png`, `docs/erd.mmd` | ERD ký hiệu IE Crow's Foot (nguồn Mermaid) |
| `docs/data_dictionary.md` | Từ điển dữ liệu 10 bảng (ISO/IEC 11179) |
| `docs/normalization_proof.md` | Chứng minh chuẩn hóa tới BCNF |
| `schema.sql` | DDL, ràng buộc, trigger, hàm (PostgreSQL 14+, PostGIS, btree_gist) |
| `docs/relational_schema_mapping.md` | Ánh xạ ERD → lược đồ quan hệ (10 quan hệ, 12 khóa ngoại) |
| `seed.sql` | Dữ liệu mẫu (DML): 30 tài khoản, 5 bãi, 40 thiết bị, hơn 1.200 phiên sạc, nạp qua trigger |
| `queries.sql` | 13 truy vấn phân tích (join, subquery, aggregation, window, PostGIS) |
| `tests.sql` | 33 kiểm thử tự động cho các ràng buộc và trigger |
| `CHANGELOG.md` | Thay đổi so với v0.2.1 |
| `database_report_v0.3.docx` | Báo cáo Word đã đồng bộ với các file trên |
| `demo_app/` | Ứng dụng demo Flask + psycopg 3 cho ADMIN / MANAGER / CUSTOMER (Phase 4), xem `demo_app/README_DEMO.md` |
| `tests/test_app.py` | Kiểm thử pytest cho `demo_app` (không cần kết nối CSDL) |
| `run_tests.ps1` | Chạy `tests.sql` và pytest trên Windows, ghi kết quả vào `ket_qua/` (không đưa lên Git) |

Chạy thử (CSDL rỗng):

```bash
createdb evt
psql -d evt -v ON_ERROR_STOP=1 -f schema.sql
psql -d evt -v ON_ERROR_STOP=1 -f seed.sql
psql -d evt -f queries.sql

createdb evt_test            # tests.sql dùng CSDL riêng (tự chèn bảng giá, có ROLLBACK)
psql -d evt_test -f schema.sql
psql -d evt_test -v ON_ERROR_STOP=1 -f tests.sql
```

## Tiêu chuẩn tuân thủ
- **ISO/IEC/IEEE 29148** — đặc tả yêu cầu (mục 5 của `business_rule.md`).
- **IE Crow's Foot (ISO/IEC 19505)** — ký hiệu ERD.
- **ISO/IEC 11179** — đặt tên metadata (hậu tố `_identifier`, `_code`, `_text`, `_count`, `_datetime`, `_time`, `_kw`, `_kwh`, `_value`, `_number`).
- **ISO 8601** — `TIMESTAMPTZ`.
- **ISO 6709 / WGS 84 (EPSG:4326)** — vị trí bằng PostGIS `GEOMETRY(Point, 4326)`.
- **ISO 4217** — mã tiền tệ (`VND`, `USD`).
- **ISO 15118 & OCPP** — định danh điểm sạc `evse_identifier`.
- **SQLStyle.guide** — snake_case, từ khóa SQL viết hoa.

## Tóm tắt quy tắc nghiệp vụ

### 1. Người dùng & phương tiện
- `user_account` đăng ký bằng email và số điện thoại (duy nhất trong tài khoản chưa xóa); vai trò `CUSTOMER`, `MANAGER`, `ADMIN`.
- Một khách sở hữu nhiều `vehicle` (biển số duy nhất). Lượt đặt chỗ và phiên sạc luôn gắn với một xe.
- Chỉ `ADMIN` phân công `MANAGER` phụ trách một hoặc nhiều `parking_facility`.

### 2. Hạ tầng & trạng thái
- `parking_facility` có tọa độ WGS 84 và sức chứa thiết kế; số `parking_space` không vượt sức chứa.
- `parking_space` ↔ `charging_equipment` là quan hệ mở rộng **1:1 tùy chọn**; thiết bị phân loại `FAST_DC` / `STANDARD_AC` và có công suất định mức.
- Ô đỗ có 4 trạng thái: `AVAILABLE`, `RESERVED`, `OCCUPIED`, `OUTOFSERVICE`. Thiết bị `FAULT`/`MAINTENANCE` ⇒ ô `OUTOFSERVICE`.

### 3. Đặt chỗ
- Đặt chỗ được khi ô không `OUTOFSERVICE` và **khung giờ không chồng** lượt đặt đang giữ chỗ (`EXCLUDE` GiST trên `tstzrange`).
- Trạng thái: `PENDING` → `CONFIRMED` → `FULFILLED`; hoặc `CANCELLED` (khách hủy) / `EXPIRED` (hệ thống hủy).
- **Quá 30 phút** kể từ giờ bắt đầu mà chưa kích hoạt phiên sạc ⇒ `EXPIRED`, ô đỗ được giải phóng và khung giờ được trả lại.

### 4. Giá động & thanh toán
- `tariff_rate` theo (loại cổng, khung giờ, dải công suất); khung giờ phủ kín 24 giờ: cao điểm 17:00–20:00, thấp điểm 22:00–05:00, còn lại giờ thường. Mức giá chọn theo **giờ bắt đầu phiên**.
- Hóa đơn:

  ```text
  Tổng = (consumed_energy_kwh × price_per_kwh_value) + (giờ đỗ quá sau khi sạc đầy × overtime_fee_per_hour_value)
  ```

- Mỗi phiên kết thúc tự tạo đúng một `payment_transaction` (1:1); hóa đơn bất biến, không xóa được.

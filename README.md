# Smart City EV Charging & Parking Management System — v0.3.1

Cơ sở dữ liệu quan hệ trên **PostgreSQL** để quản lý bãi đỗ xe tích hợp trạm sạc xe điện trong thành phố thông minh: đặt chỗ theo khung giờ, phiên sạc, tính giá động theo loại cổng / công suất / giờ và hóa đơn bất biến.

## Mục lục
1. [Thành viên](#thành-viên--nhóm-m3b)
2. [Cấu trúc thư mục](#cấu-trúc-thư-mục)
3. [Công nghệ và yêu cầu môi trường](#công-nghệ-và-yêu-cầu-môi-trường)
4. [Chạy thử](#chạy-thử)
5. [Mô hình dữ liệu](#mô-hình-dữ-liệu)
6. [Tiêu chuẩn được áp dụng](#tiêu-chuẩn-được-áp-dụng)
7. [Định nghĩa biến và thuật ngữ](#định-nghĩa-biến-và-thuật-ngữ)
8. [Tóm tắt quy tắc nghiệp vụ](#tóm-tắt-quy-tắc-nghiệp-vụ)
9. [Ràng buộc, trigger và hàm](#ràng-buộc-trigger-và-hàm)
10. [Kiểm thử](#kiểm-thử)

## Thành viên — Nhóm M3B
| Họ và tên | MSSV | Email | Vai trò |
|---|---|---|---|
| Nguyễn Trường Nghị | N24DCCN142 | n24dccn142@student.ptithcm.edu.vn | Project Owner |
| Phạm Công Đang | N24DCCN102 | n24dccn102@student.ptithcm.edu.vn | Thành viên |
| Mai Văn Công | N24DCCN100 | n24dccn100@student.ptithcm.edu.vn | Thành viên |

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
| `seed.sql` | Dữ liệu mẫu (DML) tất định: 30 tài khoản, 5 bãi, 40 thiết bị, 1.220 phiên sạc, nạp qua trigger |
| `queries.sql` | 13 truy vấn phân tích (join, subquery, aggregation, window, PostGIS) |
| `tests.sql` | 33 kiểm thử tự động cho các ràng buộc và trigger |
| `CHANGELOG.md` | Lịch sử thay đổi: v0.2.1 → v0.3 → v0.3.1 |
| `database_report_v0.3.1.docx` | Báo cáo Word đã đồng bộ với các file trên (có mục F: Phase 4) |
| `demo_app/` | Ứng dụng demo Flask + psycopg 3 cho ADMIN / MANAGER / CUSTOMER (Phase 4), xem `demo_app/README_DEMO.md` |
| `tests/test_app.py` | Kiểm thử pytest cho `demo_app` (không cần kết nối CSDL) |
| `run_tests.ps1` | Chạy `tests.sql` và pytest trên Windows, ghi kết quả vào `ket_qua/` (không đưa lên Git) |

## Công nghệ và yêu cầu môi trường
| Thành phần | Phiên bản / ghi chú |
|---|---|
| PostgreSQL | 14 trở lên (đã kiểm chứng trên 18.6 và 16) |
| Extension `postgis` | Bắt buộc cho cột `GEOMETRY(Point, 4326)`, chỉ mục GiST và truy vấn Q13 |
| Extension `btree_gist` | Bắt buộc cho các ràng buộc `EXCLUDE` (chống chồng giờ đặt chỗ, chống chồng ô giá) |
| Extension `pg_cron` | Tùy chọn, để gọi `fn_expire_overdue_reservations()` mỗi phút |
| Python | 3.9 trở lên cho `demo_app` (đã chạy trên 3.13); Flask ≥ 3.0, psycopg[binary] ≥ 3.1 |

## Chạy thử

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

Chạy ứng dụng demo (Phase 4): xem [`demo_app/README_DEMO.md`](demo_app/README_DEMO.md).

## Mô hình dữ liệu
Lược đồ gồm **10 bảng** (sơ đồ đầy đủ: `docs/ERD_Diagram.png`; mô tả từng cột: `docs/data_dictionary.md`).

| Bảng | Vai trò | Quan hệ chính |
|---|---|---|
| `user_account` | Tài khoản, phân loại bằng `role_code` | 1:N `vehicle`; N:M `parking_facility` qua `facility_manager` |
| `vehicle` | Xe điện của khách | N:1 `user_account`; 1:N `reservation`, `service_session` |
| `parking_facility` | Bãi đỗ (có tọa độ WGS 84, sức chứa thiết kế) | 1:N `parking_space` |
| `facility_manager` | Bảng trung gian MANAGER ↔ bãi | N:M |
| `parking_space` | Ô đỗ | 1:1 tùy chọn `charging_equipment`; 1:N `reservation` |
| `charging_equipment` | Trụ sạc gắn với một ô đỗ | 1:N `service_session` |
| `tariff_rate` | Ô giá theo (loại cổng, khung giờ, dải công suất) | 1:N `payment_transaction` |
| `reservation` | Lượt đặt chỗ theo khung giờ | 0..1:1 `service_session` |
| `service_session` | Phiên sạc thực tế | 1:1 `payment_transaction` |
| `payment_transaction` | Hóa đơn, bất biến | N:1 `tariff_rate` |

Lược đồ đạt **BCNF**; chứng minh ở `docs/normalization_proof.md`. Dữ liệu dư thừa có kiểm soát (trạng thái ô đỗ, tiền hóa đơn, sức chứa) được liệt kê ở mục 11 của `docs/data_dictionary.md`.

## Tiêu chuẩn được áp dụng

| Tiêu chuẩn | Áp dụng cho | Nơi thể hiện |
|---|---|---|
| **ISO/IEC/IEEE 29148** (thay IEEE 830) | Đặc tả yêu cầu: tách yêu cầu người dùng (UR) với yêu cầu hệ thống (FR/NFR), liệt kê quy tắc nghiệp vụ | `docs/business_rule.md` mục 5 |
| **IE Crow's Foot (ISO/IEC 19505 / Information Engineering)** | Ký hiệu ERD; không dùng EER của Elmasri nên không cần Mapping Appendix | `docs/ERD_Diagram.png`, `docs/erd.mmd` |
| **Quy tắc ánh xạ ER → quan hệ (Elmasri & Navathe)** | Ánh xạ thực thể mạnh, 1:1, 1:N, M:N, chuyên biệt hóa, thuộc tính suy diễn | `docs/relational_schema_mapping.md` |
| **Chuẩn hóa 3NF / BCNF** | Loại bỏ phụ thuộc hàm không xuất phát từ khóa | `docs/normalization_proof.md` |
| **ISO/IEC 11179** (metadata registry) | Đặt tên cột theo *representation term* (hậu tố); từ điển dữ liệu có đủ kiểu, khóa, nullable, mặc định, ràng buộc | `docs/data_dictionary.md` |
| **ISO 8601** | Thời điểm lưu bằng `TIMESTAMPTZ` (UTC), hiển thị theo `Asia/Ho_Chi_Minh` | `schema.sql`, API `/api/time` |
| **ISO 6709 / WGS 84 (EPSG:4326)** | Vị trí bãi đỗ bằng PostGIS `GEOMETRY(Point, 4326)` | `parking_facility.geographic_location` |
| **ISO 4217** | Mã tiền tệ `VND`, `USD` | `payment_transaction.currency_code` |
| **ISO 15118 & OCPP** | Định danh điểm sạc `evse_identifier` tương thích giao thức trạm sạc | `charging_equipment.evse_identifier` |
| **SQLStyle.guide (Simon Holywell)** | `lowercase snake_case` cho định danh, từ khóa SQL viết hoa, thụt lề cho join và subquery | Toàn bộ `*.sql` |

## Định nghĩa biến và thuật ngữ

### 1. Hậu tố tên cột (ISO/IEC 11179)
Mọi cột kết thúc bằng một *representation term* cho biết kiểu ý nghĩa của giá trị.

| Hậu tố | Ý nghĩa | Kiểu dữ liệu | Ví dụ |
|---|---|---|---|
| `_identifier` | Định danh | `UUID` (riêng `evse_identifier`: `VARCHAR`) | `account_identifier` |
| `_code` | Mã hoặc phân loại thuộc tập giá trị đóng | `VARCHAR` + `CHECK` | `role_code` |
| `_text` | Chuỗi mô tả | `VARCHAR` | `full_name_text` |
| `_count` | Số lượng đếm | `INT` | `total_capacity_count` |
| `_datetime` | Thời điểm (có múi giờ) | `TIMESTAMPTZ` | `start_datetime` |
| `_time` | Giờ trong ngày | `TIME` | `start_time` |
| `_kw` | Công suất, đơn vị kW | `DECIMAL(10,2)` | `max_power_kw` |
| `_kwh` | Điện năng, đơn vị kWh | `DECIMAL(10,2)` | `consumed_energy_kwh` |
| `_value` | Giá trị số, thường là tiền | `DECIMAL(10,2)` hoặc `(12,2)` | `price_per_kwh_value` |
| `_number` | Số điện thoại | `VARCHAR` | `contact_phone_number` |
| `_location` | Tọa độ địa lý | `GEOMETRY(Point, 4326)` | `geographic_location` |

Tiền tố của đối tượng CSDL: `ux_` (chỉ mục duy nhất), `ix_` (chỉ mục thường), `ex_` (ràng buộc `EXCLUDE`), `fn_` (hàm), `trg_` (trigger).
Ký hiệu khóa trong từ điển dữ liệu: `PK` khóa chính, `FK` khóa ngoại, `UK` duy nhất, `UK*` duy nhất **từng phần** (`WHERE deleted_datetime IS NULL`, để bản ghi đã xóa mềm không chiếm khóa).

### 2. Giá trị của các cột `*_code`
| Cột | Giá trị | Ý nghĩa |
|---|---|---|
| `user_account.role_code` | `CUSTOMER` | Khách hàng, mặc định khi đăng ký |
| | `MANAGER` | Quản lý, chỉ thấy bãi được phân công |
| | `ADMIN` | Quản trị, phân công MANAGER, cấu hình giá |
| `parking_space.availability_status_code` | `AVAILABLE` | Trống |
| | `RESERVED` | Đang trong khung giờ của lượt đặt `CONFIRMED` |
| | `OCCUPIED` | Đang có phiên sạc |
| | `OUTOFSERVICE` | Ngừng hoạt động (thiết bị `FAULT`/`MAINTENANCE`) |
| `charging_equipment.connector_type_code` | `FAST_DC` | Sạc nhanh một chiều |
| | `STANDARD_AC` | Sạc thường xoay chiều |
| `charging_equipment.equipment_status_code` | `READY`, `CHARGING`, `FAULT`, `MAINTENANCE` | Sẵn sàng, đang sạc, lỗi, bảo trì |
| `tariff_rate.time_band_code` | `PEAK` | Cao điểm 17:00–20:00 |
| | `STANDARD` | Giờ thường 05:00–17:00 và 20:00–22:00 |
| | `OFF_PEAK` | Thấp điểm 22:00–05:00 |
| `reservation.reservation_status_code` | `PENDING` → `CONFIRMED` → `FULFILLED` | Chờ xác nhận, đã xác nhận, đã kích hoạt phiên sạc |
| | `CANCELLED` | Khách hủy |
| | `EXPIRED` | Hệ thống hủy do quá 30 phút |
| `payment_transaction.transaction_status_code` | `PENDING`, `SUCCESS`, `FAILED`, `REFUNDED` | Chờ thanh toán, thành công, thất bại, hoàn tiền |
| `payment_transaction.payment_method_code` | `CREDIT_CARD`, `E_WALLET`, `BANK_TRANSFER` | Thẻ, ví điện tử, chuyển khoản |
| `payment_transaction.currency_code` | `VND`, `USD` | Tiền tệ theo ISO 4217 |

### 3. Biến trong công thức tính hóa đơn
| Biến | Nguồn | Ý nghĩa |
|---|---|---|
| `consumed_energy_kwh` | `service_session` | Điện năng đã sạc (kWh) |
| `price_per_kwh_value` | `tariff_rate` | Đơn giá điện (VND/kWh) của ô giá được chọn |
| `overtime_fee_per_hour_value` | `tariff_rate` | Phí đỗ quá giờ sau khi sạc đầy (VND/giờ) |
| `fully_charged_datetime` | `service_session` | Thời điểm pin đầy; `NULL` nghĩa là chưa ghi nhận sạc đầy |
| `end_datetime` | `service_session` | Thời điểm kết thúc phiên |
| `overtime_hours` | suy ra | `max(0, end_datetime − fully_charged_datetime)` tính bằng giờ; bằng 0 nếu chưa sạc đầy |
| `energy_amount_value` | `payment_transaction` | Tiền điện = `consumed_energy_kwh × price_per_kwh_value` |
| `overtime_amount_value` | `payment_transaction` | Tiền quá giờ = `overtime_hours × overtime_fee_per_hour_value` |
| `transaction_amount_value` | `payment_transaction` | Tổng tiền = `energy_amount_value + overtime_amount_value` (ràng buộc `CHECK`) |

Ô giá được chọn bằng `fn_select_tariff` theo ba điều kiện: loại cổng của thiết bị, **giờ bắt đầu phiên** (giờ địa phương `Asia/Ho_Chi_Minh`) nằm trong `[start_time, end_time)`, và `charging_equipment.max_power_kw` nằm trong `[min_power_kw, max_power_kw)`. Một phiên chỉ áp dụng một ô giá, kể cả khi kéo dài qua nhiều khung giờ.

### 4. Hằng số và tham số hệ thống
| Tên | Giá trị | Ý nghĩa |
|---|---|---|
| Hạn giữ chỗ | 30 phút | Quá hạn kể từ `start_datetime` mà chưa có phiên sạc thì lượt đặt chuyển `EXPIRED` |
| Múi giờ nghiệp vụ | `Asia/Ho_Chi_Minh` | Dùng để chọn khung giá và hiển thị; dữ liệu lưu ở UTC |
| SRID | 4326 | Hệ tọa độ WGS 84 của vị trí bãi đỗ |
| Khung giờ | `[start_time, end_time)` | Khoảng nửa mở, không vắt qua nửa đêm (khung 22:00–05:00 lưu thành hai dòng) |
| Dải công suất | `[min_power_kw, max_power_kw)` | Khoảng nửa mở, so với công suất định mức của thiết bị |
| `total_capacity_count` | Do ADMIN khai báo | Sức chứa thiết kế của bãi; số ô chưa xóa không được vượt giá trị này |

### 5. Biến môi trường của `demo_app`
| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `DATABASE_URL` | `postgresql://postgres@localhost:5432/evt` | Chuỗi kết nối PostgreSQL |
| `SECRET_KEY` | `dev-only-change-me` | Khóa ký phiên Flask và mã CSRF; **phải đổi khi chạy thật** |

### 6. Từ viết tắt
| Viết tắt | Nghĩa |
|---|---|
| UR / FR / NFR | User Requirement / Functional Requirement / Non-Functional Requirement |
| RBAC | Role-Based Access Control, phân quyền theo vai trò |
| ERD / IE | Entity-Relationship Diagram / Information Engineering |
| FD | Functional Dependency, phụ thuộc hàm |
| 3NF / BCNF | Dạng chuẩn 3 / dạng chuẩn Boyce-Codd |
| EVSE | Electric Vehicle Supply Equipment, điểm cấp điện cho xe |
| OCPP | Open Charge Point Protocol |
| GiST | Generalized Search Tree, kiểu chỉ mục cho phạm vi và không gian |
| PostGIS / SRID | Extension dữ liệu không gian của PostgreSQL / mã hệ tọa độ |
| DDL / DML | Ngôn ngữ định nghĩa / thao tác dữ liệu |

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

### 5. Phân quyền (RBAC)
| Vai trò | Quyền chính |
|---|---|
| `CUSTOMER` | Quản lý xe của mình, tìm ô trống, đặt và hủy chỗ, xem và thanh toán hóa đơn của mình |
| `MANAGER` | Xem sơ đồ ô và thiết bị của bãi được phân công, báo `FAULT`/`MAINTENANCE`, xác nhận hoặc hủy lượt đặt |
| `ADMIN` | Quản lý bãi, ô, thiết bị, phân công MANAGER, cấu hình biểu giá, xem doanh thu và đối soát |

Ma trận đầy đủ ở mục 3 của `docs/business_rule.md`.

## Ràng buộc, trigger và hàm
| Đối tượng | Chức năng | Yêu cầu |
|---|---|---|
| `ex_reservation_no_overlap` | Chặn hai lượt đặt giữ chỗ chồng giờ trên cùng ô; lượt `CANCELLED`, `EXPIRED` hoặc đã xóa không chiếm khung giờ | FR-01 |
| `ex_tariff_rate_no_overlap` | Chặn hai ô giá cùng loại cổng chồng cả giờ lẫn công suất | FR-03 |
| `ux_service_session_open_equipment` | Mỗi thiết bị tối đa một phiên đang mở | NFR-03 |
| `fn_expire_overdue_reservations()` | Chuyển lượt đặt quá 30 phút sang `EXPIRED` (gọi bằng `pg_cron` mỗi phút) | FR-02 |
| `fn_refresh_reserved_spaces()` | Đồng bộ cờ `RESERVED` của ô đỗ với bảng đặt chỗ | FR-05 |
| `fn_is_space_available(space, start, end)` | Kiểm tra ô còn trống trong cả khung giờ yêu cầu | FR-01 |
| `fn_select_tariff` | Chọn ô giá theo loại cổng, giờ bắt đầu phiên và công suất | FR-03 |
| `trg_reservation_validate` | Từ chối đặt ô đã xóa hoặc `OUTOFSERVICE`, hoặc xe đã xóa | FR-01 |
| `trg_session_validate` | Kiểm tra phiên khớp lượt đặt (cùng xe, cùng ô), thiết bị không lỗi, khách vãng lai không đè lịch đã đặt | FR-01 |
| `trg_session_start` | Ô → `OCCUPIED`, thiết bị → `CHARGING`, lượt đặt → `FULFILLED` | FR-05 |
| `trg_session_finish` | Giải phóng thiết bị và ô, tự lập đúng một hóa đơn | FR-04 |
| `trg_equipment_status_sync` | Thiết bị `FAULT`/`MAINTENANCE` ⇒ ô `OUTOFSERVICE` | FR-05 |
| `trg_space_capacity` | Chặn thêm ô vượt sức chứa của bãi | FR-06 |
| `trg_facility_manager_role` | Chỉ tài khoản `MANAGER` chưa xóa được phân công bãi | FR-07 |
| `trg_payment_immutable` | Cấm xóa hóa đơn, cấm sửa phiên, ô giá, số tiền và tiền tệ | FR-08 |

## Kiểm thử
| Bộ kiểm thử | Phạm vi | Cách chạy |
|---|---|---|
| `tests.sql` | 33 kiểm thử ràng buộc và trigger; chạy trong giao dịch có `ROLLBACK` trên CSDL riêng | `psql -d evt_test -v ON_ERROR_STOP=1 -f tests.sql` |
| `tests/test_app.py` | pytest cho `demo_app` (API giờ, tính khung giá, trang khách và quản lý, đăng ký, tạo tài khoản admin), không cần CSDL | `pytest tests` |
| `run_tests.ps1` | Chạy cả hai bộ trên Windows, ghi kết quả vào `ket_qua/` (không đưa lên Git) | `./run_tests.ps1` |

Lưu ý tương thích: ràng buộc `ON DELETE RESTRICT` báo SQLSTATE `23001` ở PostgreSQL 18 nhưng `23503` ở bản 17 trở xuống; `tests.sql` chấp nhận cả hai mã.

Chưa đo hiệu năng thực tế (`EXPLAIN ANALYZE`) cho NFR-01, NFR-02 và NFR-05; đây vẫn là mục tiêu thiết kế.

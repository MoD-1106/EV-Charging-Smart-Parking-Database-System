# Từ điển Dữ liệu (Data Dictionary)
## Dự án: Smart City EV Charging & Parking Management (theo ISO/IEC 11179)
**Nhóm:** M3B | **Môn:** INT1313 Cơ sở dữ liệu

* Thành viên nhóm:
  * Nguyễn Trường Nghị - n24dccn142@student.ptithcm.edu.vn
  * Phạm Công Đang - n24dccn102@student.ptithcm.edu.vn
  * Mai Văn Công - n24dccn100@student.ptithcm.edu.vn

> Tài liệu này khớp 1-1 với `schema.sql`. Mọi ràng buộc ghi ở đây đã được kiểm thử bằng `tests.sql`.

## 0. Quy ước đặt tên (ISO/IEC 11179)

Tên bảng và cột dùng `lowercase snake_case`. Mỗi cột kết thúc bằng một **representation term**:

| Hậu tố | Ý nghĩa | Ví dụ |
|---|---|---|
| `_identifier` | Định danh | `account_identifier` |
| `_code` | Mã/phân loại (tập giá trị đóng) | `role_code` |
| `_text` | Chuỗi mô tả | `full_name_text` |
| `_count` | Số lượng đếm | `total_capacity_count` |
| `_datetime` | Thời điểm (`TIMESTAMPTZ`, ISO 8601) | `start_datetime` |
| `_time` | Giờ trong ngày (`TIME`) | `start_time` |
| `_kw`, `_kwh` | Công suất, điện năng | `max_power_kw` |
| `_value` | Giá trị số / tiền tệ | `price_per_kwh_value` |
| `_number`, `_location` | Số điện thoại, tọa độ | `contact_phone_number` |

Các hậu tố `_amount` ở bản cũ được thống nhất thành `_value`. Các cột đổi tên so với v0.2: `deleted_at → deleted_datetime`, `license_plate → license_plate_text`, `gateway_reference_id → gateway_reference_identifier`.

**Ký hiệu Key Type:** PK, FK, UK. `UK*` = ràng buộc duy nhất **từng phần** (`WHERE deleted_datetime IS NULL`), để bản ghi đã xóa mềm không chiếm khóa.

---

## 1. USER_ACCOUNT

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `account_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh tài khoản. |
| `full_name_text` | VARCHAR(100) | None | No | None | Họ và tên. |
| `contact_phone_number` | VARCHAR(15) | UK* | No | None | CHECK `~ '^\+?[0-9]{8,14}$'`; duy nhất trong các tài khoản chưa xóa. |
| `email_address` | VARCHAR(255) | UK* | No | None | Duy nhất không phân biệt hoa/thường (`lower(email_address)`). |
| `password_hash_text` | VARCHAR(255) | None | No | None | Mật khẩu đã băm (bcrypt/argon2); không lưu mật khẩu thô. |
| `role_code` | VARCHAR(20) | None | No | `'CUSTOMER'` | CHECK: `CUSTOMER`, `MANAGER`, `ADMIN`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm tạo tài khoản. |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 2. VEHICLE

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `vehicle_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phương tiện. |
| `account_identifier` | UUID | FK | No | None | → `user_account`; `ON DELETE CASCADE`. Chủ xe. |
| `license_plate_text` | VARCHAR(20) | UK* | No | None | Biển số; duy nhất trong các xe chưa xóa (đăng ký lại được sau xóa mềm). |
| `battery_capacity_kwh` | DECIMAL(10,2) | None | No | None | CHECK `> 0`. |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 3. PARKING_FACILITY

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `facility_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh bãi đỗ. |
| `facility_name_text` | VARCHAR(100) | None | No | None | Tên bãi. |
| `geographic_location` | GEOMETRY(Point, 4326) | None | No | None | PostGIS WGS 84; có chỉ mục GiST. |
| `address_text` | VARCHAR(255) | None | No | None | Địa chỉ. |
| `total_capacity_count` | INT | None | No | None | CHECK `> 0`. **Sức chứa thiết kế** (do Admin khai báo, không suy ra từ dữ liệu); số `parking_space` chưa xóa không được vượt giá trị này (trigger `trg_space_capacity`). |

## 4. FACILITY_MANAGER

Bảng trung gian N:M giữa `USER_ACCOUNT` (vai trò `MANAGER`) và `PARKING_FACILITY`.

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `manager_identifier` | UUID | PK, FK | No | None | → `user_account`; `ON DELETE CASCADE`. Trigger `trg_facility_manager_role` bắt buộc tài khoản là `MANAGER` chưa xóa. |
| `facility_identifier` | UUID | PK, FK | No | None | → `parking_facility`; `ON DELETE CASCADE`. |

## 5. PARKING_SPACE

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `space_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh ô đỗ. |
| `facility_identifier` | UUID | FK | No | None | → `parking_facility`; `ON DELETE CASCADE`. |
| `space_code` | VARCHAR(10) | UK* | No | None | Ví dụ `A-01`; duy nhất theo (`facility_identifier`, `space_code`) trong các ô chưa xóa. |
| `availability_status_code` | VARCHAR(20) | None | No | `'AVAILABLE'` | CHECK: `AVAILABLE`, `RESERVED`, `OCCUPIED`, `OUTOFSERVICE`. Là **trạng thái vận hành hiện tại** (xem mục 11). |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 6. CHARGING_EQUIPMENT

Quan hệ mở rộng 1:1 (tùy chọn) với `PARKING_SPACE`: ô đỗ thường không có dòng ở bảng này.

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `equipment_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh thiết bị sạc. |
| `space_identifier` | UUID | FK, UK* | No | None | → `parking_space`; `ON DELETE CASCADE`; UNIQUE bảo đảm 1:1. |
| `evse_identifier` | VARCHAR(50) | UK* | No | None | Mã điểm sạc (ISO 15118 / OCPP). |
| `connector_type_code` | VARCHAR(50) | None | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK `> 0`. Công suất **định mức**; dùng để chọn dải giá trong `tariff_rate`. |
| `equipment_status_code` | VARCHAR(20) | None | No | `'READY'` | CHECK: `READY`, `CHARGING`, `FAULT`, `MAINTENANCE`. `FAULT`/`MAINTENANCE` ⇒ ô đỗ `OUTOFSERVICE` (trigger `trg_equipment_status_sync`). |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 7. TARIFF_RATE

Mỗi dòng là một **ô giá** theo (loại cổng, khung giờ, dải công suất). Quy ước:
* Khung giờ **không vắt qua nửa đêm**: `22:00–05:00` lưu thành hai dòng `22:00–24:00` và `00:00–05:00`. Khoảng thời gian là nửa mở `[start_time, end_time)`.
* Dải công suất nửa mở `[min_power_kw, max_power_kw)`, so với `charging_equipment.max_power_kw`.
* Giờ theo múi `Asia/Ho_Chi_Minh`; **mức giá được chọn theo thời điểm bắt đầu phiên sạc** (`fn_select_tariff`).
* Để bao phủ 24 giờ: `OFF_PEAK` 22:00–05:00, `PEAK` 17:00–20:00, `STANDARD` 05:00–17:00 và 20:00–22:00.

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `rate_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh ô giá. |
| `connector_type_code` | VARCHAR(50) | None | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `time_band_code` | VARCHAR(20) | None | No | None | CHECK: `PEAK`, `STANDARD`, `OFF_PEAK` (nhãn mô tả). |
| `start_time` | TIME | None | No | None | Bắt đầu khung giờ (bao gồm). |
| `end_time` | TIME | None | No | None | CHECK `end_time > start_time`; có thể là `24:00`. |
| `min_power_kw` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`. |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK `> min_power_kw`. |
| `price_per_kwh_value` | DECIMAL(10,2) | None | No | None | CHECK `>= 0`; VND/kWh. |
| `overtime_fee_per_hour_value` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`; VND/giờ. |
| `ex_tariff_rate_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (connector_type_code WITH =, int4range(giây(start_time), giây(end_time)) WITH &&, numrange(min_power_kw, max_power_kw) WITH &&)` — hai ô giá cùng loại cổng không được chồng cả giờ lẫn công suất. |

## 8. RESERVATION

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `reservation_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh lượt đặt. |
| `vehicle_identifier` | UUID | FK | No | None | → `vehicle`; `ON DELETE RESTRICT`. Tài khoản đặt chỗ suy ra qua `vehicle.account_identifier`. |
| `space_identifier` | UUID | FK | No | None | → `parking_space`; `ON DELETE RESTRICT`. |
| `start_datetime` | TIMESTAMPTZ | None | No | None | Bắt đầu dự kiến. |
| `end_datetime` | TIMESTAMPTZ | None | No | None | CHECK `end_datetime > start_datetime`. |
| `reservation_status_code` | VARCHAR(20) | None | No | `'PENDING'` | CHECK: `PENDING`, `CONFIRMED`, `FULFILLED` (đã kích hoạt phiên sạc), `CANCELLED` (khách hủy), `EXPIRED` (quá 30 phút, hệ thống hủy). |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm tạo. |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |
| `ex_reservation_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (space_identifier WITH =, tstzrange(start_datetime, end_datetime) WITH &&) WHERE (reservation_status_code IN ('PENDING','CONFIRMED','FULFILLED') AND deleted_datetime IS NULL)`. Lượt `CANCELLED`/`EXPIRED`/đã xóa **không** chiếm khung giờ. Yêu cầu extension `btree_gist`. |

Trigger `trg_reservation_validate` (khi INSERT): từ chối nếu ô đỗ đã xóa hoặc `OUTOFSERVICE`, hoặc xe đã xóa.

## 9. SERVICE_SESSION

Chủ tài khoản của phiên suy ra qua `vehicle.account_identifier` (không lặp cột `account_identifier`).

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `session_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phiên. |
| `reservation_identifier` | UUID | FK, UK | Yes | `NULL` | → `reservation`; `ON DELETE SET NULL`; UNIQUE (một lượt đặt chỉ sinh tối đa một phiên). NULL = khách vãng lai. |
| `vehicle_identifier` | UUID | FK | No | None | → `vehicle`; `ON DELETE RESTRICT`. |
| `equipment_identifier` | UUID | FK | No | None | → `charging_equipment`; `ON DELETE RESTRICT`. |
| `start_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm cắm sạc thực tế. |
| `end_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `>= start_datetime`. Khi chuyển từ NULL sang có giá trị, trigger `trg_session_finish` giải phóng thiết bị và **tự lập hóa đơn**. |
| `fully_charged_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `>= start_datetime` và `<= end_datetime` (nếu có). |
| `peak_charging_power_kw` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`. |
| `consumed_energy_kwh` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`. |

Ràng buộc bổ sung: chỉ mục duy nhất từng phần `ux_service_session_open_equipment` (mỗi thiết bị tối đa một phiên đang mở); trigger `trg_session_validate` kiểm tra phiên khớp với lượt đặt (cùng xe, cùng ô), thiết bị không `FAULT`/`MAINTENANCE`, và khách vãng lai không được bắt đầu trong khung giờ đã được người khác đặt.

## 10. PAYMENT_TRANSACTION

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `transaction_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh giao dịch. |
| `session_identifier` | UUID | FK, UK | No | None | → `service_session`; `ON DELETE RESTRICT`; quan hệ 1:1. |
| `rate_identifier` | UUID | FK | No | None | → `tariff_rate`; `ON DELETE RESTRICT`. Ô giá được áp dụng (chọn theo giờ bắt đầu phiên). |
| `energy_amount_value` | DECIMAL(12,2) | None | No | None | `consumed_energy_kwh × price_per_kwh_value`. |
| `overtime_amount_value` | DECIMAL(12,2) | None | No | `0.00` | `max(0, (end_datetime − fully_charged_datetime) tính bằng giờ) × overtime_fee_per_hour_value`. |
| `transaction_amount_value` | DECIMAL(12,2) | None | No | None | CHECK `= energy_amount_value + overtime_amount_value`. Số tiền **chốt** tại thời điểm xuất hóa đơn. |
| `currency_code` | CHAR(3) | None | No | `'VND'` | CHECK: `VND`, `USD` (ISO 4217). |
| `payment_method_code` | VARCHAR(50) | None | Yes | `NULL` | CHECK: `CREDIT_CARD`, `E_WALLET`, `BANK_TRANSFER`. NULL cho tới khi khách chọn cách thanh toán. |
| `gateway_reference_identifier` | VARCHAR(100) | None | Yes | `NULL` | Mã đối soát từ cổng (MoMo, VNPay, Stripe). NULL khi giao dịch còn `PENDING`. |
| `transaction_status_code` | VARCHAR(20) | None | No | `'PENDING'` | CHECK: `PENDING`, `SUCCESS`, `FAILED`, `REFUNDED`. `SUCCESS` yêu cầu đã có `payment_method_code` và `gateway_reference_identifier`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm tạo. |

Bất biến: trigger `trg_payment_immutable` cấm `DELETE` và cấm sửa session, rate, các số tiền, tiền tệ; chỉ cho cập nhật trạng thái, phương thức và mã cổng.

---

## 11. Ghi chú thiết kế về dữ liệu có kiểm soát dư thừa

| Dữ liệu | Lý do giữ | Cơ chế giữ nhất quán |
|---|---|---|
| `parking_space.availability_status_code` | Hiển thị bản đồ thời gian thực, truy vấn nhanh. Là trạng thái **tại thời điểm hiện tại**, không phải lịch tương lai. | Triggers `trg_equipment_status_sync`, `trg_session_start/finish`; hàm `fn_refresh_reserved_spaces()` (pg_cron). |
| Khả dụng của **khung giờ yêu cầu** | Rule "chỉ đặt chỗ khi `AVAILABLE` trong toàn bộ khung giờ". | Không lưu cột; tính bằng `fn_is_space_available(space, start, end)` + `EXCLUDE` trên `reservation`. |
| `transaction_amount_value` và các thành phần | Hóa đơn phải bất biến dù bảng giá đổi sau này. | `CHECK` tổng = thành phần; trigger bất biến. |
| `total_capacity_count` | Giá trị thiết kế, không phải số đếm. | Trigger `trg_space_capacity`. |

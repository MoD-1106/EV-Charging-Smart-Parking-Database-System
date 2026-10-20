# Từ điển Dữ liệu (Data Dictionary)
## Dự án: Smart City EV Charging & Parking Management (Theo chuẩn ISO/IEC 11179)
**Nhóm:** M3B | **Môn:** Cơ sở dữ liệu
* Thành viên nhóm:
  * Nguyễn Trường Nghị - n24dccn142@student.ptithcm.edu.vn
  * Phạm Công Đang - n24dccn102@student.ptithcm.edu.vn
  * Mai Văn Công - n24dccn100@student.ptithcm.edu.vn
# TỪ ĐIỂN DỮ LIỆU CƠ SỞ DỮ LIỆU (DATA DICTIONARY)

## 1. USER_ACCOUNT

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `account_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất toàn cầu cho tài khoản người dùng. |
| `full_name_text` | VARCHAR(100) | None | No | None | Họ và tên đầy đủ của người dùng. |
| `contact_phone_number` | VARCHAR(15) | UK | No | None | Số điện thoại liên lạc; phải là duy nhất. |
| `email_address` | VARCHAR(255) | UK | No | None | Địa chỉ email cá nhân; phải là duy nhất. |
| `role_code` | VARCHAR(20) | None | No | `'CUSTOMER'` | CHECK: `CUSTOMER`, `MANAGER`, `ADMIN`. |
| `deleted_at` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm ghi nhận khi tài khoản bị xóa mềm. |

## 2. VEHICLE

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `vehicle_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng phương tiện xe điện. |
| `account_identifier` | UUID | FK | No | None | FK → `user_account(account_identifier)`; `ON DELETE CASCADE`. |
| `license_plate` | VARCHAR(20) | UK | No | None | Biển số xe đăng ký; phải là duy nhất. |
| `battery_capacity_kwh` | DECIMAL(10,2) | None | No | None | CHECK: `battery_capacity_kwh > 0`. Dung lượng pin tối đa theo kWh. |
| `deleted_at` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm ghi nhận khi phương tiện bị xóa mềm. |

## 3. PARKING_FACILITY

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `facility_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho bãi đỗ xe. |
| `facility_name_text` | VARCHAR(100) | None | No | None | Tên gọi công cộng của bãi đỗ xe. |
| `geographic_location` | GEOMETRY(Point, 4326) | None | No | None | Tọa độ không gian địa lý PostGIS WGS 84 (EPSG:4326). |
| `address_text` | VARCHAR(255) | None | No | None | Địa chỉ hành chính chi tiết của bãi đỗ xe. |
| `total_capacity_count` | INT | None | No | None | CHECK: `total_capacity_count > 0`. Tổng số vị trí đỗ xe tại bãi. |

## 4. FACILITY_MANAGER

Bảng trung gian giải quyết quan hệ N:M giữa `USER_ACCOUNT` (vai trò MANAGER) và `PARKING_FACILITY`.

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `manager_identifier` | UUID | PK, FK | No | None | FK → `user_account(account_identifier)`; `ON DELETE CASCADE`. Tài khoản phải có vai trò `MANAGER`. |
| `facility_identifier` | UUID | PK, FK | No | None | FK → `parking_facility(facility_identifier)`; `ON DELETE CASCADE`. |

## 5. PARKING_SPACE

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `space_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng ô/vị trí đỗ xe. |
| `facility_identifier` | UUID | FK | No | None | FK → `parking_facility(facility_identifier)`; `ON DELETE CASCADE`. |
| `space_code` | VARCHAR(10) | None | No | None | Mã vị trí, ví dụ `A-01`; UNIQUE theo cặp (`facility_identifier`, `space_code`). |
| `availability_status_code` | VARCHAR(20) | None | No | `'AVAILABLE'` | CHECK: `AVAILABLE`, `RESERVED`, `OCCUPIED`, `OUTOFSERVICE`. |
| `deleted_at` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm ghi nhận khi vị trí đỗ bị ngưng sử dụng hoặc tháo dỡ. |

## 6. CHARGING_EQUIPMENT

Quan hệ mở rộng 1:1 với `PARKING_SPACE`.

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `equipment_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho bộ/trụ sạc phần cứng. |
| `space_identifier` | UUID | FK, UK | No | None | FK → `parking_space(space_identifier)`; `ON DELETE CASCADE`; bảo đảm quan hệ 1:1. |
| `evse_identifier` | VARCHAR(50) | UK | No | None | Mã định danh điểm sạc; phải là duy nhất. |
| `connector_type_code` | VARCHAR(50) | None | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK: `max_power_kw > 0`; công suất sạc tối đa (kW). |
| `equipment_status_code` | VARCHAR(20) | None | No | `'READY'` | Trạng thái: `READY`, `CHARGING`, `FAULT`, `MAINTENANCE`. |
| `deleted_at` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm ghi nhận khi thiết bị bị tháo dỡ/ngưng vận hành. |

## 7. TARIFF_RATE

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `rate_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng cấu hình mức giá. |
| `connector_type_code` | VARCHAR(50) | None | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `start_time` | TIME | None | No | None | Khung giờ bắt đầu áp dụng giá. |
| `end_time` | TIME | None | No | None | Khung giờ kết thúc; CHECK: `end_time <> start_time`. |
| `min_power_kw` | DECIMAL(10,2) | None | No | `0.00` | CHECK: `min_power_kw >= 0`; nấc công suất nhỏ nhất áp dụng khung giá. |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK: `max_power_kw > min_power_kw`; nấc công suất lớn nhất áp dụng khung giá. |
| `price_per_kwh_value` | DECIMAL(10,2) | None | No | None | CHECK: `price_per_kwh_value >= 0`; đơn giá tiền điện (VND/kWh). |
| `overtime_fee_per_hour_value` | DECIMAL(10,2) | None | No | `0.00` | CHECK: `overtime_fee_per_hour_value >= 0`; phí đỗ phạt quá giờ (VND/giờ). |

## 8. RESERVATION

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `reservation_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho lượt đặt chỗ. |
| `account_identifier` | UUID | FK | Yes | `NULL` | FK → `user_account(account_identifier)`; `ON DELETE SET NULL`. |
| `space_identifier` | UUID | FK | No | None | FK → `parking_space(space_identifier)`. |
| `start_datetime` | TIMESTAMPTZ | None | No | None | Thời điểm bắt đầu dự kiến. |
| `end_datetime` | TIMESTAMPTZ | None | No | None | CHECK: `end_datetime > start_datetime`. |
| `reservation_status_code` | VARCHAR(20) | None | No | `'PENDING'` | CHECK: `PENDING`, `CONFIRMED`, `COMPLETED`, `CANCELLED`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm khởi tạo yêu cầu đặt chỗ. |
| `deleted_at` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm ghi nhận khi lượt đặt chỗ bị xóa vết. |
| `constraint` | EXCLUDE | None | No | None | `EXCLUDE USING gist (space_identifier WITH =, tsrange(start_datetime, end_datetime) WITH &&)` để chống chồng lấp lịch. |

## 9. SERVICE_SESSION

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `session_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho phiên sạc/đỗ xe thực tế. |
| `reservation_identifier` | UUID | FK | Yes | `NULL` | FK → `reservation(reservation_identifier)`; `ON DELETE SET NULL`. |
| `account_identifier` | UUID | FK | Yes | `NULL` | FK → `user_account(account_identifier)`; `ON DELETE SET NULL`. |
| `equipment_identifier` | UUID | FK | Yes | `NULL` | FK → `charging_equipment(equipment_identifier)`; `ON DELETE SET NULL`. |
| `start_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm thực tế bắt đầu cắm sạc. |
| `end_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm kết thúc; CHECK: `end_datetime >= start_datetime`. |
| `fully_charged_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm pin đạt 100%; CHECK: `fully_charged_datetime >= start_datetime`. |
| `peak_charging_power_kw` | DECIMAL(10,2) | None | No | `0.00` | CHECK: `peak_charging_power_kw >= 0`; công suất sạc đỉnh thực tế. |
| `consumed_energy_kwh` | DECIMAL(10,2) | None | No | `0.00` | CHECK: `consumed_energy_kwh >= 0`; tổng điện năng thực tế đã nạp. |

## 10. PAYMENT_TRANSACTION

| Attribute | Data Type | Key Type | Nullable | Default | Constraints / Description |
|---|---|---|---|---|---|
| `transaction_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh duy nhất cho giao dịch thanh toán. |
| `session_identifier` | UUID | FK, UK | No | None | FK → `service_session(session_identifier)`; `ON DELETE RESTRICT`; quan hệ Strict 1:1. |
| `rate_identifier` | UUID | FK | No | None | FK → `tariff_rate(rate_identifier)`; `ON DELETE RESTRICT`. |
| `transaction_amount_value` | DECIMAL(12,2) | None | No | None | CHECK: `transaction_amount_value >= 0`; tổng tiền thanh toán (VND). |
| `currency_code` | CHAR(3) | None | No | `'VND'` | Mã tiền tệ quốc tế. |
| `payment_method_code` | VARCHAR(50) | None | No | None | Phương thức thanh toán, ví dụ `CREDIT_CARD`, `E_WALLET`. |
| `gateway_reference_id` | VARCHAR(100) | None | No | `NULL` | Mã đối soát giao dịch từ cổng thanh toán bên thứ ba. |
| `transaction_status_code` | VARCHAR(20) | None | No | `'PENDING'` | `PENDING`, `SUCCESS`, `FAILED`, `REFUNDED`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm khởi tạo giao dịch thanh toán. |

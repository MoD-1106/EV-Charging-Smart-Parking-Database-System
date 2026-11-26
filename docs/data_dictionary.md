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

Các hậu tố `_amount` ở bản cũ được thống nhất thành `_value`. Các cột đổi tên so với thiết kế trước: `deleted_at → deleted_datetime`, `license_plate → license_plate_text`, `gateway_reference_id → gateway_reference_identifier`.

**Ký hiệu Key Type:** PK, FK, UK. `UK*` = ràng buộc duy nhất **từng phần** (`WHERE deleted_datetime IS NULL`), để bản ghi đã xóa mềm không chiếm khóa.

---

## 1. USER_ACCOUNT

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `account_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh tài khoản. |
| `full_name_text` | VARCHAR(100) | None | No | None | Họ và tên; không được chỉ gồm dấu cách (`ck_user_account_name`). |
| `contact_phone_number` | VARCHAR(15) | UK* | No | None | CHECK `~ '^\+?[0-9]{8,14}$'`; duy nhất trong các tài khoản chưa xóa. |
| `email_address` | VARCHAR(255) | UK* | No | None | Duy nhất không phân biệt hoa/thường (`lower(email_address)`); kiểm tra định dạng (`ck_user_account_email`). |
| `password_hash_text` | VARCHAR(255) | None | No | None | Mật khẩu đã băm (scrypt, `werkzeug.security`); dùng để đăng nhập. |
| `role_code` | VARCHAR(20) | None | No | `'CUSTOMER'` | CHECK: `CUSTOMER`, `MANAGER`, `ADMIN`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm tạo tài khoản. |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |
| `password_plain_text` | VARCHAR(255) | None | Yes | `NULL` | Mật khẩu gốc để ADMIN xem (lựa chọn của nhóm khi demo, không phải yêu cầu của đề). Ghi khi đăng ký, khi admin tạo hoặc đặt lại, và ở lần đăng nhập đầu nếu còn trống; bị xóa khi xóa vĩnh viễn. |
| `purged_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Đã xóa vĩnh viễn thông tin cá nhân (quá 30 phút sau khi xóa mềm). |

## 2. VEHICLE

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `vehicle_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phương tiện. |
| `account_identifier` | UUID | FK | No | None | → `user_account`; `ON DELETE CASCADE`. Chủ xe. |
| `license_plate_text` | VARCHAR(20) | UK* | No | None | Biển số; duy nhất trong các xe chưa xóa (đăng ký lại được sau xóa mềm). |
| `battery_capacity_kwh` | DECIMAL(10,2) | None | No | None | CHECK `> 0`. |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 3. PARKING_FACILITY

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `facility_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh bãi đỗ. |
| `facility_name_text` | VARCHAR(100) | None | No | None | Tên bãi. |
| `geographic_location` | GEOMETRY(Point, 4326) | None | No | None | PostGIS WGS 84; có chỉ mục GiST. |
| `address_text` | VARCHAR(255) | None | No | None | Địa chỉ. |
| `total_capacity_count` | INT | None | No | None | CHECK `> 0`. **Sức chứa thiết kế** (do Admin khai báo, không suy ra từ dữ liệu); số `parking_space` chưa xóa không được vượt giá trị này (trigger `trg_space_capacity`). |

## 4. FACILITY_MANAGER

Bảng trung gian N:M giữa `USER_ACCOUNT` (vai trò `MANAGER`) và `PARKING_FACILITY`.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `manager_identifier` | UUID | PK, FK | No | None | → `user_account`; `ON DELETE CASCADE`. Trigger `trg_facility_manager_role` bắt buộc tài khoản là `MANAGER` chưa xóa. |
| `facility_identifier` | UUID | PK, FK | No | None | → `parking_facility`; `ON DELETE CASCADE`. |

## 5. PARKING_SPACE

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `space_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh ô đỗ. |
| `facility_identifier` | UUID | FK | No | None | → `parking_facility`; `ON DELETE CASCADE`. |
| `space_code` | VARCHAR(10) | UK* | No | None | Ví dụ `A-01`; duy nhất theo (`facility_identifier`, `space_code`) trong các ô chưa xóa. |
| `availability_status_code` | VARCHAR(20) | None | No | `'AVAILABLE'` | CHECK: `AVAILABLE`, `RESERVED`, `OCCUPIED`, `OUTOFSERVICE`. Là **trạng thái vận hành hiện tại** (xem mục 15). |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 6. CHARGING_EQUIPMENT

Quan hệ mở rộng 1:1 (tùy chọn) với `PARKING_SPACE`: ô đỗ thường không có dòng ở bảng này.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `equipment_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh thiết bị sạc. |
| `space_identifier` | UUID | FK, UK* | No | None | → `parking_space`; `ON DELETE CASCADE`; UNIQUE bảo đảm 1:1. |
| `evse_identifier` | VARCHAR(50) | UK* | No | None | Mã điểm sạc (ISO 15118 / OCPP). |
| `connector_type_code` | VARCHAR(50) | None | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK `> 0`. Công suất **định mức**; dùng để chọn dải công suất trong `power_tier`. |
| `equipment_status_code` | VARCHAR(20) | None | No | `'READY'` | CHECK: `READY`, `CHARGING`, `FAULT`, `MAINTENANCE`. `FAULT`/`MAINTENANCE` ⇒ ô đỗ `OUTOFSERVICE` (trigger `trg_equipment_status_sync`). |
| `deleted_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Xóa mềm. |

## 7. TIME_BAND

Danh mục khung giá. Tách khỏi bảng giá để tên khung chỉ lưu một lần.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `time_band_code` | VARCHAR(20) | PK | No | None | CHECK: `PEAK`, `STANDARD`, `OFF_PEAK`. |
| `time_band_name` | VARCHAR(50) | None | No | None | Tên hiển thị: Cao điểm, Bình thường, Thấp điểm. |

## 8. TIME_BAND_WINDOW

Lịch khung giờ trong ngày, khai báo **một lần cho cả hệ thống** (không lặp lại theo loại cổng hay dải công suất). Quy ước:
* Khoảng thời gian nửa mở `[start_time, end_time)`, giờ theo múi `Asia/Ho_Chi_Minh`.
* Khung **không vắt qua nửa đêm**: `22:00–05:00` lưu thành hai dòng `22:00–24:00` và `00:00–05:00`.
* Các dòng phủ kín 24 giờ: `OFF_PEAK` 22:00–05:00, `PEAK` 17:00–20:00, `STANDARD` 05:00–17:00 và 20:00–22:00.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `start_time` | TIME | PK | No | None | Bắt đầu khoảng giờ (bao gồm). |
| `end_time` | TIME | None | No | None | CHECK `end_time > start_time`; có thể là `24:00`. |
| `time_band_code` | VARCHAR(20) | FK | No | None | → `time_band`; `ON DELETE RESTRICT`. Khung của khoảng giờ. |
| `ex_time_band_window_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (int4range(giây(start_time), giây(end_time)) WITH &&)` — hai khoảng giờ không được chồng nhau. |

## 9. POWER_TIER

Dải công suất của từng loại cổng, khai báo **một lần** (không lặp theo khung giá). Dải là nửa mở `[min_power_kw, max_power_kw)`, so với `charging_equipment.max_power_kw`.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `connector_type_code` | VARCHAR(50) | PK | No | None | CHECK: `FAST_DC`, `STANDARD_AC`. |
| `min_power_kw` | DECIMAL(10,2) | PK | No | `0.00` | CHECK `>= 0`. Khóa chính ghép (`connector_type_code`, `min_power_kw`). |
| `max_power_kw` | DECIMAL(10,2) | None | No | None | CHECK `> min_power_kw`. |
| `ex_power_tier_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (connector_type_code WITH =, numrange(min_power_kw, max_power_kw) WITH &&)` — các dải của một loại cổng không chồng nhau. |

## 10. TARIFF_RATE

Mỗi dòng là một **phiên bản giá** của một ô giá (dải công suất, khung giá), có hiệu lực trong `[effective_from, effective_to)`. Quy ước:
* **Đổi giá không sửa đè**: hàm `fn_change_tariff` đóng phiên bản hiện tại (ghi `effective_to`) và thêm phiên bản mới; trigger `trg_tariff_rate_fixed` cấm mọi sửa đổi khác. Nhờ vậy hóa đơn cũ luôn truy về đúng mức giá đã áp dụng.
* **Mức giá chọn theo thời điểm bắt đầu phiên sạc** (`fn_select_tariff`): khung của giờ bắt đầu (tra `time_band_window`), dải công suất chứa công suất trụ (tra `power_tier`), và phiên bản có hiệu lực tại thời điểm đó.
* `overtime_fee_per_hour_value` gắn với từng ô giá nên **có thể khác nhau theo loại trụ**. Trong dữ liệu mẫu các loại trụ trùng phí quá giờ trong cùng khung; đó là trùng hợp của dữ liệu, không phải ràng buộc.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `rate_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phiên bản giá. |
| `connector_type_code` | VARCHAR(50) | FK, UK | No | None | Cùng `min_power_kw` → `power_tier`; `ON DELETE RESTRICT`. |
| `min_power_kw` | DECIMAL(10,2) | FK, UK | No | None | Xem dòng trên (khóa ngoại ghép). |
| `time_band_code` | VARCHAR(20) | FK, UK | No | None | → `time_band`; `ON DELETE RESTRICT`. |
| `price_per_kwh_value` | DECIMAL(10,2) | None | No | None | CHECK `>= 0`; VND/kWh. |
| `overtime_fee_per_hour_value` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`; VND/giờ. |
| `effective_from` | TIMESTAMPTZ | UK | No | `CURRENT_TIMESTAMP` | Bắt đầu hiệu lực (bao gồm). |
| `effective_to` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `> effective_from`; NULL = đang hiệu lực. Chỉ được ghi một lần (đóng phiên bản). |
| `uq_tariff_rate_key` | UNIQUE | UK | — | None | `(connector_type_code, min_power_kw, time_band_code, effective_from)`: khóa ứng viên nghiệp vụ. |
| `ex_tariff_rate_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (connector_type_code WITH =, min_power_kw WITH =, time_band_code WITH =, tstzrange(effective_from, effective_to) WITH &&)` — các phiên bản của một ô giá không chồng thời gian hiệu lực. |

## 11. PARKING_RATE

Giá đỗ xe theo giờ cho ô **không có trụ sạc**, theo khung giá, có lịch sử phiên bản giống `tariff_rate` (đổi qua `fn_change_parking_rate`, `trg_parking_rate_fixed` cấm sửa đè). Giá chọn theo khung của giờ xe vào bãi (`fn_select_parking_rate`).

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `parking_rate_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phiên bản giá đỗ. |
| `time_band_code` | VARCHAR(20) | FK, UK | No | None | → `time_band`; `ON DELETE RESTRICT`. |
| `price_per_hour_value` | DECIMAL(10,2) | None | No | None | CHECK `>= 0`; VND/giờ. |
| `effective_from` | TIMESTAMPTZ | UK | No | `CURRENT_TIMESTAMP` | Bắt đầu hiệu lực. |
| `effective_to` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `> effective_from`; NULL = đang hiệu lực. |
| `uq_parking_rate_key` | UNIQUE | UK | — | None | `(time_band_code, effective_from)`. |
| `ex_parking_rate_no_overlap` | EXCLUDE | None | — | None | `EXCLUDE USING gist (time_band_code WITH =, tstzrange(effective_from, effective_to) WITH &&)`. |

## 12. RESERVATION

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
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

Trigger `trg_reservation_validate` (khi INSERT): từ chối nếu ô đỗ đã xóa hoặc `OUTOFSERVICE`, xe hoặc chủ xe đã xóa, hoặc ô đang sạc và lượt đặt bắt đầu trong 30 phút tới.

Ràng buộc bổ sung: `ex_reservation_vehicle_no_overlap` (một xe không giữ hai ô chồng giờ); `ck_reservation_duration` (tối đa 24 giờ); `trg_reservation_fixed` (không sửa xe, ô, giờ); `trg_reservation_status_flow` (trạng thái một chiều; không xác nhận lượt quá hạn; ô có trụ chỉ thành `FULFILLED` qua phiên sạc; ô chỉ đỗ xe được ghi nhận đến từ sớm 15 phút đến trễ 30 phút).

## 13. SERVICE_SESSION

Phiên sử dụng là **phiên sạc** (dùng trụ, `equipment_identifier` + `rate_identifier`) hoặc **phiên chỉ đỗ xe** ở ô không có trụ (`space_identifier` + `parking_rate_identifier`), đúng một trong hai (`ck_service_session_kind`). Ô của phiên sạc suy ra qua thiết bị nên không lưu lặp. Chủ tài khoản suy ra qua `vehicle.account_identifier`.

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `session_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh phiên. |
| `reservation_identifier` | UUID | FK, UK | Yes | `NULL` | → `reservation`; `ON DELETE SET NULL`; UNIQUE (một lượt đặt chỉ sinh tối đa một phiên). NULL = khách vãng lai. |
| `vehicle_identifier` | UUID | FK | No | None | → `vehicle`; `ON DELETE RESTRICT`. |
| `equipment_identifier` | UUID | FK | Yes | `NULL` | → `charging_equipment`; `ON DELETE RESTRICT`. Có giá trị khi là phiên sạc. |
| `space_identifier` | UUID | FK | Yes | `NULL` | → `parking_space`; `ON DELETE RESTRICT`. Có giá trị khi là phiên chỉ đỗ xe (ô không có trụ). |
| `rate_identifier` | UUID | FK | Yes | `NULL` | → `tariff_rate`; `ON DELETE RESTRICT`. Phiên bản giá sạc chốt lúc bắt đầu (trigger ghi, không sửa được). |
| `parking_rate_identifier` | UUID | FK | Yes | `NULL` | → `parking_rate`; `ON DELETE RESTRICT`. Phiên bản giá đỗ chốt lúc xe vào (trigger ghi, không sửa được). |
| `start_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm cắm sạc hoặc xe vào đỗ. |
| `end_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `>= start_datetime`. Khi chuyển từ NULL sang có giá trị, trigger `trg_session_finish` giải phóng thiết bị và **tự lập hóa đơn**. |
| `fully_charged_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | CHECK `>= start_datetime` và `<= end_datetime` (nếu có). |
| `peak_charging_power_kw` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`. Khi kết thúc ghi bằng công suất trụ. |
| `consumed_energy_kwh` | DECIMAL(10,2) | None | No | `0.00` | CHECK `>= 0`. Khi kết thúc lấy từ `fn_session_estimate`; không quá 110 % dung lượng pin và công suất trụ × (thời gian sạc + 5 phút). |
| `start_battery_percent` | DECIMAL(5,2) | None | Yes | `NULL` | % pin lúc cắm sạc do quản lý nhập; CHECK `0 <= x < 100`; không sửa được. NULL (phiên cũ) thì ước tính coi là 20 %. Phiên chỉ đỗ xe: NULL, điện năng và công suất bằng 0. |

Ràng buộc bổ sung: chỉ mục duy nhất từng phần `ux_service_session_open_equipment` (mỗi thiết bị tối đa một phiên đang mở) và `ux_service_session_open_space` (mỗi ô chỉ đỗ tối đa một phiên đang mở); trigger `trg_session_validate` chọn phiên bản giá có hiệu lực, chặn phiên chỉ đỗ ở ô có trụ; trigger `trg_session_validate` kiểm tra phiên khớp với lượt đặt (cùng xe, cùng ô), thiết bị không `FAULT`/`MAINTENANCE`, và khách vãng lai không được bắt đầu trong khung giờ đã được người khác đặt. Thêm: `ux_service_session_open_vehicle`; `trg_session_validate` còn chặn xe của tài khoản đã xóa, đến sớm quá 15 phút, dùng lượt đặt trễ quá 30 phút; `trg_session_energy_limit`; `trg_session_fixed` (không xóa phiên, không đổi xe, trụ, ô, giờ bắt đầu, phiên bản giá); `trg_session_immutable` (phiên đã kết thúc chỉ đọc).

## 14. PAYMENT_TRANSACTION

| Attribute Name | Data Type | Key Type | Nullable? | Default Value | Business Rules / Constraints |
|---|---|---|---|---|---|
| `transaction_identifier` | UUID | PK | No | `gen_random_uuid()` | Mã định danh giao dịch. |
| `session_identifier` | UUID | FK, UK | No | None | → `service_session`; `ON DELETE RESTRICT`; quan hệ 1:1. |
| `energy_amount_value` | DECIMAL(12,2) | None | No | `0.00` | Phiên sạc: `consumed_energy_kwh × price_per_kwh_value` của phiên bản giá đã chốt. |
| `overtime_amount_value` | DECIMAL(12,2) | None | No | `0.00` | Phiên sạc: `max(0, (end_datetime − fully_charged_datetime) tính bằng giờ) × overtime_fee_per_hour_value`. |
| `parking_amount_value` | DECIMAL(12,2) | None | No | `0.00` | Phiên chỉ đỗ xe: `(end_datetime − start_datetime) tính bằng giờ × price_per_hour_value` của phiên bản giá đỗ đã chốt. |
| `transaction_amount_value` | DECIMAL(12,2) | None | No | None | CHECK `= energy_amount_value + overtime_amount_value + parking_amount_value`. Số tiền **chốt** tại thời điểm xuất hóa đơn (thuộc tính dẫn xuất được lưu). |
| `currency_code` | CHAR(3) | None | No | `'VND'` | CHECK: `VND`, `USD` (ISO 4217). |
| `payment_method_code` | VARCHAR(50) | None | Yes | `NULL` | CHECK: `CREDIT_CARD`, `E_WALLET`, `BANK_TRANSFER`. NULL cho tới khi khách chọn cách thanh toán. |
| `gateway_reference_identifier` | VARCHAR(100) | None | Yes | `NULL` | Mã đối soát từ cổng (MoMo, VNPay, Stripe). NULL khi giao dịch còn `PENDING`. |
| `transaction_status_code` | VARCHAR(20) | None | No | `'PENDING'` | CHECK: `PENDING`, `PROCESSING` (khách đã trả, chờ quản lý xác nhận), `SUCCESS`, `FAILED`, `REFUNDED`. `PROCESSING` và `SUCCESS` yêu cầu đã có `payment_method_code` và `gateway_reference_identifier`. |
| `created_datetime` | TIMESTAMPTZ | None | No | `CURRENT_TIMESTAMP` | Thời điểm tạo. |
| `customer_name_text` | VARCHAR(100) | None | No | trigger ghi | Họ tên khách lúc lập hóa đơn. `trg_payment_snapshot` tự chụp, không sửa được, còn nguyên khi tài khoản bị xóa. |
| `customer_phone_number` | VARCHAR(15) | None | No | trigger ghi | Số điện thoại lúc lập hóa đơn. `trg_payment_snapshot` tự chụp, không sửa được, còn nguyên khi tài khoản bị xóa. |
| `customer_email_address` | VARCHAR(255) | None | No | trigger ghi | Email lúc lập hóa đơn. `trg_payment_snapshot` tự chụp, không sửa được, còn nguyên khi tài khoản bị xóa. |
| `confirmed_by_identifier` | UUID | FK | Yes | `NULL` | → `user_account`; `ON DELETE RESTRICT`. Quản lý xác nhận hoặc từ chối; phải là MANAGER chưa xóa đang phụ trách bãi nơi khách sạc (`ck_payment_confirmed_by_manager`). Bắt buộc khi trạng thái là `SUCCESS`, `FAILED`, `REFUNDED` (`ck_payment_confirmed`). |
| `confirmed_datetime` | TIMESTAMPTZ | None | Yes | `NULL` | Thời điểm quản lý xác nhận hoặc từ chối (trigger ghi `now()`). |
| `license_plate_text` | VARCHAR(20) | None | No | trigger ghi | Biển số lúc lập hóa đơn. `trg_payment_snapshot` tự chụp, không sửa được, còn nguyên khi tài khoản bị xóa. |

Bất biến: trigger `trg_payment_immutable` cấm `DELETE` và cấm sửa phiên, các số tiền, tiền tệ và thông tin khách trên hóa đơn; chỉ cho cập nhật trạng thái, phương thức và mã cổng. `trg_payment_requires_end` chỉ cho lập hóa đơn cho phiên đã kết thúc.

---

## Quy tắc toàn vẹn liên bảng

| Trigger | Quy tắc |
|---|---|
| `trg_account_guard` | Khách đã có xe, quản lý đang được phân công không đổi được vai trò; không xóa được ADMIN; xóa mềm thì hủy lượt đặt sắp tới, bỏ phân công, xóa mềm xe; khôi phục được trong 30 phút (`ck_account_restore_expired`), không khôi phục tài khoản đã xóa vĩnh viễn. |
| `trg_admin_keep` | Không `DELETE` được tài khoản ADMIN. |
| `trg_payment_snapshot` | Chụp họ tên, điện thoại, email, biển số vào hóa đơn lúc lập. |
| `fn_session_estimate` (hàm) | Điện năng, thời điểm đầy pin, % pin và công suất của một phiên tại thời điểm cho trước: công suất trụ × thời gian × 90 %, tối đa phần pin còn thiếu. |
| `fn_purge_deleted_accounts` (hàm) | Quá 30 phút: tài khoản chưa có lịch sử thì xóa hẳn; có lịch sử thì xóa thông tin cá nhân, giữ phiên sạc và hóa đơn; đang sạc thì chờ phiên kết thúc. |
| `trg_space_removal` | Không xóa mềm ô đang sạc; xóa mềm ô thì hủy lượt đặt sắp tới. |
| `trg_equipment_charging_guard` | Trạng thái `CHARGING` phải khớp với phiên đang mở. |
| `trg_facility_capacity` | Không giảm sức chứa xuống dưới số ô đang có. |

Tài khoản CSDL cho web: `roles.sql` tạo `evc_app` với quyền tối thiểu.

## 15. Ghi chú thiết kế về dữ liệu có kiểm soát dư thừa

| Dữ liệu | Lý do giữ | Cơ chế giữ nhất quán |
|---|---|---|
| `parking_space.availability_status_code` | Hiển thị bản đồ thời gian thực, truy vấn nhanh. Là trạng thái **tại thời điểm hiện tại**, không phải lịch tương lai. | Triggers `trg_equipment_status_sync`, `trg_session_start/finish`; hàm `fn_refresh_reserved_spaces()` (pg_cron). |
| Khả dụng của **khung giờ yêu cầu** | Rule "chỉ đặt chỗ khi `AVAILABLE` trong toàn bộ khung giờ". | Không lưu cột; tính bằng `fn_is_space_available(space, start, end)` + `EXCLUDE` trên `reservation`. |
| `transaction_amount_value` và các thành phần | Hóa đơn bất biến; tổng là thuộc tính dẫn xuất được lưu. | `CHECK` tổng = các thành phần; trigger bất biến. Giá dùng để tính thì không lưu lặp: phiên trỏ tới phiên bản giá bất biến. |
| `total_capacity_count` | Giá trị thiết kế, không phải số đếm. | Trigger `trg_space_capacity`. |
| `user_account.password_plain_text` | Lựa chọn của nhóm để tiện demo: ADMIN xem được mật khẩu. Trùng thông tin với `password_hash_text`; không dùng cho hệ thống thật. | Ghi cùng lúc ở mọi đường tạo/đổi mật khẩu; đăng nhập chỉ kiểm bản băm; xóa khi xóa vĩnh viễn tài khoản. |
| Lịch khung giờ, dải công suất | Không lưu lặp trong bảng giá. | Khai báo một lần trong `time_band_window` và `power_tier`; `fn_select_tariff` tra khung, dải và phiên bản giá theo giờ bắt đầu phiên. Lịch khung giờ phải phủ kín 24 giờ (`trg_time_band_window_coverage`, kiểm tra cuối giao dịch). |

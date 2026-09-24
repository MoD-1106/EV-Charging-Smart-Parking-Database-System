# TỪ ĐIỂN DỮ LIỆU CƠ SỞ DỮ LIỆU (DATA DICTIONARY)

## Thông tin dự án
* **Tên dự án:** Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện (EV) thông minh)
* **ID & Phân loại:** #1: Smart City EV Charging & Parking Management
* **Thời hạn hoàn thành (Due Date):** August 29, 2026 - Week 8
* **Tên nhóm:** M3B
* **Thành viên nhóm:**
  * Nguyễn Trường Nghị - `n24dccn142@student.ptithcm.edu.vn`
  * Phạm Công Đang - `n24dccn102@student.ptithcm.edu.vn`
  * Mai Văn Công - `n24dccn100@student.ptithcm.edu.vn`
* **Hệ quản trị CSDL:** PostgreSQL (hỗ trợ PostGIS và btree_gist)
* **Tiêu chuẩn thiết kế:** ISO/IEC 11179 (Metadata Registry), ISO 8601, ISO 4217, ISO 15118, ISO 6709

---

## 1. QUY CHUẨN ĐẶT TÊN & KÝ HIỆU (ISO/IEC 11179)

Tất cả các tên bảng và tên thuộc tính trong hệ thống đều tuân thủ nghiêm ngặt chuẩn đặt tên nhất quán (`snake_case`) kết hợp các hậu tố phân loại ngữ nghĩa (Semantic Suffixes):

| Hậu tố (Suffix) | Ý nghĩa ngữ nghĩa | Kiểu dữ liệu tương ứng | Ví dụ minh họa |
| :--- | :--- | :--- | :--- |
| `_identifier` | Khóa chính, khóa ngoại, mã định danh duy nhất | `UUID`, `VARCHAR` | `account_identifier`, `evse_identifier` |
| `_code` | Mã phân loại, giá trị thuộc danh mục cố định | `VARCHAR`, `CHAR` | `role_code`, `connector_type_code` |
| `_text` | Chuỗi văn bản mô tả, tên gọi, địa chỉ | `VARCHAR`, `TEXT` | `facility_name_text`, `address_text` |
| `_datetime` | Mốc thời gian đầy đủ kèm múi giờ (ISO 8601) | `TIMESTAMPTZ` | `start_datetime`, `fully_charged_datetime` |
| `_time` | Mốc giờ trong ngày (không kèm ngày) | `TIME` | `start_time`, `end_time` |
| `_count` | Đại lượng số đếm nguyên | `INT`, `BIGINT` | `total_capacity_count` |
| `_kw` | Đơn vị đo công suất sạc điện (Kilowatt) | `DECIMAL(10,2)` | `max_power_kw`, `peak_charging_power_kw` |
| `_kwh` | Đơn vị đo năng lượng điện tích lũy (Kilowatt-hour) | `DECIMAL(10,2)` | `battery_capacity_kwh`, `consumed_energy_kwh` |
| `_value` | Đại lượng giá trị số, đơn giá, tổng tiền tài chính | `DECIMAL(12,2)` | `price_per_kwh_value`, `transaction_amount_value` |

---

## 2. DANH MỤC BẢNG TRONG CƠ SỞ DỮ LIỆU

| STT | Tên bảng (Table Name) | Phân hệ chức năng | Mô tả tóm tắt |
| :---: | :--- | :--- | :--- |
| 1 | `user_account` | Người dùng & Phân quyền | Lưu trữ thông tin tài khoản, xác thực và vai trò người dùng |
| 2 | `vehicle` | Phương tiện | Quản lý thông tin xe điện thuộc quyền sở hữu của khách hàng |
| 3 | `parking_facility` | Hạ tầng bãi đỗ | Quản lý vị trí địa lý GIS, tên bãi và quy mô sức chứa |
| 4 | `facility_manager` | Phân công vận hành | Bảng liên kết N:M giữa nhân viên quản lý và bãi đỗ xe |
| 5 | `parking_space` | Vị trí đỗ xe | Quản lý chi tiết từng ô đỗ xe vật lý và trạng thái khả dụng |
| 6 | `charging_equipment` | Thiết bị sạc | Trụ/cổng sạc xe điện lắp đặt mở rộng 1:1 tại các ô đỗ |
| 7 | `tariff_rate` | Cấu hình biểu giá | Danh mục đơn giá sạc động theo loại cổng, công suất và khung giờ |
| 8 | `reservation` | Đặt chỗ trước | Lịch đặt giữ chỗ trước ô đỗ/cổng sạc có chống đè lịch |
| 9 | `service_session` | Phiên sử dụng & Sạc | Ghi nhận quá trình cắm sạc, công suất đỉnh và năng lượng nạp |
| 10 | `payment_transaction` | Giao dịch tài chính | Hóa đơn thanh toán và lưu vết kiểm toán (Audit Log) kế toán |

---

## 3. CHI TIẾT TỪ ĐIỂN DỮ LIỆU TỪNG THỰC THỂ

### 3.1. Bảng `user_account` (Quản lý Tài khoản Người dùng)
* **Định nghĩa:** Bảng lưu trữ toàn bộ thông tin định danh, liên lạc và vai trò của các cá nhân tương tác với hệ thống (Khách hàng, Người quản lý, Quản trị viên).
* **Mục đích sử dụng:** Quản lý xác thực người dùng, phân quyền truy cập chức năng hệ thống (`CUSTOMER`, `MANAGER`, `ADMIN`), đồng thời làm cơ sở liên kết cho các hoạt động đăng ký phương tiện, đặt chỗ, sạc xe và thanh toán hóa đơn.

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `account_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất toàn cầu cho tài khoản người dùng. |
| `full_name_text` | `VARCHAR(100)` | - | No | *None* | Họ và tên đầy đủ của người dùng. |
| `contact_phone_number` | `VARCHAR(15)` | **UK** | No | *None* | Số điện thoại liên lạc (chuẩn E.164). Phải là duy nhất (`UNIQUE`). |
| `email_address` | `VARCHAR(255)` | **UK** | No | *None* | Địa chỉ email cá nhân. Phải là duy nhất (`UNIQUE`). |
| `role_code` | `VARCHAR(20)` | - | No | `'CUSTOMER'` | `CHECK (role_code IN ('CUSTOMER', 'MANAGER', 'ADMIN'))`. |
| `deleted_at` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian ghi nhận khi tài khoản bị xóa mềm. |

---

### 3.2. Bảng `vehicle` (Quản lý Phương tiện Xe điện)
* **Định nghĩa:** Bảng lưu trữ danh sách các phương tiện xe điện thuộc sở hữu của người dùng[cite: 1].
* **Mục đích sử dụng:** Quản lý quan hệ sở hữu 1:N giữa người dùng và các xe điện[cite: 1]. Lưu trữ thông tin biển số và dung lượng pin nhằm nhận diện phương tiện khi vào bãi đỗ và phục vụ thuật toán tính toán thời gian sạc[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `vehicle_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng phương tiện xe điện[cite: 1]. |
| `account_identifier` | `UUID` | **FK** | No | *None* | Khóa ngoại tham chiếu đến `user_account(account_identifier)` với quy tắc `ON DELETE CASCADE`[cite: 1]. |
| `license_plate` | `VARCHAR(20)` | **UK** | No | *None* | Biển số xe đăng ký[cite: 1]. Phải là duy nhất (`UNIQUE`)[cite: 1]. |
| `battery_capacity_kwh` | `DECIMAL(10,2)` | - | No | *None* | `CHECK (battery_capacity_kwh > 0)`[cite: 1]. Dung lượng pin tối đa tính theo kWh[cite: 1]. |
| `deleted_at` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian ghi nhận khi phương tiện bị xóa mềm khỏi tài khoản[cite: 1]. |

---

### 3.3. Bảng `parking_facility` (Quản lý Bãi đỗ xe)
* **Định nghĩa:** Bảng lưu trữ thông tin hạ tầng tổng quan của các bãi đỗ xe tích hợp trạm sạc thuộc hệ thống[cite: 1].
* **Mục đích sử dụng:** Quản lý quy mô bãi đỗ, vị trí địa lý GIS (tọa độ GPS) để phục vụ chức năng định vị bãi đỗ/trạm sạc gần nhất trên bản đồ ứng dụng di động cho người dùng[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `facility_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho bãi đỗ xe[cite: 1]. |
| `facility_name_text` | `VARCHAR(100)` | - | No | *None* | Tên gọi công cộng của bãi đỗ xe[cite: 1]. |
| `geographic_location` | `GEOMETRY(Point, 4326)` | - | No | *None* | Tọa độ không gian địa lý PostGIS WGS 84 (EPSG:4326) tuân thủ ISO 6709[cite: 1]. |
| `address_text` | `VARCHAR(255)` | - | No | *None* | Địa chỉ hành chính chi tiết của bãi đỗ xe[cite: 1]. |
| `total_capacity_count` | `INT` | - | No | *None* | `CHECK (total_capacity_count > 0)`[cite: 1]. Tổng số lượng vị trí đỗ xe tại bãi[cite: 1]. |

---

### 3.4. Bảng `facility_manager` (Phân công Quản lý Bãi đỗ)
* **Định nghĩa:** Bảng trung gian giải quyết mối quan hệ nhiều - nhiều (N:M) giữa người dùng (vai trò Quản lý) và các bãi đỗ xe[cite: 1].
* **Mục đích sử dụng:** Phân công chi tiết nhân viên/quản lý chịu trách nhiệm giám sát, vận hành và quản lý một hoặc nhiều bãi đỗ xe cụ thể trong hệ thống[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `manager_identifier` | `UUID` | **PK, FK** | No | *None* | Khóa ngoại tham chiếu đến `user_account(account_identifier)` với `ON DELETE CASCADE`[cite: 1]. Vai trò tài khoản phải là `'MANAGER'`[cite: 1]. |
| `facility_identifier` | `UUID` | **PK, FK** | No | *None* | Khóa ngoại tham chiếu đến `parking_facility(facility_identifier)` với quy tắc `ON DELETE CASCADE`[cite: 1]. |

---

### 3.5. Bảng `parking_space` (Quản lý Vị trí đỗ xe)
* **Định nghĩa:** Bảng lưu trữ thông tin về từng ô/vị trí đỗ xe vật lý cụ thể thuộc một bãi đỗ xe[cite: 1].
* **Mục đích sử dụng:** Quản lý mã vị trí ô đỗ, trạng thái khả dụng thời gian thực[cite: 1]. Làm đối tượng trực tiếp để người dùng đặt chỗ giữ vị trí đỗ[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `space_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng ô/vị trí đỗ xe[cite: 1]. |
| `facility_identifier` | `UUID` | **FK** | No | *None* | Khóa ngoại tham chiếu đến `parking_facility(facility_identifier)` với quy tắc `ON DELETE CASCADE`[cite: 1]. |
| `space_code` | `VARCHAR(10)` | - | No | *None* | Ký hiệu/Mã số vị trí đỗ (vd: `A-01`)[cite: 1]. Ràng buộc: `UNIQUE (facility_identifier, space_code)`[cite: 1]. |
| `availability_status_code` | `VARCHAR(20)` | - | No | `'AVAILABLE'` | `CHECK (availability_status_code IN ('AVAILABLE', 'RESERVED', 'OCCUPIED', 'OUTOFSERVICE'))`[cite: 1]. |
| `deleted_at` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian ghi nhận khi vị trí đỗ bị ngưng sử dụng hoặc tháo dỡ[cite: 1]. |

---

### 3.6. Bảng `charging_equipment` (Quản lý Thiết bị/Cổng sạc)
* **Định nghĩa:** Bảng lưu trữ thông tin thiết bị/cổng sạc phần cứng được lắp đặt mở rộng tại vị trí đỗ (Mối quan hệ mở rộng 1:1 Extension / Association)[cite: 1].
* **Mục đích sử dụng:** Quản lý thông số phần cứng bộ sạc, mã định danh EVSE ID (theo chuẩn ISO 15118), phân loại cổng sạc (Sạc nhanh DC / Tiêu chuẩn AC), công suất tối đa và trạng thái kỹ thuật phần cứng[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `equipment_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho bộ/trụ sạc phần cứng[cite: 1]. |
| `space_identifier` | `UUID` | **FK, UK** | No | *None* | Khóa ngoại tham chiếu đến `parking_space(space_identifier)` với `ON DELETE CASCADE`[cite: 1]. Ràng buộc quan hệ mở rộng 1:1 (`UNIQUE`)[cite: 1]. |
| `evse_identifier` | `VARCHAR(50)` | **UK** | No | *None* | Mã định danh điểm sạc toàn cầu tuân thủ ISO 15118[cite: 1]. Phải là duy nhất (`UNIQUE`)[cite: 1]. |
| `connector_type_code` | `VARCHAR(50)` | - | No | *None* | `CHECK (connector_type_code IN ('FAST_DC', 'STANDARD_AC'))`[cite: 1]. |
| `max_power_kw` | `DECIMAL(10,2)` | - | No | *None* | `CHECK (max_power_kw > 0)`[cite: 1]. Công suất sạc tối đa của thiết bị (kW)[cite: 1]. |
| `equipment_status_code` | `VARCHAR(20)` | - | No | `'READY'` | Trạng thái kỹ thuật phần cứng: `('READY', 'CHARGING', 'FAULT', 'MAINTENANCE')`[cite: 1]. |
| `deleted_at` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian ghi nhận khi thiết bị sạc bị tháo dỡ/ngưng vận hành[cite: 1]. |

---

### 3.7. Bảng `tariff_rate` (Cấu hình Bảng giá Linh hoạt)
* **Định nghĩa:** Bảng lưu trữ danh mục cấu hình đơn giá dịch vụ sạc điện và đơn giá phí phạt đỗ quá giờ[cite: 1].
* **Mục đích sử dụng:** Hỗ trợ cơ chế tính giá linh hoạt (Dynamic Pricing) theo khung giờ (cao điểm/thấp điểm), theo loại cổng sạc (`FAST_DC` / `STANDARD_AC`) và dải công suất sạc tương ứng[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `rate_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng cấu hình mức giá[cite: 1]. |
| `connector_type_code` | `VARCHAR(50)` | - | No | *None* | `CHECK (connector_type_code IN ('FAST_DC', 'STANDARD_AC'))`[cite: 1]. |
| `start_time` | `TIME` | - | No | *None* | Khung giờ bắt đầu có hiệu lực áp dụng giá[cite: 1]. |
| `end_time` | `TIME` | - | No | *None* | Khung giờ kết thúc hiệu lực áp dụng giá[cite: 1]. `CHECK (end_time <> start_time)`[cite: 1]. |
| `min_power_kw` | `DECIMAL(10,2)` | - | No | `0.00` | `CHECK (min_power_kw >= 0)`[cite: 1]. Nấc công suất nhỏ nhất áp dụng khung giá (kW)[cite: 1]. |
| `max_power_kw` | `DECIMAL(10,2)` | - | No | *None* | `CHECK (max_power_kw > min_power_kw)`[cite: 1]. Nấc công suất lớn nhất áp dụng khung giá (kW)[cite: 1]. |
| `price_per_kwh_value` | `DECIMAL(10,2)` | - | No | *None* | `CHECK (price_per_kwh_value >= 0)`[cite: 1]. Đơn giá tiền điện (VND/kWh)[cite: 1]. |
| `overtime_fee_per_hour_value` | `DECIMAL(10,2)` | - | No | `0.00` | `CHECK (overtime_fee_per_hour_value >= 0)`[cite: 1]. Đơn giá phí đỗ phạt quá giờ (VND/giờ)[cite: 1]. |

---

### 3.8. Bảng `reservation` (Quản lý Đặt chỗ trước)
* **Định nghĩa:** Bảng lưu trữ thông tin các lịch giữ chỗ trước vị trí đỗ/trạm sạc do người dùng khởi tạo trên ứng dụng[cite: 1].
* **Mục đích sử dụng:** Quản lý quy trình đặt chỗ trước[cite: 1]. Sử dụng ràng buộc `EXCLUSION CONSTRAINT` để ngăn chặn triệt để lỗi chồng lấp khoảng thời gian đặt chỗ (Slot Overlapping) trên cùng một vị trí đỗ[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `reservation_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng lượt đặt chỗ[cite: 1]. |
| `account_identifier` | `UUID` | **FK** | Yes | `NULL` | Khóa ngoại tham chiếu đến `user_account(account_identifier)` với `ON DELETE SET NULL`[cite: 1]. |
| `space_identifier` | `UUID` | **FK** | No | *None* | Khóa ngoại tham chiếu đến `parking_space(space_identifier)`[cite: 1]. |
| `start_datetime` | `TIMESTAMPTZ` | - | No | *None* | Thời điểm bắt đầu dự kiến của lượt giữ chỗ (chuẩn ISO 8601)[cite: 1]. |
| `end_datetime` | `TIMESTAMPTZ` | - | No | *None* | Thời điểm kết thúc dự kiến[cite: 1]. `CHECK (end_datetime > start_datetime)`[cite: 1]. |
| `reservation_status_code` | `VARCHAR(20)` | - | No | `'PENDING'` | `CHECK (reservation_status_code IN ('PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED'))`[cite: 1]. |
| `created_datetime` | `TIMESTAMPTZ` | - | No | `CURRENT_TIMESTAMP` | Thời điểm khởi tạo yêu cầu đặt chỗ trên hệ thống (ISO 8601)[cite: 1]. |
| `deleted_at` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian ghi nhận khi lượt đặt chỗ bị xóa vết[cite: 1]. |

* **Ràng buộc loại trừ chống đè lịch đặt chỗ (PostgreSQL GiST):**
  ```sql
  CONSTRAINT no_overlapping_reservations EXCLUDE USING gist (
      space_identifier WITH =,
      tsrange(start_datetime, end_datetime) WITH &&
  );
  ### 3.9. Bảng `service_session` (Quản lý Phiên sử dụng & Sạc)
* **Định nghĩa:** Bảng ghi nhận thông tin chi tiết quá trình vận hành của một phiên đỗ xe và sạc điện thời gian thực[cite: 1].
* **Mục đích sử dụng:** Lưu vết chính xác thời điểm bắt đầu cắm sạc, thời điểm sạc đầy 100% pin (`fully_charged_datetime`), thời điểm rút sạc kết thúc, công suất đỉnh và tổng điện năng tiêu thụ (`consumed_energy_kwh`) làm cơ sở tính chi phí[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `session_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng phiên sạc/đỗ xe thực tế[cite: 1]. |
| `reservation_identifier` | `UUID` | **FK** | Yes | `NULL` | Khóa ngoại tham chiếu đến `reservation(reservation_identifier)` với `ON DELETE SET NULL`[cite: 1]. |
| `account_identifier` | `UUID` | **FK** | Yes | `NULL` | Khóa ngoại tham chiếu đến `user_account(account_identifier)` với `ON DELETE SET NULL`[cite: 1]. |
| `equipment_identifier` | `UUID` | **FK** | Yes | `NULL` | Khóa ngoại tham chiếu đến `charging_equipment(equipment_identifier)` với `ON DELETE SET NULL`[cite: 1]. |
| `start_datetime` | `TIMESTAMPTZ` | - | No | `CURRENT_TIMESTAMP` | Thời điểm thực tế bắt đầu cắm sạc (ISO 8601)[cite: 1]. |
| `end_datetime` | `TIMESTAMPTZ` | - | Yes | `NULL` | Thời điểm thực tế rút sạc/kết thúc phiên. `CHECK (end_datetime >= start_datetime)`[cite: 1]. |
| `fully_charged_datetime` | `TIMESTAMPTZ` | - | Yes | `NULL` | Mốc thời gian pin xe đạt 100%. `CHECK (fully_charged_datetime >= start_datetime)`. Dùng tính Phí phạt quá giờ[cite: 1]. |
| `peak_charging_power_kw` | `DECIMAL(10,2)` | - | No | `0.00` | `CHECK (peak_charging_power_kw >= 0)`. Công suất sạc đỉnh thực tế ghi nhận được trong phiên (kW)[cite: 1]. |
| `consumed_energy_kwh` | `DECIMAL(10,2)` | - | No | `0.00` | `CHECK (consumed_energy_kwh >= 0)`. Tổng điện năng thực tế đã nạp vào xe (kWh)[cite: 1]. |

---

### 3.10. Bảng `payment_transaction` (Giao dịch Thanh toán & Audit Log)
* **Định nghĩa:** Bảng lưu vết toàn bộ hóa đơn và giao dịch tài chính phát sinh sau khi kết thúc phiên sạc[cite: 1].
* **Mục đích sử dụng:** Quản lý việc tính tổng tiền (Số kWh tiêu thụ × Đơn giá kWh + Phí quá giờ), lưu trữ phương thức thanh toán, mã đối soát qua cổng thanh toán[cite: 1]. Sử dụng ràng buộc `ON DELETE RESTRICT` để bảo đảm tính vẹn toàn vết kế toán (Audit Log) không bị xóa[cite: 1].

| Tên thuộc tính | Kiểu dữ liệu | Key Type | Nullable? | Giá trị mặc định | Quy tắc / Ràng buộc (Business Rules / Constraints) |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `transaction_identifier` | `UUID` | **PK** | No | `gen_random_uuid()` | Mã định danh duy nhất cho từng giao dịch thanh toán[cite: 1]. |
| `session_identifier` | `UUID` | **FK, UK** | No | *None* | Khóa ngoại tham chiếu đến `service_session(session_identifier)` với `ON DELETE RESTRICT`. Quan hệ Strict 1:1 (`UNIQUE`)[cite: 1]. |
| `rate_identifier` | `UUID` | **FK** | No | *None* | Khóa ngoại tham chiếu đến `tariff_rate(rate_identifier)` với `ON DELETE RESTRICT`[cite: 1]. |
| `transaction_amount_value` | `DECIMAL(12,2)` | - | No | *None* | `CHECK (transaction_amount_value >= 0)`. Tổng số tiền thanh toán thực tế của hóa đơn (VND)[cite: 1]. |
| `currency_code` | `CHAR(3)` | - | No | `'VND'` | Mã tiền tệ quốc tế tuân thủ ISO 4217[cite: 1]. |
| `payment_method_code` | `VARCHAR(50)` | - | No | *None* | Phương thức thanh toán (vd: `'CREDIT_CARD'`, `'E_WALLET'`)[cite: 1]. |
| `gateway_reference_id` | `VARCHAR(100)` | - | Yes | `NULL` | Mã đối soát giao dịch từ cổng thanh toán bên thứ ba (MOMO, VNPay, Stripe)[cite: 1]. |
| `transaction_status_code` | `VARCHAR(20)` | - | No | `'PENDING'` | Trạng thái giao dịch (`'PENDING'`, `'SUCCESS'`, `'FAILED'`, `'REFUNDED'`)[cite: 1]. |
| `created_datetime` | `TIMESTAMPTZ` | - | No | `CURRENT_TIMESTAMP` | Thời điểm khởi tạo giao dịch thanh toán (ISO 8601)[cite: 1]. |

# Từ điển Dữ liệu (Data Dictionary)
## Dự án: Smart City EV Charging & Parking Management (Theo chuẩn ISO/IEC 11179)
**Nhóm:** M3B | **Môn:** Cơ sở dữ liệu
* Thành viên nhóm:
  * Nguyễn Trường Nghị - n24dccn142@student.ptithcm.edu.vn
  * Phạm Công Đang - n24dccn102@student.ptithcm.edu.vn
  * Mai Văn Công - n24dccn100@student.ptithcm.edu.vn

---

Dựa trên tiêu chuẩn ISO/IEC 11179: Từ điển dữ liệu và tên các thuộc tính được thiết kế tuân thủ nghiêm ngặt quy chuẩn đặt tên nhất quán (sử dụng các hậu tố định danh chuẩn như `_identifier`, `_code`, `_datetime`, `_count`, `_amount`, `_value`, `_text`, `_kw`) nhằm đảm bảo tính đồng bộ, rõ nghĩa và chuẩn hóa dữ liệu trên toàn bộ cơ sở dữ liệu.

---

### 1. Bảng Quản lý Người dùng & Phương tiện

#### Bảng `user_account`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `user_account` | `account_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho tài khoản người dùng |
| `user_account` | `full_name_text` | VARCHAR(100) | NOT NULL | Họ và tên đầy đủ của người dùng |
| `user_account` | `contact_phone_number` | VARCHAR(15) | UNIQUE, NOT NULL | Số điện thoại liên lạc |
| `user_account` | `email_address` | VARCHAR(255) | UNIQUE, NOT NULL | Địa chỉ email xác thực |
| `user_account` | `role_code` | VARCHAR(20) | NOT NULL, CHECK (`role_code IN ('CUSTOMER', 'MANAGER', 'ADMIN')`), DEFAULT 'CUSTOMER' | Vai trò người dùng trong hệ thống |
| `user_account` | `deleted_at` | TIMESTAMPTZ | Soft Delete, mặc định NULL | Dấu vết thời gian xóa mềm tài khoản |

#### Bảng `vehicle`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `vehicle` | `vehicle_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho phương tiện |
| `vehicle` | `account_identifier` | UUID | FOREIGN KEY REFERENCES `user_account(account_identifier)` | Tài khoản chủ sở hữu xe |
| `vehicle` | `license_plate` | VARCHAR(20) | UNIQUE, NOT NULL | Biển số xe điện |
| `vehicle` | `battery_capacity_kwh` | DECIMAL(10,2) | NOT NULL, CHECK (`battery_capacity_kwh > 0`) | Dung lượng pin tối đa của xe (kWh) |
| `vehicle` | `deleted_at` | TIMESTAMPTZ | Soft Delete, mặc định NULL | Dấu vết thời gian xóa mềm phương tiện |

---

### 2. Bảng Quản lý Bãi đỗ xe, Trạm sạc & Cổng sạc

#### Bảng `parking_facility`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `parking_facility` | `facility_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho bãi đỗ xe |
| `parking_facility` | `facility_name_text` | VARCHAR(100) | NOT NULL | Tên bãi đỗ xe / trạm sạc |
| `parking_facility` | `street_address_text` | VARCHAR(255) | NOT NULL | Địa chỉ hành chính chi tiết của bãi đỗ |
| `parking_facility` | `geographic_location` | GEOMETRY(Point, 4326) | Tuân thủ ISO 6709 (PostGIS WGS 84) | Tọa độ địa lý GPS của bãi đỗ xe |
| `parking_facility` | `total_capacity_count` | INT | NOT NULL, CHECK (`total_capacity_count > 0`) | Tổng sức chứa vị trí đỗ xe tối đa |

#### Bảng `parking_space`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `parking_space` | `space_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho vị trí đỗ xe |
| `parking_space` | `facility_identifier` | UUID | FOREIGN KEY REFERENCES `parking_facility(facility_identifier)` | Bãi đỗ xe chứa vị trí đỗ này |
| `parking_space` | `space_code` | VARCHAR(10) | NOT NULL | Mã vị trí đỗ (ví dụ: A-01, B-02) |
| `parking_space` | `availability_status_code` | VARCHAR(20) | CHECK (`availability_status_code IN ('AVAILABLE', 'RESERVED', 'OCCUPIED', 'OUTOFSERVICE')`), DEFAULT 'AVAILABLE' | Trạng thái rảnh/đặt/đang sử dụng/bảo trì |
| `parking_space` | `deleted_at` | TIMESTAMPTZ | Soft Delete, mặc định NULL | Dấu vết thời gian xóa mềm vị trí đỗ |

#### Bảng `charging_equipment`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `charging_equipment` | `equipment_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho thiết bị sạc |
| `charging_equipment` | `space_identifier` | UUID | FOREIGN KEY REFERENCES `parking_space(space_identifier)`, UNIQUE | Vị trí đỗ gắn cổng sạc này (Quan hệ 1-1) |
| `charging_equipment` | `evse_identifier` | VARCHAR(50) | UNIQUE, NOT NULL | Mã định danh thiết bị sạc tuân thủ ISO 15118 |
| `charging_equipment` | `connector_type_code` | VARCHAR(50) | CHECK (`connector_type_code IN ('FAST_DC', 'STANDARD_AC')`) | Phân loại chuẩn súng/cổng sạc (Sạc nhanh/Thường) |
| `charging_equipment` | `max_power_kw` | DECIMAL(8,2) | NOT NULL, CHECK (`max_power_kw > 0`) | Công suất sạc tối đa thiết kế của thiết bị (kW) |
| `charging_equipment` | `equipment_status_code` | VARCHAR(20) | CHECK (`equipment_status_code IN ('READY', 'CHARGING', 'FAULTED', 'OUT_OF_SERVICE')`), DEFAULT 'READY' | Trạng thái hoạt động phần cứng thiết bị sạc |
| `charging_equipment` | `deleted_at` | TIMESTAMPTZ | Soft Delete, mặc định NULL | Dấu vết thời gian xóa mềm thiết bị sạc |

#### Bảng `service_session`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `service_session` | `session_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất phiên sạc/đỗ xe |
| `service_session` | `reservation_identifier` | UUID | FOREIGN KEY REFERENCES `reservation(reservation_identifier)` ON DELETE SET NULL | Lượt đặt chỗ liên kết (nếu có) |
| `service_session` | `account_identifier` | UUID | FOREIGN KEY REFERENCES `user_account(account_identifier)` ON DELETE SET NULL | Tài khoản người dùng thực hiện phiên |
| `service_session` | `equipment_identifier` | UUID | FOREIGN KEY REFERENCES `charging_equipment(equipment_identifier)` ON DELETE SET NULL | Thiết bị sạc được sử dụng |
| `service_session` | `start_datetime` | TIMESTAMPTZ | Chuẩn ISO 8601, DEFAULT CURRENT_TIMESTAMP | Thời điểm bắt đầu phiên |
| `service_session` | `end_datetime` | TIMESTAMPTZ | CHECK (`end_datetime >= start_datetime`) | Thời điểm kết thúc phiên và giải phóng chỗ |
| `service_session` | `consumed_energy_kwh` | DECIMAL(10,2) | DEFAULT 0.00, CHECK (`consumed_energy_kwh >= 0`) | Tổng điện năng tiêu thụ (kWh) |
| `service_session` | `peak_charging_power_kw` | DECIMAL(8,2) | DEFAULT 0.00, CHECK (`peak_charging_power_kw >= 0`) | Công suất sạc đỉnh thực tế đo được trong phiên (kW) |
| `service_session` | `fully_charged_datetime` | TIMESTAMPTZ | CHECK (`fully_charged_datetime >= start_datetime`) | Thời điểm xe hoàn tất sạc đầy (dùng tính phí quá giờ) |

---

### 3. Bảng Quy tắc Đặt chỗ trước (Reservation Rules)

#### Bảng `reservation`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `reservation` | `reservation_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cho lượt đặt chỗ |
| `reservation` | `account_identifier` | UUID | FOREIGN KEY REFERENCES `user_account(account_identifier)` ON DELETE SET NULL | Tài khoản thực hiện đặt chỗ |
| `reservation` | `space_identifier` | UUID | FOREIGN KEY REFERENCES `parking_space(space_identifier)` | Vị trí đỗ được đặt trước |
| `reservation` | `start_datetime` | TIMESTAMPTZ | NOT NULL, Chuẩn ISO 8601 | Thời gian bắt đầu dự kiến |
| `reservation` | `end_datetime` | TIMESTAMPTZ | NOT NULL, CHECK (`end_datetime > start_datetime`) | Thời gian kết thúc dự kiến |
| `reservation` | `reservation_status_code` | VARCHAR(20) | CHECK (`reservation_status_code IN ('PENDING', 'CONFIRMED', 'COMPLETED', 'CANCELLED')`), DEFAULT 'PENDING' | Trạng thái của lượt đặt chỗ |
| `reservation` | `created_datetime` | TIMESTAMPTZ | DEFAULT CURRENT_TIMESTAMP, Chuẩn ISO 8601 | Thời điểm tạo lượt đặt chỗ |
| `reservation` | `deleted_at` | TIMESTAMPTZ | Soft Delete, mặc định NULL | Dấu vết thời gian xóa mềm lượt đặt chỗ |
| `reservation` | `(constraint)` | EXCLUDE | EXCLUDE USING gist (`space_identifier WITH =`, `tsrange(start_datetime, end_datetime) WITH &&`) | Ràng buộc chống xung đột đặt trùng thời gian |

---

### 4. Bảng Xử lý Thanh toán

#### Bảng `payment_transaction`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `payment_transaction` | `transaction_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất giao dịch thanh toán |
| `payment_transaction` | `session_identifier` | UUID | FOREIGN KEY REFERENCES `service_session(session_identifier)` ON DELETE RESTRICT | Phiên sử dụng được thanh toán |
| `payment_transaction` | `rate_identifier` | UUID | FOREIGN KEY REFERENCES `tariff_rate(rate_identifier)` ON DELETE RESTRICT | Mức giá áp dụng cho giao dịch |
| `payment_transaction` | `transaction_amount_value` | DECIMAL(12,2) | NOT NULL, CHECK (`transaction_amount_value >= 0`) | Tổng số tiền thanh toán |
| `payment_transaction` | `currency_code` | CHAR(3) | Tuân thủ ISO 4217, DEFAULT 'VND' | Mã đơn vị tiền tệ (ISO 4217) |
| `payment_transaction` | `payment_method_code` | VARCHAR(50) | NOT NULL | Phương thức thanh toán (CREDIT_CARD, E_WALLET, BANK_TRANSFER) |
| `payment_transaction` | `gateway_reference_id` | VARCHAR(100) | Mã đối soát từ cổng thanh toán bên thứ ba |
| `payment_transaction` | `transaction_status_code` | VARCHAR(20) | CHECK (`transaction_status_code IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')`), DEFAULT 'PENDING' | Trạng thái xử lý giao dịch |
| `payment_transaction` | `created_datetime` | TIMESTAMPTZ | Chuẩn ISO 8601, DEFAULT CURRENT_TIMESTAMP | Thời điểm khởi tạo giao dịch |

---

### 5. Bảng Cấu hình Giá (Tariff Rate)

#### Bảng `tariff_rate`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `tariff_rate` | `rate_identifier` | UUID | PRIMARY KEY, mặc định `gen_random_uuid()` | Định danh duy nhất cấu hình giá |
| `tariff_rate` | `connector_type_code` | VARCHAR(50) | NOT NULL, CHECK (`connector_type_code IN ('FAST_DC', 'STANDARD_AC')`) | Loại cổng sạc áp dụng mức giá |
| `tariff_rate` | `min_power_kw` | DECIMAL(8,2) | DEFAULT 0.00, CHECK (`min_power_kw >= 0`) | Hạn mức công suất tối thiểu áp dụng bảng giá (kW) |
| `tariff_rate` | `max_power_kw` | DECIMAL(8,2) | NOT NULL, CHECK (`max_power_kw > min_power_kw`) | Hạn mức công suất tối đa áp dụng bảng giá (kW) |
| `tariff_rate` | `start_time` | TIME | NOT NULL | Khung giờ bắt đầu áp dụng |
| `tariff_rate` | `end_time` | TIME | NOT NULL, CHECK (`end_time <> start_time`) | Khung giờ kết thúc áp dụng |
| `tariff_rate` | `price_per_kwh_value` | DECIMAL(10,2) | NOT NULL, CHECK (`price_per_kwh_value >= 0`) | Đơn giá điện năng áp dụng cho dải công suất (VND/kWh) |
| `tariff_rate` | `overtime_fee_per_hour_value` | DECIMAL(10,2) | DEFAULT 0.00, CHECK (`overtime_fee_per_hour_value >= 0`) | Đơn giá phí phạt đỗ quá giờ / giờ |

---

### 6. Bảng Phân công Quản lý Bãi đỗ xe (Facility Manager Assignment)

#### Bảng `facility_manager`
| Tên Bảng (Table Name) | Tên Thuộc tính (Attribute Name) | Kiểu Dữ liệu (Data Type) | Ràng buộc / Khóa (Constraints / Keys) | Mô tả (Description) |
| :--- | :--- | :--- | :--- | :--- |
| `facility_manager` | `manager_identifier` | UUID | FOREIGN KEY REFERENCES `user_account(account_identifier)` ON DELETE CASCADE | Định danh tài khoản quản lý (Role MANAGER) |
| `facility_manager` | `facility_identifier` | UUID | FOREIGN KEY REFERENCES `parking_facility(facility_identifier)` ON DELETE CASCADE | Định danh bãi đỗ xe được phân công |
| `facility_manager` | `(constraint)` | PRIMARY KEY | PRIMARY KEY (`manager_identifier`, `facility_identifier`) | Khóa chính phức hợp giải quyết quan hệ n-n |

# TÀI LIỆU CHỨNG MINH DẠNG CHUẨN (NORMALIZATION PROOFS)

## Thông tin dự án
* **Tên dự án:** Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện (EV) thông minh)
* **ID Dự Án:** #1: Smart City EV Charging & Parking Management
* **Tên nhóm:** M3B
* **Thành viên nhóm:**
  * Nguyễn Trường Nghị - `n24dccn142@student.ptithcm.edu.vn`
  * Phạm Công Đang - `n24dccn102@student.ptithcm.edu.vn`
  * Mai Văn Công - `n24dccn100@student.ptithcm.edu.vn`
* **Thời hạn dự án:** 29/08/2026 - Week 8

---

## 1. Tổng quan & Phương pháp Chuẩn hóa

Quá trình chuẩn hóa cơ sở dữ liệu đóng vai trò cốt lõi nhằm triệt tiêu sự dư thừa dữ liệu (Data Redundancy), loại bỏ các bất thường khi thao tác dữ liệu (Insertion, Update, Deletion Anomalies), và bảo toàn tính toàn vẹn dữ liệu trong các hệ thống xử lý giao dịch thời gian thực (OLTP).

Tài liệu này trình bày chi tiết chứng minh quá trình chuẩn hóa từng bước từ **Mô hình Phi chuẩn hóa (Unnormalized Form - UNF)** đến **Dạng chuẩn Boyce-Codd (BCNF)** cho toàn bộ 10 thực thể/bảng thuộc hệ thống **Smart City EV Charging & Parking Management**.

---

## 2. Chứng Minh Chi Tiết Quá Trình Chuẩn Hóa (1NF -> BCNF)

### 2.1. Bước 1: Chứng minh Dạng chuẩn 1 (1NF - First Normal Form)

**Định nghĩa 1NF:** Một quan hệ ở Dạng chuẩn 1 (1NF) khi và chỉ khi tất cả các thuộc tính đều chứa các giá trị nguyên tố (Atomic Values), không chứa các thuộc tính đa trị (Multivalued Attributes) hoặc các nhóm thuộc tính lặp lại (Repeating Groups).

#### Phân tích & Xử lý Triệt tiêu Thuộc tính Đa trị / Nhóm Lặp:
1. **Phân tách Quản lý Phương tiện (`user_account` & `vehicle`):**
   * *Mô hình phi chuẩn hóa (UNF):* Nếu lưu trữ trực tiếp danh sách biển số xe điện thuộc sở hữu của người dùng dưới dạng chuỗi hoặc mảng trong bảng `user_account` (ví dụ: `[51H-123.45, 60A-678.90]`), thuộc tính sẽ mang giá trị đa trị, vi phạm nghiêm trọng 1NF.
   * *Giải pháp 1NF:* Tách dữ liệu phương tiện xe điện ra khỏi `user_account` thành quan hệ `vehicle` độc lập, liên kết qua khóa ngoại `account_identifier` (Mối quan hệ sở hữu 1:N).
2. **Tính Nguyên tố của Kiểu Dữ liệu Phức hợp:**
   * Thuộc tính vị trí địa lý `geographic_location` sử dụng kiểu dữ liệu PostGIS `GEOMETRY(Point, 4326)` tuân thủ ISO 6709 (PostGIS WGS 84), được hệ quản trị CSDL PostgreSQL xử lý như một điểm hình học nguyên tố đơn lẻ.
   * Các thuộc tính mốc thời gian (`TIMESTAMPTZ` tuân thủ ISO 8601) và đơn vị tiền tệ (`DECIMAL` tuân thủ ISO 4217) đều lưu trữ giá trị đơn không thể phân chia.

**Kết luận:** Toàn bộ 10 bảng trong hệ thống đạt chuẩn **1NF**.

---

### 2.2. Bước 2: Chứng minh Dạng chuẩn 2 (2NF - Second Normal Form)

**Định nghĩa 2NF:** Một quan hệ ở Dạng chuẩn 2 (2NF) khi nó đã đạt 1NF và mọi thuộc tính không phải là khóa chính (Non-key attributes) phải phụ thuộc hàm đầy đủ (Full Functional Dependency) vào toàn bộ khóa chính, không tồn tại phụ thuộc hàm một phần vào bất kỳ khóa con nào (No Partial Dependency).

#### Phân tích Phụ thuộc Hàm dựa trên Cấu trúc Khóa:
1. **Đối với các Bảng có Khóa chính Đơn (Single Primary Key - UUID):**
   * Các bảng `user_account`, `vehicle`, `parking_facility`, `parking_space`, `charging_equipment`, `tariff_rate`, `reservation`, `service_session`, và `payment_transaction` đều sử dụng khóa chính đơn dạng UUID tự sinh (`gen_random_uuid()`).
   * *Chứng minh toán học:* Vì khóa chính chỉ bao gồm duy nhất 1 thuộc tính (|PK| = 1), không tồn tại tập con thực sự nào của khóa chính. Do đó, về mặt lý thuyết mệnh đề phụ thuộc hàm, **không thể xuất hiện Phụ thuộc hàm một phần (Partial Dependency)**.
2. **Đối với Bảng có Khóa phức hợp (`facility_manager`):**
   * Khóa chính phức hợp: PK = (manager_identifier, facility_identifier).
   * Bảng này chỉ đóng vai trò là bảng trung gian giải quyết quan hệ Nhiều - Nhiều (N:M), hoàn toàn không chứa thuộc tính phi khóa nào khác ngoài các thuộc tính tham gia cấu thành khóa chính.
   * Do không có thuộc tính phi khóa, không tồn tại phụ thuộc hàm dạng A -> B với A thuộc tập con thực sự của PK và B không thuộc PK.

**Kết luận:** Toàn bộ các quan hệ trong hệ thống đạt chuẩn **2NF**.

---

### 2.3. Bước 3: Chứng minh Dạng chuẩn 3 (3NF - Third Normal Form)

**Định nghĩa 3NF:** Một quan hệ đạt Dạng chuẩn 3 (3NF) khi nó đã đạt 2NF và không chứa bất kỳ thuộc tính không khóa nào phụ thuộc bắc cầu (Transitive Dependency) vào khóa chính. Tức là không tồn tại chuỗi phụ thuộc X -> Y -> Z, trong đó X là khóa chính, Y và Z là các thuộc tính phi khóa.

#### Phân tích & Triệt tiêu Phụ thuộc Bắc cầu trên các Thực thể:
1. **Tách Thực thể `parking_space` & `charging_equipment` (1:1 Extension):**
   * *Rủi ro phi chuẩn hóa nếu gộp:* Nếu đưa toàn bộ thông tin bộ sạc vào chung bảng vị trí đỗ `parking_space`, sẽ phát sinh phụ thuộc bắc cầu:
     `space_identifier -> equipment_identifier -> connector_type_code`
   * *Giải pháp 3NF:* Tách thành 2 bảng riêng biệt `parking_space` và `charging_equipment`, liên kết mở rộng 1:1 qua khóa ngoại `space_identifier` (FK, UK).
2. **Tách Thực thể `payment_transaction` & `tariff_rate` (Dynamic Pricing):**
   * *Rủi ro phi chuẩn hóa nếu gộp:* Nếu lưu trực tiếp cấu hình đơn giá/khung giờ vào giao dịch thanh toán, sẽ phát sinh phụ thuộc bắc cầu:
     `transaction_identifier -> rate_identifier -> price_per_kwh_value`
   * *Giải pháp 3NF:* Tách bảng cấu hình giá `tariff_rate` riêng biệt. Bảng `payment_transaction` chỉ lưu khóa ngoại `rate_identifier` tham chiếu và số tiền tổng `transaction_amount_value` được chốt cố định tại thời điểm xuất hóa đơn.
3. **Thực thể `service_session`:**
   * Các thuộc tính phi khóa (`start_datetime`, `end_datetime`, `fully_charged_datetime`, `peak_charging_power_kw`, `consumed_energy_kwh`) phụ thuộc trực tiếp và duy nhất vào khóa chính `session_identifier`. Không tồn tại phụ thuộc Y -> Z giữa các thuộc tính phi khóa.

**Kết luận:** Toàn bộ hệ thống đạt chuẩn **3NF**.

---

### 2.4. Bước 4: Chứng minh Dạng chuẩn Boyce-Codd (BCNF - Boyce-Codd Normal Form)

**Định nghĩa BCNF:** Một quan hệ đạt Dạng chuẩn Boyce-Codd (BCNF) khi và chỉ khi đối với mọi Phụ thuộc hàm (Functional Dependency - FD) không tầm thường (non-trivial) có dạng X -> Y tồn tại trong quan hệ, vế trái X bắt buộc phải là một **Siêu khóa (Superkey)** hoặc **Khóa ứng viên (Candidate Key)**.

#### Phân tích Chi tiết Tập Phụ thuộc Hàm (FD Sets) trên từng Quan hệ:

#### 1. Bảng `user_account` (Quản lý Tài khoản Người dùng)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {account_identifier} -> {full_name_text, contact_phone_number, email_address, role_code, deleted_at}
  * FD2: {contact_phone_number} -> {account_identifier, full_name_text, email_address, role_code, deleted_at}
  * FD3: {email_address} -> {account_identifier, full_name_text, contact_phone_number, role_code, deleted_at}
* **Đánh giá BCNF:** 
  * Primary Key: {account_identifier}
  * Candidate Keys: {contact_phone_number}, {email_address}
  * Các vế trái X của FD1, FD2, FD3 đều là Siêu khóa / Khóa ứng viên. => **Đạt BCNF**.

#### 2. Bảng `vehicle` (Quản lý Phương tiện Xe điện)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {vehicle_identifier} -> {account_identifier, license_plate, battery_capacity_kwh, deleted_at}
  * FD2: {license_plate} -> {vehicle_identifier, account_identifier, battery_capacity_kwh, deleted_at}
* **Đánh giá BCNF:** 
  * Primary Key: {vehicle_identifier}
  * Candidate Key: {license_plate}
  * Vế trái X của FD1 và FD2 đều là Khóa ứng viên. => **Đạt BCNF**.

#### 3. Bảng `parking_facility` (Quản lý Bãi đỗ xe)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {facility_identifier} -> {facility_name_text, geographic_location, address_text, total_capacity_count}
* **Đánh giá BCNF:** 
  * Primary Key: {facility_identifier}
  * Vế trái X duy nhất là Primary Key (Superkey). => **Đạt BCNF**.

#### 4. Bảng `facility_manager` (Phân công Quản lý Bãi đỗ)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {manager_identifier, facility_identifier} -> Tập rỗng (Không có thuộc tính phi khóa)
* **Đánh giá BCNF:** 
  * Primary Key: Phức hợp {manager_identifier, facility_identifier}
  * Vế trái X chính là Khóa chính (Superkey). => **Đạt BCNF**.

#### 5. Bảng `parking_space` (Quản lý Vị trí đỗ xe)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {space_identifier} -> {facility_identifier, space_code, availability_status_code, deleted_at}
  * FD2: {facility_identifier, space_code} -> {space_identifier, availability_status_code, deleted_at}
* **Đánh giá BCNF:** 
  * Primary Key: {space_identifier}
  * Candidate Key: {facility_identifier, space_code}
  * Vế trái X của FD1 và FD2 đều là Khóa ứng viên hợp lệ. => **Đạt BCNF**.

#### 6. Bảng `charging_equipment` (Quản lý Thiết bị/Cổng sạc)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {equipment_identifier} -> {space_identifier, evse_identifier, connector_type_code, max_power_kw, equipment_status_code, deleted_at}
  * FD2: {evse_identifier} -> {equipment_identifier, space_identifier, connector_type_code, max_power_kw, equipment_status_code, deleted_at}
  * FD3: {space_identifier} -> {equipment_identifier, evse_identifier, connector_type_code, max_power_kw, equipment_status_code, deleted_at}
* **Đánh giá BCNF:** 
  * Primary Key: {equipment_identifier}
  * Candidate Keys: {evse_identifier} (ISO 15118 ID duy nhất), {space_identifier} (Ràng buộc 1:1 Extension)
  * Cả 3 vế trái X đều xác định duy nhất bản ghi phần cứng và đóng vai trò là Khóa ứng viên. => **Đạt BCNF**.

#### 7. Bảng `tariff_rate` (Cấu hình Bảng giá Linh hoạt)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {rate_identifier} -> {connector_type_code, start_time, end_time, min_power_kw, max_power_kw, price_per_kwh_value, overtime_fee_per_hour_value}
* **Đánh giá BCNF:** 
  * Primary Key: {rate_identifier}
  * Vế trái X duy nhất là Primary Key (Superkey). => **Đạt BCNF**.

#### 8. Bảng `reservation` (Quản lý Đặt chỗ trước)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {reservation_identifier} -> {account_identifier, space_identifier, start_datetime, end_datetime, reservation_status_code, created_datetime, deleted_at}
* **Đánh giá BCNF:** 
  * Primary Key: {reservation_identifier}
  * Vế trái X là Primary Key (Superkey). Ràng buộc loại trừ chống đè lịch `EXCLUDE USING gist` được cài đặt ở mức CSDL để bảo vệ vẹn toàn khoảng thời gian đỗ. => **Đạt BCNF**.

#### 9. Bảng `service_session` (Quản lý Phiên sử dụng & Sạc)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {session_identifier} -> {reservation_identifier, account_identifier, equipment_identifier, start_datetime, end_datetime, fully_charged_datetime, peak_charging_power_kw, consumed_energy_kwh}
* **Đánh giá BCNF:** 
  * Primary Key: {session_identifier}
  * Vế trái X là Primary Key (Superkey). => **Đạt BCNF**.

#### 10. Bảng `payment_transaction` (Giao dịch Thanh toán & Audit Log)
* **Tập Phụ thuộc Hàm (FD Set):**
  * FD1: {transaction_identifier} -> {session_identifier, rate_identifier, transaction_amount_value, currency_code, payment_method_code, gateway_reference_id, transaction_status_code, created_datetime}
  * FD2: {session_identifier} -> {transaction_identifier, rate_identifier, transaction_amount_value, currency_code, payment_method_code, gateway_reference_id, transaction_status_code, created_datetime}
* **Đánh giá BCNF:** 
  * Primary Key: {transaction_identifier}
  * Candidate Key: {session_identifier} (Ràng buộc FK, UK bảo đảm quan hệ Strict 1:1)
  * Cả hai vế trái X của FD1 và FD2 đều đóng vai trò là Khóa ứng viên / Superkey. => **Đạt BCNF**.

---

## 3. Tổng Kết Kết Quả Chuẩn Hóa

Mọi Phụ thuộc Hàm X -> Y tồn tại trong mô hình cơ sở dữ liệu đều thỏa mãn điều kiện X là một **Siêu khóa (Superkey)** hoặc **Khóa ứng viên (Candidate Key)**. 

Toàn bộ Lược đồ Quan hệ của hệ thống **Smart City EV Charging & Parking Management** đạt mức chuẩn cao nhất: **Boyce-Codd Normal Form (BCNF)**. Thiết kế này bảo đảm tuyệt đối tính toàn vẹn dữ liệu, triệt tiêu mọi rủi ro bất thường (Insertion/Update/Deletion Anomalies), đồng thời tối ưu hóa hiệu năng truy vấn giao dịch thời gian thực trên hệ quản trị cơ sở dữ liệu PostgreSQL.
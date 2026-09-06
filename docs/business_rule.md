# Thông tin dự án
**Tên dự án:** Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện (EV) thông minh)
**Tên nhóm:** M3B
**Thành viên nhóm:**
* Nguyễn Trường Nghị - n24dccn142@student.ptithcm.edu.vn
* Phạm Công Đang - n24dccn102@student.ptithcm.edu.vn
* Mai Văn Công - n24dccn100@student.ptithcm.edu.vn

---

## Quy tắc nghiệp vụ & ràng buộc

### 1. Quản lý Người dùng & Phương tiện
* **Đăng ký tài khoản (`user_account`):** Mỗi người dùng đăng ký một tài khoản duy nhất (xác thực qua Email và Số điện thoại duy nhất). Tài khoản được phân vai trò (`role_code`): `CUSTOMER` (Khách hàng), `MANAGER` (Quản lý bãi đỗ), hoặc `ADMIN` (Quản trị hệ thống).
* **Quản lý Phương tiện (`vehicle`):** Mỗi khách hàng có thể sở hữu nhiều xe điện. Mỗi xe điện được định danh duy nhất bằng Biển số xe (`license_plate`) và ghi nhận dung lượng pin tối đa (`battery_capacity_kwh`).
* **Phân công Quản lý (`facility_manager`):**
  * Một bãi đỗ xe (`parking_facility`) có thể được quản lý bởi nhiều nhân viên (`MANAGER`), và một `MANAGER` có thể phụ trách nhiều bãi đỗ xe khác nhau.
  * Chỉ tài khoản có vai trò `ADMIN` mới có quyền phân công hoặc gán `MANAGER` vào bãi đỗ xe thông qua bảng trung gian `facility_manager`.

### 2. Quản lý Bãi đỗ xe, Trạm sạc & Cổng sạc
* **Cấu trúc Bãi đỗ (`parking_facility`):**
  * Mỗi bãi đỗ xe nằm tại một vị trí địa lý cụ thể, bao gồm tên bãi đỗ, địa chỉ hành chính chi tiết (`street_address_text`), tọa độ địa lý PostGIS WGS 84 (`geographic_location`) và tổng sức chứa đăng ký (`total_capacity_count`).
  * Tổng số lượng vị trí đỗ (`parking_space`) khởi tạo thực tế thuộc bãi đỗ không được vượt quá `total_capacity_count`.
* **Vị trí đỗ (`parking_space`) & Thiết bị Sạc (`charging_equipment`):**
  * Mỗi vị trí đỗ có mã định danh `space_code` (ví dụ: `A-01`, `B-02`). Vị trí đỗ có thể là chỗ đỗ có bộ sạc xe điện hoặc chỗ đỗ thuần túy.
  * Với vị trí đỗ có bộ sạc, thiết bị sạc (`charging_equipment`) liên kết 1-1 với vị trí đỗ, được định danh theo chuẩn ISO 15118 (`evse_identifier`), thuộc phân loại sạc nhanh (`FAST_DC`) hoặc sạc tiêu chuẩn (`STANDARD_AC`), đồng thời ghi nhận công suất sạc định mức tối đa (`max_power_kw`).
* **Trạng thái Khả dụng:**
  * Tại một thời điểm, vị trí đỗ (`parking_space`) ở một trong các trạng thái (`availability_status_code`): `AVAILABLE` (Rảnh), `RESERVED` (Đã đặt chỗ), `OCCUPIED` (Đang đỗ/sạc), hoặc `OUTOFSERVICE` (Bảo trì).
  * Trạng thái của vị trí đỗ phải đồng bộ với trạng thái hoạt động của thiết bị sạc (`equipment_status_code`).

### 3. Quy tắc Đặt chỗ trước (Reservation Rules)
* **Khả năng đặt chỗ:** Khách hàng chỉ được đặt trước vị trí đỗ/cổng sạc có trạng thái `AVAILABLE`.
* **Chống đè lịch (Overlap Prevention):** Khoảng thời gian đặt chỗ (`start_datetime` đến `end_datetime`) không được trùng đè lên bất kỳ lịch đặt chỗ hoặc phiên sử dụng nào khác trên cùng một vị trí đỗ (Sử dụng ràng buộc chống xung đột `EXCLUSION CONSTRAINT` trên PostgreSQL).
* **Trạng thái Đặt chỗ (`reservation`):** Lượt đặt chỗ có các trạng thái (`reservation_status_code`): `PENDING` (Chờ xác nhận), `CONFIRMED` (Đã xác nhận), `COMPLETED` (Đã hoàn thành), hoặc `CANCELLED` (Đã hủy).
* **Tự động Hủy (Timeout):** Nếu quá 30 phút so với `start_datetime` mà khách hàng không đến kích hoạt phiên sạc, hệ thống tự động chuyển trạng thái `reservation` thành `CANCELLED` và giải phóng `parking_space` về trạng thái `AVAILABLE`.

### 4. Tính giá theo Công suất & Phiên sạc (Power-based Dynamic Pricing & Charging Sessions)
* **Bảng giá Linh hoạt theo Công suất & Khung giờ (`tariff_rate`):**
  * Bảng giá được cấu hình linh hoạt dựa trên phân loại cổng sạc (`connector_type_code`), dải công suất sạc (`min_power_kw` đến `max_power_kw`), và khung giờ áp dụng (`start_time` đến `end_time`).
* **Phiên sử dụng (`service_session`):**
  * Khi bắt đầu sạc, hệ thống khởi tạo phiên sạc và ghi nhận `start_datetime`.
  * Trong quá trình sạc, hệ thống liên tục giám sát và ghi nhận công suất sạc thực tế tối đa đạt được trong phiên (`peak_charging_power_kw`).
  * Khi xe sạc đầy pin, hệ thống ghi nhận `fully_charged_datetime`.
  * Khi kết thúc phiên và rút sạc/rời vị trí, hệ thống ghi nhận `end_datetime` và điện năng tiêu thụ thực tế (`consumed_energy_kwh`).
* **Tính phí & Giao dịch thanh toán (`payment_transaction`):**
  * Chi phí tổng của phiên sạc được tính toán dựa trên đơn giá điện năng theo dải công suất thực tế/định mức và phí đỗ quá giờ (nếu có) với công thức: `Tổng tiền = (consumed_energy_kwh * price_per_kwh_value) + Phí phạt quá giờ`
  * Phí đỗ quá giờ (`overtime_fee_per_hour_value`) được tự động áp dụng nếu thời gian rút sạc rời vị trí (`end_datetime`) muộn hơn thời điểm xe đã sạc đầy (`fully_charged_datetime`).
  * Mỗi phiên hoàn tất sẽ khởi tạo một giao dịch thanh toán (`payment_transaction`) lưu trữ đơn vị tiền tệ tuân thủ ISO 4217 (`VND`), phương thức thanh toán (`payment_method_code`), và mã đối soát từ cổng thanh toán bên thứ ba (`gateway_reference_id`).

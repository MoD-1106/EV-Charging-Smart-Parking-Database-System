# TÀI LIỆU QUY TẮC NGHIỆP VỤ & RÀNG BUỘC HỆ THỐNG (BUSINESS RULES)

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

## 1. Mục tiêu & Phạm vi Hệ thống (ISO/IEC/IEEE 29148)

Hệ thống được xây dựng trên nền tảng cơ sở dữ liệu quan hệ PostgreSQL chuẩn hóa, hướng đến giải quyết các bài toán hạ tầng giao thông đô thị thông minh:
* Quản lý tập trung hạ tầng bãi đỗ xe tích hợp các trạm sạc xe điện (EVSE).
* Quản lý tài khoản khách hàng, đăng ký phương tiện và điều phối phân quyền quản trị đa cấp (RBAC).
* Tự động hóa quy trình đặt chỗ trước (Reservation) và ngăn chặn xung đột thời gian thực.
* Vận hành phiên sạc xe điện, giám sát công suất đỉnh và tính giá động (Dynamic Pricing) theo dải công suất và khung giờ.
* Đảm bảo tính toàn vẹn dữ liệu giao dịch tài chính và lưu vết kiểm toán (Audit Trail) theo các tiêu chuẩn quốc tế ISO 8601, ISO 4217, ISO 11179 và ISO 15118.

---

## 2. Quy tắc Nghiệp vụ & Ràng buộc Chi tiết

### 2.1. Quản lý Người dùng & Phương tiện (User & Vehicle Management)
* **Đăng ký tài khoản (`user_account`):**
  * Mỗi người dùng chỉ được đăng ký một tài khoản duy nhất trên hệ thống.
  * Định danh và xác thực bắt buộc thông qua số điện thoại (`contact_phone_number`) và thư điện tử (`email_address`). Cả hai trường đều có ràng buộc tính duy nhất toàn cục (`UNIQUE`).
  * Tài khoản được phân quyền truy cập nghiêm ngặt thông qua trường vai trò (`role_code`):
    * `CUSTOMER`: Khách hàng sử dụng dịch vụ bãi đỗ và sạc xe.
    * `MANAGER`: Nhân viên/Quản lý vận hành tại các bãi đỗ xe được phân công.
    * `ADMIN`: Quản trị viên cấp cao toàn quyền quản lý hệ thống.
* **Quản lý Phương tiện (`vehicle`):**
  * Mỗi khách hàng (`CUSTOMER`) có thể sở hữu và đăng ký nhiều xe điện trong hệ thống (Quan hệ sở hữu 1:N).
  * Mỗi phương tiện được định danh duy nhất bằng Biển số xe (`license_plate`).
  * Ghi nhận dung lượng pin tối đa của xe (`battery_capacity_kwh`) với ràng buộc giá trị phải lớn hơn 0:
    ```sql
    CHECK (battery_capacity_kwh > 0)
    ```
* **Phân công Quản lý (`facility_manager`):**
  * Một bãi đỗ xe (`parking_facility`) có thể được quản lý đồng thời bởi nhiều nhân viên vận hành (`MANAGER`), và một `MANAGER` có thể được phân công phụ trách nhiều bãi đỗ xe khác nhau (Quan hệ N:M).
  * **Ràng buộc phân quyền:** Chỉ tài khoản có vai trò `ADMIN` mới có quyền phân công, gán hoặc thu hồi quyền quản lý của `MANAGER` tại các bãi đỗ xe thông qua bảng trung gian `facility_manager`.
* **Xóa mềm dữ liệu (Soft Delete):**
  * Tài khoản và phương tiện khi ngừng sử dụng sẽ được gắn nhãn thời gian qua trường `deleted_at` (`TIMESTAMPTZ`) thay vì xóa vật lý khỏi cơ sở dữ liệu để bảo tồn lịch sử giao dịch.

---

### 2.2. Quản lý Bãi đỗ xe, Trạm sạc & Cổng sạc (Parking Facilities & Charging Equipment)
* **Cấu trúc Bãi đỗ (`parking_facility`):**
  * Mỗi bãi đỗ xe nằm tại một vị trí địa lý xác định, lưu trữ đầy đủ thông tin: tên bãi đỗ (`facility_name_text`), địa chỉ hành chính chi tiết (`address_text`), tọa độ địa lý PostGIS WGS 84 (`geographic_location` kiểu `GEOMETRY(Point, 4326)` tuân thủ ISO 6709), và tổng sức chứa đăng ký (`total_capacity_count`).
  * **Ràng buộc sức chứa:** Tổng số lượng vị trí đỗ (`parking_space`) được khởi tạo thực tế thuộc bãi đỗ tại mọi thời điểm không được vượt quá tổng sức chứa thiết kế:
    ```text
    Số lượng (parking_space thuộc bãi đỗ) <= total_capacity_count
    ```
* **Vị trí đỗ (`parking_space`) & Thiết bị Sạc (`charging_equipment`):**
  * Mỗi vị trí đỗ có mã định danh hiển thị `space_code` (ví dụ: `A-01`, `B-02`). 
  * **Ràng buộc duy nhất:** Ký hiệu ô đỗ là duy nhất trong phạm vi từng cơ sở bãi đỗ:
    ```sql
    UNIQUE (facility_identifier, space_code)
    ```
  * Vị trí đỗ có thể là chỗ đỗ xe thuần túy hoặc chỗ đỗ có tích hợp trạm sạc xe điện.
  * Đối với vị trí có trạm sạc, thiết bị sạc (`charging_equipment`) liên kết theo mô hình mở rộng 1:1 với vị trí đỗ (`parking_space`), được định danh chuẩn toàn cầu ISO 15118 (`evse_identifier`), phân loại chuẩn đầu sạc (`connector_type_code` gồm `FAST_DC` - sạc nhanh hoặc `STANDARD_AC` - sạc tiêu chuẩn), và ghi nhận công suất sạc định mức tối đa (`CHECK (max_power_kw > 0)`).
* **Trạng thái Khả dụng & Tính đồng bộ:**
  * Tại một thời điểm, vị trí đỗ (`parking_space`) chỉ nằm ở một trong các trạng thái (`availability_status_code`):
    * `AVAILABLE`: Sẵn sàng phục vụ đỗ/sạc.
    * `RESERVED`: Đã có khách đặt giữ chỗ trước.
    * `OCCUPIED`: Đang có phương tiện đỗ hoặc đang thực hiện phiên sạc.
    * `OUTOFSERVICE`: Vị trí tạm dừng hoạt động do bảo trì hoặc sự cố.
  * **Quy tắc đồng bộ thiết bị:** Trạng thái của vị trí đỗ phải được đồng bộ với trạng thái kỹ thuật của thiết bị sạc (`equipment_status_code`: `READY`, `CHARGING`, `FAULT`, `MAINTENANCE`). Khi thiết bị chuyển sang trạng thái `FAULT` hoặc `MAINTENANCE`, vị trí đỗ tương ứng phải tự động chuyển sang `OUTOFSERVICE`.

---

### 2.3. Quy tắc Đặt chỗ trước (Reservation Rules)
* **Điều kiện đặt chỗ:** Khách hàng chỉ được phép tạo lượt đặt trước (`reservation`) nếu vị trí đỗ xe/cổng sạc đang ở trạng thái `AVAILABLE` trong toàn bộ khung thời gian yêu cầu.
* **Thời gian đặt chỗ hợp lệ:** Mốc thời gian kết thúc phải sau thời gian bắt đầu:
  ```sql
  CHECK (end_datetime > start_datetime)
  ```
* **Chống đè lịch (Overlap Prevention):** Khoảng thời gian đặt chỗ (`start_datetime` đến `end_datetime`) không được phép đè lên (overlap) bất kỳ lịch đặt chỗ hợp lệ hoặc phiên sử dụng nào khác trên cùng một vị trí đỗ. Hệ thống áp dụng ràng buộc loại trừ PostgreSQL GiST:
  ```sql
  EXCLUDE USING gist (
      space_identifier WITH =,
      tsrange(start_datetime, end_datetime) WITH &&
  )
  ```
* **Vòng đời trạng thái đặt chỗ (`reservation_status_code`):**
  * `PENDING`: Lượt đặt chỗ mới tạo, chờ hệ thống xác nhận.
  * `CONFIRMED`: Đặt chỗ thành công, ô đỗ chuyển trạng thái `RESERVED`.
  * `COMPLETED`: Khách hàng đã đến bãi và kích hoạt phiên sạc thực tế.
  * `CANCELLED`: Lượt đặt chỗ bị hủy bởi khách hàng hoặc bị hệ thống thu hồi.
* **Tự động Hủy quá hạn (Timeout):** Nếu quá 30 phút kể từ mốc `start_datetime` mà khách hàng không đến cắm sạc/kích hoạt phiên sử dụng:
  * Hệ thống tự động chuyển trạng thái `reservation` thành `CANCELLED`.
  * Vị trí đỗ (`parking_space`) ngay lập tức được giải phóng về trạng thái `AVAILABLE` để phục vụ khách hàng khác.

---

### 2.4. Tính giá theo Công suất & Phiên sạc (Power-based Dynamic Pricing & Charging Sessions)
* **Bảng giá Linh hoạt theo Công suất & Khung giờ (`tariff_rate`):**
  * Giá dịch vụ được cấu hình linh hoạt dựa trên sự kết hợp đồng thời của 3 yếu tố:
    1. **Phân loại cổng sạc (`connector_type_code`):** `FAST_DC` (sạc nhanh DC) hoặc `STANDARD_AC` (sạc tiêu chuẩn AC).
    2. **Dải công suất định mức/thực tế:** `[min_power_kw, max_power_kw]` với điều kiện `max_power_kw > min_power_kw >= 0`.
    3. **Khung giờ áp dụng:** `[start_time, end_time]` (phân biệt rõ khung giờ cao điểm và giờ thấp điểm trong ngày).
* **Quản lý Phiên sử dụng (`service_session`):**
  * **Khởi tạo:** Khi phương tiện cắm sạc vào trụ, hệ thống ghi nhận thời điểm bắt đầu thực tế (`start_datetime`).
  * **Giám sát công suất đỉnh:** Trong suốt tiến trình sạc, hệ thống liên tục đo lường và cập nhật công suất sạc thực tế cao nhất đạt được trong phiên (`peak_charging_power_kw >= 0`).
  * **Ghi nhận sạc đầy:** Khi pin xe đạt 100%, hệ thống ghi nhận mốc thời gian sạc đầy (`fully_charged_datetime`), thỏa mãn:
    ```sql
    CHECK (fully_charged_datetime >= start_datetime)
    ```
  * **Kết thúc phiên:** Khi xe ngắt kết nối rút sạc và rời vị trí, hệ thống ghi nhận `end_datetime` (`end_datetime >= start_datetime`) và chốt tổng điện năng thực tế đã nạp (`consumed_energy_kwh >= 0`).
* **Tính phí & Giao dịch thanh toán (`payment_transaction`):**
  * Chi phí tổng của phiên sạc được tính toán dựa trên đơn giá điện năng theo dải công suất/khung giờ và phí đỗ xe quá giờ (nếu có):
    ```text
    Tổng tiền = (consumed_energy_kwh * price_per_kwh_value) + Phí phạt quá giờ
    ```
  * **Quy tắc tính Phí phạt quá giờ:** Áp dụng đơn giá phạt quá giờ (`overtime_fee_per_hour_value`) nếu thời gian rút sạc rời vị trí (`end_datetime`) muộn hơn thời điểm pin đã sạc đầy (`fully_charged_datetime`):
    ```text
    Thời gian quá giờ (giờ) = max(0, (end_datetime - fully_charged_datetime) / 3600)
    Phí phạt quá giờ = Thời gian quá giờ * overtime_fee_per_hour_value
    ```
  * **Xuất hóa đơn & Giao dịch tài chính:**
    * Mỗi phiên kết thúc thành công sẽ tự động tạo một giao dịch thanh toán (`payment_transaction`) tương ứng (Quan hệ nghiêm ngặt 1:1 với `service_session`).
    * Thông qua phiên sạc, giao dịch truy xuất trực tiếp danh tính tài khoản khách hàng để phát hành hóa đơn.
    * Ghi nhận đơn vị tiền tệ ISO 4217 (`VND`), phương thức thanh toán (`payment_method_code`: thẻ ngân hàng, ví điện tử MoMo, VNPay), và mã đối soát từ cổng thanh toán đối tác (`gateway_reference_id`).
  * **Bảo toàn Dữ liệu Kiểm toán (Audit Log):** Bảng thanh toán thiết lập khóa ngoại với ràng buộc `ON DELETE RESTRICT` đối với `service_session` và `tariff_rate`. Dữ liệu giao dịch tài chính không thể bị xóa vật lý để đảm bảo đối soát kế toán và kiểm toán hệ thống.

---

## 3. Ma trận Phân quyền Truy cập (RBAC Matrix)

| Chức năng / Thao tác | CUSTOMER | MANAGER | ADMIN |
| :--- | :---: | :---: | :---: |
| Đăng ký & quản lý hồ sơ cá nhân | ✓ | ✓ | ✓ |
| Đăng ký & liên kết xe điện (`vehicle`) | ✓ | - | - |
| Tìm kiếm bãi đỗ & tra cứu vị trí đỗ khả dụng | ✓ | ✓ | ✓ |
| Đặt chỗ trước ô đỗ/cổng sạc (`reservation`) | ✓ | - | - |
| Hủy lượt đặt chỗ cá nhân | ✓ | - | - |
| Hủy lượt đặt chỗ quá hạn 30 phút | Tự động | ✓ | ✓ |
| Giám sát thông số phiên sạc cá nhân thời gian thực | ✓ | - | - |
| Thực hiện thanh toán hóa đơn phiên sạc | ✓ | - | - |
| Giám sát sơ đồ, trạng thái ô đỗ bãi phụ trách | - | ✓ | ✓ |
| Điều chỉnh trạng thái thiết bị sạc (`FAULT`, `MAINTENANCE`) | - | ✓ | ✓ |
| Khởi tạo & phân công quản lý bãi đỗ (`facility_manager`) | - | - | ✓ |
| Thêm/Sửa/Xóa cấu hình Bãi đỗ (`parking_facility`) | - | - | ✓ |
| Cấu hình Biểu giá linh hoạt theo công suất (`tariff_rate`) | - | - | ✓ |
| Thẩm tra toàn bộ nhật ký kế toán & đối soát giao dịch | - | - | ✓ |

---

## 4. Các Tiêu chuẩn Kỹ thuật Tuân thủ

1. **ISO/IEC 19505 / Information Engineering (IE):** Mô hình dữ liệu quan hệ ở mức chuẩn 3NF (Third Normal Form), quan hệ mở rộng 1:1 giữa thực thể vật lý (`parking_space`) và thiết bị kỹ thuật (`charging_equipment`).
2. **ISO/IEC 11179 Metadata Standards:** Quy chuẩn đặt tên trường thuộc tính nhất quán theo tiền tố và hậu tố ngữ nghĩa (`_identifier`, `_code`, `_datetime`, `_text`, `_count`, `_kwh`, `_kw`, `_value`).
3. **ISO 8601:** Đồng bộ thời gian hệ thống lưu trữ dưới định dạng `TIMESTAMPTZ` (UTC-aware).
4. **ISO 4217:** Mã hóa tiền tệ thanh toán tiêu chuẩn (`VND`).
5. **ISO 15118 & OCPP:** Mã định danh điểm sạc toàn cầu `evse_identifier` nhằm đồng bộ và tương thích với giao thức điều khiển trạm sạc xe điện thông minh.
6. **OpenGIS / PostGIS (EPSG:4326):** Quản lý dữ liệu không gian WGS 84 phục vụ định vị và tính toán khoảng cách địa lý chính xác.

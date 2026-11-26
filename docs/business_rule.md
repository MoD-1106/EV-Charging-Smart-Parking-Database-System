# TÀI LIỆU QUY TẮC NGHIỆP VỤ & RÀNG BUỘC HỆ THỐNG (BUSINESS RULES)

## Thông tin dự án
* **Tên dự án:** Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện (EV) thông minh)
* **ID Dự Án:** #1: Smart City EV Charging & Parking Management
* **Tên nhóm:** M3B
* **Thành viên nhóm:**
  * Nguyễn Trường Nghị - `n24dccn142@student.ptithcm.edu.vn`
  * Phạm Công Đang - `n24dccn102@student.ptithcm.edu.vn`
  * Mai Văn Công - `n24dccn100@student.ptithcm.edu.vn`

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
  * Định danh và xác thực bắt buộc thông qua số điện thoại (`contact_phone_number`) và thư điện tử (`email_address`). Cả hai trường duy nhất trong các tài khoản chưa bị xóa mềm (**chỉ mục duy nhất từng phần**, email so sánh không phân biệt hoa/thường), nhờ vậy người dùng đã xóa tài khoản có thể đăng ký lại.
  * Đăng nhập kiểm mật khẩu băm (`password_hash_text`). Theo yêu cầu của đồ án, mật khẩu gốc cũng được lưu (`password_plain_text`) để ADMIN xem; cột này bị xóa khi tài khoản bị xóa vĩnh viễn.
  * Tài khoản được phân quyền truy cập nghiêm ngặt thông qua trường vai trò (`role_code`):
    * `CUSTOMER`: Khách hàng sử dụng dịch vụ bãi đỗ và sạc xe.
    * `MANAGER`: Nhân viên/Quản lý vận hành tại các bãi đỗ xe được phân công.
    * `ADMIN`: Quản trị viên cấp cao toàn quyền quản lý hệ thống.
* **Định nghĩa & Ví dụ minh họa các Role:**
  *  Khách hàng (CUSTOMER): 
     * Định nghĩa: Người dùng cá nhân/tổ chức sử dụng ứng dụng để đặt đỗ và sạc xe.
     * Ví dụ: Khách hàng Nguyễn Văn A (`account_identifier` = 'usr-001') đăng ký sở hữu xe VinFast VF8 trong bảng `vehicle` (biển số `license_plate_text` = '51H-123.45', dung lượng pin `battery_capacity_kwh` = 82.00). Anh A tạo đơn đặt chỗ trước tại bãi Vincom Đồng Khởi ô A-01 từ 18:00 đến 19:30. Sau khi sạc 45.50 kWh, hệ thống phát hành hóa đơn 182,000 VND trong `payment_transaction` và anh A thanh toán qua ví MoMo (`payment_method_code` = 'E_WALLET').
  *  Quản lý Bãi đỗ xe (MANAGER):
     * Định nghĩa: Nhân viên trực tiếp vận hành bãi đỗ được phân công quản lý.
     * Ví dụ: Quản lý Trần Thị B (`role_code` = 'MANAGER', `account_identifier` = 'mng-002') được gán phụ trách Bãi đỗ Central Park qua bảng `facility_manager`. Chị B theo dõi sơ đồ 50 ô đỗ thời gian thực, phát hiện ô B-05 báo `OCCUPIED` nhưng trụ sạc báo lỗi `FAULT` để cử kỹ thuật xử lý. Nếu lượt đặt chỗ quá 30 phút khách không đến, chị B (hoặc tiến trình tự động) đổi trạng thái `reservation_status_code` = 'EXPIRED' để mở ô đỗ về `AVAILABLE`.
  *  Quản trị viên Hệ thống (ADMIN):
     * Định nghĩa: Cấp quản trị cao nhất toàn quyền cấu hình và kiểm soát hệ thống.
     * Ví dụ: Admin tạo bãi đỗ mới "Trạm sạc Bến Thành" trong `parking_facility` với tọa độ GIS PostGIS `geographic_location`, thêm các ô đỗ `parking_space` và đăng ký trụ sạc chuẩn ISO 15118 (`evse_identifier` = 'VN*EVSE*E99999'). Admin cấu hình chính sách giá linh hoạt trong `tariff_rate` (Giờ cao điểm 17:00-20:00 giá 4,000 VND/kWh, phí đỗ ngâm quá giờ 60,000 VND/giờ). Admin thẩm tra báo cáo doanh thu từ `payment_transaction` (ràng buộc `ON DELETE RESTRICT` ngăn xóa mất hóa đơn tài chính).
* **Quản lý Phương tiện (`vehicle`):**
  * Mỗi khách hàng (`CUSTOMER`) có thể sở hữu và đăng ký nhiều xe điện trong hệ thống (Quan hệ sở hữu 1:N).
  * **Ràng buộc chủ xe:** trigger `trg_vehicle_owner_role` bảo đảm `vehicle.account_identifier` là tài khoản `CUSTOMER` chưa bị xóa.
  * Mỗi phương tiện được định danh duy nhất bằng Biển số xe (`license_plate_text`) trong các xe chưa xóa mềm (chỉ mục duy nhất từng phần).
  * Mọi lượt đặt chỗ (`reservation`) và phiên sạc (`service_session`) **bắt buộc gắn với một xe** (`vehicle_identifier`); tài khoản của lượt đặt/phiên sạc được suy ra từ chủ xe, không lưu trùng.
  * Ghi nhận dung lượng pin tối đa của xe (`battery_capacity_kwh`) với ràng buộc giá trị phải lớn hơn 0:
    ```sql
    CHECK (battery_capacity_kwh > 0)
    ```
* **Phân công Quản lý (`facility_manager`):**
  * Một bãi đỗ xe (`parking_facility`) có thể được quản lý đồng thời bởi nhiều nhân viên vận hành (`MANAGER`), và một `MANAGER` có thể được phân công phụ trách nhiều bãi đỗ xe khác nhau (Quan hệ N:M).
  * **Ràng buộc phân quyền:** Chỉ tài khoản có vai trò `ADMIN` mới có quyền phân công, gán hoặc thu hồi quyền quản lý của `MANAGER` (kiểm soát ở tầng ứng dụng/RBAC). Ở tầng CSDL, trigger `trg_facility_manager_role` bảo đảm `manager_identifier` luôn là tài khoản `MANAGER` chưa bị xóa.
* **Xóa mềm dữ liệu (Soft Delete):**
  * Tài khoản và phương tiện khi ngừng sử dụng sẽ được gắn nhãn thời gian qua trường `deleted_datetime` (`TIMESTAMPTZ`) thay vì xóa vật lý khỏi cơ sở dữ liệu để bảo tồn lịch sử giao dịch.
* **Xóa và khôi phục tài khoản:**
  * ADMIN xóa được tài khoản MANAGER và CUSTOMER; không xóa được tài khoản ADMIN.
  * Khách đang sạc hoặc còn hóa đơn chưa trả: hiện lưu ý, ADMIN xác nhận rồi mới xóa. Phiên đang mở vẫn được quản lý kết thúc và lập hóa đơn.
  * Khôi phục được trong 30 phút. Quá 30 phút thì xóa vĩnh viễn thông tin cá nhân (tài khoản chưa có lịch sử thì xóa hẳn); đang sạc thì chờ phiên kết thúc.
  * Hóa đơn ghi sẵn họ tên, điện thoại, email, biển số của khách nên vẫn còn đủ thông tin sau khi tài khoản bị xóa.

---

### 2.2. Quản lý Bãi đỗ xe, Trạm sạc & Cổng sạc (Parking Facilities & Charging Equipment)
* **Cấu trúc Bãi đỗ (`parking_facility`):**
  * Mỗi bãi đỗ xe nằm tại một vị trí địa lý xác định, lưu trữ đầy đủ thông tin: tên bãi đỗ (`facility_name_text`), địa chỉ hành chính chi tiết (`address_text`), tọa độ địa lý PostGIS WGS 84 (`geographic_location` kiểu `GEOMETRY(Point, 4326)` tuân thủ ISO 6709), và tổng sức chứa đăng ký (`total_capacity_count`).
  * **Ràng buộc sức chứa:** Tổng số lượng vị trí đỗ (`parking_space`) được khởi tạo thực tế thuộc bãi đỗ tại mọi thời điểm không được vượt quá tổng sức chứa thiết kế:
    ```text
    Số lượng (parking_space chưa xóa thuộc bãi đỗ) <= total_capacity_count
    ```
    Được thực thi bằng trigger `trg_space_capacity`. `total_capacity_count` là sức chứa thiết kế do Admin khai báo, không phải giá trị suy ra.
* **Vị trí đỗ (`parking_space`) & Thiết bị Sạc (`charging_equipment`):**
  * Mỗi vị trí đỗ có mã định danh hiển thị `space_code` (ví dụ: `A-01`, `B-02`). 
  * **Ràng buộc duy nhất:** Ký hiệu ô đỗ là duy nhất trong phạm vi từng cơ sở bãi đỗ:
    ```sql
    UNIQUE (facility_identifier, space_code) WHERE deleted_datetime IS NULL
    ```
  * Vị trí đỗ có thể là chỗ đỗ xe thuần túy hoặc chỗ đỗ có tích hợp trạm sạc xe điện.
  * Đối với vị trí có trạm sạc, thiết bị sạc (`charging_equipment`) liên kết theo mô hình mở rộng 1:1 với vị trí đỗ (`parking_space`), được định danh chuẩn toàn cầu ISO 15118 (`evse_identifier`), phân loại chuẩn đầu sạc (`connector_type_code` gồm `FAST_DC` - sạc nhanh hoặc `STANDARD_AC` - sạc tiêu chuẩn), và ghi nhận công suất sạc định mức tối đa (`CHECK (max_power_kw > 0)`).
* **Trạng thái Khả dụng & Tính đồng bộ:**
  * Tại một thời điểm, vị trí đỗ (`parking_space`) chỉ nằm ở một trong các trạng thái (`availability_status_code`):
    * `AVAILABLE`: Sẵn sàng phục vụ đỗ/sạc.
    * `RESERVED`: Đã có khách đặt giữ chỗ trước.
    * `OCCUPIED`: Đang có phương tiện đỗ hoặc đang thực hiện phiên sạc.
    * `OUTOFSERVICE`: Vị trí tạm dừng hoạt động do bảo trì hoặc sự cố.
  * **Quy tắc đồng bộ thiết bị:** Trạng thái của vị trí đỗ phải được đồng bộ với trạng thái kỹ thuật của thiết bị sạc (`equipment_status_code`: `READY`, `CHARGING`, `FAULT`, `MAINTENANCE`). Khi thiết bị chuyển sang `FAULT` hoặc `MAINTENANCE`, vị trí đỗ tự động chuyển sang `OUTOFSERVICE`; khi thiết bị về `READY`, vị trí đỗ đang `OUTOFSERVICE` trở lại `AVAILABLE` (trigger `trg_equipment_status_sync`).
  * **Lưu ý:** `availability_status_code` là trạng thái vận hành **hiện tại**. Khả dụng trong một **khung giờ tương lai** không đọc từ cột này mà tính từ bảng `reservation` (xem 2.3).

---

### 2.3. Quy tắc Đặt chỗ trước (Reservation Rules)
* **Điều kiện đặt chỗ:** "Vị trí đỗ `AVAILABLE` trong toàn bộ khung giờ yêu cầu" được định nghĩa là: (1) ô đỗ và thiết bị chưa bị xóa và không ở trạng thái `OUTOFSERVICE`; (2) **không có** lượt đặt đang giữ chỗ (`PENDING`, `CONFIRMED`, `FULFILLED`) chồng lên khung giờ đó. Hàm `fn_is_space_available(space, start, end)` kiểm tra điều kiện này; trigger `trg_reservation_validate` chặn đặt vào ô `OUTOFSERVICE`.
* **Thời gian hợp lệ:** `CHECK (end_datetime > start_datetime)`.
* **Chống đè lịch (Overlap Prevention):** các lượt đặt đang giữ chỗ không được chồng thời gian trên cùng một ô đỗ. Dùng `tstzrange` (không phải `tsrange`, vì cột là `TIMESTAMPTZ`) và chỉ tính các lượt còn hiệu lực, để lượt đã hủy/hết hạn trả lại khung giờ:
  ```sql
  EXCLUDE USING gist (
      space_identifier WITH =,
      tstzrange(start_datetime, end_datetime) WITH &&
  ) WHERE (reservation_status_code IN ('PENDING', 'CONFIRMED', 'FULFILLED')
           AND deleted_datetime IS NULL)
  ```
  Yêu cầu extension `btree_gist`.
* **Khách vãng lai (không đặt trước):** `service_session` không có `reservation_identifier` chỉ được bắt đầu nếu thời điểm bắt đầu không rơi vào khung giờ của lượt đặt `PENDING`/`CONFIRMED` của người khác (trigger `trg_session_validate`). Mỗi thiết bị chỉ có tối đa một phiên đang mở (`end_datetime IS NULL`).
* **Vòng đời trạng thái đặt chỗ (`reservation_status_code`):**

  | Trạng thái | Ý nghĩa |
  |---|---|
  | `PENDING` | Mới tạo, chờ xác nhận. |
  | `CONFIRMED` | Đã xác nhận; ô đỗ có thể hiển thị `RESERVED` khi đến khung giờ. |
  | `FULFILLED` | Khách đã đến và **bắt đầu** phiên sạc (thay cho `COMPLETED` trước đây, vì trạng thái được đặt lúc bắt đầu chứ không phải lúc kết thúc). |
  | `CANCELLED` | Khách chủ động hủy. |
  | `EXPIRED` | Hệ thống hủy do quá 30 phút không kích hoạt. |
* **Tự động hủy quá hạn (Timeout):** hàm `fn_expire_overdue_reservations()` (chạy bằng `pg_cron` mỗi phút) chuyển `PENDING`/`CONFIRMED` có `start_datetime + 30 phút < now()` và chưa có phiên sạc sang `EXPIRED`, sau đó đồng bộ lại cờ `RESERVED` của ô đỗ.

---

### 2.4. Tính giá theo Công suất & Phiên sạc (Power-based Dynamic Pricing & Charging Sessions)
* **Bảng giá (`tariff_rate`):** mỗi dòng là một ô giá xác định bởi (loại cổng `connector_type_code`, khung giờ `[start_time, end_time)`, dải công suất `[min_power_kw, max_power_kw)`).
  * **Khung giờ phủ kín 24 giờ**, tối thiểu gồm: `PEAK` 17:00–20:00; `OFF_PEAK` 22:00–05:00; `STANDARD` 05:00–17:00 và 20:00–22:00. Khung vắt qua nửa đêm được lưu thành hai dòng (22:00–24:00 và 00:00–05:00).
  * **Dải công suất** so với **công suất định mức** của thiết bị (`charging_equipment.max_power_kw`).
  * Hai ô giá cùng loại cổng không được chồng cả giờ lẫn công suất (`ex_tariff_rate_no_overlap`).
  * Điều kiện: `end_time > start_time`, `max_power_kw > min_power_kw >= 0`.
* **Quy tắc chọn giá cho phiên kéo dài qua nhiều khung giờ:** áp dụng **một** ô giá duy nhất, chọn theo **giờ địa phương (Asia/Ho_Chi_Minh) tại thời điểm bắt đầu phiên** (`fn_select_tariff`). Ví dụ: phiên bắt đầu 19:50 tính giá cao điểm cho toàn bộ điện năng dù kết thúc sau 20:00. *(Phương án mở rộng nếu cần tính theo từng đoạn: thêm bảng `session_rate_segment`; nằm ngoài phạm vi hiện tại.)*
* **Quản lý phiên (`service_session`):**
  * Bắt đầu: ghi `start_datetime`; ô đỗ chuyển `OCCUPIED`, thiết bị `CHARGING`, lượt đặt (nếu có) chuyển `FULFILLED`.
  * Quản lý nhập % pin lúc cắm (`start_battery_percent`, 0 đến dưới 100, không sửa được). Điện năng ước tính = công suất trụ × thời gian × hiệu suất 90 %, tối đa phần pin còn thiếu (`fn_session_estimate`); thiếu % pin thì coi là 20 %.
  * Giám sát: `peak_charging_power_kw >= 0` (khi kết thúc ghi bằng công suất trụ).
  * Sạc đầy: `fully_charged_datetime` (tự tính) với `>= start_datetime` và `<= end_datetime`.
  * Kết thúc: ghi `end_datetime` (`>= start_datetime`), `consumed_energy_kwh` và `fully_charged_datetime` lấy từ `fn_session_estimate`; thiết bị về `READY`, ô đỗ về `AVAILABLE` (không ghi đè `FAULT`/`MAINTENANCE`/`OUTOFSERVICE`).
* **Tính phí & hóa đơn (`payment_transaction`):**
  ```text
  energy_amount_value   = consumed_energy_kwh * price_per_kwh_value
  overtime_hours        = max(0, (end_datetime - fully_charged_datetime) tính bằng giờ)   -- 0 nếu chưa ghi nhận sạc đầy
  overtime_amount_value = overtime_hours * overtime_fee_per_hour_value
  transaction_amount_value = energy_amount_value + overtime_amount_value
  ```
  * Khi `end_datetime` được ghi lần đầu, trigger `trg_session_finish` **tự tạo** đúng một giao dịch (`session_identifier` UNIQUE), trạng thái `PENDING`, lưu `rate_identifier` đã áp dụng.
  * Khách chọn phương thức (`CREDIT_CARD`, `E_WALLET`, `BANK_TRANSFER`) và cổng (MoMo, VNPay, Stripe…) sau đó; giao dịch chỉ chuyển `SUCCESS` khi đã có `payment_method_code` và `gateway_reference_identifier`.
  * Tiền tệ theo ISO 4217 (`VND`, `USD`).
  * **Bảo toàn kiểm toán:** FK tới `service_session` và `tariff_rate` là `ON DELETE RESTRICT`; trigger `trg_payment_immutable` cấm xóa giao dịch và cấm sửa số tiền, phiên, ô giá.

---

### 2.5. Quy tắc Toàn vẹn Bổ sung
* Một xe không được giữ hai lượt đặt có khung giờ chồng nhau và chỉ có một phiên sạc đang mở.
* Một lượt đặt dài tối đa 24 giờ.
* Trạng thái đặt chỗ: `PENDING` → `CONFIRMED` / `FULFILLED` / `CANCELLED` / `EXPIRED`; `CONFIRMED` → `FULFILLED` / `CANCELLED` / `EXPIRED`; ba trạng thái cuối không đổi được.
* Phiên theo lượt đặt được bắt đầu sớm tối đa 15 phút và trước khi khung giờ kết thúc.
* Khách vãng lai không được bắt đầu sạc trên ô có lượt đặt đang diễn ra hoặc bắt đầu trong 30 phút tới.
* Ô đang có phiên sạc không nhận lượt đặt bắt đầu trong 30 phút tới.
* Thiết bị chuyển `FAULT`/`MAINTENANCE` thì các lượt đặt chưa dùng trên ô đó bị hủy.
* Phiên đã kết thúc không sửa được. Hóa đơn (bắt buộc trong CSDL): khách thanh toán thì `PENDING`/`FAILED` → `PROCESSING` (chờ xác nhận); chỉ quản lý đang phụ trách bãi nơi khách sạc mới chuyển `PROCESSING` → `SUCCESS` (xác nhận) hoặc → `FAILED` (từ chối, khách trả lại được), CSDL ghi `confirmed_by_identifier` và `confirmed_datetime`; `SUCCESS` → `REFUNDED`. Không có đường tắt từ `PENDING` sang `SUCCESS`.
* Khách còn hóa đơn chưa trả hoặc đang chờ quản lý xác nhận thì không đặt chỗ mới trên web; đặt tiếp được khi mọi hóa đơn đã được xác nhận.
* Giá, công suất, dung lượng pin và điện năng không nhận giá trị `NaN`.
* Đơn giá và phí quá giờ được chốt lúc bắt đầu phiên; ADMIN đổi biểu giá không ảnh hưởng phiên đang sạc.
* Điện năng của phiên không quá 110 % dung lượng pin và không quá công suất trụ × (thời gian sạc + 5 phút).
* Lượt đặt trễ quá 30 phút không dùng, không xác nhận được và không còn giữ ô.
* Ô chỉ đỗ xe: quản lý ghi nhận khách đến, từ sớm 15 phút đến trễ 30 phút.
* Xe, ô, giờ của lượt đặt không sửa được. Phiên sạc không xóa được. Chỉ lập hóa đơn cho phiên đã kết thúc.
* Khách đã có xe, quản lý đang được phân công không đổi được vai trò. Xóa mềm tài khoản thì hủy lượt đặt sắp tới, bỏ phân công, chặn đặt và sạc; phiên đăng nhập trên web hết hiệu lực.
* Trên web: đặt trước tối đa 30 ngày, mỗi khách giữ tối đa 3 lượt, còn hóa đơn chưa trả hoặc đang chờ quản lý xác nhận thì không đặt thêm.

---

## 3. Ma trận Phân quyền Truy cập (RBAC Matrix)

| Chức năng / Thao tác trên web | CUSTOMER | MANAGER | ADMIN |
| :--- | :---: | :---: | :---: |
| Đăng nhập, đăng xuất | ✓ | ✓ | ✓ |
| Tự đăng ký tài khoản kèm xe đầu tiên | ✓ | - | - |
| Thêm xe của mình | ✓ | - | - |
| Tìm ô đỗ trống theo khung giờ | ✓ | - | - |
| Đặt chỗ, hủy lượt đặt của mình | ✓ | - | - |
| Xem phiên sạc, hóa đơn của mình và thanh toán | ✓ | - | - |
| Xem sơ đồ ô và thiết bị của bãi được phân công | - | ✓ | - |
| Đổi trạng thái thiết bị (`READY`, `FAULT`, `MAINTENANCE`) | - | ✓ | - |
| Xác nhận đặt chỗ, hủy đặt chỗ quá hạn 30 phút | - | ✓ | - |
| Ghi nhận khách đến ô chỉ đỗ xe | - | ✓ | - |
| Bắt đầu phiên sạc (chọn biển số, nhập % pin), kết thúc phiên (điện năng tự tính, hiện bảng chi tiết hóa đơn vừa lập) | - | ✓ | - |
| Xem danh sách xe đang đỗ trong bãi (tự cập nhật) | - | ✓ | - |
| Giám sát lịch đặt chỗ của bãi kèm thông tin xe, khách; thanh thời gian từng ô (xanh trống, vàng đã đặt, đỏ đang sử dụng) | - | ✓ | - |
| Xác nhận, từ chối thanh toán của khách đã sạc ở bãi mình | - | ✓ | - |
| Phân công, thu hồi quản lý bãi (`facility_manager`) | - | - | ✓ |
| Tạo tài khoản MANAGER, ADMIN | - | - | ✓ |
| Xem mật khẩu, đặt lại mật khẩu tài khoản | - | - | ✓ |
| Xóa, khôi phục (trong 30 phút) tài khoản MANAGER, CUSTOMER | - | - | ✓ |
| Sửa giá điện và phí quá giờ (`tariff_rate`) | - | - | ✓ |
| Xem doanh thu, đối soát giao dịch | - | - | ✓ |
| Đối soát lịch đặt theo thời gian thực: tổng hợp theo bãi, phát hiện chỗ lệch, thanh thời gian mọi bãi | - | - | ✓ |

Đặt chỗ quá hạn còn được hệ thống tự hủy. Thêm, sửa, xóa bãi đỗ, ô đỗ, thiết bị chưa có trên web; hiện thực hiện trực tiếp trong CSDL.

---

## 4. Các Tiêu chuẩn Kỹ thuật Tuân thủ

1. **IE Crow's Foot (ISO/IEC 19505 / Information Engineering):** ERD vẽ bằng ký hiệu chân chim (`ERD_Diagram.png`, nguồn `erd.mmd`); lược đồ đạt BCNF; quan hệ mở rộng 1:1 giữa `parking_space` và `charging_equipment`. Sơ đồ khái niệm EER (Elmasri) ở `../EER_Diagram.png`, kèm phụ lục ánh xạ `eer_mapping_appendix.md`.
2. **ISO/IEC 11179 Metadata Standards:** Quy chuẩn đặt tên trường thuộc tính nhất quán theo tiền tố và hậu tố ngữ nghĩa (`_identifier`, `_code`, `_datetime`, `_time`, `_text`, `_count`, `_kwh`, `_kw`, `_value`, `_number`).
3. **ISO 8601:** Đồng bộ thời gian hệ thống lưu trữ dưới định dạng `TIMESTAMPTZ` (UTC-aware).
4. **ISO 4217:** Mã hóa tiền tệ thanh toán tiêu chuẩn (`VND`).
5. **ISO 15118 & OCPP:** Mã định danh điểm sạc toàn cầu `evse_identifier` nhằm đồng bộ và tương thích với giao thức điều khiển trạm sạc xe điện thông minh.
6. **OpenGIS / PostGIS (EPSG:4326):** Quản lý dữ liệu không gian WGS 84 phục vụ định vị và tính toán khoảng cách địa lý chính xác.

---

## 5. Đặc tả Yêu cầu (theo ISO/IEC/IEEE 29148)

### 5.1. Yêu cầu người dùng (User Requirements)
| Mã | Vai trò | Yêu cầu |
|---|---|---|
| UR-01 | CUSTOMER | Đăng ký tài khoản kèm xe điện đầu tiên và thêm các xe khác. |
| UR-02 | CUSTOMER | Tìm bãi đỗ gần mình và xem ô đỗ/trụ sạc còn trống theo khung giờ mong muốn. |
| UR-03 | CUSTOMER | Đặt, hủy chỗ trước; được thông báo nếu bị hủy do quá 30 phút. |
| UR-04 | CUSTOMER | Theo dõi phiên sạc, xem hóa đơn và thanh toán. |
| UR-05 | MANAGER | Xem sơ đồ và trạng thái ô đỗ, thiết bị của bãi mình phụ trách; báo `FAULT`/`MAINTENANCE`; xác nhận đặt chỗ; bắt đầu phiên sạc (chọn biển số, nhập % pin) và kết thúc phiên (điện năng tự tính); xem xe đang đỗ trong bãi. |
| UR-06 | ADMIN | Phân công MANAGER, tạo tài khoản quản lý và quản trị, xem và đặt lại mật khẩu, xóa và khôi phục tài khoản quản lý, khách hàng (cảnh báo khi khách đang sạc hoặc còn nợ; xóa vĩnh viễn sau 30 phút), sửa bảng giá, đối soát doanh thu. |

### 5.2. Yêu cầu hệ thống (System Requirements)
**Chức năng (Functional) — tập trung vào dữ liệu**

| Mã | Yêu cầu | Hiện thực trong CSDL |
|---|---|---|
| FR-01 | Hệ thống phải từ chối đặt chỗ chồng thời gian trên cùng ô đỗ. | `ex_reservation_no_overlap` |
| FR-02 | Hệ thống phải tự chuyển lượt đặt sang `EXPIRED` sau 30 phút không kích hoạt và giải phóng ô đỗ. | `fn_expire_overdue_reservations()` |
| FR-03 | Hệ thống phải tính giá theo loại cổng, dải công suất và khung giờ bắt đầu phiên. | `tariff_rate`, `fn_select_tariff` |
| FR-04 | Khi phiên kết thúc, hệ thống phải tự lập đúng một hóa đơn gồm tiền điện và phí quá giờ. | `trg_session_finish` |
| FR-05 | Hệ thống phải đồng bộ trạng thái ô đỗ với trạng thái thiết bị sạc. | `trg_equipment_status_sync` |
| FR-06 | Hệ thống phải chặn thêm ô đỗ vượt sức chứa của bãi. | `trg_space_capacity` |
| FR-07 | Hệ thống phải chỉ cho phép tài khoản `MANAGER` được phân công bãi đỗ. | `trg_facility_manager_role` |
| FR-08 | Hệ thống phải lưu vết bất biến mọi giao dịch tài chính. | `trg_payment_immutable`, FK `RESTRICT` |
| FR-09 | Hệ thống phải tự tính điện năng và thời điểm đầy pin từ % pin lúc cắm, công suất trụ và thời gian sạc. | `fn_session_estimate`, `start_battery_percent` |
| FR-10 | Thanh toán của khách chỉ hoàn tất khi quản lý bãi nơi khách sạc xác nhận; khách chỉ đặt chỗ mới khi mọi hóa đơn đã được xác nhận. | `PROCESSING`, `confirmed_by_identifier`, `trg_payment_immutable` |

**Phi chức năng (Non-functional) — ràng buộc riêng cho CSDL**

| Mã | Loại | Yêu cầu |
|---|---|---|
| NFR-01 | Hiệu năng | Truy vấn "ô đỗ trống gần tôi" (GiST trên `geographic_location`) trả kết quả < 200 ms với 100.000 ô đỗ. |
| NFR-02 | Hiệu năng | Kiểm tra chồng lịch đặt chỗ < 50 ms nhờ chỉ mục GiST của `EXCLUDE`. |
| NFR-03 | Toàn vẹn | Không có hai phiên đang mở trên cùng thiết bị; không có hai lượt đặt giữ chỗ chồng giờ. |
| NFR-04 | Bảo mật | Mật khẩu lưu dạng băm (*theo yêu cầu đồ án, bản gốc cũng được lưu để ADMIN xem; không phù hợp cho hệ thống thật*); kết nối CSDL qua TLS; mã hóa đĩa (encryption at rest) cho dữ liệu cá nhân và giao dịch; phân quyền theo vai trò PostgreSQL (`customer_role`, `manager_role`, `admin_role`). *Hiện thực: web dùng được role quyền tối thiểu `evc_app` (`roles.sql`); phân quyền CUSTOMER / MANAGER / ADMIN nằm ở tầng ứng dụng; chưa có ba role PostgreSQL riêng, TLS và mã hóa đĩa.* |
| NFR-05 | Sẵn sàng | Sao lưu hằng ngày + WAL archiving, RPO ≤ 15 phút. |
| NFR-06 | Kiểm toán | Dữ liệu tài chính không xóa vật lý; dữ liệu người dùng/phương tiện dùng xóa mềm; thông tin cá nhân của tài khoản đã xóa quá 30 phút được xóa vĩnh viễn, riêng bản ghi trên hóa đơn được giữ. |
| NFR-07 | Thời gian | Lưu `TIMESTAMPTZ` (UTC); hiển thị theo `Asia/Ho_Chi_Minh`. |

*(NFR-01, 02, 05 là mục tiêu thiết kế, sẽ được đo ở Phase 3.)*

### 5.3. Ánh xạ chuyên biệt hóa người dùng
ERD thể hiện `USER_ACCOUNT` là **một** thực thể với thuộc tính phân loại `role_code` (`CUSTOMER`, `MANAGER`, `ADMIN`); không tách bảng con cho từng vai trò, vì các vai trò không có thuộc tính riêng. Việc ADMIN phân công MANAGER được kiểm soát ở tầng ứng dụng; CSDL không lưu người phân công.

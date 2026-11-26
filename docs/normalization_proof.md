# TÀI LIỆU CHỨNG MINH DẠNG CHUẨN (NORMALIZATION PROOFS)

## Thông tin dự án
* **Tên dự án:** Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện (EV) thông minh)
* **ID Dự Án:** #1: Smart City EV Charging & Parking Management
* **Tên nhóm:** M3B
* **Thành viên nhóm:**
  * Nguyễn Trường Nghị - `n24dccn142@student.ptithcm.edu.vn`
  * Phạm Công Đang - `n24dccn102@student.ptithcm.edu.vn`
  * Mai Văn Công - `n24dccn100@student.ptithcm.edu.vn`

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
   * Các thuộc tính phi khóa (`start_datetime`, `end_datetime`, `fully_charged_datetime`, `peak_charging_power_kw`, `consumed_energy_kwh`, `applied_price_per_kwh_value`, `applied_overtime_fee_per_hour_value`, `start_battery_percent`) phụ thuộc trực tiếp và duy nhất vào khóa chính `session_identifier`. Không tồn tại phụ thuộc Y -> Z giữa các thuộc tính phi khóa.
   * Hai cột `applied_*` là giá **tại thời điểm bắt đầu phiên**. Chúng không xác định được từ thuộc tính nào khác trong bảng, và không suy lại được từ `tariff_rate` sau khi ADMIN đổi giá, nên không phải dữ liệu trùng lặp.

**Kết luận:** Toàn bộ hệ thống đạt chuẩn **3NF**.

---

### 2.4. Bước 4: Chứng minh Dạng chuẩn Boyce-Codd (BCNF - Boyce-Codd Normal Form)

**Định nghĩa BCNF:** Một quan hệ đạt Dạng chuẩn Boyce-Codd (BCNF) khi và chỉ khi đối với mọi Phụ thuộc hàm (Functional Dependency - FD) không tầm thường (non-trivial) có dạng X -> Y tồn tại trong quan hệ, vế trái X bắt buộc phải là một **Siêu khóa (Superkey)** hoặc **Khóa ứng viên (Candidate Key)**.

#### Phân tích Chi tiết Tập Phụ thuộc Hàm (FD Sets) trên từng Quan hệ

Quy ước: chỉ liệt kê FD không tầm thường; "→ R" nghĩa là xác định toàn bộ thuộc tính còn lại. Khóa ứng viên của các bảng có xóa mềm là **khóa từng phần** (partial unique index, chỉ xét các dòng `deleted_datetime IS NULL`); FD dưới đây được hiểu trên tập các dòng đang hoạt động.

| # | Quan hệ | Khóa ứng viên | FD không tầm thường | Kết luận |
|---|---|---|---|---|
| 1 | `user_account` | {account_identifier}, {contact_phone_number}, {lower(email_address)} | mỗi khóa → R | BCNF |
| 2 | `vehicle` | {vehicle_identifier}, {license_plate_text} | mỗi khóa → R | BCNF |
| 3 | `parking_facility` | {facility_identifier} | facility_identifier → R | BCNF |
| 4 | `facility_manager` | {manager_identifier, facility_identifier} | không có (toàn bộ thuộc tính thuộc khóa) | BCNF |
| 5 | `parking_space` | {space_identifier}, {facility_identifier, space_code} | mỗi khóa → R | BCNF |
| 6 | `charging_equipment` | {equipment_identifier}, {space_identifier}, {evse_identifier} | mỗi khóa → R | BCNF |
| 7 | `tariff_rate` | {rate_identifier}, **{connector_type_code, time_band_code, start_time, min_power_kw}** | mỗi khóa → R | BCNF |
| 8 | `reservation` | {reservation_identifier} | reservation_identifier → R | BCNF |
| 9 | `service_session` | {session_identifier}, {reservation_identifier} (khi khác NULL) | mỗi khóa → R | BCNF |
| 10 | `payment_transaction` | {transaction_identifier}, {session_identifier} | mỗi khóa → R | BCNF |

**Điểm khác so với thiết kế trước (các FD ngầm đã được loại bỏ):**

1. **`service_session` không còn `account_identifier`.** Trước đây, khi `reservation_identifier` khác NULL thì `reservation_identifier → account_identifier` đã tồn tại trong cùng bảng (vế trái không phải khóa) ⇒ vi phạm 3NF/BCNF. Hiện nay tài khoản được suy ra qua `vehicle_identifier → account_identifier` (xem bảng `vehicle`), nên `service_session` chỉ còn các FD từ khóa. Lập luận tương tự cho `reservation`.
2. **`service_session.reservation_identifier` là UNIQUE**, nên FD `reservation_identifier → R` (khi khác NULL) là FD từ khóa ứng viên, phù hợp quan hệ 0..1 – 1 trên ERD.
3. **`tariff_rate` có khóa ứng viên nghiệp vụ** (loại cổng, nhãn khung giờ, giờ bắt đầu, công suất tối thiểu) và ràng buộc `EXCLUDE` chống chồng ô giá. Nhờ đó với mỗi (loại cổng, giờ, công suất) có **đúng một** ô giá.
4. **`payment_transaction`:** `rate_identifier` không bị xác định bởi một thuộc tính phi khóa nào trong bảng; việc nó "suy ra được" từ giờ bắt đầu phiên và thiết bị là quy tắc nghiệp vụ tại thời điểm xuất hóa đơn. Lưu lại `rate_identifier` và các số tiền thành phần là **snapshot có chủ đích** để hóa đơn bất biến khi bảng giá thay đổi (xem trigger `trg_payment_immutable`). Ràng buộc `transaction_amount_value = energy_amount_value + overtime_amount_value` là CHECK trong dòng, không tạo phụ thuộc bắc cầu giữa các bảng. Các cột `customer_name_text`, `customer_phone_number`, `customer_email_address`, `license_plate_text` cũng là snapshot: chúng ghi thông tin **tại thời điểm lập hóa đơn**, có thể khác thông tin hiện tại hoặc còn lại sau khi tài khoản bị xóa, nên không suy được từ bảng khác. Trong bảng, giữa chúng không có FD nào được đảm bảo (một email hay biển số có thể được người khác dùng lại ở thời điểm khác), nên bảng vẫn đạt BCNF.

---

## 3. Dư thừa có kiểm soát (không thuộc phạm vi FD trong một quan hệ)

BCNF chỉ xét FD **bên trong** từng quan hệ. Các thông tin dưới đây phụ thuộc vào dữ liệu ở bảng khác nên được liệt kê riêng cùng cơ chế giữ nhất quán:

| Thông tin | Phụ thuộc vào | Cơ chế |
|---|---|---|
| `parking_space.availability_status_code` | `reservation`, `service_session`, `charging_equipment.equipment_status_code` | Triggers đồng bộ; khả dụng theo **khung giờ** tính bằng `fn_is_space_available` thay vì cột trạng thái. |
| `parking_facility.total_capacity_count` | Là sức chứa thiết kế, **không** suy ra từ số dòng `parking_space` | Trigger `trg_space_capacity` chặn vượt sức chứa. |
| `service_session.applied_*` | `tariff_rate` tại thời điểm bắt đầu phiên | Trigger tự ghi, `trg_session_fixed` không cho sửa. |
| `payment_transaction` (số tiền, `rate_identifier`) | `service_session`, `tariff_rate` tại thời điểm xuất hóa đơn | Snapshot bất biến + CHECK tổng. |
| `payment_transaction` (`customer_name_text`, `customer_phone_number`, `customer_email_address`, `license_plate_text`) | `user_account`, `vehicle` tại thời điểm xuất hóa đơn | `trg_payment_snapshot` chụp lại, `trg_payment_immutable` không cho sửa; giữ thông tin khi tài khoản bị xóa vĩnh viễn. |
| `service_session` (`consumed_energy_kwh`, `fully_charged_datetime`) | `start_battery_percent`, công suất trụ, dung lượng pin, thời gian | Ghi một lần khi kết thúc phiên từ `fn_session_estimate`; sau đó hóa đơn dùng số đã ghi. |
| `user_account.password_plain_text` | Cùng mật khẩu với `password_hash_text` | Ghi cùng lúc ở mọi đường tạo/đổi mật khẩu; đăng nhập chỉ kiểm bản băm; bị xóa khi xóa vĩnh viễn (yêu cầu của đồ án). |

## 4. Giới hạn của chuẩn hóa và cơ chế toàn vẹn mở rộng

| Vấn đề không giải quyết được bằng chuẩn hóa | Cơ chế trong `schema.sql` |
|---|---|
| Hai lượt đặt chồng giờ trên cùng ô đỗ | `ex_reservation_no_overlap` (GiST, `tstzrange`, chỉ tính trạng thái đang giữ chỗ) |
| Khách vãng lai chen vào khung giờ đã đặt | `trg_session_validate`; `ux_service_session_open_equipment` |
| Hai ô giá chồng nhau | `ex_tariff_rate_no_overlap` |
| Chỉ `MANAGER` mới được phân công bãi | `trg_facility_manager_role` |
| Số ô đỗ vượt sức chứa | `trg_space_capacity` |
| Tự hủy sau 30 phút | `fn_expire_overdue_reservations()` (gọi bằng pg_cron mỗi phút) |
| Xóa mềm làm kẹt khóa UNIQUE | Partial unique index `WHERE deleted_datetime IS NULL` |
| Hóa đơn không được sửa/xóa | `trg_payment_immutable` + FK `ON DELETE RESTRICT` |

## 5. Tổng Kết Kết Quả Chuẩn Hóa

Sau khi loại các phụ thuộc ngầm nêu ở mục 2.4, mọi FD không tầm thường trong 10 quan hệ đều có vế trái là siêu khóa ⇒ lược đồ đạt **BCNF**. Các thông tin phụ thuộc chéo bảng được liệt kê và kiểm soát ở mục 3; các quy tắc mà chuẩn hóa không biểu diễn được (chống chồng lịch, đồng bộ trạng thái, bất biến hóa đơn) được hiện thực bằng ràng buộc và trigger ở mục 4, đã kiểm thử bằng `tests.sql`.

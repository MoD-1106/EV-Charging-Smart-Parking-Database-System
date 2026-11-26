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

Tài liệu này trình bày chi tiết chứng minh quá trình chuẩn hóa từng bước từ **Mô hình Phi chuẩn hóa (Unnormalized Form - UNF)** đến **Dạng chuẩn Boyce-Codd (BCNF)** cho toàn bộ 14 thực thể/bảng thuộc hệ thống **Smart City EV Charging & Parking Management**.

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

**Kết luận:** Toàn bộ 14 bảng trong hệ thống đạt chuẩn **1NF**.

---

### 2.2. Bước 2: Chứng minh Dạng chuẩn 2 (2NF - Second Normal Form)

**Định nghĩa 2NF:** Một quan hệ ở Dạng chuẩn 2 (2NF) khi nó đã đạt 1NF và mọi thuộc tính **không khóa** (không thuộc khóa ứng viên nào) phụ thuộc hàm đầy đủ vào **mọi khóa ứng viên**, tức là không phụ thuộc vào một tập con thực sự của bất kỳ khóa ứng viên nào. 2NF xét mọi khóa ứng viên, không chỉ khóa chính: một bảng có khóa chính UUID vẫn có thể vi phạm 2NF nếu nó còn một khóa ứng viên nghiệp vụ nhiều thuộc tính.

#### Phân tích Phụ thuộc Hàm dựa trên Các Khóa ứng viên:
1. **Bảng mà mọi khóa ứng viên chỉ có một thuộc tính:**
   * `user_account`, `vehicle`, `parking_facility`, `parking_space`, `charging_equipment`, `reservation`, `service_session`, `payment_transaction` (khóa UUID; các khóa ứng viên khác như `service_session.reservation_identifier`, `payment_transaction.session_identifier` cũng chỉ một thuộc tính), `time_band` (khóa `time_band_code`) và `time_band_window` (khóa `start_time`).
   * Khóa ứng viên một thuộc tính không có tập con thực sự khác rỗng, nên **không thể** có phụ thuộc bộ phận vào nó. Các bảng này đạt 2NF.
   * Lưu ý: kết luận này chỉ đúng sau khi đã kiểm tra rằng bảng **không còn** khóa ứng viên nhiều thuộc tính nào. Mục 3 và 4 dưới đây là hai trường hợp bảng có khóa chính UUID nhưng khóa ứng viên nghiệp vụ nhiều thuộc tính từng gây vi phạm 2NF.
2. **Bảng có khóa nhiều thuộc tính và không có thuộc tính không khóa (`facility_manager`):**
   * Khóa chính phức hợp: PK = (manager_identifier, facility_identifier).
   * Bảng này chỉ đóng vai trò là bảng trung gian giải quyết quan hệ Nhiều - Nhiều (N:M), hoàn toàn không chứa thuộc tính phi khóa nào khác ngoài các thuộc tính tham gia cấu thành khóa chính.
   * Do không có thuộc tính phi khóa, không tồn tại phụ thuộc hàm dạng A -> B với A thuộc tập con thực sự của PK và B không thuộc PK.
3. **Khóa ứng viên nhiều thuộc tính của `tariff_rate` và việc tách lịch khung giờ:**
   * 2NF phải xét **mọi** khóa ứng viên, không chỉ khóa chính UUID. Ở thiết kế trước, mỗi dòng `tariff_rate` lưu cả khung giờ: (`rate_identifier`, `connector_type_code`, `time_band_code`, `start_time`, `end_time`, `min_power_kw`, `max_power_kw`, `price_per_kwh_value`, `overtime_fee_per_hour_value`), với khóa ứng viên nghiệp vụ {`connector_type_code`, `start_time`, `min_power_kw`}.
   * Lịch khung giờ là chung cho cả hệ thống, nên có FD `start_time → time_band_code, end_time`. Vế trái chỉ là **một phần** của khóa ứng viên ⇒ phụ thuộc bộ phận, vi phạm 2NF (và BCNF). Hệ quả thấy được trên dữ liệu mẫu: 5 khoảng giờ bị lặp lại cho 3 nhóm trụ (15 dòng); muốn dời giờ cao điểm phải sửa nhiều dòng, sửa thiếu một dòng thì hai loại trụ có hai lịch cao điểm khác nhau (bất thường cập nhật).
   * *Giải pháp:* tách thành ba quan hệ
     * `time_band` (**time_band_code**, time_band_name)
     * `time_band_window` (**start_time**, end_time, *time_band_code*)
     * `tariff_rate` (**rate_identifier**, connector_type_code, *time_band_code*, min_power_kw, max_power_kw, price_per_kwh_value, overtime_fee_per_hour_value), khóa ứng viên {connector_type_code, time_band_code, min_power_kw} (dạng trung gian, tiếp tục tách ở mục 4).
   * *Phép tách không mất thông tin:* thuộc tính chung `time_band_code` là khóa của `time_band`; ghép `time_band_window` với `tariff_rate` theo `time_band_code` cho lại đúng các ô giá theo (loại cổng, khoảng giờ, công suất) như trước. *Bảo toàn phụ thuộc:* FD `start_time → time_band_code, end_time` nằm trọn trong `time_band_window`; FD từ khóa của bảng giá nằm trọn trong `tariff_rate`. Dữ liệu mẫu còn 5 dòng lịch và 9 ô giá, số tiền mọi hóa đơn không đổi.
4. **Tách dải công suất khỏi bảng giá (`power_tier`):**
   * Sau khi tách lịch khung giờ, `tariff_rate` còn (`connector_type_code`, `min_power_kw`, `max_power_kw`, `time_band_code`, ...) với khóa ứng viên nghiệp vụ {`connector_type_code`, `min_power_kw`, `time_band_code`}. Các dải công suất là chung cho mọi khung giá, nên có FD `(connector_type_code, min_power_kw) → max_power_kw`, vế trái là một phần khóa ⇒ lại là phụ thuộc bộ phận. Dữ liệu mẫu cho thấy mỗi dải lặp lại cho cả 3 khung.
   * *Giải pháp:* tách `power_tier` (**connector_type_code**, **min_power_kw**, max_power_kw); `tariff_rate` giữ khóa ngoại ghép (`connector_type_code`, `min_power_kw`) tới `power_tier` và không còn `max_power_kw`. Phép tách không mất thông tin vì thuộc tính chung là khóa của `power_tier`; FD về dải công suất nằm trọn trong `power_tier`.
5. **Lịch sử giá (`effective_from`, `effective_to`):**
   * Mỗi dòng `tariff_rate` là một **phiên bản giá**; khóa ứng viên nghiệp vụ mở rộng thành {`connector_type_code`, `min_power_kw`, `time_band_code`, `effective_from`}. Giá, phí quá giờ và `effective_to` phụ thuộc vào **toàn bộ** khóa này (cùng ô giá, khác thời điểm thì khác giá), không vào tập con nào ⇒ đạt 2NF. Tương tự `parking_rate` với khóa {`time_band_code`, `effective_from`}.
   * `overtime_fee_per_hour_value` **được giữ trong `tariff_rate`** theo quyết định nghiệp vụ: phí quá giờ có thể khác nhau theo loại trụ và dải công suất, nên nó phụ thuộc vào cả khóa {loại cổng, dải công suất, khung, thời điểm hiệu lực}, không chỉ vào khung. Trong dữ liệu mẫu, các loại trụ có cùng phí quá giờ trong cùng khung; đó là trùng hợp của dữ liệu, không phải FD `time_band_code → overtime_fee_per_hour_value` của nghiệp vụ.

**Kết luận:** Toàn bộ các quan hệ trong hệ thống đạt chuẩn **2NF**.

---

### 2.3. Bước 3: Chứng minh Dạng chuẩn 3 (3NF - Third Normal Form)

**Định nghĩa 3NF:** Một quan hệ đạt Dạng chuẩn 3 (3NF) khi nó đã đạt 2NF và không chứa bất kỳ thuộc tính không khóa nào phụ thuộc bắc cầu (Transitive Dependency) vào khóa chính. Tức là không tồn tại chuỗi phụ thuộc X -> Y -> Z, trong đó X là khóa chính, Y và Z là các thuộc tính phi khóa.

#### Phân tích & Triệt tiêu Phụ thuộc Bắc cầu trên các Thực thể:
1. **Tách Thực thể `parking_space` & `charging_equipment` (1:1 Extension):**
   * *Rủi ro phi chuẩn hóa nếu gộp:* Nếu đưa toàn bộ thông tin bộ sạc vào chung bảng vị trí đỗ `parking_space`, sẽ phát sinh phụ thuộc bắc cầu:
     `space_identifier -> equipment_identifier -> connector_type_code`
   * *Giải pháp 3NF:* Tách thành 2 bảng riêng biệt `parking_space` và `charging_equipment`, liên kết mở rộng 1:1 qua khóa ngoại `space_identifier` (FK, UK).
2. **Tách Thực thể `service_session` & `tariff_rate` (Dynamic Pricing):**
   * *Rủi ro phi chuẩn hóa nếu gộp:* Nếu lưu cả mã phiên bản giá lẫn đơn giá trong phiên sạc, sẽ phát sinh phụ thuộc bắc cầu:
     `session_identifier -> rate_identifier -> price_per_kwh_value`
   * *Giải pháp 3NF:* Phiên chỉ lưu khóa ngoại `rate_identifier` (hoặc `parking_rate_identifier` cho phiên chỉ đỗ) trỏ tới **phiên bản giá** đã áp dụng. Vì phiên bản giá không bao giờ bị sửa (đổi giá = thêm phiên bản mới), đơn giá của phiên cũ luôn tra lại được mà không cần lưu bản sao trong phiên. Thiết kế trước lưu `applied_price_per_kwh_value`, `applied_overtime_fee_per_hour_value` trong phiên vì bảng giá bị sửa đè; hai cột này đã được bỏ. Hóa đơn cũng không còn `rate_identifier` riêng (suy ra qua phiên), tránh lưu một sự kiện ở hai bảng.
3. **Thực thể `service_session`:**
   * Các thuộc tính phi khóa (`start_datetime`, `end_datetime`, `fully_charged_datetime`, `peak_charging_power_kw`, `consumed_energy_kwh`, `start_battery_percent`, các khóa ngoại tới trụ, ô, phiên bản giá) phụ thuộc trực tiếp vào khóa `session_identifier`. Không tồn tại phụ thuộc Y -> Z giữa các thuộc tính phi khóa.
   * Phiên sạc và phiên chỉ đỗ xe dùng ràng buộc loại trừ: phiên sạc có `equipment_identifier`, phiên chỉ đỗ có `space_identifier`, không bao giờ cả hai (`ck_service_session_kind`). Nếu phiên sạc lưu thêm ô đỗ thì có `equipment_identifier → space_identifier` trong cùng bảng (bắc cầu); ô của phiên sạc vì vậy được suy ra qua `charging_equipment`.

**Kết luận:** Toàn bộ hệ thống đạt chuẩn **3NF**.

---

### 2.4. Bước 4: Chứng minh Dạng chuẩn Boyce-Codd (BCNF - Boyce-Codd Normal Form)

**Định nghĩa BCNF:** Một quan hệ đạt Dạng chuẩn Boyce-Codd (BCNF) khi và chỉ khi đối với mọi Phụ thuộc hàm (Functional Dependency - FD) không tầm thường (non-trivial) có dạng X -> Y tồn tại trong quan hệ, vế trái X bắt buộc phải là một **Siêu khóa (Superkey)** hoặc **Khóa ứng viên (Candidate Key)**.

#### Phân tích Chi tiết Tập Phụ thuộc Hàm (FD Sets) trên từng Quan hệ

Quy ước: chỉ liệt kê FD không tầm thường; "→ R" nghĩa là xác định toàn bộ thuộc tính còn lại.

**Khóa ứng viên và xóa mềm.** Số điện thoại, email, biển số, `evse_identifier`, (`facility_identifier`, `space_code`) và `charging_equipment.space_identifier` chỉ duy nhất **trong các dòng chưa xóa** (partial unique index `WHERE deleted_datetime IS NULL`). Một dòng đã xóa mềm có thể trùng giá trị với một dòng đang hoạt động, nên trên **toàn bộ** quan hệ các cột này không phải khóa ứng viên và không có FD từ chúng. Khóa ứng viên của các bảng này chỉ là mã định danh; các ràng buộc duy nhất từng phần là quy tắc nghiệp vụ, được liệt kê ở mục 4. Vì vế trái của mọi FD vẫn là mã định danh, kết luận BCNF không đổi.

| # | Quan hệ | Khóa ứng viên | FD không tầm thường | Kết luận |
|---|---|---|---|---|
| 1 | `user_account` | {account_identifier} | account_identifier → R | BCNF |
| 2 | `vehicle` | {vehicle_identifier} | vehicle_identifier → R | BCNF |
| 3 | `parking_facility` | {facility_identifier} | facility_identifier → R | BCNF |
| 4 | `facility_manager` | {manager_identifier, facility_identifier} | không có (toàn bộ thuộc tính thuộc khóa) | BCNF |
| 5 | `parking_space` | {space_identifier} | space_identifier → R | BCNF |
| 6 | `charging_equipment` | {equipment_identifier} | equipment_identifier → R | BCNF |
| 7 | `time_band` | {time_band_code} | time_band_code → time_band_name | BCNF |
| 8 | `time_band_window` | {start_time} | start_time → end_time, time_band_code | BCNF |
| 9 | `power_tier` | {connector_type_code, min_power_kw} | khóa → max_power_kw | BCNF |
| 10 | `tariff_rate` | {rate_identifier}, **{connector_type_code, min_power_kw, time_band_code, effective_from}** | mỗi khóa → R | BCNF |
| 11 | `parking_rate` | {parking_rate_identifier}, {time_band_code, effective_from} | mỗi khóa → R | BCNF |
| 12 | `reservation` | {reservation_identifier} | reservation_identifier → R | BCNF |
| 13 | `service_session` | {session_identifier}, {reservation_identifier} (khi khác NULL) | mỗi khóa → R | BCNF |
| 14 | `payment_transaction` | {transaction_identifier}, {session_identifier} | mỗi khóa → R | BCNF |

**Điểm khác so với thiết kế trước (các FD ngầm đã được loại bỏ):**

1. **`service_session` không còn `account_identifier`.** Trước đây, khi `reservation_identifier` khác NULL thì `reservation_identifier → account_identifier` đã tồn tại trong cùng bảng (vế trái không phải khóa) ⇒ vi phạm 3NF/BCNF. Hiện nay tài khoản được suy ra qua `vehicle_identifier → account_identifier` (xem bảng `vehicle`), nên `service_session` chỉ còn các FD từ khóa. Lập luận tương tự cho `reservation`.
2. **`service_session.reservation_identifier` là UNIQUE**, nên FD `reservation_identifier → R` (khi khác NULL) là FD từ khóa ứng viên, phù hợp quan hệ 0..1 – 1 trên ERD.
3. **Lịch khung giờ và dải công suất tách khỏi bảng giá** (xem 2.2, mục 3 và 4). `tariff_rate` không còn `start_time`, `end_time`, `max_power_kw`, nên không còn FD có vế trái là một phần khóa. Khóa ứng viên nghiệp vụ (`uq_tariff_rate_key`) cùng ràng buộc `EXCLUDE` chống chồng thời gian hiệu lực bảo đảm mỗi (dải công suất, khung) có **đúng một** phiên bản giá tại mỗi thời điểm; `ex_time_band_window_no_overlap` và `trg_time_band_window_coverage` bảo đảm mỗi giờ trong ngày thuộc đúng một khung; `ex_power_tier_no_overlap` bảo đảm mỗi công suất thuộc tối đa một dải.
4. **`payment_transaction`:** không còn `rate_identifier` (phiên bản giá truy qua phiên). Các số tiền thành phần được lưu để hóa đơn bất biến (xem trigger `trg_payment_immutable`). `transaction_amount_value` là **thuộc tính dẫn xuất được lưu có chủ đích**: trong bảng có FD `{energy_amount_value, overtime_amount_value, parking_amount_value} → transaction_amount_value` với vế trái không phải khóa, nên xét chặt thì đây là một phụ thuộc bắc cầu qua các cột tiền thành phần. Nhóm giữ cột tổng vì hóa đơn bất biến và được truy vấn thường xuyên; dư thừa này không gây bất thường cập nhật vì `ck_payment_amounts` buộc tổng bằng ba khoản thành phần và `trg_payment_immutable` cấm sửa số tiền. Nếu bỏ cột tổng (tính khi truy vấn), bảng đạt BCNF theo nghĩa chặt. Các cột `customer_name_text`, `customer_phone_number`, `customer_email_address`, `license_plate_text` cũng là snapshot: chúng ghi thông tin **tại thời điểm lập hóa đơn**, có thể khác thông tin hiện tại hoặc còn lại sau khi tài khoản bị xóa, nên không suy được từ bảng khác. Trong bảng, giữa chúng không có FD nào được đảm bảo (một email hay biển số có thể được người khác dùng lại ở thời điểm khác), nên bảng vẫn đạt BCNF.

---

## 3. Dư thừa có kiểm soát (không thuộc phạm vi FD trong một quan hệ)

BCNF chỉ xét FD **bên trong** từng quan hệ. Các thông tin dưới đây phụ thuộc vào dữ liệu ở bảng khác nên được liệt kê riêng cùng cơ chế giữ nhất quán:

| Thông tin | Phụ thuộc vào | Cơ chế |
|---|---|---|
| `parking_space.availability_status_code` | `reservation`, `service_session`, `charging_equipment.equipment_status_code` | Triggers đồng bộ; khả dụng theo **khung giờ** tính bằng `fn_is_space_available` thay vì cột trạng thái. |
| `parking_facility.total_capacity_count` | Là sức chứa thiết kế, **không** suy ra từ số dòng `parking_space` | Trigger `trg_space_capacity` chặn vượt sức chứa. |
| `payment_transaction` (các số tiền) | `service_session` và phiên bản giá của phiên tại thời điểm xuất hóa đơn | Tính một lần trong `trg_session_finish`; `trg_payment_immutable` không cho sửa. |
| `payment_transaction.transaction_amount_value` | `energy_amount_value + overtime_amount_value + parking_amount_value` trong cùng dòng (thuộc tính dẫn xuất được lưu) | `ck_payment_amounts`; `trg_payment_immutable`. |
| `payment_transaction` (`customer_name_text`, `customer_phone_number`, `customer_email_address`, `license_plate_text`) | `user_account`, `vehicle` tại thời điểm xuất hóa đơn | `trg_payment_snapshot` chụp lại, `trg_payment_immutable` không cho sửa; giữ thông tin khi tài khoản bị xóa vĩnh viễn. |
| `service_session` (`consumed_energy_kwh`, `fully_charged_datetime`) | `start_battery_percent`, công suất trụ, dung lượng pin, thời gian | Ghi một lần khi kết thúc phiên từ `fn_session_estimate`; sau đó hóa đơn dùng số đã ghi. |
| `user_account.password_plain_text` | Cùng mật khẩu với `password_hash_text` | Nhóm chọn lưu để ADMIN xem mật khẩu khi demo (không phải yêu cầu của đề, không dùng cho hệ thống thật). Ghi cùng lúc ở mọi đường tạo/đổi mật khẩu; đăng nhập chỉ kiểm bản băm; bị xóa khi xóa vĩnh viễn. |

## 4. Giới hạn của chuẩn hóa và cơ chế toàn vẹn mở rộng

| Vấn đề không giải quyết được bằng chuẩn hóa | Cơ chế trong `schema.sql` |
|---|---|
| Hai lượt đặt chồng giờ trên cùng ô đỗ | `ex_reservation_no_overlap` (GiST, `tstzrange`, chỉ tính trạng thái đang giữ chỗ) |
| Khách vãng lai chen vào khung giờ đã đặt | `trg_session_validate`; `ux_service_session_open_equipment` |
| Hai khoảng giờ của lịch khung giờ chồng nhau | `ex_time_band_window_no_overlap` |
| Lịch khung giờ có khe hở (giờ không thuộc khung nào) | `trg_time_band_window_coverage` (kiểm tra cuối giao dịch) |
| Hai dải công suất của một loại cổng chồng nhau | `ex_power_tier_no_overlap` |
| Hai phiên bản giá của một ô giá chồng thời gian hiệu lực; phiên bản bị sửa đè | `ex_tariff_rate_no_overlap`, `ex_parking_rate_no_overlap`; `trg_tariff_rate_fixed`, `trg_parking_rate_fixed` |
| Phiên vừa dùng trụ vừa dùng ô chỉ đỗ | `ck_service_session_kind` |
| Số điện thoại, email, biển số, `evse_identifier`, mã ô trong bãi duy nhất giữa các dòng chưa xóa | Partial unique index `WHERE deleted_datetime IS NULL` |
| Chỉ `MANAGER` mới được phân công bãi | `trg_facility_manager_role` |
| Số ô đỗ vượt sức chứa | `trg_space_capacity` |
| Tự hủy sau 30 phút | `fn_expire_overdue_reservations()` (gọi bằng pg_cron mỗi phút) |
| Xóa mềm làm kẹt khóa UNIQUE | Partial unique index `WHERE deleted_datetime IS NULL` |
| Hóa đơn không được sửa/xóa | `trg_payment_immutable` + FK `ON DELETE RESTRICT` |

## 5. Tổng Kết Kết Quả Chuẩn Hóa

Sau khi loại các phụ thuộc ngầm nêu ở mục 2.4, tách lịch khung giờ và dải công suất khỏi bảng giá, và thay bản sao đơn giá trong phiên bằng phiên bản giá bất biến, mọi FD không tầm thường trong 14 quan hệ đều có vế trái là siêu khóa ⇒ lược đồ đạt **BCNF**; ngoại lệ có chủ đích duy nhất là cột tổng tiền dẫn xuất của hóa đơn, được kiểm soát bằng CHECK và trigger (mục 2.4 và 3). Các thông tin phụ thuộc chéo bảng được liệt kê và kiểm soát ở mục 3; các quy tắc mà chuẩn hóa không biểu diễn được (chống chồng lịch, đồng bộ trạng thái, bất biến hóa đơn) được hiện thực bằng ràng buộc và trigger ở mục 4, đã kiểm thử bằng `tests.sql`.

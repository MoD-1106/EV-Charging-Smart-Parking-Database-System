# ÁNH XẠ LƯỢC ĐỒ QUAN HỆ (RELATIONAL SCHEMA MAPPING)

## Thông tin dự án
* **Dự án:** #1 Smart City EV Charging & Parking Management (Hệ thống Quản lý Bãi đỗ xe và Sạc xe điện thông minh)
* **Nhóm:** M3B — Môn INT1313 Databases
* **Thành viên:**
  * Nguyễn Trường Nghị - `n24dccn142@student.ptithcm.edu.vn`
  * Phạm Công Đang - `n24dccn102@student.ptithcm.edu.vn`
  * Mai Văn Công - `n24dccn100@student.ptithcm.edu.vn`
* **Đầu vào:** `ERD_Diagram.png` / `erd.mmd` (IE Crow's Foot) và `business_rule.md`
* **Đầu ra:** 10 quan hệ trong `schema.sql`, mô tả chi tiết cột ở `data_dictionary.md`

---

## 1. Cơ sở và quy ước

| Nội dung | Quy ước |
|---|---|
| Hệ quản trị | PostgreSQL 14+ (PostGIS, `btree_gist`) |
| Khóa chính | Khóa thay thế `UUID DEFAULT gen_random_uuid()` cho mọi bảng, trừ bảng trung gian `facility_manager` (khóa ghép). |
| Đặt tên | `lowercase snake_case`; hậu tố theo ISO/IEC 11179: `_identifier`, `_code`, `_text`, `_count`, `_datetime`, `_time`, `_kw`, `_kwh`, `_value`, `_number`. |
| Thời gian | `TIMESTAMPTZ` (ISO 8601); giờ trong ngày dùng `TIME`. |
| Vị trí | `GEOMETRY(Point, 4326)` (WGS 84). |
| Tiền tệ | `DECIMAL` kèm `currency_code` (ISO 4217). |
| Xóa mềm | Cột `deleted_datetime` ở các bảng danh mục (`user_account`, `vehicle`, `parking_space`, `charging_equipment`, `reservation`); ràng buộc duy nhất là **chỉ mục duy nhất từng phần** `WHERE deleted_datetime IS NULL`. |

**Ký hiệu trong tài liệu:** **tên_cột** = khóa chính (PK); *tên_cột* = khóa ngoại (FK); `[UQ]` = ràng buộc duy nhất; `[NN]` = `NOT NULL`.

---

## 2. Các bước ánh xạ từ ERD sang quan hệ

### Bước 1. Thực thể mạnh (Strong Entity Types)
Mỗi thực thể có định danh riêng được ánh xạ thành một quan hệ; thuộc tính đơn trị trở thành cột; định danh trở thành khóa chính `UUID`.

| Thực thể ERD | Quan hệ | Khóa chính | Khóa ứng viên khác |
|---|---|---|---|
| USER_ACCOUNT | `user_account` | `account_identifier` | `contact_phone_number`, `lower(email_address)` |
| VEHICLE | `vehicle` | `vehicle_identifier` | `license_plate_text` |
| PARKING_FACILITY | `parking_facility` | `facility_identifier` | — |
| PARKING_SPACE | `parking_space` | `space_identifier` | (`facility_identifier`, `space_code`) |
| CHARGING_EQUIPMENT | `charging_equipment` | `equipment_identifier` | `space_identifier`, `evse_identifier` |
| TARIFF_RATE | `tariff_rate` | `rate_identifier` | — (không chồng lấn được bảo đảm bởi `EXCLUDE`, xem mục 5) |
| RESERVATION | `reservation` | `reservation_identifier` | — |
| SERVICE_SESSION | `service_session` | `session_identifier` | `reservation_identifier` (khi khác NULL) |
| PAYMENT_TRANSACTION | `payment_transaction` | `transaction_identifier` | `session_identifier` |

> Các khóa ứng viên trong dấu ngoặc nhiều cột của bảng có xóa mềm chỉ có hiệu lực trên các dòng chưa xóa (partial unique index).

### Bước 2. Thực thể yếu (Weak Entity Types)
**Không có.** `parking_space` được định danh trong phạm vi bãi đỗ bằng (`facility_identifier`, `space_code`), nhưng nhóm chọn khóa thay thế `space_identifier` để các bảng khác (`reservation`, `charging_equipment`) tham chiếu bằng một cột duy nhất; cặp (`facility_identifier`, `space_code`) vẫn được bảo đảm duy nhất.

### Bước 3. Quan hệ 1:1
Với quan hệ 1:1, khóa ngoại đặt ở phía có **tham gia toàn phần** (hoặc phía phụ thuộc) và gắn ràng buộc `UNIQUE`.

| Quan hệ ERD | Tham gia | Ánh xạ | Ghi chú |
|---|---|---|---|
| PARKING_SPACE **1** — **0..1** CHARGING_EQUIPMENT | Thiết bị luôn thuộc một ô; ô có thể không có thiết bị | `charging_equipment.space_identifier` là *FK* + `UNIQUE` (từng phần) `NOT NULL` | Dùng cách "tách bảng" thay vì gộp để tránh NULL ở các ô đỗ thường. |
| SERVICE_SESSION **1** — **0..1** PAYMENT_TRANSACTION | Mỗi giao dịch thuộc đúng một phiên | `payment_transaction.session_identifier` là *FK* + `UNIQUE` `NOT NULL` | Giao dịch được trigger `trg_session_finish` tự tạo khi phiên kết thúc. |
| RESERVATION **0..1** — **0..1** SERVICE_SESSION | Phiên có thể không có đặt chỗ (khách vãng lai) | `service_session.reservation_identifier` là *FK* nullable + `UNIQUE` | Một lượt đặt sinh tối đa một phiên. |

### Bước 4. Quan hệ 1:N
Khóa chính phía **1** được thêm vào phía **N** làm khóa ngoại.

| Phía 1 | Phía N | Khóa ngoại ở phía N | Bắt buộc | ON DELETE |
|---|---|---|---|---|
| `user_account` | `vehicle` | `account_identifier` | Có | CASCADE |
| `parking_facility` | `parking_space` | `facility_identifier` | Có | CASCADE |
| `parking_space` | `reservation` | `space_identifier` | Có | RESTRICT |
| `vehicle` | `reservation` | `vehicle_identifier` | Có | RESTRICT |
| `vehicle` | `service_session` | `vehicle_identifier` | Có | RESTRICT |
| `charging_equipment` | `service_session` | `equipment_identifier` | Có | RESTRICT |
| `tariff_rate` | `payment_transaction` | `rate_identifier` | Có | RESTRICT |
| `user_account` (MANAGER) | `payment_transaction` | `confirmed_by_identifier` | Không | RESTRICT |

**Quan hệ đã loại bỏ so với thiết kế trước:** `user_account` → `reservation` và `user_account` → `service_session` không còn khóa ngoại riêng. Tài khoản của một lượt đặt hoặc phiên sạc được suy ra qua chủ xe (`vehicle.account_identifier`), tránh dư thừa và phụ thuộc bắc cầu.

### Bước 5. Quan hệ M:N
Mỗi quan hệ M:N trở thành một quan hệ trung gian có khóa chính ghép từ hai khóa ngoại.

| Quan hệ ERD | Quan hệ trung gian | Khóa chính | Ràng buộc bổ sung |
|---|---|---|---|
| USER_ACCOUNT (vai trò MANAGER) **M** — **N** PARKING_FACILITY | `facility_manager` | (*manager_identifier*, *facility_identifier*), cả hai cùng là FK, `ON DELETE CASCADE` | Trigger `trg_facility_manager_role`: `manager_identifier` phải là tài khoản `MANAGER` chưa xóa. |

### Bước 6. Thuộc tính đa trị
**Không có.** Danh sách xe của một người dùng (có thể bị hiểu là thuộc tính đa trị) được tách thành quan hệ `vehicle` (1:N) để đạt 1NF.

### Bước 7. Quan hệ n-ngôi
**Không có.** Mọi quan hệ trong ERD đều là quan hệ hai ngôi.

### Bước 8. Chuyên biệt hóa (Specialization / Generalization)
Thực thể người dùng có ba vai trò **rời nhau** (disjoint): `CUSTOMER`, `MANAGER`, `ADMIN`. Các vai trò **không có thuộc tính riêng**, nên áp dụng cách *một quan hệ duy nhất kèm thuộc tính phân loại* (single relation with type attribute):

* một bảng `user_account` với cột `role_code` `CHECK (role_code IN ('CUSTOMER','MANAGER','ADMIN'))`;
* quan hệ đặc thù theo vai trò thể hiện ở nơi cần: chỉ `CUSTOMER` sở hữu `vehicle`; chỉ `MANAGER` xuất hiện trong `facility_manager` (kiểm tra bằng trigger).

Cách này tránh NULL từ thuộc tính riêng (vì không có) và tránh phép nối thừa khi truy vấn.

### Bước 9. Thuộc tính suy diễn (Derived)
Không lưu các giá trị có thể tính từ dữ liệu khác, ngoại trừ các trường hợp có chủ đích:

| Giá trị | Cách xử lý |
|---|---|
| Tài khoản của đặt chỗ / phiên sạc | Suy ra qua `vehicle.account_identifier`. |
| Khả dụng của ô đỗ trong một khung giờ | Tính bằng `fn_is_space_available(space, start, end)`; cột `availability_status_code` chỉ là trạng thái **hiện tại**. |
| Đơn giá của phiên | Lưu **snapshot** `applied_price_per_kwh_value`, `applied_overtime_fee_per_hour_value` trên `service_session` lúc bắt đầu sạc. |
| Số tiền hóa đơn | Lưu **snapshot** `energy_amount_value`, `overtime_amount_value`, `transaction_amount_value` để hóa đơn không đổi khi bảng giá thay đổi; `CHECK` tổng bằng hai thành phần. |

---

## 3. Lược đồ quan hệ kết quả (10 quan hệ)

1. `user_account` (**account_identifier**, full_name_text `[NN]`, contact_phone_number `[UQ][NN]`, email_address `[UQ][NN]`, password_hash_text `[NN]`, password_plain_text, role_code `[NN]`, created_datetime `[NN]`, deleted_datetime, purged_datetime)
2. `vehicle` (**vehicle_identifier**, *account_identifier* `[NN]`, license_plate_text `[UQ][NN]`, battery_capacity_kwh `[NN]`, deleted_datetime)
3. `parking_facility` (**facility_identifier**, facility_name_text `[NN]`, geographic_location `[NN]`, address_text `[NN]`, total_capacity_count `[NN]`)
4. `facility_manager` (***manager_identifier***, ***facility_identifier***)
5. `parking_space` (**space_identifier**, *facility_identifier* `[NN]`, space_code `[NN]`, availability_status_code `[NN]`, deleted_datetime, `[UQ(facility_identifier, space_code)]`)
6. `charging_equipment` (**equipment_identifier**, *space_identifier* `[UQ][NN]`, evse_identifier `[UQ][NN]`, connector_type_code `[NN]`, max_power_kw `[NN]`, equipment_status_code `[NN]`, deleted_datetime)
7. `tariff_rate` (**rate_identifier**, connector_type_code `[NN]`, time_band_code `[NN]`, start_time `[NN]`, end_time `[NN]`, min_power_kw `[NN]`, max_power_kw `[NN]`, price_per_kwh_value `[NN]`, overtime_fee_per_hour_value `[NN]`)
8. `reservation` (**reservation_identifier**, *vehicle_identifier* `[NN]`, *space_identifier* `[NN]`, start_datetime `[NN]`, end_datetime `[NN]`, reservation_status_code `[NN]`, created_datetime `[NN]`, deleted_datetime)
9. `service_session` (**session_identifier**, *reservation_identifier* `[UQ]`, *vehicle_identifier* `[NN]`, *equipment_identifier* `[NN]`, start_datetime `[NN]`, end_datetime, fully_charged_datetime, peak_charging_power_kw `[NN]`, consumed_energy_kwh `[NN]`, applied_price_per_kwh_value, applied_overtime_fee_per_hour_value, start_battery_percent)
10. `payment_transaction` (**transaction_identifier**, *session_identifier* `[UQ][NN]`, *rate_identifier* `[NN]`, energy_amount_value `[NN]`, overtime_amount_value `[NN]`, transaction_amount_value `[NN]`, currency_code `[NN]`, payment_method_code, gateway_reference_identifier, transaction_status_code `[NN]`, created_datetime `[NN]`, customer_name_text `[NN]`, customer_phone_number `[NN]`, customer_email_address `[NN]`, license_plate_text `[NN]`, *confirmed_by_identifier*, confirmed_datetime)

---

## 4. Danh mục khóa ngoại và chính sách tham chiếu

| # | Bảng chứa FK | Cột FK | Bảng tham chiếu | Cột tham chiếu | ON DELETE | Lý do |
|---|---|---|---|---|---|---|
| 1 | `vehicle` | `account_identifier` | `user_account` | `account_identifier` | CASCADE | Xe thuộc quyền sở hữu trực tiếp của tài khoản. |
| 2 | `facility_manager` | `manager_identifier` | `user_account` | `account_identifier` | CASCADE | Bỏ phân công khi tài khoản bị xóa. |
| 3 | `facility_manager` | `facility_identifier` | `parking_facility` | `facility_identifier` | CASCADE | Bỏ phân công khi bãi đỗ bị giải tỏa. |
| 4 | `parking_space` | `facility_identifier` | `parking_facility` | `facility_identifier` | CASCADE | Ô đỗ trực thuộc bãi. |
| 5 | `charging_equipment` | `space_identifier` | `parking_space` | `space_identifier` | CASCADE | Thiết bị gắn liền ô đỗ. |
| 6 | `reservation` | `vehicle_identifier` | `vehicle` | `vehicle_identifier` | RESTRICT | Bảo toàn lịch sử đặt chỗ. |
| 7 | `reservation` | `space_identifier` | `parking_space` | `space_identifier` | RESTRICT | Không xóa ô đỗ đang có lịch sử đặt. |
| 8 | `service_session` | `reservation_identifier` | `reservation` | `reservation_identifier` | SET NULL | Phiên sạc vẫn được giữ nếu lượt đặt bị xóa. |
| 9 | `service_session` | `vehicle_identifier` | `vehicle` | `vehicle_identifier` | RESTRICT | Bảo toàn lịch sử phiên sạc. |
| 10 | `service_session` | `equipment_identifier` | `charging_equipment` | `equipment_identifier` | RESTRICT | Bảo toàn lịch sử phiên sạc. |
| 11 | `payment_transaction` | `session_identifier` | `service_session` | `session_identifier` | RESTRICT | Audit log tài chính không được mất. |
| 12 | `payment_transaction` | `rate_identifier` | `tariff_rate` | `rate_identifier` | RESTRICT | Hóa đơn phải truy vết được ô giá đã áp dụng. |
| 13 | `payment_transaction` | `confirmed_by_identifier` | `user_account` | `account_identifier` | RESTRICT | Giữ người đã xác nhận thanh toán; tài khoản quản lý đó chỉ bị ẩn thông tin, không xóa hẳn. |

Nguyên tắc: **CASCADE** cho cấu trúc sở hữu/hạ tầng; **RESTRICT** cho dữ liệu lịch sử và tài chính; **SET NULL** chỉ cho liên kết lịch sử không bắt buộc (mục 8). Vì tài khoản, xe, ô đỗ dùng xóa mềm nên việc xóa vật lý chỉ xảy ra ngoài luồng nghiệp vụ thông thường.

---

## 5. Ràng buộc không biểu diễn được bằng khóa/khóa ngoại

Một số quy tắc nghiệp vụ không thể mô tả bằng phép ánh xạ cấu trúc; chúng được hiện thực bằng ràng buộc khai báo hoặc trigger (đều được kiểm thử trong `tests.sql`).

| Quy tắc | Cơ chế |
|---|---|
| Không đặt chỗ chồng giờ trên cùng ô đỗ | `ex_reservation_no_overlap` — `EXCLUDE USING gist (space_identifier WITH =, tstzrange(start_datetime, end_datetime) WITH &&) WHERE (status IN ('PENDING','CONFIRMED','FULFILLED') AND deleted_datetime IS NULL)` |
| Không có hai ô giá chồng nhau (cùng loại cổng) | `ex_tariff_rate_no_overlap` — `EXCLUDE USING gist` trên (`connector_type_code`, khoảng giờ, khoảng công suất) |
| Mỗi thiết bị chỉ có một phiên đang mở | Chỉ mục duy nhất từng phần `ux_service_session_open_equipment` (`WHERE end_datetime IS NULL`) |
| Khách vãng lai không chen vào lịch đã đặt | Trigger `trg_session_validate` |
| Chỉ MANAGER được phân công bãi | Trigger `trg_facility_manager_role` |
| Chỉ CUSTOMER được sở hữu xe | Trigger `trg_vehicle_owner_role` |
| Số ô đỗ không vượt sức chứa | Trigger `trg_space_capacity` |
| Không đặt chỗ ở ô `OUTOFSERVICE` | Trigger `trg_reservation_validate` |
| Thiết bị `FAULT`/`MAINTENANCE` ⇒ ô `OUTOFSERVICE` | Trigger `trg_equipment_status_sync` |
| Tự lập hóa đơn khi kết thúc phiên | Trigger `trg_session_finish` (chọn giá bằng `fn_select_tariff`) |
| Hóa đơn bất biến | Trigger `trg_payment_immutable` + FK `RESTRICT` |
| Hóa đơn giữ thông tin khách | `trg_payment_snapshot` |
| Xóa vĩnh viễn sau 30 phút | `fn_purge_deleted_accounts` |
| Không đổi vai trò khi còn xe / phân công; không xóa ADMIN; xóa mềm thì dọn lượt đặt, phân công và xe; khôi phục trong 30 phút | `trg_account_guard` |
| Không sửa xe, ô, giờ của lượt đặt | `trg_reservation_fixed` |
| Không xóa phiên; xe, trụ, giờ bắt đầu, giá chốt cố định | `trg_session_fixed` |
| Điện năng không vượt pin và công suất × thời gian | `trg_session_energy_limit` |
| Trạng thái trụ `CHARGING` khớp phiên đang mở | `trg_equipment_charging_guard` |
| Chỉ lập hóa đơn cho phiên đã kết thúc | `trg_payment_requires_end` |
| Xóa mềm ô đỗ | `trg_space_removal` |
| Tự hủy đặt chỗ sau 30 phút | Hàm `fn_expire_overdue_reservations()` (pg_cron mỗi phút) |

---

## 6. Ánh xạ kiểu dữ liệu

| Khái niệm trong ERD | Kiểu PostgreSQL | Lý do |
|---|---|---|
| Định danh | `UUID` | Duy nhất toàn cục, sinh bằng `gen_random_uuid()`, không lộ thứ tự bản ghi. |
| Mã phân loại (`_code`) | `VARCHAR(n)` + `CHECK ... IN (...)` | Tập giá trị đóng, dễ đọc hơn `ENUM` khi cần thay đổi. |
| Thời điểm | `TIMESTAMPTZ` | Chính xác bất kể múi giờ (ISO 8601). |
| Giờ trong ngày (khung giá) | `TIME` | Khung giờ lặp lại hằng ngày; có thể là `24:00` để kết thúc ngày. |
| Công suất, điện năng, dung lượng | `DECIMAL(10,2)` | Tránh sai số số thực. |
| Tiền tệ | `DECIMAL(12,2)` + `CHAR(3)` | Chính xác tuyệt đối; mã ISO 4217. |
| Tọa độ | `GEOMETRY(Point, 4326)` + chỉ mục GiST | Truy vấn khoảng cách/vùng lân cận. |
| Số điện thoại | `VARCHAR(15)` + `CHECK` regex | Dạng E.164 rút gọn. |

---

## 7. Kiểm tra tính đầy đủ của ánh xạ

| Hạng mục | Kết quả |
|---|---|
| Số thực thể ERD → số quan hệ | 9 thực thể + 1 bảng trung gian (M:N) = **10 quan hệ** |
| Số đường quan hệ trong ERD → khóa ngoại | 13 đường quan hệ = 8 (1:N, gồm CONFIRMS) + 3 (1:1) + 2 (hai nhánh của `facility_manager`) = **13 khóa ngoại** |
| Mọi cột trong ERD có mặt trong `schema.sql` | Có (đã đối chiếu tự động tên cột ERD với DDL) |
| Mọi khóa ngoại có chính sách ON DELETE | Có (mục 4) |
| Thuộc tính đa trị / n-ngôi | Không phát sinh |
| Thuộc tính suy diễn được xử lý rõ ràng | Có (Bước 9) |

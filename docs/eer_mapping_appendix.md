# Phụ lục: Ánh xạ EER (Elmasri) sang sơ đồ vật lý

Sơ đồ khái niệm: `../EER_Diagram.png` (bản vector: `EER_Diagram.svg`; mã Mermaid: `../eer.mmd`).
Sơ đồ vật lý theo chuẩn IE Crow's Foot: `ERD_Diagram.png` (nguồn `erd.mmd`). Định nghĩa bảng: `../schema.sql`.

## 1. Thực thể mạnh

| Thực thể EER | Bảng | Khóa chính |
|---|---|---|
| USER_ACCOUNT | `user_account` | `account_identifier` |
| VEHICLE | `vehicle` | `vehicle_identifier` |
| PARKING_FACILITY | `parking_facility` | `facility_identifier` |
| PARKING_SPACE | `parking_space` | `space_identifier` |
| CHARGING_EQUIPMENT | `charging_equipment` | `equipment_identifier` |
| TIME_BAND | `time_band` | `time_band_code` |
| TIME_BAND_WINDOW | `time_band_window` | `start_time` |
| POWER_TIER | `power_tier` | (`connector_type_code`, `min_power_kw`) |
| TARIFF_RATE | `tariff_rate` | `rate_identifier` |
| PARKING_RATE | `parking_rate` | `parking_rate_identifier` |
| RESERVATION | `reservation` | `reservation_identifier` |
| SERVICE_SESSION | `service_session` | `session_identifier` |
| PAYMENT_TRANSACTION | `payment_transaction` | `transaction_identifier` |

## 2. Chuyên biệt hóa USER_ACCOUNT

CUSTOMER, MANAGER, ADMIN là các lớp con rời nhau (d) và toàn phần của USER_ACCOUNT. Các lớp con không có thuộc tính riêng, nên được ánh xạ vào **một quan hệ duy nhất** `user_account` với thuộc tính phân loại `role_code` (`NOT NULL`, `CHECK`).

Quyền thao tác không thuộc ký hiệu EER nên được ghi trong khung riêng trên sơ đồ:

| Lớp | Thao tác trên web | Quan hệ riêng | Nơi kiểm soát |
|---|---|---|---|
| USER_ACCOUNT | Đăng nhập, đăng xuất | | `/login`, `/logout` |
| CUSTOMER | Tự đăng ký kèm xe đầu tiên, thêm xe; tìm ô; đặt, hủy chỗ; xem phiên sạc; xem và thanh toán hóa đơn của mình (chờ quản lý xác nhận) | OWNS | `role_required`, điều kiện chủ xe trong SQL, `trg_vehicle_owner_role` |
| MANAGER | Chỉ ở bãi được phân công: xem sơ đồ; đổi trạng thái trụ; xác nhận, hủy quá hạn đặt chỗ; ghi nhận xe vào đỗ, rời bãi ở ô chỉ đỗ (tính phí theo giờ); bắt đầu sạc (chọn biển số, nhập % pin), kết thúc sạc (điện năng tự tính); xem xe đang đỗ, lịch đặt và thanh thời gian; xác nhận, từ chối thanh toán | MANAGES | `role_required`, lọc theo `facility_manager`, `trg_facility_manager_role` |
| ADMIN | Xem doanh thu, hóa đơn; đổi giá sạc, giá đỗ (thêm phiên bản giá); phân công, thu hồi quản lý bãi; tạo tài khoản MANAGER, ADMIN; xóa, khôi phục tài khoản MANAGER, CUSTOMER; đối soát lịch đặt | Không có | `role_required` |

ADMIN không có quan hệ riêng vì CSDL không lưu người thực hiện các thao tác của quản trị.

## 3. Quan hệ

| Quan hệ EER | Tỷ số | Ánh xạ | Ràng buộc trong CSDL |
|---|---|---|---|
| OWNS (CUSTOMER, VEHICLE) | 1:N | `vehicle.account_identifier` | FK, `NOT NULL`; `trg_vehicle_owner_role` (chủ xe phải là `CUSTOMER` còn hoạt động) |
| MANAGES (MANAGER, PARKING_FACILITY) | M:N | Bảng `facility_manager` | Khóa chính ghép, 2 FK; `trg_facility_manager_role` |
| CONTAINS (PARKING_FACILITY, PARKING_SPACE) | 1:N | `parking_space.facility_identifier` | FK, `NOT NULL`; `trg_space_capacity` |
| HAS (PARKING_SPACE, CHARGING_EQUIPMENT) | 1:1 | `charging_equipment.space_identifier` | FK, `NOT NULL`, chỉ mục duy nhất từng phần |
| MAKES (VEHICLE, RESERVATION) | 1:N | `reservation.vehicle_identifier` | FK, `NOT NULL` |
| BOOKS (PARKING_SPACE, RESERVATION) | 1:N | `reservation.space_identifier` | FK, `NOT NULL`; `ex_reservation_no_overlap` |
| ACTIVATES (RESERVATION, SERVICE_SESSION) | 1:1 | `service_session.reservation_identifier` | FK, `UNIQUE`, cho phép `NULL` |
| CHARGES (VEHICLE, SERVICE_SESSION) | 1:N | `service_session.vehicle_identifier` | FK, `NOT NULL` |
| SERVES (CHARGING_EQUIPMENT, SERVICE_SESSION) | 1:N | `service_session.equipment_identifier` | FK, cho phép NULL (phiên chỉ đỗ); mỗi trụ tối đa một phiên đang mở |
| HOSTS (PARKING_SPACE, SERVICE_SESSION) | 1:N | `service_session.space_identifier` | FK, cho phép NULL (phiên sạc); chỉ ô không có trụ; `ck_service_session_kind` buộc đúng một trong SERVES, HOSTS |
| BILLED_BY (SERVICE_SESSION, PAYMENT_TRANSACTION) | 1:1 | `payment_transaction.session_identifier` | FK, `NOT NULL`, `UNIQUE`. Phiên đang mở chưa có hóa đơn |
| APPLIES (TARIFF_RATE, SERVICE_SESSION) | 1:N | `service_session.rate_identifier` | FK; phiên bản giá chốt lúc bắt đầu sạc (trigger ghi, không sửa được) |
| APPLIES_PARKING (PARKING_RATE, SERVICE_SESSION) | 1:N | `service_session.parking_rate_identifier` | FK; phiên bản giá đỗ chốt lúc xe vào |
| IN_TIER (POWER_TIER, TARIFF_RATE) | 1:N | `tariff_rate.(connector_type_code, min_power_kw)` | FK ghép, `NOT NULL`, `ON DELETE RESTRICT` |
| PRICED_IN (TIME_BAND, TARIFF_RATE) | 1:N | `tariff_rate.time_band_code` | FK, `NOT NULL`, `ON DELETE RESTRICT`; `uq_tariff_rate_key` |
| PARKING_IN (TIME_BAND, PARKING_RATE) | 1:N | `parking_rate.time_band_code` | FK, `NOT NULL`, `ON DELETE RESTRICT` |
| COVERS (TIME_BAND, TIME_BAND_WINDOW) | 1:N | `time_band_window.time_band_code` | FK, `NOT NULL`, `ON DELETE RESTRICT` |
| CONFIRMS (MANAGER, PAYMENT_TRANSACTION), thuộc tính `confirmed_datetime` | 1:N | `payment_transaction.confirmed_by_identifier`, `confirmed_datetime` | FK, cho phép NULL khi chưa xác nhận; `ck_payment_confirmed`; trigger kiểm tra người xác nhận là MANAGER của bãi nơi sạc |

## 4. Thuộc tính dẫn xuất

`energy_amount_value`, `overtime_amount_value`, `parking_amount_value` và `transaction_amount_value` được tính khi kết thúc phiên và **vẫn lưu** trong `payment_transaction` vì hóa đơn là bất biến. `ck_payment_amounts` bảo đảm tổng bằng ba khoản thành phần.

`reservation_duration` và `session_duration` bằng `end_datetime - start_datetime`, **không lưu** thành cột mà tính khi truy vấn.

## 5. Ràng buộc không biểu diễn được bằng ký hiệu

| Ràng buộc | Hiện thực |
|---|---|
| Email, số điện thoại, biển số, `evse_identifier` duy nhất trong các bản ghi chưa xóa | Chỉ mục duy nhất từng phần |
| `space_code` duy nhất trong từng bãi | `ux_parking_space_code` |
| Một ô và một xe không có hai đặt chỗ chồng giờ | `ex_reservation_no_overlap`, `ex_reservation_vehicle_no_overlap` |
| Đặt chỗ dài tối đa 24 giờ | `ck_reservation_duration` |
| Một trụ và một xe chỉ có một phiên đang mở | `ux_service_session_open_equipment`, `ux_service_session_open_vehicle` |
| Bắt đầu sạc theo đặt chỗ sớm tối đa 15 phút | `trg_session_validate` |
| Chỉ CUSTOMER sở hữu xe, chỉ MANAGER quản lý bãi | `trg_vehicle_owner_role`, `trg_facility_manager_role` |
| Số ô không vượt sức chứa | `trg_space_capacity`, `trg_facility_capacity` |
| Phiên đã kết thúc và số tiền hóa đơn không sửa được | `trg_session_immutable`, `trg_payment_immutable` |
| Đơn giá chốt lúc bắt đầu sạc; phiên không xóa được | `trg_session_validate`, `trg_session_fixed` |
| Điện năng không vượt pin và công suất × thời gian | `trg_session_energy_limit` |
| Giữ vai trò khi còn xe / phân công | `trg_account_guard` |
| Xe, ô, giờ của lượt đặt không sửa được | `trg_reservation_fixed` |
| Khoảng giờ của các khung không chồng nhau, phủ kín 24 giờ | `ex_time_band_window_no_overlap`; `trg_time_band_window_coverage` (kiểm tra cuối giao dịch) |
| Dải công suất của một loại cổng không chồng nhau | `ex_power_tier_no_overlap` |
| Phiên bản giá không chồng thời gian hiệu lực, không bị sửa đè | `ex_tariff_rate_no_overlap`, `ex_parking_rate_no_overlap`; `trg_tariff_rate_fixed`, `trg_parking_rate_fixed` |
| Phiên dùng đúng một trong hai: trụ sạc (SERVES) hoặc ô chỉ đỗ (HOSTS) | `ck_service_session_kind`; `trg_session_validate` |
| Một ô chỉ đỗ có tối đa một phiên đang mở | `ux_service_session_open_space` |

## 6. Thuộc tính cài đặt chỉ có ở sơ đồ vật lý

Sơ đồ EER chỉ giữ thuộc tính nghiệp vụ. Các cột sau phục vụ cài đặt nên chỉ có trong ERD vật lý và `schema.sql`:

| Cột | Bảng | Lý do |
|---|---|---|
| `deleted_datetime`, `purged_datetime` | `user_account`, `vehicle`, `parking_space`, `charging_equipment`, `reservation` | Xóa mềm và xóa vĩnh viễn thông tin cá nhân |
| `password_plain_text` | `user_account` | Lựa chọn của nhóm để ADMIN xem mật khẩu khi demo; EER chỉ có thuộc tính `password` |
| `customer_name_text`, `customer_phone_number`, `customer_email_address`, `license_plate_text` | `payment_transaction` | Bản sao thông tin khách lúc lập hóa đơn, để hóa đơn còn nguyên khi tài khoản bị xóa |

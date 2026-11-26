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
| TARIFF_RATE | `tariff_rate` | `rate_identifier` |
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
| MANAGER | Chỉ ở bãi được phân công: xem sơ đồ; đổi trạng thái trụ; xác nhận, hủy quá hạn đặt chỗ; ghi nhận khách đến ô chỉ đỗ; bắt đầu sạc (chọn biển số, nhập % pin), kết thúc sạc (điện năng tự tính); xem xe đang đỗ, lịch đặt và thanh thời gian; xác nhận, từ chối thanh toán | MANAGES | `role_required`, lọc theo `facility_manager`, `trg_facility_manager_role` |
| ADMIN | Xem doanh thu, hóa đơn; sửa biểu giá; phân công, thu hồi quản lý bãi; tạo tài khoản MANAGER, ADMIN; xóa, khôi phục tài khoản MANAGER, CUSTOMER; đối soát lịch đặt | Không có | `role_required` |

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
| SERVES (CHARGING_EQUIPMENT, SERVICE_SESSION) | 1:N | `service_session.equipment_identifier` | FK, `NOT NULL`; mỗi trụ tối đa một phiên đang mở |
| BILLED_BY (SERVICE_SESSION, PAYMENT_TRANSACTION) | 1:1 | `payment_transaction.session_identifier` | FK, `NOT NULL`, `UNIQUE`. Phiên đang mở chưa có hóa đơn |
| APPLIES (TARIFF_RATE, PAYMENT_TRANSACTION) | 1:N | `payment_transaction.rate_identifier` | FK, `NOT NULL` |
| CONFIRMS (MANAGER, PAYMENT_TRANSACTION), thuộc tính `confirmed_datetime` | 1:N | `payment_transaction.confirmed_by_identifier`, `confirmed_datetime` | FK, cho phép NULL khi chưa xác nhận; `ck_payment_confirmed`; trigger kiểm tra người xác nhận là MANAGER của bãi nơi sạc |

## 4. Thuộc tính dẫn xuất

`energy_amount_value`, `overtime_amount_value` và `transaction_amount_value` được tính khi kết thúc phiên và **vẫn lưu** trong `payment_transaction` vì hóa đơn là bất biến. `ck_payment_amounts` bảo đảm tổng bằng hai khoản thành phần.

`reservation_duration` và `charging_duration` bằng `end_datetime - start_datetime`, **không lưu** thành cột mà tính khi truy vấn.

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

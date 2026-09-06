# Smart City EV Charging & Parking Management System

A robust, scalable relational database system designed on **PostgreSQL** to manage integrated Electric Vehicle (EV) charging stations and parking infrastructure within smart cities. This project addresses large-scale spatial data management, real-time tracking, and automated dynamic pricing workflows.

---

## 👥 Team Members - Group M3B
* **Nguyen Truong Nghi** - n24dccn142@student.ptithcm.edu.vn (Project Owner)
* **Pham Cong Dang** - n24dccn102@student.ptithcm.edu.vn
* **Mai Van Cong** - n24dccn100@student.ptithcm.edu.vn

**Class:** D24CQCN02-N  
**Instructor:** Le Ha Thanh  
**Institution:** Posts and Telecommunications Institute of Technology (Ho Chi Minh City Campus )  

---

## 🛠️ Compliance Standards
This system strictly adheres to industry standards for technical modeling and telemetry:
- **ISO/IEC 29148:** Systems and software engineering — Lifecycle processes — Requirements engineering.
- **ISO/IEC 19505 / IE:** Visual entity-relationship notation (Crow's Foot diagram layout).
- **ISO/IEC 11179:** Metadata registries registry standards (Unified naming syntax suffixes like `_identifier`, `_code`, `_datetime`, `_count`, `_amount`).
- **ISO 8601:** Date and time representation using global standard `TIMESTAMPTZ`.
- **ISO 6709 & WGS 84:** Standard representation of geographic point locations via PostGIS geometry.
- **ISO 4217:** Alpha-3 global standard currency code definitions (`VND`, `USD`).
- **ISO 15118 & OCPP:** EV-to-Grid communication compliance using dedicated `evse_identifier` protocols.

---

## 📋 Business Rules & Constraints

### 1. Identity & Assets
- A `User` registers a unique account verified by an Email or Phone number.
- Each `User` can own multiple `Vehicles`, distinctively identified by a standard `LicensePlate` and maximum battery capacity (`kWh`).
- Admin/Staff users are mapped directly to manage one or more physical `Parking_Lots`.

### 2. Infrastructure & Real-Time Status
- Each `Parking_Facility` maps to a physical WGS 84 point position (`POINT`).
- A `Parking_Space` is linked to an `EV_Charger` via a strict 1:1 hardware extension. Chargers are classified by `ConnectorType` and power profiles (`DC Fast / AC Standard`).
- Slots maintain 4 operational states: `Available`, `Reserved`, `Occupied`, or `OutOfService`.

### 3. Reservation Policies
- Customers can only reserve slots under the `Available` status flags.
- Reserved timestamps (`StartTime` to `EndTime`) are validated against any time over-laps on the exact requested hardware slot.
- **30-Minute Grace Period:** If a session is not activated within 30 minutes from `StartTime`, the system automatically moves the reservation status to `Cancelled` and clears the slot back to `Available`.

### 4. Dynamic Pricing & Transactions
- Standard rates (`TariffRate`) vary based on operational hours (Peak hours 17:00-20:00 vs. Off-peak hours 22:00-05:00) and charger capabilities (DC commands a higher cost/kWh).
- **Billing Calculation:** 
  \[\text{Total Invoice Amount} = (\text{EnergyConsumed\_kWh} \times \text{HourlyTariffRate}) + \text{Overtime\_Idle\_Fee}\]
- Successful compilation of a `Service_Session` immediately creates an immutable `Payment_Transaction`.

---

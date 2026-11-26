-- =============================================================================
-- Quản lý trạm sạc xe điện và bãi đỗ thông minh - truy vấn phân tích
-- Chạy trên cơ sở dữ liệu đã nạp schema.sql + seed.sql:
--     psql -d evt -f queries.sql
-- 12 truy vấn (Q1-Q12) chạy trên PostgreSQL thuần; Q13 cần PostGIS.
-- Mỗi truy vấn nêu câu hỏi nghiệp vụ, tính năng SQL được dùng và các bảng
-- liên quan. Mọi mốc thời gian hiển thị theo Asia/Ho_Chi_Minh.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Lịch sử sạc của một khách hàng kèm hóa đơn (JOIN 7 bảng)
-- Câu hỏi  : khách "Đặng Quốc Phong" đã sạc gì, ở đâu và hết bao nhiêu tiền?
-- Kỹ thuật : INNER/LEFT JOIN, ORDER BY, LIMIT
-- Bảng     : user_account, vehicle, service_session, charging_equipment,
--            parking_space, parking_facility, payment_transaction
-- -----------------------------------------------------------------------------
SELECT u.full_name_text,
       v.license_plate_text,
       f.facility_name_text,
       s.space_code,
       ce.connector_type_code,
       (ss.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIMESTAMP(0) AS start_local,
       ss.consumed_energy_kwh,
       p.transaction_amount_value,
       p.transaction_status_code
FROM user_account AS u
JOIN vehicle AS v ON v.account_identifier = u.account_identifier
JOIN service_session AS ss ON ss.vehicle_identifier = v.vehicle_identifier
JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
LEFT JOIN payment_transaction AS p ON p.session_identifier = ss.session_identifier
WHERE u.full_name_text = 'Đặng Quốc Phong'
ORDER BY ss.start_datetime DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Q2. Doanh thu theo bãi và khung giá (gộp nhóm + HAVING)
-- Câu hỏi  : cặp bãi / khung giá nào thu hơn 1.000.000 VND
--            từ các thanh toán thành công?
-- Kỹ thuật : GROUP BY, SUM/COUNT/AVG, HAVING
-- Bảng     : payment_transaction, tariff_rate, service_session,
--            charging_equipment, parking_space, parking_facility
-- -----------------------------------------------------------------------------
SELECT f.facility_name_text,
       t.time_band_code,
       count(*)                           AS invoice_count,
       sum(p.energy_amount_value)         AS energy_revenue,
       sum(p.overtime_amount_value)       AS overtime_revenue,
       sum(p.transaction_amount_value)    AS total_revenue,
       round(avg(p.transaction_amount_value), 0) AS avg_invoice
FROM payment_transaction AS p
JOIN tariff_rate AS t ON t.rate_identifier = p.rate_identifier
JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
WHERE p.transaction_status_code = 'SUCCESS'
GROUP BY f.facility_name_text, t.time_band_code
HAVING sum(p.transaction_amount_value) > 1000000
ORDER BY f.facility_name_text, total_revenue DESC;

-- -----------------------------------------------------------------------------
-- Q3. Hiệu suất sử dụng trụ sạc theo bãi trong 30 ngày cuối của lịch sử
--     (CTE + gộp nhóm có điều kiện)
-- Câu hỏi  : tỷ lệ giờ-trụ khả dụng thực sự được dùng là bao nhiêu?
-- Kỹ thuật : WITH (CTE), cắt khoảng thời gian bằng GREATEST/LEAST, tỷ lệ
-- Bảng     : service_session, charging_equipment, parking_space, parking_facility
-- Kỳ xét   : 2026-09-27 .. 2026-10-27 (cố định để kết quả tái lập được)
-- -----------------------------------------------------------------------------
WITH period AS (
    SELECT TIMESTAMPTZ '2026-09-27 00:00:00+07' AS period_start,
           TIMESTAMPTZ '2026-10-27 00:00:00+07' AS period_end
),
used AS (
    SELECT s.facility_identifier,
           sum(extract(epoch FROM (
               least(ss.end_datetime, pr.period_end)
               - greatest(ss.start_datetime, pr.period_start))) / 3600.0) AS used_hours
    FROM service_session AS ss
    JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
    JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
    CROSS JOIN period AS pr
    WHERE ss.end_datetime > pr.period_start
      AND ss.start_datetime < pr.period_end
    GROUP BY s.facility_identifier
),
capacity AS (
    SELECT s.facility_identifier,
           count(*) * extract(epoch FROM (pr.period_end - pr.period_start)) / 3600.0
               AS available_hours
    FROM charging_equipment AS ce
    JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
    CROSS JOIN period AS pr
    WHERE ce.deleted_datetime IS NULL
    GROUP BY s.facility_identifier, pr.period_start, pr.period_end
)
SELECT f.facility_name_text,
       round(u.used_hours::NUMERIC, 1)      AS used_hours,
       round(c.available_hours::NUMERIC, 0) AS available_hours,
       round(100 * u.used_hours / c.available_hours, 2) AS utilisation_percent
FROM parking_facility AS f
JOIN capacity AS c ON c.facility_identifier = f.facility_identifier
LEFT JOIN used AS u ON u.facility_identifier = f.facility_identifier
ORDER BY utilisation_percent DESC;

-- -----------------------------------------------------------------------------
-- Q4. Trụ sạc không được dùng trong 30 ngày cuối (anti-join bằng NOT EXISTS)
-- Câu hỏi  : trụ nào không tạo doanh thu, cần di dời hoặc kiểm tra?
-- Kỹ thuật : truy vấn con tương quan NOT EXISTS
-- Bảng     : charging_equipment, parking_space, parking_facility, service_session
-- -----------------------------------------------------------------------------
SELECT f.facility_name_text,
       s.space_code,
       ce.evse_identifier,
       ce.equipment_status_code
FROM charging_equipment AS ce
JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
WHERE NOT EXISTS (
    SELECT 1
    FROM service_session AS ss
    WHERE ss.equipment_identifier = ce.equipment_identifier
      AND ss.start_datetime >= TIMESTAMPTZ '2026-09-27 00:00:00+07'
)
ORDER BY f.facility_name_text, s.space_code;

-- -----------------------------------------------------------------------------
-- Q5. Phiên sạc dài hơn nhiều so với trung bình cùng loại trụ
--     (truy vấn con vô hướng tương quan)
-- Câu hỏi  : phiên nào kéo dài hơn hai lần thời lượng trung bình của
--            loại cổng đó? (xe có thể bị kẹt hoặc bỏ quên)
-- Kỹ thuật : truy vấn con vô hướng trong WHERE, phép tính interval
-- Bảng     : service_session, charging_equipment, vehicle
-- -----------------------------------------------------------------------------
SELECT v.license_plate_text,
       ce.connector_type_code,
       (ss.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIMESTAMP(0) AS start_local,
       round(extract(epoch FROM (ss.end_datetime - ss.start_datetime)) / 3600.0, 2)
           AS duration_hours,
       ss.consumed_energy_kwh
FROM service_session AS ss
JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
WHERE ss.end_datetime IS NOT NULL
  AND ss.end_datetime - ss.start_datetime > 2 * (
        SELECT avg(x.end_datetime - x.start_datetime)
        FROM service_session AS x
        JOIN charging_equipment AS xe ON xe.equipment_identifier = x.equipment_identifier
        WHERE xe.connector_type_code = ce.connector_type_code
          AND x.end_datetime IS NOT NULL)
ORDER BY duration_hours DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Q6. Khách hàng dùng nhiều điện nhất mỗi tháng kèm xếp hạng (hàm cửa sổ)
-- Câu hỏi  : 3 khách tiêu thụ điện nhiều nhất mỗi tháng là ai?
-- Kỹ thuật : CTE, RANK() OVER (PARTITION BY ... ORDER BY ...), date_trunc
-- Bảng     : user_account, vehicle, service_session
-- -----------------------------------------------------------------------------
WITH monthly AS (
    SELECT date_trunc('month', ss.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE
               AS month_start,
           u.account_identifier,
           u.full_name_text,
           sum(ss.consumed_energy_kwh) AS total_kwh,
           count(*)                    AS session_count
    FROM service_session AS ss
    JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
    JOIN user_account AS u ON u.account_identifier = v.account_identifier
    WHERE ss.end_datetime IS NOT NULL
    GROUP BY 1, u.account_identifier, u.full_name_text
),
ranked AS (
    SELECT m.*,
           rank() OVER (PARTITION BY m.month_start ORDER BY m.total_kwh DESC) AS energy_rank
    FROM monthly AS m
)
SELECT month_start, energy_rank, full_name_text, total_kwh, session_count
FROM ranked
WHERE energy_rank <= 3
ORDER BY month_start, energy_rank;

-- -----------------------------------------------------------------------------
-- Q7. Doanh thu theo ngày kèm lũy kế và trung bình trượt 7 ngày
--     (khung cửa sổ)
-- Câu hỏi  : doanh thu thay đổi theo từng ngày ra sao?
-- Kỹ thuật : SUM() OVER (ORDER BY ...), AVG() OVER (ROWS BETWEEN 6 PRECEDING ...)
-- Bảng     : payment_transaction
-- -----------------------------------------------------------------------------
WITH daily AS (
    SELECT (p.created_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::DATE AS revenue_date,
           sum(p.transaction_amount_value) AS day_revenue
    FROM payment_transaction AS p
    WHERE p.transaction_status_code = 'SUCCESS'
    GROUP BY 1
)
SELECT revenue_date,
       day_revenue,
       sum(day_revenue) OVER (ORDER BY revenue_date) AS running_total,
       round(avg(day_revenue) OVER (ORDER BY revenue_date
                                    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0)
           AS moving_avg_7d
FROM daily
ORDER BY revenue_date
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Q8. Quá giờ (đỗ tiếp sau khi sạc đầy): ai chiếm trụ sạc quá lâu?
-- Câu hỏi  : xe nào trả phí quá giờ nhiều nhất, và phí quá giờ chiếm
--            bao nhiêu phần hóa đơn?
-- Kỹ thuật : GROUP BY, HAVING, tỷ lệ, NULLIF để tránh chia cho 0
-- Bảng     : payment_transaction, service_session, vehicle, user_account
-- -----------------------------------------------------------------------------
SELECT u.full_name_text,
       v.license_plate_text,
       count(*)                          AS invoice_count,
       sum(p.overtime_amount_value)      AS overtime_total,
       sum(p.transaction_amount_value)   AS bill_total,
       round(100 * sum(p.overtime_amount_value)
                 / nullif(sum(p.transaction_amount_value), 0), 1) AS overtime_percent
FROM payment_transaction AS p
JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
JOIN user_account AS u ON u.account_identifier = v.account_identifier
GROUP BY u.full_name_text, v.license_plate_text
HAVING sum(p.overtime_amount_value) > 100000
ORDER BY overtime_total DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Q9. Độ tin cậy trong đặt chỗ của khách (gộp nhóm có điều kiện)
-- Câu hỏi  : khách nào hay đặt nhưng không đến?
-- Kỹ thuật : COUNT(*) FILTER, HAVING, gộp theo tài khoản không dùng LEFT JOIN
-- Bảng     : reservation, vehicle, user_account
-- -----------------------------------------------------------------------------
SELECT u.full_name_text,
       count(*)                                                   AS total_bookings,
       count(*) FILTER (WHERE r.reservation_status_code = 'FULFILLED') AS fulfilled,
       count(*) FILTER (WHERE r.reservation_status_code = 'CANCELLED') AS cancelled,
       count(*) FILTER (WHERE r.reservation_status_code = 'EXPIRED')   AS no_show,
       round(100.0 * count(*) FILTER (WHERE r.reservation_status_code = 'EXPIRED')
             / count(*), 1)                                       AS no_show_percent
FROM reservation AS r
JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
JOIN user_account AS u ON u.account_identifier = v.account_identifier
GROUP BY u.account_identifier, u.full_name_text
HAVING count(*) FILTER (WHERE r.reservation_status_code = 'EXPIRED') >= 3
ORDER BY no_show_percent DESC, total_bookings DESC;

-- -----------------------------------------------------------------------------
-- Q10. Nhu cầu theo giờ trong ngày và khung giá áp dụng (chia nhóm thời gian)
-- Câu hỏi  : khách bắt đầu sạc vào giờ địa phương nào, và khung giá
--            có khớp với nhu cầu không?
-- Kỹ thuật : EXTRACT(HOUR ...), CASE, GROUP BY biểu thức, phần trăm trên tổng
-- Bảng     : service_session
-- -----------------------------------------------------------------------------
WITH by_hour AS (
    SELECT extract(hour FROM ss.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::INT
               AS start_hour,
           count(*)                    AS session_count,
           round(avg(ss.consumed_energy_kwh), 1) AS avg_kwh
    FROM service_session AS ss
    GROUP BY 1
)
SELECT h.start_hour,
       CASE WHEN h.start_hour BETWEEN 17 AND 19 THEN 'PEAK'
            WHEN h.start_hour >= 22 OR h.start_hour < 5 THEN 'OFF_PEAK'
            ELSE 'STANDARD' END AS time_band_code,
       h.session_count,
       h.avg_kwh,
       round(100.0 * h.session_count / sum(h.session_count) OVER (), 1) AS share_percent
FROM by_hour AS h
ORDER BY h.start_hour;

-- -----------------------------------------------------------------------------
-- Q11. Phiên đang sạc có thể cản lượt đặt kế tiếp trên cùng ô
--      (truy vấn theo trạng thái hiện tại, dùng now())
-- Câu hỏi  : phiên sạc đang chạy nào đụng với lượt đặt bắt đầu trong
--            3 giờ tới trên cùng ô đỗ?
-- Kỹ thuật : JOIN theo khoảng thời gian, so sánh interval, vận hành thời gian thực
-- Bảng     : service_session, charging_equipment, reservation, vehicle
-- Lưu ý    : trả về các dòng có từ lúc nạp dữ liệu mẫu; kết quả phụ thuộc
--            vào thời điểm hiện tại.
-- -----------------------------------------------------------------------------
SELECT f.facility_name_text,
       s.space_code,
       v_now.license_plate_text   AS charging_now,
       (ss.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIMESTAMP(0) AS started_local,
       r.reservation_status_code,
       v_next.license_plate_text  AS next_booking,
       (r.start_datetime AT TIME ZONE 'Asia/Ho_Chi_Minh')::TIMESTAMP(0) AS next_booking_start_local,
       round(extract(epoch FROM (r.start_datetime - now())) / 60.0)
           AS minutes_until_next_booking
FROM service_session AS ss
JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
JOIN vehicle AS v_now ON v_now.vehicle_identifier = ss.vehicle_identifier
JOIN reservation AS r
  ON r.space_identifier = s.space_identifier
 AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
 AND r.start_datetime BETWEEN now() AND now() + INTERVAL '3 hours'
JOIN vehicle AS v_next ON v_next.vehicle_identifier = r.vehicle_identifier
WHERE ss.end_datetime IS NULL
ORDER BY r.start_datetime;

-- -----------------------------------------------------------------------------
-- Q12. Giá trung bình mỗi kWh thực thu, theo loại cổng và mức công suất
--      (kiểm tra thiết kế biểu giá theo công suất)
-- Câu hỏi  : mức từ 100 kW và khung cao điểm có thật sự đắt hơn mỗi kWh?
-- Kỹ thuật : GROUP BY kết hợp JOIN biểu giá, trung bình có trọng số (SUM/SUM),
--            UNION ALL để thêm dòng tổng cộng
-- Bảng     : payment_transaction, tariff_rate, service_session
-- -----------------------------------------------------------------------------
SELECT t.connector_type_code,
       t.min_power_kw || ' - ' || t.max_power_kw AS power_range_kw,
       t.time_band_code,
       count(*)                  AS invoice_count,
       sum(ss.consumed_energy_kwh) AS total_kwh,
       round(sum(p.energy_amount_value) / nullif(sum(ss.consumed_energy_kwh), 0), 0)
           AS effective_price_per_kwh
FROM payment_transaction AS p
JOIN tariff_rate AS t ON t.rate_identifier = p.rate_identifier
JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
GROUP BY t.connector_type_code, t.min_power_kw, t.max_power_kw, t.time_band_code
UNION ALL
SELECT 'ALL', '-', '-',
       count(*), sum(ss.consumed_energy_kwh),
       round(sum(p.energy_amount_value) / nullif(sum(ss.consumed_energy_kwh), 0), 0)
FROM payment_transaction AS p
JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
ORDER BY 1, 2, 3;

-- -----------------------------------------------------------------------------
-- Q13. (cần PostGIS) Các bãi gần nhất hiện còn trụ sạc trống
-- Câu hỏi  : khách ở tọa độ (106.70, 10.78), ba bãi nào gần nhất và
--            còn ít nhất một trụ sẵn sàng, chưa bị đặt?
-- Kỹ thuật : KNN không gian (toán tử <-> dùng chỉ mục GiST), CTE, LATERAL
-- Bảng     : parking_facility, parking_space, charging_equipment
-- Lưu ý    : cần extension postgis; không chạy trong môi trường kiểm thử
--            dùng cho các truy vấn khác (ở đó không có PostGIS).
-- -----------------------------------------------------------------------------
SELECT f.facility_name_text,
       round(ST_DistanceSphere(
                 f.geographic_location,
                 ST_SetSRID(ST_MakePoint(106.70, 10.78), 4326))::NUMERIC, 0)
           AS distance_metre,
       free.free_charger_count
FROM parking_facility AS f
CROSS JOIN LATERAL (
    SELECT count(*) AS free_charger_count
    FROM parking_space AS s
    JOIN charging_equipment AS ce ON ce.space_identifier = s.space_identifier
    WHERE s.facility_identifier = f.facility_identifier
      AND s.availability_status_code = 'AVAILABLE'
      AND ce.equipment_status_code = 'READY'
) AS free
WHERE free.free_charger_count > 0
ORDER BY f.geographic_location
         <-> ST_SetSRID(ST_MakePoint(106.70, 10.78), 4326)
LIMIT 3;

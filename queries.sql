-- =============================================================================
-- Smart City EV Charging & Parking Management - analytical queries - v0.3.1
-- Run on a database loaded with schema.sql + seed.sql:
--     psql -d evt -f queries.sql
-- 12 queries (Q1-Q12) run on plain PostgreSQL; Q13 needs PostGIS.
-- Each query states the business question, the SQL features it shows and the
-- tables it touches. All times are shown in Asia/Ho_Chi_Minh.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Charging history of one customer, with invoice (JOIN of 7 tables)
-- Question : what did customer "Đặng Quốc Phong" charge, where and for how much?
-- Features : INNER/LEFT JOIN, ORDER BY, LIMIT
-- Tables   : user_account, vehicle, service_session, charging_equipment,
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
-- Q2. Revenue by facility and tariff band (aggregation + HAVING)
-- Question : which facility / band combinations earned more than 1,000,000 VND
--            from successful payments?
-- Features : GROUP BY, SUM/COUNT/AVG, HAVING
-- Tables   : payment_transaction, tariff_rate, service_session,
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
-- Q3. Charger utilisation per facility over the last 30 days of history
--     (CTE + conditional aggregation)
-- Question : what share of the available charger-hours was actually used?
-- Features : WITH (CTE), GREATEST/LEAST clipping of intervals, ratio
-- Tables   : service_session, charging_equipment, parking_space, parking_facility
-- Window   : 2026-09-27 .. 2026-10-27 (fixed so the result is reproducible)
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
-- Q4. Chargers that were never used in the last 30 days (NOT EXISTS anti-join)
-- Question : which chargers earn nothing and may need relocation or checking?
-- Features : correlated NOT EXISTS subquery
-- Tables   : charging_equipment, parking_space, parking_facility, service_session
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
-- Q5. Sessions much longer than the average of the same charger type
--     (correlated scalar subquery)
-- Question : which sessions lasted more than twice the average duration of
--            their connector type? (possible stuck or abandoned vehicles)
-- Features : scalar subquery in WHERE, interval arithmetic
-- Tables   : service_session, charging_equipment, vehicle
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
-- Q6. Top customers by energy per month with ranking (window function)
-- Question : who are the top 3 energy consumers in each month?
-- Features : CTE, RANK() OVER (PARTITION BY ... ORDER BY ...), date_trunc
-- Tables   : user_account, vehicle, service_session
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
-- Q7. Daily revenue with running total and 7-day moving average
--     (window frames)
-- Question : how does revenue evolve day by day?
-- Features : SUM() OVER (ORDER BY ...), AVG() OVER (ROWS BETWEEN 6 PRECEDING ...)
-- Tables   : payment_transaction
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
-- Q8. Overtime (idle after full charge): who occupies chargers too long?
-- Question : which vehicles pay the most overtime fees, and what share of
--            their bill is overtime?
-- Features : GROUP BY, HAVING, ratio, NULLIF to avoid division by zero
-- Tables   : payment_transaction, service_session, vehicle, user_account
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
-- Q9. Reliability of customers' reservations (conditional aggregation)
-- Question : which customers often book but do not show up?
-- Features : COUNT(*) FILTER, HAVING, LEFT JOIN-free aggregation by account
-- Tables   : reservation, vehicle, user_account
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
-- Q10. Demand by hour of day and applicable band (time bucketing)
-- Question : at which local hours do customers start charging, and is the
--            price band matched to demand?
-- Features : EXTRACT(HOUR ...), CASE, GROUP BY expression, percentage of total
-- Tables   : service_session
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
-- Q11. Running sessions that may block the next booking on the same space
--      (state-dependent query using now())
-- Question : which charging sessions started now collide with a booking that
--            begins within the next 3 hours on the same space?
-- Features : JOIN on time range, interval comparison, current-state operations
-- Tables   : service_session, charging_equipment, reservation, vehicle
-- Note     : returns the rows present when the seed was loaded; results depend
--            on the current time.
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
-- Q12. Average price per kWh actually charged, by connector type and power tier
--      (checks the power-based tariff design)
-- Question : do the 100+ kW tier and the peak band really cost more per kWh?
-- Features : GROUP BY with joins on the tariff, weighted average (SUM/SUM),
--            UNION ALL for a grand-total row
-- Tables   : payment_transaction, tariff_rate, service_session
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
-- Q13. (needs PostGIS) Nearest facilities that currently have a free charger
-- Question : from a customer at (106.70, 10.78), which three facilities are
--            closest and have at least one ready, unreserved charger?
-- Features : spatial KNN (<-> operator uses the GiST index), CTE, LATERAL
-- Tables   : parking_facility, parking_space, charging_equipment
-- Note     : requires the postgis extension; not run in the test environment
--            used for the other queries (no PostGIS there).
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

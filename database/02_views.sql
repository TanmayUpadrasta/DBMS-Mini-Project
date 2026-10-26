-- =====================================================================
--  File 2/5 : Views
--  Views hide the joins so the application (and the examiner) can ask
--  simple questions like "SELECT * FROM v_price_comparison".
-- =====================================================================
USE vehicle_rental_db;

-- ---------------------------------------------------------------------
-- Every vehicle with its catalogue, branch and provider details
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_vehicle_details AS
SELECT  v.vehicle_id, v.registration_no, v.color, v.manufacture_year,
        v.daily_rate, v.security_deposit, v.km_limit_per_day, v.extra_km_charge,
        v.status,
        m.model_id, m.brand, m.model_name, m.vehicle_type, m.fuel_type,
        m.transmission, m.seats,
        b.branch_id, b.branch_name, b.city,
        p.provider_id, p.provider_name, p.provider_type
FROM    vehicle   v
JOIN    car_model m ON m.model_id    = v.model_id
JOIN    branch    b ON b.branch_id   = v.branch_id
JOIN    provider  p ON p.provider_id = b.provider_id;

-- ---------------------------------------------------------------------
-- Provider rating = average of all reviews on rentals of its vehicles.
-- LEFT JOINs keep providers that have no reviews yet (rating NULL).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_provider_ratings AS
SELECT  p.provider_id, p.provider_name,
        ROUND(AVG(rv.rating), 1) AS avg_rating,
        COUNT(rv.review_id)      AS review_count
FROM    provider p
LEFT JOIN branch  b  ON b.provider_id = p.provider_id
LEFT JOIN vehicle v  ON v.branch_id   = b.branch_id
LEFT JOIN rental  r  ON r.vehicle_id  = v.vehicle_id
LEFT JOIN review  rv ON rv.rental_id  = r.rental_id
GROUP BY p.provider_id, p.provider_name;

-- ---------------------------------------------------------------------
-- THE CORE FEATURE: price of the same car at every provider branch.
-- (Date-independent snapshot; sp_compare_prices adds date availability.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_price_comparison AS
SELECT  m.model_id,
        CONCAT(m.brand, ' ', m.model_name)         AS car,
        m.fuel_type, m.transmission,
        b.city,
        p.provider_name, p.provider_type,
        b.branch_name,
        MIN(v.daily_rate)                          AS daily_rate,
        COUNT(*)                                   AS units_listed,
        SUM(v.status = 'Available')                AS units_available_now,
        RANK() OVER (PARTITION BY m.model_id, b.city
                     ORDER BY MIN(v.daily_rate))   AS price_rank
FROM    vehicle   v
JOIN    car_model m ON m.model_id    = v.model_id
JOIN    branch    b ON b.branch_id   = v.branch_id
JOIN    provider  p ON p.provider_id = b.provider_id
WHERE   v.status <> 'Retired' AND p.is_active = TRUE
GROUP BY m.model_id, m.brand, m.model_name, m.fuel_type, m.transmission,
         b.city, p.provider_name, p.provider_type, b.branch_name;

-- ---------------------------------------------------------------------
-- Per car & city: cheapest vs costliest offer and how much you save
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_model_price_summary AS
SELECT  m.model_id,
        CONCAT(m.brand, ' ', m.model_name)  AS car,
        m.vehicle_type, b.city,
        COUNT(DISTINCT p.provider_id)       AS providers,
        MIN(v.daily_rate)                   AS lowest_rate,
        MAX(v.daily_rate)                   AS highest_rate,
        ROUND(AVG(v.daily_rate), 0)         AS average_rate,
        ROUND((MAX(v.daily_rate) - MIN(v.daily_rate))
              / MAX(v.daily_rate) * 100, 1) AS max_saving_pct
FROM    vehicle   v
JOIN    car_model m ON m.model_id    = v.model_id
JOIN    branch    b ON b.branch_id   = v.branch_id
JOIN    provider  p ON p.provider_id = b.provider_id
WHERE   v.status <> 'Retired' AND p.is_active = TRUE
GROUP BY m.model_id, m.brand, m.model_name, m.vehicle_type, b.city;

-- ---------------------------------------------------------------------
-- Rentals with everything a receipt or a "My bookings" page needs
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_rental_details AS
SELECT  r.rental_id, r.status, r.booking_date,
        r.rental_date, r.expected_return_date, r.actual_return_date,
        DATEDIFF(r.expected_return_date, r.rental_date) AS planned_days,
        r.daily_rate_at_booking, r.base_amount, r.late_fee, r.total_amount,
        c.customer_id, c.name AS customer_name, c.phone AS customer_phone,
        vd.vehicle_id, vd.registration_no, vd.brand, vd.model_name,
        vd.vehicle_type, vd.branch_id, vd.branch_name, vd.city,
        vd.provider_id, vd.provider_name,
        e.name AS handled_by,
        pay.payment_mode, pay.payment_status, pay.amount AS amount_paid,
        rv.rating AS review_rating
FROM    rental r
JOIN    customer          c   ON c.customer_id = r.customer_id
JOIN    v_vehicle_details vd  ON vd.vehicle_id = r.vehicle_id
LEFT JOIN employee        e   ON e.employee_id = r.employee_id
LEFT JOIN payment         pay ON pay.rental_id = r.rental_id
LEFT JOIN review          rv  ON rv.rental_id  = r.rental_id;

-- ---------------------------------------------------------------------
-- Branch-wise activity & revenue report (from the case study)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_branch_revenue AS
SELECT  b.branch_id, b.branch_name, b.city, p.provider_name,
        (SELECT COUNT(*) FROM vehicle v2
          WHERE v2.branch_id = b.branch_id AND v2.status <> 'Retired') AS fleet_size,
        COUNT(r.rental_id)                                        AS total_rentals,
        SUM(r.status = 'Completed')                               AS completed,
        SUM(r.status IN ('Booked','Ongoing'))                     AS active,
        SUM(r.status = 'Cancelled')                               AS cancelled,
        COALESCE(SUM(CASE WHEN pay.payment_status = 'Paid'
                          THEN pay.amount END), 0)                AS revenue
FROM    branch   b
JOIN    provider p   ON p.provider_id = b.provider_id
LEFT JOIN vehicle v  ON v.branch_id   = b.branch_id
LEFT JOIN rental  r  ON r.vehicle_id  = v.vehicle_id
LEFT JOIN payment pay ON pay.rental_id = r.rental_id
GROUP BY b.branch_id, b.branch_name, b.city, p.provider_name;

-- ---------------------------------------------------------------------
-- What the platform earns from each provider (commission model)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_platform_earnings AS
SELECT  p.provider_id, p.provider_name, p.commission_pct,
        COUNT(pay.payment_id)                                  AS paid_rentals,
        COALESCE(SUM(pay.amount), 0)                           AS gross_value,
        ROUND(COALESCE(SUM(pay.amount), 0) * p.commission_pct / 100, 2) AS platform_commission,
        ROUND(COALESCE(SUM(pay.amount), 0) * (1 - p.commission_pct / 100), 2) AS provider_payout
FROM    provider p
LEFT JOIN branch  b   ON b.provider_id = p.provider_id
LEFT JOIN vehicle v   ON v.branch_id   = b.branch_id
LEFT JOIN rental  r   ON r.vehicle_id  = v.vehicle_id
LEFT JOIN payment pay ON pay.rental_id = r.rental_id AND pay.payment_status = 'Paid'
GROUP BY p.provider_id, p.provider_name, p.commission_pct;

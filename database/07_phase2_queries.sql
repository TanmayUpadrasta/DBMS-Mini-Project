-- Exp 8 - Project Phase II: SQL queries (joins, aggregates, subqueries)
USE vehicle_rental_db;

-- ===================== JOINS

-- Q1
SELECT r.rental_id, c.name AS customer, CONCAT(m.brand, ' ', m.model_name) AS car,
       p.provider_name, b.branch_name, r.rental_date, r.status
FROM rental r
INNER JOIN customer  c ON c.customer_id = r.customer_id
INNER JOIN vehicle   v ON v.vehicle_id  = r.vehicle_id
INNER JOIN car_model m ON m.model_id    = v.model_id
INNER JOIN branch    b ON b.branch_id   = v.branch_id
INNER JOIN provider  p ON p.provider_id = b.provider_id
WHERE r.status IN ('Booked', 'Ongoing')
ORDER BY r.rental_date;

-- Q2
SELECT c.customer_id, c.name, c.city, COUNT(r.rental_id) AS rentals
FROM customer c
LEFT JOIN rental r ON r.customer_id = c.customer_id
GROUP BY c.customer_id, c.name, c.city
ORDER BY rentals, c.name;

-- Q3
SELECT v.registration_no, CONCAT(m.brand, ' ', m.model_name) AS car,
       b.branch_name, v.status, r.rental_id
FROM rental r
RIGHT JOIN vehicle v ON v.vehicle_id = r.vehicle_id
JOIN car_model m ON m.model_id  = v.model_id
JOIN branch    b ON b.branch_id = v.branch_id
WHERE r.rental_id IS NULL AND b.branch_id = 1;

-- Q4
SELECT CONCAT(m.brand, ' ', m.model_name) AS car,
       pa.provider_name AS cheaper_provider, va.daily_rate AS cheaper_rate,
       pb.provider_name AS costlier_provider, vb.daily_rate AS costlier_rate,
       vb.daily_rate - va.daily_rate AS difference
FROM vehicle va
JOIN vehicle vb   ON vb.model_id = va.model_id AND vb.daily_rate > va.daily_rate
JOIN branch  ba   ON ba.branch_id = va.branch_id
JOIN branch  bb   ON bb.branch_id = vb.branch_id AND bb.city = ba.city
JOIN provider pa  ON pa.provider_id = ba.provider_id
JOIN provider pb  ON pb.provider_id = bb.provider_id AND pb.provider_id <> pa.provider_id
JOIN car_model m  ON m.model_id = va.model_id
WHERE m.model_name = 'Creta' AND ba.city = 'Mumbai'
GROUP BY car, cheaper_provider, cheaper_rate, costlier_provider, costlier_rate
ORDER BY difference DESC
LIMIT 6;

-- Q5
SELECT r.rental_id, c.name AS customer, e.name AS handled_by, e.role,
       pay.amount, pay.payment_mode, rv.rating
FROM rental r
JOIN customer  c   ON c.customer_id = r.customer_id
JOIN employee  e   ON e.employee_id = r.employee_id
JOIN payment   pay ON pay.rental_id = r.rental_id
LEFT JOIN review rv ON rv.rental_id = r.rental_id
WHERE r.status = 'Completed'
ORDER BY pay.amount DESC
LIMIT 6;

-- Q6
SELECT p.provider_name, m.vehicle_type
FROM provider p
CROSS JOIN (SELECT DISTINCT vehicle_type FROM car_model
            WHERE vehicle_type IN ('Luxury', 'Bike')) AS m
WHERE NOT EXISTS (SELECT 1 FROM vehicle v
                  JOIN branch b     ON b.branch_id = v.branch_id
                  JOIN car_model cm ON cm.model_id = v.model_id
                  WHERE b.provider_id = p.provider_id AND cm.vehicle_type = m.vehicle_type)
ORDER BY m.vehicle_type, p.provider_name;

-- ===================== AGGREGATE FUNCTIONS

-- Q7
SELECT COUNT(*) AS total_vehicles,
       COUNT(DISTINCT model_id) AS car_models,
       MIN(daily_rate) AS cheapest_rate,
       MAX(daily_rate) AS costliest_rate,
       ROUND(AVG(daily_rate), 2) AS average_rate,
       SUM(status = 'Available') AS available_now
FROM vehicle
WHERE status <> 'Retired';

-- Q8
SELECT b.city, p.provider_name,
       COUNT(r.rental_id) AS rentals,
       SUM(pay.amount) AS revenue,
       ROUND(AVG(pay.amount), 2) AS avg_bill
FROM payment pay
JOIN rental   r ON r.rental_id   = pay.rental_id
JOIN vehicle  v ON v.vehicle_id  = r.vehicle_id
JOIN branch   b ON b.branch_id   = v.branch_id
JOIN provider p ON p.provider_id = b.provider_id
WHERE pay.payment_status = 'Paid'
GROUP BY b.city, p.provider_name
ORDER BY b.city, revenue DESC;

-- Q9
SELECT CONCAT(m.brand, ' ', m.model_name) AS car, b.city,
       COUNT(DISTINCT b.provider_id) AS providers,
       MIN(v.daily_rate) AS lowest, MAX(v.daily_rate) AS highest,
       MAX(v.daily_rate) - MIN(v.daily_rate) AS spread
FROM vehicle v
JOIN car_model m ON m.model_id  = v.model_id
JOIN branch    b ON b.branch_id = v.branch_id
GROUP BY m.model_id, m.brand, m.model_name, b.city
HAVING COUNT(DISTINCT b.provider_id) >= 4
ORDER BY spread DESC;

-- Q10
SELECT p.provider_name,
       COUNT(rv.review_id) AS reviews,
       ROUND(AVG(rv.rating), 2) AS avg_rating,
       MIN(rv.rating) AS worst, MAX(rv.rating) AS best
FROM provider p
JOIN branch  b  ON b.provider_id = p.provider_id
JOIN vehicle v  ON v.branch_id   = b.branch_id
JOIN rental  r  ON r.vehicle_id  = v.vehicle_id
JOIN review  rv ON rv.rental_id  = r.rental_id
GROUP BY p.provider_name
HAVING COUNT(rv.review_id) >= 2
ORDER BY avg_rating DESC;

-- Q11
SELECT payment_mode,
       COUNT(*) AS payments,
       SUM(amount) AS total_amount,
       ROUND(100 * SUM(amount) / (SELECT SUM(amount) FROM payment
                                  WHERE payment_status = 'Paid'), 1) AS share_pct
FROM payment
WHERE payment_status = 'Paid'
GROUP BY payment_mode
ORDER BY total_amount DESC;

-- Q12
SELECT m.vehicle_type,
       COUNT(r.rental_id) AS rentals,
       SUM(DATEDIFF(r.expected_return_date, r.rental_date)) AS days_booked,
       SUM(r.late_fee) AS late_fees,
       SUM(r.total_amount) AS billed
FROM rental r
JOIN vehicle   v ON v.vehicle_id = r.vehicle_id
JOIN car_model m ON m.model_id   = v.model_id
WHERE r.status <> 'Cancelled'
GROUP BY m.vehicle_type
ORDER BY billed DESC;

-- ===================== SUBQUERIES

-- Q13
SELECT v.registration_no, CONCAT(m.brand, ' ', m.model_name) AS car, v.daily_rate
FROM vehicle v
JOIN car_model m ON m.model_id = v.model_id
WHERE v.daily_rate > (SELECT AVG(daily_rate) FROM vehicle)
  AND m.vehicle_type = 'SUV'
ORDER BY v.daily_rate DESC
LIMIT 6;

-- Q14
SELECT customer_id, name, phone, city
FROM customer
WHERE customer_id IN (SELECT r.customer_id
                      FROM rental r
                      JOIN vehicle   v ON v.vehicle_id = r.vehicle_id
                      JOIN car_model m ON m.model_id   = v.model_id
                      WHERE m.vehicle_type IN ('SUV', 'Luxury'));

-- Q15
SELECT CONCAT(m.brand, ' ', m.model_name) AS car, b.city,
       p.provider_name, b.branch_name, v.daily_rate
FROM vehicle v
JOIN car_model m ON m.model_id    = v.model_id
JOIN branch    b ON b.branch_id   = v.branch_id
JOIN provider  p ON p.provider_id = b.provider_id
WHERE v.daily_rate = (SELECT MIN(v2.daily_rate)
                      FROM vehicle v2
                      JOIN branch b2 ON b2.branch_id = v2.branch_id
                      WHERE v2.model_id = v.model_id AND b2.city = b.city)
  AND b.city = 'Mumbai'
GROUP BY car, b.city, p.provider_name, b.branch_name, v.daily_rate
ORDER BY car;

-- Q16
SELECT b.branch_name, p.provider_name, b.city
FROM branch b
JOIN provider p ON p.provider_id = b.provider_id
WHERE NOT EXISTS (SELECT 1
                  FROM vehicle v
                  JOIN rental r ON r.vehicle_id = v.vehicle_id
                  WHERE v.branch_id = b.branch_id
                    AND r.status IN ('Booked', 'Ongoing'));

-- Q17
SELECT t.provider_name, t.revenue, t.rentals
FROM (SELECT p.provider_name,
             SUM(pay.amount) AS revenue,
             COUNT(*)        AS rentals
      FROM payment pay
      JOIN rental   r ON r.rental_id   = pay.rental_id
      JOIN vehicle  v ON v.vehicle_id  = r.vehicle_id
      JOIN branch   b ON b.branch_id   = v.branch_id
      JOIN provider p ON p.provider_id = b.provider_id
      WHERE pay.payment_status = 'Paid'
      GROUP BY p.provider_name) AS t
WHERE t.revenue > (SELECT AVG(x.rev)
                   FROM (SELECT SUM(pay.amount) AS rev
                         FROM payment pay
                         JOIN rental   r ON r.rental_id   = pay.rental_id
                         JOIN vehicle  v ON v.vehicle_id  = r.vehicle_id
                         JOIN branch   b ON b.branch_id   = v.branch_id
                         WHERE pay.payment_status = 'Paid'
                         GROUP BY b.provider_id) AS x)
ORDER BY t.revenue DESC;

-- Q18
SELECT c.name, c.city,
       (SELECT COUNT(*) FROM rental r
         WHERE r.customer_id = c.customer_id AND r.status = 'Completed') AS completed,
       (SELECT COALESCE(SUM(pay.amount), 0)
          FROM payment pay JOIN rental r ON r.rental_id = pay.rental_id
         WHERE r.customer_id = c.customer_id AND pay.payment_status = 'Paid') AS total_spent
FROM customer c
WHERE c.customer_id = ANY (SELECT customer_id FROM rental WHERE late_fee > 0)
ORDER BY total_spent DESC;

-- Q19
SELECT v.registration_no, p.provider_name, v.daily_rate
FROM vehicle v
JOIN branch   b ON b.branch_id   = v.branch_id
JOIN provider p ON p.provider_id = b.provider_id
WHERE v.model_id = 9
  AND v.daily_rate > ALL (SELECT v.daily_rate
                        FROM vehicle v
                        JOIN branch b ON b.branch_id = v.branch_id
                        WHERE v.model_id = 9 AND b.provider_id = 4)
ORDER BY v.daily_rate DESC;

-- ===================== COMBINED

-- Q20
SELECT p.provider_name, b.branch_name,
       MIN(v.daily_rate)          AS daily_rate,
       MIN(v.daily_rate) * 2      AS trip_total_2_days,
       MIN(v.security_deposit)    AS deposit,
       COUNT(*)                   AS units_free,
       pr.avg_rating,
       MIN(v.daily_rate) - (SELECT MIN(v2.daily_rate)
                            FROM vehicle v2
                            JOIN branch b2 ON b2.branch_id = v2.branch_id
                            WHERE v2.model_id = m.model_id AND b2.city = b.city) AS above_cheapest
FROM vehicle v
JOIN car_model m ON m.model_id    = v.model_id
JOIN branch    b ON b.branch_id   = v.branch_id
JOIN provider  p ON p.provider_id = b.provider_id
LEFT JOIN (SELECT b3.provider_id, ROUND(AVG(rv.rating), 1) AS avg_rating
           FROM review rv
           JOIN rental  r3 ON r3.rental_id  = rv.rental_id
           JOIN vehicle v3 ON v3.vehicle_id = r3.vehicle_id
           JOIN branch  b3 ON b3.branch_id  = v3.branch_id
           GROUP BY b3.provider_id) AS pr ON pr.provider_id = p.provider_id
WHERE m.model_name = 'Swift' AND b.city = 'Mumbai'
  AND v.status = 'Available'
  AND NOT EXISTS (SELECT 1 FROM rental r
                  WHERE r.vehicle_id = v.vehicle_id
                    AND r.status IN ('Booked', 'Ongoing')
                    AND r.rental_date < CURDATE() + INTERVAL 3 DAY
                    AND CURDATE() + INTERVAL 1 DAY < r.expected_return_date)
GROUP BY p.provider_name, b.branch_name, pr.avg_rating, m.model_id, b.city
ORDER BY daily_rate, pr.avg_rating DESC;

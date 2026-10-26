-- =====================================================================
--  File 5/5 : Demonstration queries (run one block at a time in viva)
--  Each block is labelled with the DBMS concept it shows.
-- =====================================================================
USE vehicle_rental_db;

-- ---------------------------------------------------------------------
-- Q1  INNER JOIN + ORDER BY : every Swift in Mumbai, cheapest first
-- ---------------------------------------------------------------------
SELECT  p.provider_name, b.branch_name, v.registration_no, v.daily_rate
FROM    vehicle v
JOIN    car_model m ON m.model_id    = v.model_id
JOIN    branch    b ON b.branch_id   = v.branch_id
JOIN    provider  p ON p.provider_id = b.provider_id
WHERE   m.model_name = 'Swift' AND b.city = 'Mumbai'
ORDER BY v.daily_rate;

-- ---------------------------------------------------------------------
-- Q2  GROUP BY + HAVING : cars listed by 3 or more providers in a city
--     (only these make a meaningful price comparison)
-- ---------------------------------------------------------------------
SELECT  CONCAT(m.brand, ' ', m.model_name) AS car, b.city,
        COUNT(DISTINCT b.provider_id) AS providers,
        MIN(v.daily_rate) AS cheapest, MAX(v.daily_rate) AS costliest
FROM    vehicle v
JOIN    car_model m ON m.model_id  = v.model_id
JOIN    branch    b ON b.branch_id = v.branch_id
GROUP BY m.model_id, m.brand, m.model_name, b.city
HAVING  COUNT(DISTINCT b.provider_id) >= 3
ORDER BY providers DESC;

-- ---------------------------------------------------------------------
-- Q3  CORRELATED SUBQUERY : offers that are the cheapest for their car
--     in their city
-- ---------------------------------------------------------------------
SELECT  m.brand, m.model_name, b.city, p.provider_name, v.daily_rate
FROM    vehicle v
JOIN    car_model m ON m.model_id    = v.model_id
JOIN    branch    b ON b.branch_id   = v.branch_id
JOIN    provider  p ON p.provider_id = b.provider_id
WHERE   v.daily_rate = (SELECT MIN(v2.daily_rate)
                        FROM   vehicle v2
                        JOIN   branch  b2 ON b2.branch_id = v2.branch_id
                        WHERE  v2.model_id = v.model_id AND b2.city = b.city)
GROUP BY m.brand, m.model_name, b.city, p.provider_name, v.daily_rate
ORDER BY b.city, m.brand;

-- ---------------------------------------------------------------------
-- Q4  WINDOW FUNCTIONS : rank providers by price for each car, and show
--     how far each offer is above the cheapest one
-- ---------------------------------------------------------------------
SELECT  car, city, provider_name, branch_name, daily_rate,
        price_rank,
        daily_rate - MIN(daily_rate) OVER (PARTITION BY model_id, city) AS above_cheapest
FROM    v_price_comparison
WHERE   city = 'Mumbai'
ORDER BY car, price_rank;

-- ---------------------------------------------------------------------
-- Q5  LEFT JOIN + IS NULL : customers who have never rented
-- ---------------------------------------------------------------------
SELECT  c.customer_id, c.name, c.city
FROM    customer c
LEFT JOIN rental r ON r.customer_id = c.customer_id
WHERE   r.rental_id IS NULL;

-- ---------------------------------------------------------------------
-- Q6  NOT EXISTS : vehicles never rented (candidates for a price cut)
-- ---------------------------------------------------------------------
SELECT  vd.provider_name, vd.branch_name, vd.brand, vd.model_name,
        vd.registration_no, vd.daily_rate
FROM    v_vehicle_details vd
WHERE   NOT EXISTS (SELECT 1 FROM rental r WHERE r.vehicle_id = vd.vehicle_id)
  AND   vd.status = 'Available'
ORDER BY vd.provider_name;

-- ---------------------------------------------------------------------
-- Q7  STORED FUNCTION in a query : which units are free next weekend?
-- ---------------------------------------------------------------------
SELECT  vd.registration_no, vd.brand, vd.model_name, vd.provider_name
FROM    v_vehicle_details vd
WHERE   vd.city = 'Pune'
  AND   fn_is_vehicle_free(vd.vehicle_id,
                           CURDATE() + INTERVAL 1 DAY,
                           CURDATE() + INTERVAL 3 DAY);

-- ---------------------------------------------------------------------
-- Q8  STORED PROCEDURES : the two screens of the app
-- ---------------------------------------------------------------------
CALL sp_search_models('Mumbai', CURDATE() + INTERVAL 1 DAY, CURDATE() + INTERVAL 3 DAY, NULL);
CALL sp_compare_prices(1, 'Mumbai', CURDATE() + INTERVAL 1 DAY, CURDATE() + INTERVAL 3 DAY);

-- ---------------------------------------------------------------------
-- Q9  CASE + aggregation : monthly revenue split by payment mode
-- ---------------------------------------------------------------------
SELECT  DATE_FORMAT(payment_date, '%Y-%m')                     AS month,
        SUM(CASE WHEN payment_mode = 'UPI'  THEN amount ELSE 0 END) AS upi,
        SUM(CASE WHEN payment_mode = 'Card' THEN amount ELSE 0 END) AS card,
        SUM(CASE WHEN payment_mode NOT IN ('UPI','Card') THEN amount ELSE 0 END) AS others,
        SUM(amount)                                            AS total
FROM    payment
WHERE   payment_status = 'Paid'
GROUP BY month
ORDER BY month;

-- ---------------------------------------------------------------------
-- Q10 UNION : one contact list of all customers and provider owners
-- ---------------------------------------------------------------------
SELECT name AS person, phone, 'Customer' AS role FROM customer
UNION
SELECT owner_name, phone, CONCAT('Owner - ', provider_name) FROM provider
ORDER BY role, person;

-- ---------------------------------------------------------------------
-- Q11 REPORTS from views (branch-wise, platform commission, overdue)
-- ---------------------------------------------------------------------
SELECT * FROM v_branch_revenue    ORDER BY revenue DESC;
SELECT * FROM v_platform_earnings ORDER BY platform_commission DESC;

SELECT  rental_id, customer_name, customer_phone, brand, model_name,
        branch_name, expected_return_date,
        DATEDIFF(CURDATE(), expected_return_date) AS days_overdue
FROM    v_rental_details
WHERE   status = 'Ongoing' AND expected_return_date < CURDATE();

-- ---------------------------------------------------------------------
-- Q12 TRANSACTION + SAVEPOINT : raise all Mumbai Wheels prices by 5%,
--     undo the change for bikes and scooters only, keep the rest.
--     (Old rentals keep their price: daily_rate_at_booking is frozen.)
-- ---------------------------------------------------------------------
START TRANSACTION;
    UPDATE vehicle v
    JOIN   branch b ON b.branch_id = v.branch_id
    SET    v.daily_rate = ROUND(v.daily_rate * 1.05, -1)
    WHERE  b.provider_id = 2;
    SAVEPOINT after_hike;
    SELECT registration_no, daily_rate FROM vehicle WHERE branch_id IN (4, 5) LIMIT 5;
ROLLBACK TO SAVEPOINT after_hike;
ROLLBACK;        -- demo only: change this to COMMIT to keep the hike

-- ---------------------------------------------------------------------
-- Q13 TRIGGERS IN ACTION : each of these is rejected by the database
-- ---------------------------------------------------------------------
-- (a) double booking of a unit that is already rented out
-- INSERT INTO rental (customer_id, vehicle_id, rental_date, expected_return_date)
-- SELECT 1, vehicle_id, CURDATE(), CURDATE() + INTERVAL 1 DAY
-- FROM rental WHERE status = 'Ongoing' LIMIT 1;
--
-- (b) customer whose licence expires before the return date (Tanya, id 10)
-- CALL sp_book_rental(10, 4, 1, CURDATE() + INTERVAL 40 DAY, CURDATE() + INTERVAL 42 DAY, 'UPI', @id);
--
-- (c) reviewing a rental that is not completed
-- INSERT INTO review (rental_id, rating) SELECT rental_id, 5 FROM rental WHERE status = 'Booked' LIMIT 1;
--
-- (d) re-opening a completed rental
-- UPDATE rental SET status = 'Booked' WHERE rental_id = 1;

-- ---------------------------------------------------------------------
-- Q14 FULL LIFE-CYCLE of a booking (book -> pick up -> late return)
-- ---------------------------------------------------------------------
-- CALL sp_book_rental(1, 8, 1, CURDATE() + INTERVAL 1 DAY, CURDATE() + INTERVAL 3 DAY, 'UPI', @id);
-- SELECT @id;
-- CALL sp_start_rental(@id, 17);
-- CALL sp_return_vehicle(@id, CURDATE() + INTERVAL 4 DAY);      -- 1 day late
-- SELECT * FROM v_rental_details WHERE rental_id = @id;
-- SELECT * FROM rental_log      WHERE rental_id = @id;

-- ---------------------------------------------------------------------
-- Q15 INDEX usage : the overlap check uses idx_rental_vehicle_dates
-- ---------------------------------------------------------------------
EXPLAIN
SELECT 1 FROM rental
WHERE  vehicle_id = 5
  AND  status IN ('Booked','Ongoing')
  AND  rental_date < CURDATE() + INTERVAL 3 DAY;

-- ---------------------------------------------------------------------
-- Q16 DCL : a read-only analyst and an app user with limited rights
-- ---------------------------------------------------------------------
-- CREATE USER IF NOT EXISTS 'wd_analyst'@'localhost' IDENTIFIED BY 'Analyst@123';
-- GRANT SELECT ON vehicle_rental_db.* TO 'wd_analyst'@'localhost';
--
-- CREATE USER IF NOT EXISTS 'wd_app'@'localhost' IDENTIFIED BY 'App@123';
-- GRANT SELECT, INSERT ON vehicle_rental_db.customer TO 'wd_app'@'localhost';
-- GRANT SELECT ON vehicle_rental_db.*        TO 'wd_app'@'localhost';
-- GRANT EXECUTE ON vehicle_rental_db.*       TO 'wd_app'@'localhost';
-- -- the app cannot UPDATE rental/payment directly: only via the procedures
-- SHOW GRANTS FOR 'wd_app'@'localhost';

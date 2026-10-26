-- =====================================================================
--  File 3/5 : Stored functions, triggers and stored procedures
--  Business rules live in the database, so no client (web, mobile,
--  or a careless SQL user) can double-book a car or mis-bill a rental.
-- =====================================================================
USE vehicle_rental_db;

DROP FUNCTION  IF EXISTS fn_rental_days;
DROP FUNCTION  IF EXISTS fn_late_fee;
DROP FUNCTION  IF EXISTS fn_is_vehicle_free;
DROP TRIGGER   IF EXISTS trg_rental_before_insert;
DROP TRIGGER   IF EXISTS trg_rental_after_insert;
DROP TRIGGER   IF EXISTS trg_rental_before_update;
DROP TRIGGER   IF EXISTS trg_rental_after_update;
DROP TRIGGER   IF EXISTS trg_review_before_insert;
DROP PROCEDURE IF EXISTS sp_search_models;
DROP PROCEDURE IF EXISTS sp_compare_prices;
DROP PROCEDURE IF EXISTS sp_book_rental;
DROP PROCEDURE IF EXISTS sp_start_rental;
DROP PROCEDURE IF EXISTS sp_return_vehicle;
DROP PROCEDURE IF EXISTS sp_cancel_rental;

DELIMITER $$

-- =====================================================================
--  FUNCTIONS
-- =====================================================================

-- Number of billable days (a same-day rental is still 1 day)
CREATE FUNCTION fn_rental_days(p_start DATE, p_end DATE)
RETURNS INT
DETERMINISTIC NO SQL
BEGIN
    RETURN GREATEST(DATEDIFF(p_end, p_start), 1);
END$$

-- Late fee = each late day charged at 1.5x the booked daily rate
CREATE FUNCTION fn_late_fee(p_expected DATE, p_actual DATE, p_rate DECIMAL(8,2))
RETURNS DECIMAL(10,2)
DETERMINISTIC NO SQL
BEGIN
    IF p_actual IS NULL OR p_actual <= p_expected THEN
        RETURN 0;
    END IF;
    RETURN DATEDIFF(p_actual, p_expected) * p_rate * 1.5;
END$$

-- Is the vehicle free for [p_start, p_end)?  Two date ranges overlap when
-- start1 < end2 AND start2 < end1.  An overdue 'Ongoing' rental keeps the
-- car blocked until it is actually returned.
CREATE FUNCTION fn_is_vehicle_free(p_vehicle_id INT, p_start DATE, p_end DATE)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_status VARCHAR(20);

    SELECT status INTO v_status FROM vehicle WHERE vehicle_id = p_vehicle_id;
    IF v_status IS NULL OR v_status IN ('Maintenance', 'Retired') THEN
        RETURN FALSE;
    END IF;

    RETURN NOT EXISTS (
        SELECT 1
        FROM   rental r
        WHERE  r.vehicle_id = p_vehicle_id
          AND  r.status IN ('Booked', 'Ongoing')
          AND  r.rental_date < p_end
          AND  p_start < IF(r.status = 'Ongoing',
                            GREATEST(r.expected_return_date, CURDATE() + INTERVAL 1 DAY),
                            r.expected_return_date)
    );
END$$

-- =====================================================================
--  TRIGGERS
-- =====================================================================

-- Validate a new rental and calculate its bill automatically
CREATE TRIGGER trg_rental_before_insert
BEFORE INSERT ON rental
FOR EACH ROW
BEGIN
    DECLARE v_rate    DECIMAL(8,2);
    DECLARE v_vstatus VARCHAR(20);
    DECLARE v_expiry  DATE;

    SELECT daily_rate, status INTO v_rate, v_vstatus
    FROM   vehicle WHERE vehicle_id = NEW.vehicle_id;

    SELECT license_expiry INTO v_expiry
    FROM   customer WHERE customer_id = NEW.customer_id;

    IF v_vstatus IN ('Maintenance', 'Retired') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This vehicle is not in service right now';
    END IF;

    IF v_expiry < NEW.expected_return_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Driving licence expires before the return date';
    END IF;

    IF NEW.status IN ('Booked', 'Ongoing')
       AND NOT fn_is_vehicle_free(NEW.vehicle_id, NEW.rental_date, NEW.expected_return_date) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Double booking blocked: vehicle is already reserved for these dates';
    END IF;

    -- Automated billing: freeze today's price and compute the amounts
    SET NEW.daily_rate_at_booking = v_rate;
    SET NEW.base_amount  = fn_rental_days(NEW.rental_date, NEW.expected_return_date) * v_rate;
    SET NEW.late_fee     = fn_late_fee(NEW.expected_return_date, NEW.actual_return_date, v_rate);
    SET NEW.total_amount = NEW.base_amount + NEW.late_fee;
END$$

-- Keep vehicle.status in sync and write the audit log
CREATE TRIGGER trg_rental_after_insert
AFTER INSERT ON rental
FOR EACH ROW
BEGIN
    IF NEW.status = 'Ongoing' THEN
        UPDATE vehicle SET status = 'Rented' WHERE vehicle_id = NEW.vehicle_id;
    END IF;
    INSERT INTO rental_log (rental_id, old_status, new_status)
    VALUES (NEW.rental_id, NULL, NEW.status);
END$$

-- Enforce the status life-cycle and re-bill on return
--   Booked -> Ongoing -> Completed      Booked -> Cancelled
CREATE TRIGGER trg_rental_before_update
BEFORE UPDATE ON rental
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF OLD.status IN ('Completed', 'Cancelled') THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'A completed or cancelled rental cannot change status';
        END IF;
        IF OLD.status = 'Booked'  AND NEW.status = 'Completed' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Rental must be picked up (Ongoing) before it is completed';
        END IF;
        IF OLD.status = 'Ongoing' AND NEW.status IN ('Booked', 'Cancelled') THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'An ongoing rental can only be completed';
        END IF;
    END IF;

    IF NEW.status = 'Completed' AND NEW.actual_return_date IS NULL THEN
        SET NEW.actual_return_date = CURDATE();
    END IF;

    SET NEW.base_amount  = fn_rental_days(NEW.rental_date, NEW.expected_return_date)
                           * NEW.daily_rate_at_booking;
    SET NEW.late_fee     = fn_late_fee(NEW.expected_return_date, NEW.actual_return_date,
                                       NEW.daily_rate_at_booking);
    SET NEW.total_amount = NEW.base_amount + NEW.late_fee;
END$$

CREATE TRIGGER trg_rental_after_update
AFTER UPDATE ON rental
FOR EACH ROW
BEGIN
    IF NEW.status <> OLD.status THEN
        IF NEW.status = 'Ongoing' THEN
            UPDATE vehicle SET status = 'Rented'
            WHERE  vehicle_id = NEW.vehicle_id;
        ELSEIF NEW.status = 'Completed' THEN
            UPDATE vehicle SET status = 'Available'
            WHERE  vehicle_id = NEW.vehicle_id AND status = 'Rented';
        END IF;
        INSERT INTO rental_log (rental_id, old_status, new_status)
        VALUES (NEW.rental_id, OLD.status, NEW.status);
    END IF;
END$$

-- Only customers who finished a rental may review it
CREATE TRIGGER trg_review_before_insert
BEFORE INSERT ON review
FOR EACH ROW
BEGIN
    IF (SELECT status FROM rental WHERE rental_id = NEW.rental_id) <> 'Completed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'You can review a rental only after it is completed';
    END IF;
END$$

-- =====================================================================
--  PROCEDURES
-- =====================================================================

-- Home screen: every car available in a city for the dates, with its
-- cheapest and costliest offer (like a restaurant list with "from Rs X")
CREATE PROCEDURE sp_search_models(
    IN p_city  VARCHAR(50),
    IN p_start DATE,
    IN p_end   DATE,
    IN p_type  VARCHAR(20)          -- NULL or '' = all types
)
BEGIN
    SELECT  m.model_id, m.brand, m.model_name, m.vehicle_type,
            m.fuel_type, m.transmission, m.seats,
            COUNT(DISTINCT b.provider_id)   AS providers,
            COUNT(*)                        AS units_free,
            MIN(v.daily_rate)               AS lowest_rate,
            MAX(v.daily_rate)               AS highest_rate,
            ROUND((MAX(v.daily_rate) - MIN(v.daily_rate))
                  / MAX(v.daily_rate) * 100) AS max_saving_pct
    FROM    car_model m
    JOIN    vehicle   v ON v.model_id    = m.model_id
    JOIN    branch    b ON b.branch_id   = v.branch_id
    JOIN    provider  p ON p.provider_id = b.provider_id
    WHERE   b.city = p_city
      AND   p.is_active = TRUE
      AND   (p_type IS NULL OR p_type = '' OR m.vehicle_type = p_type)
      AND   fn_is_vehicle_free(v.vehicle_id, p_start, p_end)
    GROUP BY m.model_id, m.brand, m.model_name, m.vehicle_type,
             m.fuel_type, m.transmission, m.seats
    ORDER BY providers DESC, lowest_rate ASC;
END$$

-- Detail screen: the SAME car at every provider branch, ranked by price
CREATE PROCEDURE sp_compare_prices(
    IN p_model_id INT,
    IN p_city     VARCHAR(50),
    IN p_start    DATE,
    IN p_end      DATE
)
BEGIN
    DECLARE v_days INT DEFAULT fn_rental_days(p_start, p_end);

    SELECT  offers.*,
            RANK() OVER (ORDER BY offers.daily_rate)           AS price_rank,
            MAX(offers.trip_total) OVER () - offers.trip_total AS saving_vs_costliest
    FROM (
        SELECT  p.provider_id, p.provider_name, p.provider_type,
                b.branch_id, b.branch_name, b.address,
                MIN(v.daily_rate)          AS daily_rate,
                v_days                     AS days,
                MIN(v.daily_rate) * v_days AS trip_total,
                MIN(v.security_deposit)    AS security_deposit,
                MIN(v.km_limit_per_day)    AS km_limit_per_day,
                MIN(v.extra_km_charge)     AS extra_km_charge,
                COUNT(*)                   AS units_free,
                pr.avg_rating, pr.review_count
        FROM    vehicle  v
        JOIN    branch   b  ON b.branch_id   = v.branch_id
        JOIN    provider p  ON p.provider_id = b.provider_id
        LEFT JOIN v_provider_ratings pr ON pr.provider_id = p.provider_id
        WHERE   v.model_id = p_model_id
          AND   b.city     = p_city
          AND   p.is_active = TRUE
          AND   fn_is_vehicle_free(v.vehicle_id, p_start, p_end)
        GROUP BY p.provider_id, p.provider_name, p.provider_type,
                 b.branch_id, b.branch_name, b.address,
                 pr.avg_rating, pr.review_count
    ) AS offers
    ORDER BY offers.daily_rate ASC, offers.avg_rating DESC;
END$$

-- Book the cheapest free unit of a car at a branch: rental + payment are
-- written in ONE transaction, so either both exist or neither does.
CREATE PROCEDURE sp_book_rental(
    IN  p_customer_id INT,
    IN  p_branch_id   INT,
    IN  p_model_id    INT,
    IN  p_start       DATE,
    IN  p_end         DATE,
    IN  p_mode        VARCHAR(20),
    OUT p_rental_id   INT
)
BEGIN
    DECLARE v_vehicle_id INT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;                       -- pass the original error to the caller
    END;

    IF p_start < CURDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pickup date cannot be in the past';
    END IF;
    IF p_end <= p_start THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Return date must be after pickup date';
    END IF;

    START TRANSACTION;

    -- Lock the chosen vehicle row so two users cannot grab it together
    SELECT v.vehicle_id INTO v_vehicle_id
    FROM   vehicle v
    WHERE  v.branch_id = p_branch_id
      AND  v.model_id  = p_model_id
      AND  fn_is_vehicle_free(v.vehicle_id, p_start, p_end)
    ORDER BY v.daily_rate, v.vehicle_id
    LIMIT 1
    FOR UPDATE;

    IF v_vehicle_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Sorry, this car was just booked at this branch. Pick another offer.';
    END IF;

    INSERT INTO rental (customer_id, vehicle_id, rental_date, expected_return_date, status)
    VALUES (p_customer_id, v_vehicle_id, p_start, p_end, 'Booked');

    SET p_rental_id = LAST_INSERT_ID();

    -- Prepaid booking: payment row copies the trigger-computed total
    INSERT INTO payment (rental_id, amount, payment_mode, payment_status)
    SELECT rental_id, total_amount, p_mode, 'Paid'
    FROM   rental
    WHERE  rental_id = p_rental_id;

    COMMIT;
END$$

-- Customer picks up the car at the branch
CREATE PROCEDURE sp_start_rental(IN p_rental_id INT, IN p_employee_id INT)
BEGIN
    IF (SELECT status FROM rental WHERE rental_id = p_rental_id) <> 'Booked' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a booked rental can be started';
    END IF;
    UPDATE rental
    SET    status = 'Ongoing', employee_id = p_employee_id
    WHERE  rental_id = p_rental_id;
END$$

-- Customer returns the car: trigger adds any late fee, payment is topped up
CREATE PROCEDURE sp_return_vehicle(IN p_rental_id INT, IN p_return_date DATE)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF (SELECT status FROM rental WHERE rental_id = p_rental_id FOR UPDATE) <> 'Ongoing' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an ongoing rental can be returned';
    END IF;

    UPDATE rental
    SET    actual_return_date = COALESCE(p_return_date, CURDATE()),
           status             = 'Completed'
    WHERE  rental_id = p_rental_id;

    UPDATE payment pay
    JOIN   rental r ON r.rental_id = pay.rental_id
    SET    pay.amount         = r.total_amount,
           pay.payment_status = 'Paid',
           pay.payment_date   = NOW()
    WHERE  pay.rental_id = p_rental_id;

    COMMIT;
END$$

-- Cancel a booking before pickup and refund it
CREATE PROCEDURE sp_cancel_rental(IN p_rental_id INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF (SELECT status FROM rental WHERE rental_id = p_rental_id FOR UPDATE) <> 'Booked' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a booking that has not been picked up can be cancelled';
    END IF;

    UPDATE rental SET status = 'Cancelled' WHERE rental_id = p_rental_id;

    UPDATE payment
    SET    payment_status = IF(payment_status = 'Paid', 'Refunded', 'Cancelled')
    WHERE  rental_id = p_rental_id;

    COMMIT;
END$$

DELIMITER ;

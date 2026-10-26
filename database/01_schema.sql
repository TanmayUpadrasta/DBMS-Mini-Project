-- =====================================================================
--  WheelDeal : Vehicle Rental Management System with Price Comparison
--  File 1/5  : Schema (DDL)
--  DBMS      : MySQL 8.0+
--  Group 17, Div D, Batch B  -  SPIT, Mumbai
-- =====================================================================
--  The original ER diagram had 6 entities. To support a Zomato-style
--  marketplace where many providers list the SAME car at DIFFERENT
--  prices, the design adds:
--    PROVIDER   - the rental company / independent owner (like a restaurant)
--    CAR_MODEL  - the shared catalogue of cars (like a dish on many menus)
--    REVIEW     - customer ratings, used to rank providers
--  and splits VEHICLE so that brand/model/type live in CAR_MODEL (3NF):
--  VEHICLE now holds only per-unit facts (registration, rate, status).
-- =====================================================================

DROP DATABASE IF EXISTS vehicle_rental_db;
CREATE DATABASE vehicle_rental_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE vehicle_rental_db;

-- ---------------------------------------------------------------------
-- PROVIDER : an agency (Zoomcar-like) or an independent owner
-- ---------------------------------------------------------------------
CREATE TABLE provider (
    provider_id     INT            AUTO_INCREMENT PRIMARY KEY,
    provider_name   VARCHAR(100)   NOT NULL UNIQUE,
    provider_type   ENUM('Agency','Independent') NOT NULL DEFAULT 'Agency',
    owner_name      VARCHAR(100)   NOT NULL,
    phone           VARCHAR(15)    NOT NULL UNIQUE,
    email           VARCHAR(100)   NOT NULL UNIQUE,
    commission_pct  DECIMAL(4,2)   NOT NULL DEFAULT 10.00,   -- platform's cut
    joined_on       DATE           NOT NULL,
    is_active       BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_provider_commission CHECK (commission_pct BETWEEN 0 AND 50)
);

-- ---------------------------------------------------------------------
-- BRANCH : a pickup location owned by a provider
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    branch_id       INT            AUTO_INCREMENT PRIMARY KEY,
    provider_id     INT            NOT NULL,
    branch_name     VARCHAR(100)   NOT NULL,
    city            VARCHAR(50)    NOT NULL,
    address         VARCHAR(255)   NOT NULL,
    pincode         CHAR(6)        NOT NULL,
    phone           VARCHAR(15)    NOT NULL,
    CONSTRAINT fk_branch_provider FOREIGN KEY (provider_id)
        REFERENCES provider(provider_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT uq_branch_name UNIQUE (provider_id, branch_name),
    INDEX idx_branch_city (city)
);

-- ---------------------------------------------------------------------
-- EMPLOYEE : staff working at one branch
-- ---------------------------------------------------------------------
CREATE TABLE employee (
    employee_id     INT            AUTO_INCREMENT PRIMARY KEY,
    branch_id       INT            NOT NULL,
    name            VARCHAR(100)   NOT NULL,
    role            ENUM('Manager','Executive','Mechanic','Driver') NOT NULL,
    phone           VARCHAR(15)    NOT NULL UNIQUE,
    email           VARCHAR(100)   NOT NULL UNIQUE,
    hire_date       DATE           NOT NULL,
    CONSTRAINT fk_employee_branch FOREIGN KEY (branch_id)
        REFERENCES branch(branch_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ---------------------------------------------------------------------
-- CAR_MODEL : common catalogue so the same car can be compared
--             across providers (Swift Petrol Manual is ONE row)
-- ---------------------------------------------------------------------
CREATE TABLE car_model (
    model_id        INT            AUTO_INCREMENT PRIMARY KEY,
    brand           VARCHAR(50)    NOT NULL,
    model_name      VARCHAR(50)    NOT NULL,
    vehicle_type    ENUM('Hatchback','Sedan','SUV','MUV','Luxury','Bike','Scooter') NOT NULL,
    fuel_type       ENUM('Petrol','Diesel','CNG','Electric','Hybrid') NOT NULL,
    transmission    ENUM('Manual','Automatic') NOT NULL,
    seats           TINYINT        NOT NULL,
    CONSTRAINT uq_car_model UNIQUE (brand, model_name, fuel_type, transmission),
    CONSTRAINT chk_seats CHECK (seats BETWEEN 1 AND 12)
);

-- ---------------------------------------------------------------------
-- VEHICLE : one physical vehicle listed by a branch at its own price
-- ---------------------------------------------------------------------
CREATE TABLE vehicle (
    vehicle_id        INT           AUTO_INCREMENT PRIMARY KEY,
    model_id          INT           NOT NULL,
    branch_id         INT           NOT NULL,
    registration_no   VARCHAR(15)   NOT NULL UNIQUE,
    manufacture_year  SMALLINT      NOT NULL,
    color             VARCHAR(30)   NOT NULL,
    daily_rate        DECIMAL(8,2)  NOT NULL,          -- provider's own price
    security_deposit  DECIMAL(8,2)  NOT NULL DEFAULT 0,
    km_limit_per_day  INT           NOT NULL DEFAULT 250,
    extra_km_charge   DECIMAL(6,2)  NOT NULL DEFAULT 10,
    status            ENUM('Available','Rented','Maintenance','Retired')
                                    NOT NULL DEFAULT 'Available',
    CONSTRAINT fk_vehicle_model  FOREIGN KEY (model_id)
        REFERENCES car_model(model_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_vehicle_branch FOREIGN KEY (branch_id)
        REFERENCES branch(branch_id)   ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_vehicle_rate    CHECK (daily_rate > 0),
    CONSTRAINT chk_vehicle_deposit CHECK (security_deposit >= 0),
    CONSTRAINT chk_vehicle_year    CHECK (manufacture_year BETWEEN 2000 AND 2100),
    INDEX idx_vehicle_model_status (model_id, status)
);

-- ---------------------------------------------------------------------
-- CUSTOMER
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id     INT            AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100)   NOT NULL,
    phone           VARCHAR(15)    NOT NULL UNIQUE,
    email           VARCHAR(100)   NOT NULL UNIQUE,
    address         VARCHAR(255),
    city            VARCHAR(50)    NOT NULL,
    license_no      VARCHAR(20)    NOT NULL UNIQUE,
    license_expiry  DATE           NOT NULL,
    registered_on   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- RENTAL : one booking of one vehicle by one customer
--   daily_rate_at_booking freezes the price, so later price changes by
--   the provider do not alter old bills.
-- ---------------------------------------------------------------------
CREATE TABLE rental (
    rental_id              INT           AUTO_INCREMENT PRIMARY KEY,
    customer_id            INT           NOT NULL,
    vehicle_id             INT           NOT NULL,
    employee_id            INT           NULL,             -- staff who handled it
    booking_date           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rental_date            DATE          NOT NULL,         -- pickup date
    expected_return_date   DATE          NOT NULL,
    actual_return_date     DATE          NULL,
    daily_rate_at_booking  DECIMAL(8,2)  NOT NULL DEFAULT 0,   -- set by trigger
    base_amount            DECIMAL(10,2) NOT NULL DEFAULT 0,   -- set by trigger
    late_fee               DECIMAL(10,2) NOT NULL DEFAULT 0,   -- set by trigger
    total_amount           DECIMAL(10,2) NOT NULL DEFAULT 0,   -- set by trigger
    status                 ENUM('Booked','Ongoing','Completed','Cancelled')
                                         NOT NULL DEFAULT 'Booked',
    CONSTRAINT fk_rental_customer FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_rental_vehicle  FOREIGN KEY (vehicle_id)
        REFERENCES vehicle(vehicle_id)   ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_rental_employee FOREIGN KEY (employee_id)
        REFERENCES employee(employee_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_rental_dates  CHECK (expected_return_date > rental_date),
    CONSTRAINT chk_rental_return CHECK (actual_return_date IS NULL
                                        OR actual_return_date >= rental_date),
    INDEX idx_rental_vehicle_dates (vehicle_id, rental_date, expected_return_date),
    INDEX idx_rental_status (status)
);

-- ---------------------------------------------------------------------
-- PAYMENT : exactly one per rental (1 : 1 via UNIQUE foreign key)
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    payment_id      INT            AUTO_INCREMENT PRIMARY KEY,
    rental_id       INT            NOT NULL UNIQUE,
    amount          DECIMAL(10,2)  NOT NULL,
    payment_date    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_mode    ENUM('UPI','Card','Cash','NetBanking','Wallet') NOT NULL,
    payment_status  ENUM('Pending','Paid','Refunded','Cancelled') NOT NULL DEFAULT 'Pending',
    CONSTRAINT fk_payment_rental FOREIGN KEY (rental_id)
        REFERENCES rental(rental_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_payment_amount CHECK (amount >= 0)
);

-- ---------------------------------------------------------------------
-- REVIEW : at most one per rental, only after it is completed (trigger)
-- ---------------------------------------------------------------------
CREATE TABLE review (
    review_id       INT            AUTO_INCREMENT PRIMARY KEY,
    rental_id       INT            NOT NULL UNIQUE,
    rating          TINYINT        NOT NULL,
    comment         VARCHAR(500),
    review_date     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_review_rental FOREIGN KEY (rental_id)
        REFERENCES rental(rental_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5)
);

-- ---------------------------------------------------------------------
-- RENTAL_LOG : audit trail of every rental status change (filled by
--              trigger, never written to directly by the application)
-- ---------------------------------------------------------------------
CREATE TABLE rental_log (
    log_id          INT            AUTO_INCREMENT PRIMARY KEY,
    rental_id       INT            NOT NULL,
    old_status      VARCHAR(20),
    new_status      VARCHAR(20)    NOT NULL,
    changed_at      DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_log_rental FOREIGN KEY (rental_id)
        REFERENCES rental(rental_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- API_QUERY_LOG : every SQL statement the website runs (written by the
--                 backend) so it can be watched in MySQL Workbench.
--                 See 06_query_log.sql for ready-made queries.
-- ---------------------------------------------------------------------
CREATE TABLE api_query_log (
    log_id         INT           AUTO_INCREMENT PRIMARY KEY,
    logged_at      DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    endpoint       VARCHAR(100)  NOT NULL,
    sql_text       TEXT          NOT NULL,
    duration_ms    INT           NOT NULL DEFAULT 0,
    rows_returned  INT           NULL,
    status         ENUM('OK','Error') NOT NULL DEFAULT 'OK',
    error_message  VARCHAR(500)  NULL,
    INDEX idx_qlog_time (logged_at)
);

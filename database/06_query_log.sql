-- =====================================================================
--  File 6 : See the website's SQL live in MySQL Workbench
-- ---------------------------------------------------------------------
--  Every statement the website sends to MySQL is saved in api_query_log
--  by the backend. Run PART A once (safe to re-run; keeps old logs).
--  Then use the queries in PART B: click around the website, come back
--  here and press Ctrl+Enter on a query to see what it ran.
-- =====================================================================
USE vehicle_rental_db;

-- ---------------------------------------------------------------------
-- PART A : the log table (run once)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS api_query_log (
    log_id         INT           AUTO_INCREMENT PRIMARY KEY,
    logged_at      DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    endpoint       VARCHAR(100)  NOT NULL,            -- e.g. GET /api/models
    sql_text       TEXT          NOT NULL,            -- statement with values filled in
    duration_ms    INT           NOT NULL DEFAULT 0,
    rows_returned  INT           NULL,
    status         ENUM('OK','Error') NOT NULL DEFAULT 'OK',
    error_message  VARCHAR(500)  NULL,                -- e.g. trigger SIGNAL text
    INDEX idx_qlog_time (logged_at)
);

-- ---------------------------------------------------------------------
-- PART B : queries to watch the log  (put cursor on one, Ctrl+Enter)
-- ---------------------------------------------------------------------

-- B1  Latest 30 statements, newest first
SELECT log_id, TIME(logged_at) AS at_time, endpoint, sql_text,
       rows_returned, duration_ms, status, error_message
FROM   api_query_log
ORDER BY log_id DESC
LIMIT  30;

-- B2  Only what happened in the last 5 minutes
SELECT TIME(logged_at) AS at_time, endpoint, sql_text, status, error_message
FROM   api_query_log
WHERE  logged_at >= NOW() - INTERVAL 5 MINUTE
ORDER BY log_id DESC;

-- B3  Only the stored-procedure calls (search, compare, book, return …)
SELECT TIME(logged_at) AS at_time, endpoint, sql_text, status, error_message
FROM   api_query_log
WHERE  sql_text LIKE 'CALL %'
ORDER BY log_id DESC
LIMIT  20;

-- B4  Requests the database REJECTED (double booking, licence, etc.)
SELECT TIME(logged_at) AS at_time, endpoint, sql_text, error_message
FROM   api_query_log
WHERE  status = 'Error'
ORDER BY log_id DESC;

-- B5  Which screens hit the database most, and how fast
SELECT endpoint,
       COUNT(*)                  AS statements,
       ROUND(AVG(duration_ms),1) AS avg_ms,
       MAX(duration_ms)          AS max_ms,
       SUM(status = 'Error')     AS errors
FROM   api_query_log
GROUP BY endpoint
ORDER BY statements DESC;

-- B6  Copy-and-run: take any sql_text from B1 and run it here to get the
--     exact same result the website showed. Example:
-- CALL sp_compare_prices(1, 'Mumbai', CURDATE() + INTERVAL 1 DAY, CURDATE() + INTERVAL 3 DAY);

-- B7  Clear the log before a demo (keeps the table)
-- TRUNCATE TABLE api_query_log;

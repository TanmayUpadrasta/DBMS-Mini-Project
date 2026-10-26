// MySQL connection pool + a tiny helper that records every SQL statement
// a request runs:
//   1. sent back with the response, so the website's SQL drawer can show it
//   2. saved in the table api_query_log, so it can be watched in MySQL Workbench
const mysql = require('mysql2/promise');

// Cloud MySQL (Aiven, Railway, ...) needs an encrypted connection: set DB_SSL=true.
// DB_CA_CERT can hold the provider's CA certificate (the full -----BEGIN ... text)
// for strict verification; without it the connection is still encrypted.
function sslOptions() {
  if ((process.env.DB_SSL || 'false').toLowerCase() !== 'true') return undefined;
  const ca = process.env.DB_CA_CERT;
  return ca ? { ca: ca.replace(/\\n/g, '\n'), rejectUnauthorized: true } : { rejectUnauthorized: false };
}

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'vehicle_rental_db',
  ssl: sslOptions(),
  connectionLimit: Number(process.env.DB_POOL_SIZE || 5),   // small: serverless runs many copies
  dateStrings: true,          // return DATE/DATETIME as 'YYYY-MM-DD' strings (no timezone shifts)
  decimalNumbers: true,       // return DECIMAL as JS numbers
});

// Cloud servers run on UTC; make CURDATE()/NOW() follow Indian time so
// "today" in the database matches "today" on the website.
const TZ = process.env.DB_TIMEZONE || '+05:30';
pool.on('connection', (conn) => { conn.query('SET time_zone = ?', [TZ]); });

// Set LOG_QUERIES=false in .env to stop saving queries to api_query_log
const SAVE_TO_DB = (process.env.LOG_QUERIES || 'true').toLowerCase() !== 'false';
let warnedMissingTable = false;

// Saves one executed statement into api_query_log. Runs in the background and
// never breaks the request. The log INSERT itself is not logged.
function saveQuery(endpoint, sqlText, ms, error, rows) {
  if (!SAVE_TO_DB) return;
  pool.query(
    `INSERT INTO api_query_log (endpoint, sql_text, duration_ms, rows_returned, status, error_message)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [endpoint, sqlText, ms, rows, error ? 'Error' : 'OK', error ? String(error).slice(0, 500) : null],
  ).catch((err) => {
    if (!warnedMissingTable) {
      warnedMissingTable = true;
      console.warn('Query log not saved (' + err.message + '). Run database/06_query_log.sql once.');
    }
  });
}

// Counts rows in a result: plain SELECT → array, CALL → [rows, info]
function countRows(result) {
  if (!Array.isArray(result)) return result && result.affectedRows != null ? result.affectedRows : null;
  if (Array.isArray(result[0])) return result[0].length;
  return result.length;
}

// Creates a per-request runner. `endpoint` is e.g. "GET /api/models".
function createRunner(conn = pool, endpoint = '') {
  const log = [];
  async function run(sql, params = []) {
    const text = mysql.format(sql, params).replace(/\s+/g, ' ').trim();
    log.push(text);
    const t0 = Date.now();
    try {
      const [result] = await conn.query(sql, params);
      saveQuery(endpoint, text, Date.now() - t0, null, countRows(result));
      return result;
    } catch (err) {
      saveQuery(endpoint, text, Date.now() - t0, err.sqlMessage || err.message, null);
      throw err;
    }
  }
  return { run, log };
}

module.exports = { pool, createRunner };

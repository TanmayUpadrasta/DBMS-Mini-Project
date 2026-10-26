// WheelDeal API — a thin REST layer over the MySQL views and stored
// procedures. All business rules (pricing, double-booking, late fees,
// status changes) are enforced inside MySQL, not here.
require('dotenv').config();
const path = require('path');
const express = require('express');
const { pool, createRunner } = require('./db');

const app = express();
app.use(express.json());
// Locally Express serves the website from /public. On Vercel this line is
// ignored and Vercel's CDN serves /public instead.
app.use(express.static(path.join(__dirname, 'public')));

// Wraps a route: gives it a SQL runner and returns { data, sql } as JSON
const route = (handler) => async (req, res) => {
  const db = createRunner(pool, `${req.method} ${req.path}`);
  try {
    const data = await handler(req, db);
    res.json({ data, sql: db.log });
  } catch (err) {
    const { status, message } = describeError(err);
    if (status === 500) console.error(err);
    res.status(status).json({ error: message, sql: db.log });
  }
};

// Turns MySQL errors into messages a user can read
function describeError(err) {
  if (err.status) return err;                                  // thrown by us
  if (err.sqlState === '45000') return { status: 400, message: err.sqlMessage }; // SIGNAL from a trigger/procedure
  if (err.code === 'ER_DUP_ENTRY') {
    const field = (err.sqlMessage.match(/for key '(?:\w+\.)?(\w+)'/) || [])[1] || 'value';
    return { status: 409, message: `That ${field.replace('_', ' ')} is already registered` };
  }
  if (err.code === 'ER_CHECK_CONSTRAINT_VIOLATED') return { status: 400, message: err.sqlMessage };
  if (err.code === 'ECONNREFUSED' || err.code === 'ER_ACCESS_DENIED_ERROR' || err.code === 'ER_BAD_DB_ERROR') {
    return { status: 500, message: 'Cannot reach the database. Check the DB_* settings (.env locally, Environment Variables on Vercel) and that MySQL is running.' };
  }
  return { status: 500, message: 'Something went wrong on the server' };
}

const fail = (status, message) => Object.assign(new Error(message), { status, message });
const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || '');

function readTrip(q) {
  const { city, start, end } = q;
  if (!city || !isDate(start) || !isDate(end)) throw fail(400, 'City, pickup date and return date are required');
  if (end <= start) throw fail(400, 'Return date must be after pickup date');
  return { city, start, end };
}

// ---------------------------------------------------------------- lookups
app.get('/api/meta', route(async (req, { run }) => {
  const cities = await run('SELECT DISTINCT city FROM branch ORDER BY city');
  const types = await run('SELECT DISTINCT vehicle_type FROM car_model ORDER BY vehicle_type');
  return {
    cities: cities.map((r) => r.city),
    vehicleTypes: types.map((r) => r.vehicle_type),
    paymentModes: ['UPI', 'Card', 'NetBanking', 'Wallet', 'Cash'],
  };
}));

// ------------------------------------------------- explore & compare prices
app.get('/api/models', route(async (req, { run }) => {
  const { city, start, end } = readTrip(req.query);
  const [rows] = await run('CALL sp_search_models(?, ?, ?, ?)', [city, start, end, req.query.type || null]);
  return rows;
}));

app.get('/api/models/:id/compare', route(async (req, { run }) => {
  const { city, start, end } = readTrip(req.query);
  const [model] = await run('SELECT * FROM car_model WHERE model_id = ?', [req.params.id]);
  if (!model) throw fail(404, 'Car not found');
  const [offers] = await run('CALL sp_compare_prices(?, ?, ?, ?)', [req.params.id, city, start, end]);
  return { model, offers };
}));

// ---------------------------------------------------------------- customers
app.get('/api/customers/by-phone/:phone', route(async (req, { run }) => {
  const [customer] = await run(
    'SELECT customer_id, name, phone, email, city, license_no, license_expiry FROM customer WHERE phone = ?',
    [req.params.phone]);
  return customer || null;
}));

app.post('/api/customers', route(async (req, { run }) => {
  const { name, phone, email, address, city, license_no, license_expiry } = req.body;
  if (!name || !phone || !email || !city || !license_no || !isDate(license_expiry)) {
    throw fail(400, 'Please fill name, phone, email, city, licence number and licence expiry');
  }
  const result = await run(
    `INSERT INTO customer (name, phone, email, address, city, license_no, license_expiry)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [name.trim(), phone.trim(), email.trim(), address || null, city, license_no.trim().toUpperCase(), license_expiry]);
  const [customer] = await run('SELECT * FROM customer WHERE customer_id = ?', [result.insertId]);
  return customer;
}));

app.get('/api/customers/:id/rentals', route(async (req, { run }) => {
  return run('SELECT * FROM v_rental_details WHERE customer_id = ? ORDER BY rental_date DESC', [req.params.id]);
}));

// ----------------------------------------------------------------- bookings
// Uses ONE dedicated connection because the OUT parameter (@rental_id)
// only exists inside the session that called the procedure.
app.post('/api/bookings', async (req, res) => {
  const conn = await pool.getConnection().catch((err) => err);
  if (conn instanceof Error) {
    const { status, message } = describeError(conn);
    return res.status(status).json({ error: message, sql: [] });
  }
  const db = createRunner(conn, 'POST /api/bookings');
  try {
    const { customer_id, branch_id, model_id, start, end, payment_mode } = req.body;
    if (!customer_id || !branch_id || !model_id || !isDate(start) || !isDate(end) || !payment_mode) {
      throw fail(400, 'Missing booking details');
    }
    await db.run('CALL sp_book_rental(?, ?, ?, ?, ?, ?, @rental_id)',
      [customer_id, branch_id, model_id, start, end, payment_mode]);
    const [{ id }] = await db.run('SELECT @rental_id AS id');
    const [rental] = await db.run('SELECT * FROM v_rental_details WHERE rental_id = ?', [id]);
    res.json({ data: rental, sql: db.log });
  } catch (err) {
    const { status, message } = describeError(err);
    if (status === 500) console.error(err);
    res.status(status).json({ error: message, sql: db.log });
  } finally {
    conn.release();
  }
});

app.post('/api/rentals/:id/cancel', route(async (req, { run }) => {
  await run('CALL sp_cancel_rental(?)', [req.params.id]);
  const [rental] = await run('SELECT * FROM v_rental_details WHERE rental_id = ?', [req.params.id]);
  return rental;
}));

app.post('/api/rentals/:id/start', route(async (req, { run }) => {
  if (!req.body.employee_id) throw fail(400, 'Choose the employee handing over the car');
  await run('CALL sp_start_rental(?, ?)', [req.params.id, req.body.employee_id]);
  const [rental] = await run('SELECT * FROM v_rental_details WHERE rental_id = ?', [req.params.id]);
  return rental;
}));

app.post('/api/rentals/:id/return', route(async (req, { run }) => {
  const date = isDate(req.body.return_date) ? req.body.return_date : null;
  await run('CALL sp_return_vehicle(?, ?)', [req.params.id, date]);
  const [rental] = await run('SELECT * FROM v_rental_details WHERE rental_id = ?', [req.params.id]);
  return rental;
}));

app.post('/api/rentals/:id/review', route(async (req, { run }) => {
  const rating = Number(req.body.rating);
  if (!(rating >= 1 && rating <= 5)) throw fail(400, 'Rating must be between 1 and 5');
  await run('INSERT INTO review (rental_id, rating, comment) VALUES (?, ?, ?)',
    [req.params.id, rating, (req.body.comment || '').slice(0, 500) || null]);
  const [rental] = await run('SELECT * FROM v_rental_details WHERE rental_id = ?', [req.params.id]);
  return rental;
}));

app.get('/api/branches/:id/employees', route(async (req, { run }) => {
  return run('SELECT employee_id, name, role FROM employee WHERE branch_id = ? ORDER BY role, name', [req.params.id]);
}));

// -------------------------------------------------------------------- admin
app.get('/api/admin/summary', route(async (req, { run }) => {
  const [kpis] = await run(`
    SELECT (SELECT COUNT(*) FROM provider WHERE is_active)                      AS providers,
           (SELECT COUNT(*) FROM vehicle  WHERE status <> 'Retired')             AS vehicles,
           (SELECT COUNT(*) FROM vehicle  WHERE status = 'Rented')               AS on_road,
           (SELECT COUNT(*) FROM rental   WHERE status IN ('Booked','Ongoing'))  AS active_rentals,
           (SELECT COUNT(*) FROM rental   WHERE status = 'Ongoing'
                                            AND expected_return_date < CURDATE()) AS overdue,
           (SELECT COALESCE(SUM(amount),0) FROM payment WHERE payment_status = 'Paid') AS gross_value,
           (SELECT COALESCE(SUM(platform_commission),0) FROM v_platform_earnings)      AS commission`);
  const active = await run(`
    SELECT rental_id, status, customer_name, customer_phone, brand, model_name, registration_no,
           branch_id, branch_name, provider_name, rental_date, expected_return_date, total_amount,
           GREATEST(DATEDIFF(CURDATE(), expected_return_date), 0) AS days_overdue
    FROM   v_rental_details
    WHERE  status IN ('Booked','Ongoing')
    ORDER BY (status = 'Ongoing') DESC, rental_date`);
  const branches = await run('SELECT * FROM v_branch_revenue ORDER BY revenue DESC');
  const earnings = await run('SELECT * FROM v_platform_earnings ORDER BY gross_value DESC');
  const spread = await run(`SELECT * FROM v_model_price_summary
                            WHERE providers >= 2 ORDER BY max_saving_pct DESC LIMIT 8`);
  return { kpis, active, branches, earnings, spread };
}));

app.use('/api', (req, res) => res.status(404).json({ error: 'No such API route' }));

// Vercel imports this file and runs `app` as a serverless function.
module.exports = app;

// `npm start` / `node server.js` on your own computer starts a normal server.
if (require.main === module) {
  const PORT = Number(process.env.PORT || 3000);
  app.listen(PORT, async () => {
    console.log(`WheelDeal running at http://localhost:${PORT}`);
    try {
      await pool.query('SELECT 1 FROM rental LIMIT 1');
      console.log('Connected to MySQL database:', process.env.DB_NAME || 'vehicle_rental_db');
    } catch (err) {
      console.error('Database check failed:', err.message);
      console.error('-> Run the SQL files in /database and check .env');
    }
  });
}

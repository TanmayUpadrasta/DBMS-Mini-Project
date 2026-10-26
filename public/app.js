/* WheelDeal frontend — plain JavaScript, no build step.
   Talks to the Express API, which runs MySQL views & stored procedures. */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const rupees = (n) => '₹' + Math.round(Number(n) || 0).toLocaleString('en-IN');
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const niceDate = (d) => { if (!d) return '—'; const [y, m, day] = d.slice(0, 10).split('-'); return `${+day} ${MONTHS[m - 1]}`; };
const isoDate = (date) => { const z = new Date(date.getTime() - date.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 10); };
const addDays = (iso, n) => { const d = new Date(iso + 'T00:00:00'); d.setDate(d.getDate() + n); return isoDate(d); };
const daysBetween = (a, b) => Math.max(Math.round((new Date(b) - new Date(a)) / 86400000), 1);
const today = () => isoDate(new Date());

const store = {
  get(k) { try { return localStorage.getItem('wd_' + k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem('wd_' + k, v); } catch { /* storage unavailable */ } },
};

const state = {
  meta: null,
  trip: { city: 'Mumbai', start: addDays(today(), 1), end: addDays(today(), 3), type: '' },
  models: [],
  modelSort: 'providers',
  compare: null,          // { model, offers, sort }
  customer: null,
  sqlLog: [],
};

/* ------------------------------------------------------------------ API */
async function api(path, { method = 'GET', body, label, quiet } = {}) {
  let res, json;
  try {
    res = await fetch('/api' + path, {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
    json = await res.json();
  } catch {
    throw new Error('Cannot reach the server. Check your connection and try again.');
  }
  if (!quiet) logSql(label || `${method} ${path.split('?')[0]}`, json.sql || [], res.ok ? null : json.error);
  if (!res.ok) throw new Error(json.error || 'Request failed');
  return json.data;
}

/* ------------------------------------------------------------ SQL drawer */
const SQL_KW = /\b(SELECT|FROM|WHERE|JOIN|LEFT|ON|AND|OR|NOT|IN|IS|NULL|AS|ORDER BY|GROUP BY|LIMIT|INSERT INTO|VALUES|UPDATE|SET|CALL|DESC|ASC|DISTINCT|COUNT|SUM|COALESCE|GREATEST|DATEDIFF|CURDATE|EXISTS|CASE|WHEN|THEN|END)\b/g;
function highlight(sql) {
  return esc(sql)
    .replace(/(&#39;(?:[^&]|&(?!#39;))*?&#39;)/g, '<span class="str">$1</span>')
    .replace(/\b(sp_\w+|fn_\w+|v_\w+)\b/g, '<span class="fn">$1</span>')
    .replace(SQL_KW, '<span class="kw">$1</span>')
    .replace(/(^|[\s(,])(\d+(?:\.\d+)?)(?=[\s),;]|$)/g, '$1<span class="numl">$2</span>');
}
function logSql(label, statements, error) {
  state.sqlLog.unshift({ label, statements, error, at: new Date() });
  state.sqlLog = state.sqlLog.slice(0, 40);
  const total = state.sqlLog.reduce((n, e) => n + e.statements.length, 0);
  $('#sqlCount').textContent = total;
  renderSqlLog();
}
function renderSqlLog() {
  const box = $('#sqlLog');
  if (!state.sqlLog.length) { box.innerHTML = '<p class="empty">Nothing yet — search for a car.</p>'; return; }
  box.innerHTML = state.sqlLog.map((e) => `
    <div class="sql-entry">
      <div class="req"><b>${esc(e.label)}</b><span>${e.at.toLocaleTimeString()}</span></div>
      ${e.statements.map((s) => `<pre>${highlight(s)};</pre>`).join('')}
      ${e.error ? `<div class="req"><span class="err">MySQL said: ${esc(e.error)}</span></div>` : ''}
    </div>`).join('');
}
$('#sqlToggle').addEventListener('click', () => $('#sqlDrawer').classList.toggle('open'));
$('#sqlClose').addEventListener('click', () => $('#sqlDrawer').classList.remove('open'));

/* ---------------------------------------------------------------- toast */
let toastTimer;
function toast(msg, isError = false) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast' + (isError ? ' error' : '');
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, isError ? 5000 : 3000);
}

/* ----------------------------------------------------------- vehicle art */
const TINT = { Hatchback: '#fbe1d6', Sedan: '#dfe8f8', SUV: '#dff0e2', MUV: '#efe3f4', Luxury: '#efe6d3', Bike: '#fbe6c4', Scooter: '#d9efef' };
function vehicleSvg(type) {
  const wheels = (a, b, r = 12) => `<circle cx="${a}" cy="60" r="${r}" fill="currentColor"/><circle cx="${a}" cy="60" r="${r * 0.42}" fill="var(--tint)"/>
    <circle cx="${b}" cy="60" r="${r}" fill="currentColor"/><circle cx="${b}" cy="60" r="${r * 0.42}" fill="var(--tint)"/>`;
  const shapes = {
    Hatchback: `<path d="M12 58 L15 45 Q19 38 32 36 L60 33 L80 18 Q86 14 96 14 L134 14 Q144 14 151 22 L168 37 Q186 39 189 47 L190 58 Z" fill="currentColor"/>
      <path d="M68 33 L84 21 Q88 18 95 18 L112 18 L112 33 Z M118 18 L134 18 Q141 18 146 23 L157 33 L118 33 Z" fill="var(--tint)"/>${wheels(52, 154)}`,
    Sedan: `<path d="M6 57 L9 47 Q13 40 32 38 L62 36 L84 20 Q90 16 100 16 L128 16 Q137 16 145 23 L163 36 L186 40 Q195 42 195 50 L195 57 Z" fill="currentColor"/>
      <path d="M70 36 L87 23 Q91 20 98 20 L112 20 L112 36 Z M118 20 L128 20 Q135 20 141 25 L152 36 L118 36 Z" fill="var(--tint)"/>${wheels(50, 158)}`,
    SUV: `<path d="M10 58 L10 40 Q12 31 27 30 L48 28 L60 12 Q63 8 71 8 L158 8 Q166 8 170 14 L181 30 Q193 32 193 42 L193 58 Z" fill="currentColor"/>
      <path d="M58 28 L68 14 Q70 12 74 12 L108 12 L108 28 Z M114 12 L156 12 Q161 12 163 16 L171 28 L114 28 Z" fill="var(--tint)"/>${wheels(50, 158, 13)}`,
    Bike: `<circle cx="45" cy="56" r="20" fill="none" stroke="currentColor" stroke-width="6"/><circle cx="155" cy="56" r="20" fill="none" stroke="currentColor" stroke-width="6"/>
      <path d="M45 56 L80 28 L125 28 L155 56 M80 28 L100 56 L125 28 M118 18 L136 18 M128 18 L140 40" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M70 22 Q90 12 112 22 L108 30 L74 30 Z" fill="currentColor"/>`,
    Scooter: `<circle cx="48" cy="60" r="14" fill="currentColor"/><circle cx="152" cy="60" r="14" fill="currentColor"/>
      <path d="M30 56 Q30 36 60 36 L110 36 L118 50 L140 50 L148 20 L160 14" stroke="currentColor" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M58 26 Q80 18 104 26 L104 34 L58 34 Z" fill="currentColor"/>`,
  };
  const shape = shapes[type] || shapes.Hatchback;
  return `<svg viewBox="0 0 200 80" aria-hidden="true">${shape}</svg>`;
}
// Picks a silhouette: MUVs and 7-seat luxury cars look like SUVs, others keep their type
const vehicleShape = (m) => (m.vehicle_type === 'MUV' || (m.vehicle_type === 'Luxury' && m.seats > 5) ? 'SUV' : m.vehicle_type === 'Luxury' ? 'Sedan' : m.vehicle_type);

/* ------------------------------------------------------------------ tabs */
function showTab(name) {
  $$('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
  $$('.tab-panel').forEach((p) => p.classList.toggle('active', p.id === 'tab-' + name));
  if (name === 'admin') loadAdmin();
  if (name === 'rentals' && state.customer) loadRentals(state.customer.phone);
  history.replaceState(null, '', '#' + name);
}
$$('[data-tab]').forEach((el) => el.addEventListener('click', (e) => { e.preventDefault(); showTab(el.dataset.tab); }));

/* =============================================================== EXPLORE */
async function initExplore() {
  try {
    state.meta = await api('/meta', { label: 'Load cities & car types' });
  } catch (err) {
    $('#modelGrid').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
    return;
  }
  $('#city').innerHTML = state.meta.cities.map((c) => `<option ${c === state.trip.city ? 'selected' : ''}>${esc(c)}</option>`).join('');
  $('#start').value = state.trip.start;
  $('#end').value = state.trip.end;
  $('#start').min = today();
  $('#end').min = addDays(state.trip.start, 1);
  renderChips();
  searchModels();
}

function renderChips() {
  const types = ['', ...state.meta.vehicleTypes];
  $('#typeChips').innerHTML = types.map((t) =>
    `<button class="chip ${t === state.trip.type ? 'active' : ''}" data-type="${esc(t)}">${t || 'All'}</button>`).join('');
}
$('#typeChips').addEventListener('click', (e) => {
  const chip = e.target.closest('.chip');
  if (!chip) return;
  state.trip.type = chip.dataset.type;
  renderChips();
  searchModels();
});

$('#start').addEventListener('change', () => {
  const s = $('#start').value;
  $('#end').min = addDays(s, 1);
  if ($('#end').value <= s) $('#end').value = addDays(s, 2);
});

$('#searchForm').addEventListener('submit', (e) => {
  e.preventDefault();
  state.trip.city = $('#city').value;
  state.trip.start = $('#start').value;
  state.trip.end = $('#end').value;
  if (state.trip.end <= state.trip.start) { toast('Return date must be after pickup date', true); return; }
  searchModels();
});

$('#sortModels').addEventListener('change', (e) => { state.modelSort = e.target.value; renderModels(); });

async function searchModels() {
  const { city, start, end, type } = state.trip;
  $('#modelGrid').innerHTML = '<div class="skeleton"></div>'.repeat(4);
  try {
    const q = new URLSearchParams({ city, start, end, type });
    state.models = await api('/models?' + q, { label: 'Search cars  ·  sp_search_models' });
    renderModels();
  } catch (err) {
    $('#modelGrid').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
  }
}

function renderModels() {
  const { city, start, end, type } = state.trip;
  const days = daysBetween(start, end);
  $('#resultsTitle').innerHTML = `${state.models.length} ${type || 'car'}${state.models.length === 1 ? '' : 's'} free in ${esc(city)}
    <small>${niceDate(start)} → ${niceDate(end)} · ${days} day${days > 1 ? 's' : ''}</small>`;
  const sorted = [...state.models].sort((a, b) => {
    if (state.modelSort === 'price') return a.lowest_rate - b.lowest_rate;
    if (state.modelSort === 'saving') return b.max_saving_pct - a.max_saving_pct;
    return b.providers - a.providers || a.lowest_rate - b.lowest_rate;
  });
  if (!sorted.length) {
    $('#modelGrid').innerHTML = '<div class="empty">No cars free for these dates. Try other dates or another type.</div>';
    return;
  }
  $('#modelGrid').innerHTML = sorted.map((m) => {
    const spreadPct = m.highest_rate > m.lowest_rate ? Math.max(18, 100 - m.max_saving_pct * 2.5) : 100;
    return `
    <button class="model" data-id="${m.model_id}" style="--tint:${TINT[m.vehicle_type]}">
      <div class="model-art">
        ${m.max_saving_pct > 0 ? `<span class="save-badge">Save up to ${m.max_saving_pct}%</span>` : ''}
        <span class="type-tag">${esc(m.vehicle_type)}</span>
        ${vehicleSvg(vehicleShape(m))}
      </div>
      <div class="model-body">
        <div>
          <div class="model-brand">${esc(m.brand)}</div>
          <div class="model-name">${esc(m.model_name)}</div>
        </div>
        <div class="specs">
          <span class="spec">${esc(m.fuel_type)}</span><span class="spec">${esc(m.transmission)}</span><span class="spec">${m.seats} seats</span>
        </div>
        <div class="price-row">
          <div><div class="from">from</div><div class="price">${rupees(m.lowest_rate)}<small>/day</small></div></div>
          ${m.highest_rate > m.lowest_rate ? `<div class="upto">up to<br>${rupees(m.highest_rate)}/day</div>` : ''}
        </div>
        <div class="range" title="Price range across providers"><i style="width:${spreadPct}%"></i></div>
        <div class="model-foot"><span><b>${m.providers}</b> provider${m.providers > 1 ? 's' : ''}</span><span>${m.units_free} unit${m.units_free > 1 ? 's' : ''} free</span></div>
      </div>
    </button>`;
  }).join('');
}
$('#modelGrid').addEventListener('click', (e) => {
  const card = e.target.closest('.model');
  if (card) openCompare(card.dataset.id);
});

/* --------------------------------------------------------------- compare */
async function openCompare(modelId) {
  const { city, start, end } = state.trip;
  openOverlay('#compareOverlay');
  $('#compareBody').innerHTML = '<div class="skeleton" style="height:260px"></div>';
  try {
    const q = new URLSearchParams({ city, start, end });
    const data = await api(`/models/${modelId}/compare?${q}`, { label: 'Compare prices  ·  sp_compare_prices' });
    state.compare = { ...data, sort: 'price' };
    renderCompare();
  } catch (err) {
    $('#compareBody').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
  }
}

function stars(avg, count) {
  if (!count) return '<span class="stars"><span>No reviews yet</span></span>';
  const full = Math.round(avg);
  return `<span class="stars" title="${avg} out of 5">${'★'.repeat(full)}${'☆'.repeat(5 - full)}<span>${avg} · ${count}</span></span>`;
}

function renderCompare() {
  const { model, offers, sort } = state.compare;
  const { city, start, end } = state.trip;
  const days = daysBetween(start, end);
  const bestPrice = Math.min(...offers.map((o) => o.daily_rate));
  const topRated = Math.max(...offers.map((o) => o.avg_rating || 0));
  const sorted = [...offers].sort((a, b) => {
    if (sort === 'rating') return (b.avg_rating || 0) - (a.avg_rating || 0) || a.daily_rate - b.daily_rate;
    if (sort === 'deposit') return a.security_deposit - b.security_deposit || a.daily_rate - b.daily_rate;
    return a.daily_rate - b.daily_rate || (b.avg_rating || 0) - (a.avg_rating || 0);
  });
  const maxSave = offers.length ? Math.max(...offers.map((o) => o.saving_vs_costliest)) : 0;

  $('#compareBody').innerHTML = `
    <div class="cmp-head" style="--tint:${TINT[model.vehicle_type]}">
      <div class="cmp-art">${vehicleSvg(vehicleShape(model))}</div>
      <div>
        <h2 id="compareTitle">${esc(model.brand)} ${esc(model.model_name)}</h2>
        <div class="cmp-meta">${esc(model.fuel_type)} · ${esc(model.transmission)} · ${model.seats} seats &nbsp;|&nbsp; ${esc(city)}, ${niceDate(start)} → ${niceDate(end)} (${days} day${days > 1 ? 's' : ''})</div>
      </div>
    </div>
    ${offers.length ? `
    <div class="cmp-tools">
      <div class="seg" id="cmpSort">
        <button data-sort="price" class="${sort === 'price' ? 'active' : ''}">Lowest price</button>
        <button data-sort="rating" class="${sort === 'rating' ? 'active' : ''}">Top rated</button>
        <button data-sort="deposit" class="${sort === 'deposit' ? 'active' : ''}">Lowest deposit</button>
      </div>
      <div class="cmp-note">${offers.length} offer${offers.length > 1 ? 's' : ''}${maxSave > 0 ? ` · cheapest saves <b>${rupees(maxSave)}</b> on this trip` : ''}</div>
    </div>
    ${sorted.map((o) => {
      const isBest = o.daily_rate === bestPrice;
      const extra = o.daily_rate - bestPrice;
      return `
      <div class="offer ${isBest ? 'best' : ''}">
        <div class="rank">${o.price_rank}</div>
        <div>
          <div class="prov-name">${esc(o.provider_name)}
            <span class="tag ${o.provider_type.toLowerCase()}">${esc(o.provider_type)}</span>
            ${isBest ? '<span class="tag best">Best price</span>' : ''}
            ${o.avg_rating && o.avg_rating === topRated ? '<span class="tag top">Top rated</span>' : ''}
          </div>
          <div class="prov-sub">${esc(o.branch_name)} · ${esc(o.address)}</div>
          ${stars(o.avg_rating, o.review_count)}
        </div>
        <div class="offer-price">
          <div class="per">${rupees(o.daily_rate)}<small>/day</small></div>
          <div class="tot">${rupees(o.trip_total)} for ${o.days} day${o.days > 1 ? 's' : ''}</div>
          ${extra > 0 ? `<div class="more">+${rupees(extra * o.days)} vs cheapest</div>` : ''}
        </div>
        <div class="terms">
          <span>Deposit <b>${o.security_deposit ? rupees(o.security_deposit) : 'None'}</b></span>
          <span><b>${o.km_limit_per_day} km</b>/day free</span>
          <span>Extra km <b>${rupees(o.extra_km_charge)}</b></span>
        </div>
        <div class="offer-cta">
          <button class="btn ${isBest ? 'primary' : 'dark'} small" data-book="${o.branch_id}">Book</button>
          <span class="units">${o.units_free} left</span>
        </div>
      </div>`;
    }).join('')}` : '<div class="empty">Every unit of this car is booked for these dates. Try other dates.</div>'}`;
}

$('#compareBody').addEventListener('click', (e) => {
  const sortBtn = e.target.closest('[data-sort]');
  if (sortBtn) { state.compare.sort = sortBtn.dataset.sort; renderCompare(); return; }
  const bookBtn = e.target.closest('[data-book]');
  if (bookBtn) {
    const offer = state.compare.offers.find((o) => String(o.branch_id) === bookBtn.dataset.book);
    openBooking(offer);
  }
});

/* --------------------------------------------------------------- booking */
let booking = null;
function openBooking(offer) {
  booking = { offer, model: state.compare.model, trip: { ...state.trip }, step: 'phone', error: '', customer: null, newPhone: '' };
  if (state.customer) { booking.customer = state.customer; booking.step = 'confirm'; }
  openOverlay('#bookOverlay');
  renderBooking();
}

function bookingSummary() {
  const { offer, model, trip } = booking;
  return `
    <div class="book-summary">
      <div class="row"><span>Car</span><b>${esc(model.brand)} ${esc(model.model_name)}</b></div>
      <div class="row"><span>Provider</span><span>${esc(offer.provider_name)} · ${esc(offer.branch_name)}</span></div>
      <div class="row"><span>Dates</span><span>${niceDate(trip.start)} → ${niceDate(trip.end)}</span></div>
      <div class="row"><span>${rupees(offer.daily_rate)} × ${offer.days} day${offer.days > 1 ? 's' : ''}</span><span>${rupees(offer.trip_total)}</span></div>
      <div class="row"><span>Refundable deposit (pay at pickup)</span><span>${offer.security_deposit ? rupees(offer.security_deposit) : 'None'}</span></div>
      <div class="row total"><span>Pay now</span><span>${rupees(offer.trip_total)}</span></div>
    </div>`;
}
const errorBox = () => (booking.error ? `<div class="form-error"><b>Not booked</b>${esc(booking.error)}</div>` : '');

function renderBooking() {
  const body = $('#bookBody');
  const b = booking;
  if (b.step === 'phone') {
    body.innerHTML = `<h2>Confirm your booking</h2>${bookingSummary()}${errorBox()}
      <form id="bkPhone">
        <label class="field"><span>Mobile number</span><input type="tel" name="phone" pattern="[0-9]{10}" placeholder="10-digit mobile" required value="${esc(store.get('phone') || '')}"></label>
        <button class="btn primary" style="width:100%">Continue</button>
      </form>`;
    $('#bkPhone input').focus();
  } else if (b.step === 'register') {
    body.innerHTML = `<h2>New here? Register once</h2><p class="hint">Your licence is checked against the return date before the booking is accepted.</p>${errorBox()}
      <form id="bkRegister">
        <label class="field"><span>Full name</span><input name="name" required></label>
        <div class="fields-2">
          <label class="field"><span>Mobile</span><input name="phone" value="${esc(b.newPhone)}" pattern="[0-9]{10}" required></label>
          <label class="field"><span>Email</span><input name="email" type="email" required></label>
        </div>
        <div class="fields-2">
          <label class="field"><span>Driving licence no.</span><input name="license_no" required placeholder="MH0220200012345"></label>
          <label class="field"><span>Licence valid till</span><input name="license_expiry" type="date" required></label>
        </div>
        <div class="fields-2">
          <label class="field"><span>City</span><select name="city">${state.meta.cities.map((c) => `<option ${c === b.trip.city ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select></label>
          <label class="field"><span>Address (optional)</span><input name="address"></label>
        </div>
        <button class="btn primary" style="width:100%">Register &amp; continue</button>
      </form>`;
  } else if (b.step === 'confirm') {
    body.innerHTML = `<h2>Confirm your booking</h2>${bookingSummary()}
      <div class="greet">Booking as <b>${esc(b.customer.name)}</b> (${esc(b.customer.phone)}) · <button class="link" id="bkSwitch">not you?</button></div>
      ${errorBox()}
      <div class="field"><span>Pay with</span></div>
      <div class="pay-modes">${state.meta.paymentModes.filter((m) => m !== 'Cash').map((m, i) => `<label><input type="radio" name="mode" value="${m}" ${i === 0 ? 'checked' : ''}>${m}</label>`).join('')}</div>
      <button class="btn primary" id="bkConfirm" style="width:100%">Pay ${rupees(b.offer.trip_total)} &amp; book</button>`;
  } else if (b.step === 'done') {
    const r = b.rental;
    body.innerHTML = `<div class="success"><div class="tick">✓</div><h2>Booked!</h2>
      <p class="hint">Rental <span class="receipt-id">#${r.rental_id}</span> · show this at the branch</p></div>
      <div class="book-summary">
        <div class="row"><span>Car</span><b>${esc(r.brand)} ${esc(r.model_name)}</b></div>
        <div class="row"><span>Vehicle no.</span><span class="mono">${esc(r.registration_no)}</span></div>
        <div class="row"><span>Pickup</span><span>${esc(r.provider_name)}, ${esc(r.branch_name)} · ${niceDate(r.rental_date)}</span></div>
        <div class="row"><span>Return by</span><span>${niceDate(r.expected_return_date)}</span></div>
        <div class="row total"><span>Paid (${esc(r.payment_mode)})</span><span>${rupees(r.amount_paid)}</span></div>
      </div>
      <button class="btn dark" id="bkMine" style="width:100%">View my rentals</button>`;
  }
}

$('#bookBody').addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = e.target;
  const data = Object.fromEntries(new FormData(form));
  booking.error = '';
  try {
    if (form.id === 'bkPhone') {
      const found = await api(`/customers/by-phone/${encodeURIComponent(data.phone)}`, { label: 'Look up customer' });
      if (found) { setCustomer(found); booking.customer = found; booking.step = 'confirm'; } else { booking.newPhone = data.phone; booking.step = 'register'; }
    } else if (form.id === 'bkRegister') {
      const created = await api('/customers', { method: 'POST', body: data, label: 'Register customer' });
      setCustomer(created);
      booking.customer = created;
      booking.step = 'confirm';
      toast('Welcome to WheelDeal, ' + created.name.split(' ')[0] + '!');
    }
  } catch (err) { booking.error = err.message; }
  renderBooking();
});

$('#bookBody').addEventListener('click', async (e) => {
  if (e.target.id === 'bkSwitch') { booking.step = 'phone'; booking.customer = null; renderBooking(); }
  if (e.target.id === 'bkMine') { closeOverlays(); showTab('rentals'); }
  if (e.target.id === 'bkConfirm') {
    const btn = e.target;
    btn.disabled = true; btn.textContent = 'Booking…';
    const { offer, model, trip, customer } = booking;
    try {
      booking.rental = await api('/bookings', {
        method: 'POST',
        label: 'Book  ·  sp_book_rental (transaction)',
        body: { customer_id: customer.customer_id, branch_id: offer.branch_id, model_id: model.model_id, start: trip.start, end: trip.end, payment_mode: $('input[name=mode]:checked').value },
      });
      booking.step = 'done';
      searchModels();                    // availability changed
    } catch (err) { booking.error = err.message; }
    renderBooking();
  }
});

function setCustomer(c) {
  state.customer = c;
  store.set('phone', c.phone);
  $('#myPhone').value = c.phone;
}

/* ------------------------------------------------------------ overlays */
function openOverlay(sel) { $(sel).hidden = false; document.body.style.overflow = 'hidden'; }
function closeOverlays() { $$('.overlay').forEach((o) => { o.hidden = true; }); document.body.style.overflow = ''; }
$$('.overlay').forEach((o) => o.addEventListener('click', (e) => {
  if (e.target === o || e.target.closest('[data-close]')) {
    o.hidden = true;
    if ($$('.overlay').every((x) => x.hidden)) document.body.style.overflow = '';
  }
}));
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const open = $$('.overlay').filter((o) => !o.hidden).pop();
  if (open) { open.hidden = true; if ($$('.overlay').every((x) => x.hidden)) document.body.style.overflow = ''; } else $('#sqlDrawer').classList.remove('open');
});

/* ============================================================ MY RENTALS */
$('#phoneForm').addEventListener('submit', (e) => { e.preventDefault(); loadRentals($('#myPhone').value.trim()); });
$$('[data-phone]').forEach((b) => b.addEventListener('click', () => { $('#myPhone').value = b.dataset.phone; loadRentals(b.dataset.phone); }));

async function loadRentals(phone) {
  const box = $('#rentalList');
  try {
    const c = await api(`/customers/by-phone/${encodeURIComponent(phone)}`, { label: 'Look up customer' });
    if (!c) { box.innerHTML = '<div class="empty">No customer with this number. Book a car to register.</div>'; return; }
    setCustomer(c);
    const rentals = await api(`/customers/${c.customer_id}/rentals`, { label: 'My rentals  ·  v_rental_details' });
    renderRentals(c, rentals);
  } catch (err) {
    box.innerHTML = `<div class="empty">${esc(err.message)}</div>`;
  }
}

function renderRentals(c, rentals) {
  const box = $('#rentalList');
  const spent = rentals.filter((r) => r.payment_status === 'Paid').reduce((s, r) => s + r.amount_paid, 0);
  box.innerHTML = `<p class="who">Hi <b>${esc(c.name)}</b> · ${rentals.length} rental${rentals.length === 1 ? '' : 's'} · ${rupees(spent)} spent · licence valid till ${niceDate(c.license_expiry)} ${c.license_expiry.slice(0, 4)}</p>` +
    (rentals.length ? rentals.map((r) => {
      const overdue = r.status === 'Ongoing' && r.expected_return_date < today();
      let actions = '';
      if (r.status === 'Booked') actions = `<button class="btn danger small" data-cancel="${r.rental_id}">Cancel &amp; refund</button>`;
      if (r.status === 'Completed' && !r.review_rating) {
        actions = `<div class="review-box" data-review="${r.rental_id}">
          <div class="star-pick">${[1, 2, 3, 4, 5].map((n) => `<button type="button" data-star="${n}">★</button>`).join('')}</div>
          <textarea placeholder="How was the car and pickup?"></textarea>
          <button class="btn dark small" data-submit-review>Post review</button></div>`;
      }
      if (r.review_rating) actions = `<span class="stars">${'★'.repeat(r.review_rating)}${'☆'.repeat(5 - r.review_rating)}<span>your rating</span></span>`;
      return `
      <div class="rental">
        <div>
          <span class="pill ${r.status}">${r.status}</span> ${overdue ? '<span class="pill Overdue">Overdue</span>' : ''}
          <h3>${esc(r.brand)} ${esc(r.model_name)}</h3>
          <div class="muted">${esc(r.provider_name)} · ${esc(r.branch_name)}, ${esc(r.city)}</div>
          <div class="muted mono">#${r.rental_id} · ${esc(r.registration_no)}</div>
        </div>
        <div class="money">
          <span class="muted">Dates</span>
          <span>${niceDate(r.rental_date)} → ${niceDate(r.expected_return_date)}</span>
          ${r.actual_return_date ? `<span class="muted">Returned ${niceDate(r.actual_return_date)}</span>` : ''}
        </div>
        <div class="money">
          <span class="big">${rupees(r.total_amount)}</span>
          <span class="muted">${rupees(r.daily_rate_at_booking)}/day × ${r.planned_days}${r.late_fee ? ` + late fee ${rupees(r.late_fee)}` : ''}</span>
          <span class="muted">${esc(r.payment_mode || '')} · ${esc(r.payment_status || '')}</span>
        </div>
        <div class="rental-actions">${actions}</div>
      </div>`;
    }).join('') : '<div class="empty">No rentals yet. Find a car in Explore.</div>');
}

$('#rentalList').addEventListener('click', async (e) => {
  const star = e.target.closest('[data-star]');
  if (star) {
    const boxEl = star.closest('[data-review]');
    boxEl.dataset.rating = star.dataset.star;
    $$('[data-star]', boxEl).forEach((s) => s.classList.toggle('on', +s.dataset.star <= +star.dataset.star));
    return;
  }
  const cancel = e.target.closest('[data-cancel]');
  if (cancel) {
    if (!confirm('Cancel this booking? The payment will be refunded.')) return;
    try {
      await api(`/rentals/${cancel.dataset.cancel}/cancel`, { method: 'POST', label: 'Cancel  ·  sp_cancel_rental' });
      toast('Booking cancelled and refunded');
      loadRentals(state.customer.phone);
    } catch (err) { toast(err.message, true); }
    return;
  }
  if (e.target.closest('[data-submit-review]')) {
    const boxEl = e.target.closest('[data-review]');
    if (!boxEl.dataset.rating) { toast('Tap the stars to choose a rating', true); return; }
    try {
      await api(`/rentals/${boxEl.dataset.review}/review`, {
        method: 'POST', label: 'Post review',
        body: { rating: +boxEl.dataset.rating, comment: $('textarea', boxEl).value },
      });
      toast('Thanks! Your rating now counts in the provider’s score');
      loadRentals(state.customer.phone);
    } catch (err) { toast(err.message, true); }
  }
});

/* ================================================================ ADMIN */
$('#refreshAdmin').addEventListener('click', loadAdmin);

async function loadAdmin() {
  try {
    const d = await api('/admin/summary', { label: 'Dashboard  ·  views & aggregates' });
    const branchIds = [...new Set(d.active.filter((r) => r.status === 'Booked').map((r) => r.branch_id))];
    const staff = {};
    await Promise.all(branchIds.map(async (id) => { staff[id] = await api(`/branches/${id}/employees`, { quiet: true }); }));
    renderAdmin(d, staff);
  } catch (err) {
    $('#kpis').innerHTML = `<div class="empty">${esc(err.message)}</div>`;
  }
}

function renderAdmin({ kpis, active, branches, earnings, spread }, staff) {
  const k = [
    ['Active providers', kpis.providers], ['Vehicles listed', kpis.vehicles], ['On the road now', kpis.on_road],
    ['Open rentals', kpis.active_rentals], ['Overdue', kpis.overdue, kpis.overdue > 0],
    ['Gross bookings', rupees(kpis.gross_value)], ['Platform commission', rupees(kpis.commission)],
  ];
  $('#kpis').innerHTML = k.map(([l, v, alert]) => `<div class="kpi ${alert ? 'alert' : ''}"><div class="label">${l}</div><div class="value">${v}</div></div>`).join('');

  $('#activeTable').innerHTML = `<thead><tr><th>#</th><th>Status</th><th>Customer</th><th>Car</th><th>Branch</th><th>Dates</th><th class="num">Amount</th><th class="num">Action</th></tr></thead><tbody>` +
    (active.length ? active.map((r) => {
      let action = '';
      if (r.status === 'Booked') {
        action = `<select data-emp="${r.rental_id}">${(staff[r.branch_id] || []).map((e) => `<option value="${e.employee_id}">${esc(e.name)} (${e.role})</option>`).join('')}</select>
          <button class="btn dark small" data-start="${r.rental_id}">Hand over</button>`;
      } else {
        action = `<input type="date" data-ret="${r.rental_id}" value="${today()}" min="${r.rental_date}">
          <button class="btn primary small" data-return="${r.rental_id}">Return</button>`;
      }
      return `<tr>
        <td class="mono">${r.rental_id}</td>
        <td><span class="pill ${r.status}">${r.status}</span>${r.days_overdue > 0 ? ` <span class="pill Overdue">${r.days_overdue}d late</span>` : ''}</td>
        <td>${esc(r.customer_name)}<div class="muted">${esc(r.customer_phone)}</div></td>
        <td>${esc(r.brand)} ${esc(r.model_name)}<div class="muted mono">${esc(r.registration_no)}</div></td>
        <td>${esc(r.branch_name)}<div class="muted">${esc(r.provider_name)}</div></td>
        <td>${niceDate(r.rental_date)} → ${niceDate(r.expected_return_date)}</td>
        <td class="num">${rupees(r.total_amount)}</td>
        <td><div class="act">${action}</div></td></tr>`;
    }).join('') : '<tr><td colspan="8" class="empty">No open rentals</td></tr>') + '</tbody>';

  $('#spreadList').innerHTML = spread.map((s) => {
    return `<div class="spread">
      <div><b>${esc(s.car)}</b> <span class="muted">${esc(s.city)} · ${s.providers} providers</span></div>
      <div><b style="color:var(--good)">${s.max_saving_pct}%</b> <span class="muted">gap</span></div>
      <div class="bar"><i style="left:0;width:${Math.min(100, s.max_saving_pct * 3)}%"></i></div>
      <div class="muted">${rupees(s.lowest_rate)} – ${rupees(s.highest_rate)} per day</div><div class="muted">avg ${rupees(s.average_rate)}</div>
    </div>`;
  }).join('');

  $('#earningsTable').innerHTML = `<thead><tr><th>Provider</th><th class="num">Rate</th><th class="num">Gross</th><th class="num">Commission</th></tr></thead><tbody>` +
    earnings.map((p) => `<tr><td>${esc(p.provider_name)}<div class="muted">${p.paid_rentals} paid rentals</div></td><td class="num">${p.commission_pct}%</td><td class="num">${rupees(p.gross_value)}</td><td class="num"><b>${rupees(p.platform_commission)}</b></td></tr>`).join('') + '</tbody>';

  $('#branchTable').innerHTML = `<thead><tr><th>Branch</th><th>Provider</th><th class="num">Fleet</th><th class="num">Rentals</th><th class="num">Completed</th><th class="num">Active</th><th class="num">Cancelled</th><th class="num">Revenue</th></tr></thead><tbody>` +
    branches.map((b) => `<tr><td>${esc(b.branch_name)}<div class="muted">${esc(b.city)}</div></td><td>${esc(b.provider_name)}</td><td class="num">${b.fleet_size}</td><td class="num">${b.total_rentals}</td><td class="num">${b.completed}</td><td class="num">${b.active}</td><td class="num">${b.cancelled}</td><td class="num"><b>${rupees(b.revenue)}</b></td></tr>`).join('') + '</tbody>';
}

$('#activeTable').addEventListener('click', async (e) => {
  const start = e.target.closest('[data-start]');
  const ret = e.target.closest('[data-return]');
  try {
    if (start) {
      const id = start.dataset.start;
      const employee_id = $(`[data-emp="${id}"]`).value;
      await api(`/rentals/${id}/start`, { method: 'POST', body: { employee_id }, label: 'Hand over  ·  sp_start_rental' });
      toast(`Rental #${id} is now ongoing — vehicle marked Rented by trigger`);
      loadAdmin();
    }
    if (ret) {
      const id = ret.dataset.return;
      const r = await api(`/rentals/${id}/return`, { method: 'POST', body: { return_date: $(`[data-ret="${id}"]`).value }, label: 'Return  ·  sp_return_vehicle' });
      toast(r.late_fee > 0 ? `Returned late: ${rupees(r.late_fee)} late fee added (total ${rupees(r.total_amount)})` : `Returned on time — total ${rupees(r.total_amount)}`);
      loadAdmin();
    }
  } catch (err) { toast(err.message, true); }
});

/* ================================================================= boot */
(function boot() {
  const saved = store.get('phone');
  if (saved) $('#myPhone').value = saved;
  initExplore();
  const tab = location.hash.replace('#', '');
  if (['rentals', 'admin'].includes(tab)) showTab(tab);
  if (tab === 'rentals' && saved) loadRentals(saved);
})();

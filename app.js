/* ================= Storage =================
   tt.v1 holds everything except the logged sets; those are kept per month (tt.v1s.YYYY-MM) and listed in setMonths,
   so saving after ticking a set rewrites this month only, not years of history.
   Older saves (all sets inside tt.v1) still load; the next save splits them up. */
const KEY = 'tt.v1', SKEY = 'tt.v1s.';
const savedMonths = new Map();   // month → what was last written for it (to skip months that didn't change)
const monthSig = g => { const v = new Array(g.length * 3); g.forEach((x, i) => { v[i * 3] = x.weight; v[i * 3 + 1] = x.reps; v[i * 3 + 2] = x.slot; }); return { refs: g, v }; };
const monthSame = (m, g) => {
  const o = savedMonths.get(m);
  if (!o || o.refs.length !== g.length) return false;
  for (let i = 0; i < g.length; i++) { const x = g[i]; if (o.refs[i] !== x || o.v[i * 3] !== x.weight || o.v[i * 3 + 1] !== x.reps || o.v[i * 3 + 2] !== x.slot) return false; }
  return true;
};
function load() {
  let d = null;
  try {
    d = JSON.parse(localStorage.getItem(KEY));
    if (d && Array.isArray(d.setMonths)) {
      const sets = [];
      for (const m of d.setMonths) { const g = JSON.parse(localStorage.getItem(SKEY + m)) || []; savedMonths.set(m, monthSig(g)); for (const x of g) sets.push(x); }
      d.sets = sets;
    }
  } catch (e) { d = null; savedMonths.clear(); }
  if (d) delete d.setMonths;
  if (!d || !d.exercises) d = { exercises: [], days: {}, sets: [] };
  return migrate(d);
}
function migrate(d) {
  d.workouts = d.workouts || [];
  d.exercises.forEach(e => {
    e.track = e.track || ['weight', 'reps'];
    e.instructions = e.instructions || '';
    e.video = e.video || '';
  });
  for (const k in d.days) {
    const day = d.days[k];
    if (day.exercises && !day.items) { day.items = day.exercises.map(exId => ({ exId, sets: null })); delete day.exercises; }
    day.items = day.items || [];
    day.workouts = day.workouts || [];
  }
  // v3: every set gets a slot (its row number within that day)
  const groups = {};
  d.sets.forEach(s => { if (s.slot === undefined) (groups[s.exId + '|' + s.date] = groups[s.exId + '|' + s.date] || []).push(s); });
  Object.values(groups).forEach(g => {
    const taken = new Set(d.sets.filter(s => s.slot !== undefined && s.exId === g[0].exId && s.date === g[0].date).map(s => s.slot));
    let i = 0;
    g.sort((a, b) => a.ts - b.ts).forEach(s => { while (taken.has(i)) i++; s.slot = i++; });
  });
  d.plans = d.plans || [];
  if (d.activePlan === undefined) d.activePlan = null;
  d.settings = Object.assign({ units: 'metric', theme: 'system', weekStart: 1, defaultSets: 3, name: '' }, d.settings || {});
  d.version = 3;
  return d;
}
let data = load();
let saveError = '';
function saveLocal() {
  schedCache = null; sigMemo = null;
  try {
    const groups = new Map();
    for (const x of data.sets) { const m = String(x.date).slice(0, 7); let g = groups.get(m); if (!g) groups.set(m, g = []); g.push(x); }
    // Order matters if something fails part-way: the months first, then the list that points to them, then old months go
    for (const [m, g] of groups) if (!monthSame(m, g)) { localStorage.setItem(SKEY + m, JSON.stringify(g)); savedMonths.set(m, monthSig(g)); }
    const rest = Object.assign({}, data, { sets: [], setMonths: [...groups.keys()].sort() });
    localStorage.setItem(KEY, JSON.stringify(rest));
    for (const m of [...savedMonths.keys()]) if (!groups.has(m)) { localStorage.removeItem(SKEY + m); savedMonths.delete(m); }
    saveError = '';
  } catch (e) { savedMonths.clear(); saveError = "Couldn't save on this device."; }
}
function save() { saveLocal(); if (typeof scheduleSync === 'function') scheduleSync(); }
try { navigator.storage && navigator.storage.persist && navigator.storage.persist(); } catch (e) {}
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

/* ================= Dates ================= */
const pad = n => String(n).padStart(2, '0');
const dk = d => { const m = d.getMonth() + 1, n = d.getDate(); return d.getFullYear() + (m < 10 ? '-0' : '-') + m + (n < 10 ? '-0' : '-') + n; };
const parse = k => { const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const startOfWeek = d => addDays(d, -((d.getDay() - data.settings.weekStart + 7) % 7)); // Monday or Sunday, per Settings
const todayKey = () => dk(new Date());
const wd = () => data.settings.weekStart === 0 ? ['S', 'M', 'T', 'W', 'T', 'F', 'S'] : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
// Date text: formatters are made once and each day's text is remembered (formatting dates is slow, and lists repeat them)
const dateFmt = (opts, post = s => s) => {
  const f = new Intl.DateTimeFormat('en-GB', opts), memo = new Map();
  return k => { let s = memo.get(k); if (s === undefined) { s = post(f.format(parse(k))); if (memo.size > 3000) memo.clear(); memo.set(k, s); } return s; };
};
const fmtLong = dateFmt({ weekday: 'long', day: 'numeric', month: 'long' });
const fmtShort = dateFmt({ weekday: 'short', day: 'numeric', month: 'short' });
const fmtTiny = dateFmt({ day: 'numeric', month: 'short' });
const fmtDayYear = dateFmt({ weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }, s => s.replace(',', ''));
const MONTHS = Array.from({ length: 12 }, (_, i) => new Date(2000, i, 1).toLocaleDateString('en-GB', { month: 'long' }));
const monthName = d => MONTHS[d.getMonth()];

/* ================= Helpers ================= */
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtW = w => String(Math.round(w * 100) / 100);
const exById = id => data.exercises.find(e => e.id === id);
const woById = id => data.workouts.find(w => w.id === id);
const dayOf = k => data.days[k] || virtualDay(k) || { items: [], workouts: [] };
/* Index of logged sets: by exercise, by day and by exercise+day, so screens don't scan every set ever logged.
   Works for any list of sets (yours, or a friend's cached copy). Sets inside are the real objects, sorted by slot.
   Sets are only ever added with push, removed by making a new list, or have their weight/reps edited in place
   (the index holds the same objects, so those edits show up as they are). So: same list + same length = still valid,
   same list + longer = the new sets at the end are slotted in. */
const IX = new WeakMap();
const bySlot = (a, b) => a.slot - b.slot || a.ts - b.ts;
const byDateSlot = (p, q) => (p.date < q.date ? -1 : p.date > q.date ? 1 : bySlot(p, q));
function insertSorted(a, v, cmp) { let i = a.length; while (i > 0 && cmp(a[i - 1], v) > 0) i--; a.splice(i, 0, v); }
function ix(src = data.sets) {
  let x = IX.get(src);
  if (x && x.n === src.length) return x;
  if (x && x.n < src.length && src.length - x.n < 50) {
    for (let i = x.n; i < src.length; i++) {
      const s = src[i], ek = s.exId + '|' + s.date;
      let a = x.byExDate.get(ek); if (!a) x.byExDate.set(ek, a = []); insertSorted(a, s, bySlot);
      a = x.byEx.get(s.exId); if (!a) x.byEx.set(s.exId, a = []); insertSorted(a, s, byDateSlot);
      a = x.byDate.get(s.date); if (!a) x.byDate.set(s.date, a = []); a.push(s);
      a = x.exDates.get(s.exId); if (!a) x.exDates.set(s.exId, a = []); if (!a.includes(s.date)) insertSorted(a, s.date, (p, q) => (p < q ? -1 : p > q ? 1 : 0));
    }
    x.n = src.length;
    return x;
  }
  x = { n: src.length, byExDate: new Map(), byEx: new Map(), byDate: new Map(), exDates: new Map() };
  for (const s of src) {
    const ek = s.exId + '|' + s.date;
    let a = x.byExDate.get(ek); if (!a) x.byExDate.set(ek, a = []); a.push(s);
    a = x.byEx.get(s.exId); if (!a) x.byEx.set(s.exId, a = []); a.push(s);
    a = x.byDate.get(s.date); if (!a) x.byDate.set(s.date, a = []); a.push(s);
  }
  for (const a of x.byExDate.values()) a.sort(bySlot);
  for (const [id, a] of x.byEx) {
    a.sort(byDateSlot);
    const ds = []; for (const s of a) if (ds[ds.length - 1] !== s.date) ds.push(s.date);
    x.exDates.set(id, ds);   // the days that exercise was done, oldest first
  }
  IX.set(src, x);
  return x;
}
const NONE = Object.freeze([]);
const setsOf = (exId, k, src) => ix(src).byExDate.get(exId + '|' + k) || NONE;   // sorted by slot; don't modify
const setsFor = (exId, k) => setsOf(exId, k).slice();
const setsOn = (k, src) => ix(src).byDate.get(k) || NONE;
const hasSets = (k, src) => ix(src).byDate.has(k);
const exSets = (exId, src) => ix(src).byEx.get(exId) || NONE;        // oldest day first
const exDates = (exId, src) => ix(src).exDates.get(exId) || NONE;
// The last day before k that exercise was done
function prevDateOf(exId, k, src) {
  const ds = exDates(exId, src);
  let lo = 0, hi = ds.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (ds[m] < k) lo = m + 1; else hi = m; }
  return lo ? ds[lo - 1] : undefined;
}
const loggedDays = () => ix().byDate;   // has(k) works like the Set it used to be
// Filled dot = trained that day; ring = a planned workout day still to come
const dotCls = (k, logged) => logged.has(k) ? 'on' : (k >= todayKey() && dayOf(k).items.length) ? 'plan' : '';
const byName = (a, b) => a.name.localeCompare(b.name);
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const $ = id => document.getElementById(id);
function ytId(url) {
  const m = String(url).match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/))([\w-]{11})/);
  return m ? m[1] : null;
}
/* Units: weights are always stored in kg; shown and typed in the unit chosen in Settings */
const LB = 2.20462262;
const isImp = () => data.settings.units === 'imperial';
const U = () => isImp() ? 'lb' : 'kg';
const toU = kg => isImp() ? kg * LB : kg;
const fromU = v => isImp() ? v / LB : v;
const W = kg => isImp() ? String(Math.round(kg * LB * 10) / 10) : fmtW(kg);
const parseW = v => { const n = parseFloat(String(v).replace(',', '.')); return n >= 0 ? n : NaN; };
const parseR = v => { const n = parseInt(v, 10); return n > 0 ? n : NaN; };

/* Estimated 1RM — Wathan (1994). Among the most accurate equations for sets of
   roughly 10 reps or fewer (LeSuer et al. 1997 recommended it for squat and bench). */
const e1rm = s => s.reps <= 1 ? s.weight : (100 * s.weight) / (48.8 + 53.8 * Math.exp(-0.075 * s.reps));

const TRACK_A = [{ v: 'weight', label: 'Weight' }];
const TRACK_B = [{ v: 'reps', label: 'Reps' }];

/* ================= Icons (SF Symbols-style) ================= */
const svg = (p, s = 22, sw = 1.8) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
const ICON_BACK = svg('<path d="M15 5l-7 7 7 7"/>', 22, 2.4);
const ICON_CHEV = svg('<path d="M9 6l6 6-6 6"/>', 14, 2.6);
const ICON_CAL = svg('<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>');
const ICON_SEARCH = svg('<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>', 17, 2.2);
const ICON_CHECK = svg('<path d="M6 12.5l4 4 8-9"/>', 18, 3);
// Today's tab: a page showing today's date, like the iPhone Calendar app icon (so it doesn't look like the calendar button)
const iconToday = () => svg(`<rect x="3.5" y="3.5" width="17" height="17" rx="4.5"/><path d="M3.5 8.5h17"/><text x="12" y="17.6" text-anchor="middle" font-size="9.5" font-weight="700" fill="currentColor" stroke="none" style="font-family:var(--rounded)">${new Date().getDate()}</text>`, 26, 1.7);
const ICON_WORKOUTS = svg('<rect x="5" y="4" width="14" height="17" rx="2.5"/><path d="M9 4V3h6v1M9 10h6M9 14h6M9 18h3"/>', 26, 1.7);
const ICON_FRIENDS = svg('<circle cx="9" cy="8.5" r="3.2"/><path d="M3 19.5c.6-3.3 3-5 6-5s5.4 1.7 6 5"/><circle cx="17" cy="9.5" r="2.6"/><path d="M16.5 14.6c2.4.2 4 1.7 4.5 4.4"/>', 26, 1.7);
const ICON_SETTINGS = svg('<circle cx="12" cy="12" r="3"/><path d="M12 2.8l1.6 2.3 2.8-.4.9 2.7 2.5 1.3-.6 2.7 1.6 2.3-2.1 1.9.1 2.8-2.7.6-1.2 2.5-2.6-1-2.6 1-1.2-2.5-2.7-.6.1-2.8-2.1-1.9 1.6-2.3-.6-2.7 2.5-1.3.9-2.7 2.8.4z"/>', 26, 1.6);
const ICON_EXERCISES = svg('<path d="M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/>', 26, 1.9);
const ICON_X = svg('<path d="M6 6l12 12M18 6L6 18"/>', 18, 2.4);
const ICON_OK = svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 20, 2.6);
const ICON_GIFT = svg('<path d="M4 12l16-8-6 16-2-7-8-1z"/>', 18, 2);
const ICON_PLUS = svg('<path d="M12 5v14M5 12h14"/>', 16, 2.6);
const ICON_PREV = svg('<path d="M15 5l-7 7 7 7"/>', 18, 2.4);
const ICON_NEXT = svg('<path d="M9 5l7 7-7 7"/>', 18, 2.4);
const ICON_DOWN = svg('<path d="M5 9l7 7 7-7"/>', 22, 2.4);
// Every screen that has a back button slides down when you go back, so the button points down
const backBtn = label => `<button class="circle glass" id="back" aria-label="Back to ${esc(label)}">${ICON_DOWN}</button>`;
const closeBtn = (id, label = 'Cancel') => `<button class="circle glass" id="${id}" aria-label="${label}">${ICON_X}</button>`;
const okBtn = (id, label = 'Save') => `<button class="circle prominent" id="${id}" aria-label="${label}">${ICON_OK}</button>`;
const plusLead = `<span class="plus">${ICON_PLUS}</span>`;
const ICON_TRASH = svg('<path d="M4 7h16M9 7V4.5h6V7M6.5 7l1 13h9l1-13M10 11v6M14 11v6"/>', 20, 1.9);
const ICON_GRIP = svg('<path d="M5 9h14M5 15h14"/>', 20, 2.2);
const ICON_NOTE = svg('<path d="M14.5 4.5l5 5L9 20H4v-5z"/><path d="M12.5 6.5l5 5"/>', 17, 2);
const ICON_TIMER = svg('<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 2M9.5 2.5h5"/>', 18, 2);

/* ================= State & routing ================= */
const state = {
  tab: 'today',
  views: { today: 'day', workouts: 'wList', exercises: 'eList', friends: 'friends', settings: 'settings' },
  selected: todayKey(),
  weekStart: startOfWeek(new Date()),
  logExId: null,
  calMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  pending: null,
  pickerMode: null,
  pickerQuery: '',
  exQuery: '',
  detailExId: null,
  stat: 'e1rm',
  draft: null,        // workout being edited
  sheet: null,        // open bottom sheet
  drafts: {},         // unsaved values typed into set rows: { 'exId|date': { slot: {w, r} } }
};
const app = $('app');
const TAB_ROOT = { today: 'day', workouts: 'wList', exercises: 'eList', friends: 'friends', settings: 'settings' };

function render() {
  bgPending = false;
  if (typeof purgeStalePlanDays === 'function') purgeStalePlanDays();
  const VIEWS = { day: renderDay, log: renderLog, summary: renderSummary, history: renderHistory, picker: renderPicker, calendar: renderCalendar,
                  wList: renderWorkoutList, wEdit: renderWorkoutEdit, pView: renderPlanView, pEdit: renderPlanEdit, eList: renderExerciseList, eDetail: renderExerciseDetail,
                  friends: renderFriends, friend: renderFriend, me: renderMe, pWorkouts: renderProfWorkouts, pWorkout: renderProfWorkout,
                  fEx: renderFriendExercise, lib: renderLibrary, settings: renderSettings };
  clearInterval(timerTick);
  app.ontouchstart = app.ontouchend = null;
  VIEWS[state.views[state.tab]]();
  if (saveError) app.insertAdjacentHTML('afterbegin', `<div id="status">${saveError}</div>`);
  renderDock();
  renderSheet();
  animateSegs();
  polish();
  padAfterRender();
  document.body.classList.toggle('has-pdots', !!app.querySelector('.pdots'));
  pullSync();   // (a class instead of a :has() rule, which re-checks on every change)
  // Content that was swapped in place (another segment, filter, week or month) eases in instead of popping
  if (state.soft && !reduceMotion()) app.querySelectorAll(state.soft === true ? '.seg ~ *, .chips ~ *' : state.soft).forEach(el => { el.classList.remove('soft-in'); void el.offsetWidth; el.classList.add('soft-in'); });
  state.justTicked = null; state.justUnticked = null; state.newRow = null; state.soft = null;
}
/* Redraws that come from the background (sync, sign-in, friends, the shared database) wait until nothing is moving:
   no finger on the screen, no scroll still gliding, no screen sliding in, number pad closed. Several in a row become one.
   (Redrawing mid-swipe or mid-scroll makes things jump; this is what keeps it feeling solid.) */
let touching = 0, lastScroll = 0, bgPending = false, bgTimer = 0;
document.addEventListener('touchstart', e => { touching = e.touches.length; }, { passive: true, capture: true });
['touchend', 'touchcancel'].forEach(t => document.addEventListener(t, e => { touching = e.touches.length; if (!touching && bgPending) bgLater(120); }, { passive: true, capture: true }));
window.addEventListener('scroll', () => { lastScroll = performance.now(); }, { passive: true, capture: true });
const bgLater = ms => { clearTimeout(bgTimer); bgTimer = setTimeout(flushBg, ms); };
function bgRender() { bgPending = true; bgLater(0); }
function flushBg() {
  if (!bgPending) return;
  if (touching || np || performance.now() - lastScroll < 150 || document.querySelector('.ghost, .sheet-ghost')) return bgLater(200);
  bgPending = false;
  render();
}
const DEPTH = { day: 0, wList: 0, eList: 0, friends: 0, settings: 0, summary: 1, log: 1, picker: 1, calendar: 1, eDetail: 1, wEdit: 1, pView: 1, pEdit: 2, history: 2, friend: 1, me: 1, pWorkouts: 2, pWorkout: 3, fEx: 4, lib: 2 };
const reduceMotion = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
// How long the springy movements take (they match the --dur-* values in index.html; the springs themselves are defined there)
const SCREEN_MS = 700, SHEET_OUT_MS = 520, SWIPE_MS = 430, PULL_MS = 560;
// Snapshot of the current screen, used as the layer the new screen slides over (or that slides away)
// Only what's on the glass is copied: parts of the screen below the bottom edge are left out (long lists), and the copy
// is a window the size of the screen, scrolled to where you were. Much less to copy and to move while it animates.
function ghost(onTop) {
  const r = app.getBoundingClientRect(), vh = window.innerHeight;
  const g = app.cloneNode(true);
  const prune = (orig, copy, depth) => {
    const oc = orig.children, cc = copy.children;
    if (oc.length !== cc.length) return;
    for (let i = oc.length - 1; i >= 0; i--) {
      const b = oc[i].getBoundingClientRect();
      if (b.top > vh + 40) cc[i].remove();
      else if (depth < 6 && b.bottom > vh + 40 && oc[i].children.length) prune(oc[i], cc[i], depth + 1);
    }
  };
  prune(app, g, 0);
  g.removeAttribute('id');
  g.querySelectorAll('[id]').forEach(e => e.removeAttribute('id'));
  g.className = 'ghost' + (onTop ? ' top' : '');
  const top = Math.max(0, r.top);
  g.style.top = top + 'px'; g.style.height = (vh - top) + 'px'; g.style.paddingBottom = vh + 'px';
  g.setAttribute('aria-hidden', 'true');
  document.body.appendChild(g);
  if (r.top < 0) g.scrollTop = -r.top;
  return g;
}
function go(view, extra = {}) {
  const from = state.views[state.tab];
  const dir = extra.anim || (DEPTH[view] > DEPTH[from] ? 'up' : DEPTH[view] < DEPTH[from] ? 'down' : null);
  delete extra.anim;
  const g = dir && !reduceMotion() ? ghost(dir === 'down') : null;
  if (dir === 'up') scrollMemo[state.tab + ':' + from] = window.scrollY;
  Object.assign(state, extra);
  state.views[state.tab] = view;
  state.pending = null;
  render();
  // Going back returns you to where you were in the list; going deeper starts at the top
  const backTo = dir === 'down' ? scrollMemo[state.tab + ':' + view] || 0 : 0;
  delete scrollMemo[state.tab + ':' + view];
  window.scrollTo(0, backTo);
  syncTopbar();
  if (!g) return;
  document.querySelectorAll('.ghost').forEach(x => { if (x !== g) x.remove(); });
  app.classList.remove('enter-up', 'under');
  void app.offsetWidth;
  app.classList.add(dir === 'up' ? 'enter-up' : 'under');
  g.classList.add(dir === 'up' ? 'recede' : 'leave-down');
  setTimeout(() => { g.remove(); app.classList.remove('enter-up', 'under'); }, SCREEN_MS);
}

/* ================= Polish: the small things =================
   Runs after every screen draw. None of this adds features; it makes what's there feel finished:
   a top bar that turns to glass with a compact title once you scroll, a sliding day selection, numbers that count up
   when a screen opens, remembered scroll positions, and a soft fade where content meets the tab bar. */
let topEl = null, topThresh = Infinity, lastViewKey = '', weekPos = null;
const scrollMemo = {}, tabScroll = {};
function syncTopbar() {
  if (!topEl || !topEl.isConnected) return;
  const y = window.scrollY;
  topEl.classList.toggle('scrolled', y > 4);
  topEl.classList.toggle('titled', y > topThresh);
}
window.addEventListener('scroll', syncTopbar, { passive: true });
// Count a number up to its value (keeps its decimals and thousands separators)
function countUp(node) {
  const txt = node.textContent.trim(), m = txt.match(/^(\d[\d,]*)(\.\d+)?$/);
  if (!m) return;
  const end = parseFloat(txt.replace(/,/g, '')), dec = m[2] ? m[2].length - 1 : 0, comma = txt.includes(',');
  if (!(end > 0)) return;
  const fmt = v => comma ? v.toLocaleString('en-GB', { minimumFractionDigits: dec, maximumFractionDigits: dec }) : v.toFixed(dec);
  const t0 = performance.now(), dur = 650;
  const step = now => {
    if (!node.isConnected) return;
    const p = Math.max(0, Math.min(1, (now - t0) / dur)), e = 1 - Math.pow(1 - p, 3);   // a frame can be stamped just before t0
    node.textContent = p < 1 ? fmt(end * e) : txt;
    if (p < 1) requestAnimationFrame(step);
  };
  node.textContent = fmt(0);
  requestAnimationFrame(step);
}
function polish() {
  if (!$('dockfade')) { const f = document.createElement('div'); f.id = 'dockfade'; f.setAttribute('aria-hidden', 'true'); document.body.appendChild(f); }
  // Top bar: glass once content scrolls under it, with the screen's title in small type
  topEl = app.querySelector('header.nav, header.weekhead');
  const lt = app.querySelector('.large-title');
  topThresh = Infinity;
  if (topEl && lt && topEl.classList.contains('nav') && !topEl.querySelector('.title')) {
    const t = document.createElement('span'); t.className = 'nav-title'; t.setAttribute('aria-hidden', 'true'); t.textContent = lt.textContent;
    topEl.appendChild(t);
    topThresh = lt.getBoundingClientRect().bottom + window.scrollY - (topEl.offsetHeight + 12);
  }
  syncTopbar();
  // Week strip: the selected day's capsule slides to the day you pick
  const week = app.querySelector('#weekTrack > .week'), sel = week && week.querySelector('.day.sel');
  if (sel) {
    const ind = document.createElement('span'); ind.className = 'week-ind' + (sel.classList.contains('today') ? ' today' : ''); ind.setAttribute('aria-hidden', 'true');
    week.prepend(ind); week.classList.add('has-ind');
    const key = dk(state.weekStart), r = { x: sel.offsetLeft, w: sel.offsetWidth };
    const prev = weekPos && weekPos.key === key ? weekPos : null;
    slideTo(ind, prev, r);
    // The strip is redrawn on every tap, so the colour change is staged by hand to stay in step with the capsule
    if (prev && prev.x !== r.x && !reduceMotion()) {
      const days = [...week.querySelectorAll('.day')], left = days.find(d => d.offsetLeft === prev.x);
      sel.classList.add('arriving'); if (left) left.classList.add('leaving');
      void week.offsetWidth;
      requestAnimationFrame(() => { sel.classList.remove('arriving'); if (left) left.classList.remove('leaving'); });
    }
    weekPos = { key, ...r };
  }
  // Opening a screen: headline numbers count up
  const key = `${state.tab}:${state.views[state.tab]}:${state.logExId || ''}:${state.detailExId || ''}:${state.stat || ''}:${state.sumDate || ''}`;
  if (key !== lastViewKey && !reduceMotion()) {
    app.querySelectorAll('.stat-n').forEach(countUp);
    app.querySelectorAll('.headline').forEach(h => { if (h.firstChild && h.firstChild.nodeType === 3) countUp(h.firstChild); });
  }
  lastViewKey = key;
}

// Sets written compactly: the weight once, then the reps ("82.5 kg × 8, 7 · 85 kg × 5")
function setsCompact(ss) {
  const out = [];
  for (const s of ss) { const w = +s.weight, last = out[out.length - 1]; if (last && last.w === w) last.r.push(s.reps | 0); else out.push({ w, r: [s.reps | 0] }); }
  return out.map(g => g.w > 0 ? `${W(g.w)} ${U()} × ${g.r.join(', ')}` : `${g.r.join(', ')} reps`).join(' · ');
}
// A small ring showing how much of an exercise is done (a green check when it's all done)
function ringHTML(done, total) {
  const full = total > 0 && done >= total, C = 2 * Math.PI * 10;
  return `<span class="pring ${full ? 'full' : ''}" aria-hidden="true"><svg width="28" height="28" viewBox="0 0 28 28"><circle cx="14" cy="14" r="10" class="trk"/>${full
    ? '<path d="M9.5 14.5l3 3 6-7" class="chk"/>'
    : done ? `<circle cx="14" cy="14" r="10" class="arc" stroke-dasharray="${(C * done / total).toFixed(1)} ${C.toFixed(1)}" transform="rotate(-90 14 14)"/>` : ''}</svg></span>`;
}
// A smooth line through the points that never overshoots them (monotone cubic)
function smoothPath(P) {
  const n = P.length, f = v => v.toFixed(1);
  if (n < 3) return P.map((p, i) => `${i ? 'L' : 'M'}${f(p[0])},${f(p[1])}`).join('');
  const dx = [], m = [], t = [];
  for (let i = 0; i < n - 1; i++) { dx[i] = P[i + 1][0] - P[i][0]; m[i] = (P[i + 1][1] - P[i][1]) / (dx[i] || 1); }
  t[0] = m[0]; t[n - 1] = m[n - 2];
  for (let i = 1; i < n - 1; i++) t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
  for (let i = 0; i < n - 1; i++) {
    if (m[i] === 0) { t[i] = t[i + 1] = 0; continue; }
    const a = t[i] / m[i], b = t[i + 1] / m[i], s = a * a + b * b;
    if (s > 9) { const k = 3 / Math.sqrt(s); t[i] = k * a * m[i]; t[i + 1] = k * b * m[i]; }
  }
  let d = `M${f(P[0][0])},${f(P[0][1])}`;
  for (let i = 0; i < n - 1; i++) { const h = dx[i] / 3; d += `C${f(P[i][0] + h)},${f(P[i][1] + t[i] * h)} ${f(P[i + 1][0] - h)},${f(P[i + 1][1] - t[i + 1] * h)} ${f(P[i + 1][0])},${f(P[i + 1][1])}`; }
  return d;
}
const SKELETON = `<div class="skel-wrap" role="status" aria-label="Loading"><div class="stat-row three"><div class="skel sk-stat"></div><div class="skel sk-stat"></div><div class="skel sk-stat"></div></div>
  <div class="skel sk-title"></div><div class="skel sk-card"></div></div>`;

/* ================= Tab bar ================= */
// Place a freshly drawn selection highlight: it starts where it was last time (no animation from the edge),
// and slides only if the selection actually moved
function slideTo(el, prev, r) {
  const from = prev && (prev.x !== r.x || prev.w !== r.w) && !reduceMotion() ? prev : r;
  el.style.transition = 'none';
  el.style.width = from.w + 'px'; el.style.transform = `translateX(${from.x}px)`;
  void el.offsetWidth;
  el.style.transition = '';
  if (from !== r) { el.style.width = r.w + 'px'; el.style.transform = `translateX(${r.x}px)`; }
}
// Segmented controls: the selected "thumb" slides to its new place (remembered between renders)
const segPos = {};
function animateSegs(root = app) {
  root.querySelectorAll('.seg').forEach(seg => {
    const on = seg.querySelector('button.on'); if (!on) return;
    const key = seg.dataset.set || Object.keys(on.dataset).join(',') || 'seg';
    let th = seg.querySelector('.seg-thumb');
    if (!th) { th = document.createElement('span'); th.className = 'seg-thumb'; th.setAttribute('aria-hidden', 'true'); seg.prepend(th); }
    seg.classList.add('has-thumb');
    const r = { x: on.offsetLeft, w: on.offsetWidth };
    if (!th.style.transform || segPos[key]) slideTo(th, segPos[key], r);
    segPos[key] = r;
  });
}
/* Haptics, the way iPhone apps use them:
   'select'  a light tick when a choice changes (tabs, segments, chips, switches, wheel rows, scrubbing a chart)
   'impact'  a firmer tap for an action landing (ticking a set, a page turning, a dragged row moving, pulling past the close point)
   'success' two taps (workout finished, personal record, sent)      'warn' two slower taps (about to delete something)
   'error'   three quick taps (a set can't be ticked without numbers)
   Android vibrates in matching patterns.
   iPhone web apps can't vibrate. What they can do: a system switch (<input type=checkbox switch>, iOS 18+) plays the system
   haptic when it's toggled, and since iOS 26.5 only when YOUR tap toggles it (toggling it from code no longer ticks).
   So buttons that should tick get an invisible label laid over them, wired to a hidden switch (see hapticTargets below):
   your tap lands on the label, the label flips the switch, iOS ticks, and the tap carries on to the button as usual.
   That gives one tick per tap; haptic() itself still ticks from code on older iPhones and covers non-tap moments there. */
const IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
let hxTapAt = 0;   // when a tap last landed on one of those labels (that tap already ticked)
const haptic = (() => {
  let lbl = null, last = 0;
  const VIB = { select: 6, impact: 14, success: [12, 70, 18], warn: [22, 110, 22], error: [14, 50, 14, 50, 14] };
  const TICKS = { select: [0], impact: [0], success: [0, 110], warn: [0, 160], error: [0, 70, 140] };
  const tick = () => {
    if (!lbl) { lbl = document.createElement('label'); lbl.setAttribute('aria-hidden', 'true'); lbl.style.cssText = 'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;overflow:hidden';
      const inp = document.createElement('input'); inp.type = 'checkbox'; inp.setAttribute('switch', ''); inp.tabIndex = -1; lbl.appendChild(inp); document.body.appendChild(lbl); }
    lbl.click();
  };
  return (kind = 'select') => {
    try {
      const now = performance.now();
      if (now - last < 40) return;            // two at once would feel like one mushy buzz
      last = now;
      if (navigator.vibrate) { navigator.vibrate(VIB[kind] || VIB.select); return; }
      if (now - hxTapAt < 400) return;        // this tap already ticked through its label
      (TICKS[kind] || TICKS.select).forEach(t => t ? setTimeout(tick, t) : tick());
    } catch (e) {}
  };
})();
// Choices made anywhere get their tick without each screen having to ask: segmented controls, filter chips, switches
document.addEventListener('click', e => {
  if (!e.target.closest) return;
  if (e.target.closest('.seg button:not(.on), .np-seg button:not(.on), .chip, .pdot:not(.on), .week .day:not(.sel)')) haptic();
  const hx = e.target.closest('label.hx');
  if (hx) {
    hxTapAt = performance.now();
    // The label flips its switch only after this tap has been handled, and most taps redraw the screen, which would take the
    // label (and the tick) with it. So it steps out to the page for that moment, and goes once it has done its job.
    // (The tap still reaches the button: where it goes was settled when it landed.)
    document.body.appendChild(hx); hx.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;pointer-events:none';
    setTimeout(() => hx.remove(), 0);
  }
}, true);
// The app's on/off switches are real system switches, so on iPhone they tick by themselves when you flip them
document.addEventListener('change', e => { if (e.target.classList && e.target.classList.contains('switch') && !IS_IOS) haptic(); }, true);
// The controls that tick when tapped (on iPhone each gets the invisible label)
const HX_SEL = ['#dock button', '.seg button', '.np-seg button', '.chip', '.week .day', '.pdot', '.check', '#plus', '#minus', '.mini-stepper button',
  '.npk', '.np-step', '.np-next', '.trash', '#timer', '.pair button', '.mv-opt', '.pick-row', '.cell.destructive', '.primary', '.btn-tinted',
  '.circle.prominent', '[data-rm]', '[data-rmday]', '.capsule.tint-fill', '#rSkip', '.wheel-opt'].join(', ');
function hapticTargets() {
  for (const el of document.querySelectorAll(HX_SEL)) {
    if (el.lastElementChild && el.lastElementChild.classList.contains('hx')) continue;
    if (el.closest('.ghost, .peek, .sheet-ghost')) continue;
    if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
    const l = document.createElement('label'); l.className = 'hx'; l.setAttribute('aria-hidden', 'true');
    const sw = document.createElement('input'); sw.type = 'checkbox'; sw.setAttribute('switch', ''); sw.tabIndex = -1;
    sw.addEventListener('click', e => e.stopPropagation());   // the label passes its click to the switch: that copy goes no further
    l.appendChild(sw); el.appendChild(l);
  }
}
if (IS_IOS) {
  // Whatever gets drawn (screens, sheets, the number pad, the tab bar), its controls get their labels before you can tap them
  let q = 0;
  new MutationObserver(() => { if (!q) q = requestAnimationFrame(() => { q = 0; hapticTargets(); }); }).observe(document.body, { childList: true, subtree: true });
}
let dockPos = null;
function renderDock() {
  // Today stays in the middle
  const tabs = [['friends', 'Friends', ICON_FRIENDS], ['workouts', 'Workouts', ICON_WORKOUTS], ['today', 'Today', iconToday()], ['exercises', 'Exercises', ICON_EXERCISES], ['settings', 'Settings', ICON_SETTINGS]];
  const dock = $('dock');
  const reqs = (typeof friends !== 'undefined' && cloud.user) ? friends.links.filter(l => l.status === 'pending' && l.from !== cloud.user.uid).length + pendingGifts().length : 0;
  // Only redrawn when the selected tab, the badge or the date changes (not on every screen update)
  const sig = state.tab + '|' + reqs + '|' + todayKey();
  if (dock.dataset.sig === sig && dock.firstChild) return;
  dock.dataset.sig = sig;
  dock.innerHTML = tabs.map(([t, label, icon]) => `<button data-tab="${t}" class="${state.tab === t ? 'on' : ''}" aria-label="${label}${t === 'friends' && reqs ? `, ${reqs} new` : ''}">${icon}${t === 'friends' && reqs ? `<span class="tab-badge">${reqs}</span>` : ''}<span>${label}</span></button>`).join('');
  // The selection pill slides from the previous tab to the new one
  const on = dock.querySelector('button.on');
  if (on) {
    const ind = document.createElement('span'); ind.className = 'dock-ind'; ind.setAttribute('aria-hidden', 'true');
    dock.prepend(ind); dock.classList.add('has-ind');
    const r = { x: on.offsetLeft, w: on.offsetWidth };
    slideTo(ind, dockPos, r);
    dockPos = r;
  }
  dock.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => {
    const t = b.dataset.tab;
    if (state.tab === t) { if (state.views[t] === TAB_ROOT[t]) window.scrollTo({ top: 0, behavior: reduceMotion() ? 'auto' : 'smooth' }); else go(TAB_ROOT[t]); return; }
    haptic();
    tabScroll[state.tab] = window.scrollY;
    state.tab = t; state.pending = null; render(); window.scrollTo(0, tabScroll[t] || 0); syncTopbar();
    if (!reduceMotion()) {
      app.classList.remove('tab-in'); void app.offsetWidth; app.classList.add('tab-in');
      const nb = $('dock').querySelector('button.on'); if (nb) nb.classList.add('pop');
    }
  });
}

/* ================= Scroll wheel ================= */
const ITEM = 40;
function wheelHTML(id, options) {
  return `<div class="wheel${options.length === 1 ? ' single' : ''}" id="${id}"><div class="wheel-band"></div><div class="wheel-scroll"><div class="wheel-pad"></div>${options.map((o, i) =>
    `<div class="wheel-opt" data-i="${i}">${esc(o.label)}</div>`).join('')}<div class="wheel-pad"></div></div></div>`;
}
function initWheel(id, index) {
  const sc = $(id).querySelector('.wheel-scroll');
  const opts = [...sc.querySelectorAll('.wheel-opt')];
  // Like a real drum: rows curve away from the middle (squashed, smaller, fainter)
  let raf = 0, lastI = -1;
  const mark = () => {
    raf = 0;
    if (!sc.isConnected) return;
    const i = Math.max(0, Math.min(opts.length - 1, Math.round(sc.scrollTop / ITEM))), mid = sc.scrollTop + sc.clientHeight / 2;
    if (i !== lastI) { opts.forEach((o, j) => o.classList.toggle('on', i === j)); if (lastI >= 0) haptic(); lastI = i; }
    if (opts.length < 2) return;
    for (const o of opts) {
      const d = (o.offsetTop + ITEM / 2 - mid) / ITEM;
      if (Math.abs(d) > 3.5) { if (o._d !== 9) { o.style.transform = 'scaleY(.2)'; o.style.opacity = 0; o._d = 9; } continue; }
      const a = Math.min(Math.abs(d) * 24, 80) * Math.PI / 180;
      o.style.transform = `translateY(${-Math.sign(d) * (Math.abs(d) * ITEM - Math.sin(a) * ITEM / (24 * Math.PI / 180)) * .55}px) scaleY(${Math.cos(a).toFixed(3)}) scale(${(1 - Math.min(Math.abs(d), 3) * .05).toFixed(3)})`;
      o.style.opacity = (1 - Math.min(Math.abs(d), 3) * .22).toFixed(2);
      o._d = d;
    }
  };
  sc.scrollTop = index * ITEM;
  mark();
  sc.addEventListener('scroll', () => { if (!raf) raf = requestAnimationFrame(mark); }, { passive: true });
  opts.forEach(o => o.onclick = () => sc.scrollTo({ top: Number(o.dataset.i) * ITEM, behavior: 'smooth' }));
}
function wheelIndex(id) {
  const sc = $(id).querySelector('.wheel-scroll');
  const n = sc.querySelectorAll('.wheel-opt').length;
  return Math.max(0, Math.min(n - 1, Math.round(sc.scrollTop / ITEM)));
}

/* ================= Shared list builders ================= */
const cell = ({ attrs = '', main, sub = '', detail = '', chev = true, cls = '' }) =>
  `<button class="cell ${cls}" ${attrs}><span class="main"><div>${main}</div>${sub ? `<div class="sub">${sub}</div>` : ''}</span>${detail ? `<span class="detail">${detail}</span>` : ''}${chev ? `<span class="chev">${ICON_CHEV}</span>` : ''}</button>`;
const searchHTML = (id, ph) => `<label class="search">${ICON_SEARCH}<input id="${id}" placeholder="${ph}" autocomplete="off" type="search"></label>`;

/* ================= Drag to reorder ================= */
// Press and drag a row's grip handle; the other rows slide out of the way.
function makeSortable(list, onMove) {
  list.querySelectorAll('.drag-row .grip').forEach(grip => {
    grip.addEventListener('pointerdown', e => {
      e.preventDefault();
      const rows = [...list.querySelectorAll(':scope > .drag-row')];
      const row = grip.closest('.drag-row');
      const from = rows.indexOf(row);
      const rects = rows.map(r => r.getBoundingClientRect());
      const h = rects[from].height;
      const y0 = e.clientY;
      let to = from;
      grip.setPointerCapture(e.pointerId);
      haptic('impact');
      list.classList.add('sorting');
      row.classList.add('dragging');
      const move = ev => {
        const dy = Math.max(rects[0].top - rects[from].top - h * .6, Math.min(rects[rows.length - 1].top - rects[from].top + h * .6, ev.clientY - y0));
        row.style.transform = `translateY(${dy}px)`;
        const center = rects[from].top + h / 2 + dy, was = to;
        to = from;
        rows.forEach((r, j) => {
          const mid = rects[j].top + rects[j].height / 2;
          if (j > from && center > mid) to = j;
          if (j < from && center < mid && to === from) to = j;
        });
        if (to !== was) haptic();   // a tick each time the row passes another
        rows.forEach((r, j) => {
          if (j === from) return;
          const shift = (from < to && j > from && j <= to) ? -h : (to < from && j >= to && j < from) ? h : 0;
          r.style.transform = shift ? `translateY(${shift}px)` : '';
        });
      };
      const up = () => {
        grip.removeEventListener('pointermove', move);
        grip.removeEventListener('pointerup', up);
        grip.removeEventListener('pointercancel', up);
        list.classList.remove('sorting');
        if (to !== from) onMove(from, to);
        else { row.classList.remove('dragging'); rows.forEach(r => { r.style.transform = ''; }); }
      };
      grip.addEventListener('pointermove', move);
      grip.addEventListener('pointerup', up);
      grip.addEventListener('pointercancel', up);
    });
  });
}

/* ================= TODAY: day view ================= */
function weekLabel(ws, short) {
  const we = addDays(ws, 6);
  // When the Today button takes up room in the header, long month names are shortened so nothing gets cut off.
  if (short) return ws.getMonth() === we.getMonth()
    ? `${monthName(ws).slice(0, 3)}${ws.getFullYear() !== new Date().getFullYear() ? ` <span class="yr">${ws.getFullYear()}</span>` : ''}`
    : `${monthName(ws).slice(0, 3)}–${monthName(we).slice(0, 3)}`;
  const thisYear = new Date().getFullYear();
  const yr = y => y === thisYear ? '' : ` <span class="yr">${y}</span>`;
  if (ws.getMonth() === we.getMonth()) return `${monthName(ws)}${yr(ws.getFullYear())}`;
  return `${monthName(ws).slice(0, 3)} – ${monthName(we).slice(0, 3)}${yr(we.getFullYear())}`;
}

// A day whose exercises were all removed starts over: no workout name, no timer/finished state.
// If YOU emptied a planned day (trash), it becomes a moved rest day so the plan moves along, like "Move back a day"
// with "Just this workout". Otherwise (e.g. an exercise was deleted) the stored copy goes and the plan shows the day again.
function clearEmptyDay(k, byUser) {
  const d = data.days[k]; if (!d) return;
  d.workouts = [];
  if (!hasSets(k)) delete d.session;
  if (d.session) return;
  if (byUser && d.plan && !d.pinned && k >= todayKey() && activePlan()) data.days[k] = { items: [], workouts: [], rest: true, absorb: 'next' };
  else delete data.days[k];
}

// "Do it today" from another day:
//  • the next workout of your plan, while today is a rest day → it's brought to today (nothing is skipped)
//  • a one-off workout you put on a day yourself → moved to today (copied if it's in the past)
const todayIsFree = () => { const tk = todayKey(); return !hasSets(tk) && !(dayOf(tk).session) && !dayOf(tk).items.length; };
function canDoToday(k) {
  const tk = todayKey(), d = dayOf(k);
  if (k === tk || !d.items.length || hasSets(k) || d.session) return false;
  const pd = planDayFor(k);
  if (pd && pd.workout && !(data.days[k] && !data.days[k].plan)) { const nx = upNext(); return k > tk && todayIsFree() && nx && nx.k === k; }
  return true;
}
function doToday(k) {
  const pd = planDayFor(k);
  if (pd && pd.workout && !(data.days[k] && !data.days[k].plan)) return pinToday();
  const tk = todayKey(), src = dayOf(k);
  const name = src.workouts.length ? src.workouts.map(w => w.name).join(' + ') : 'Workout';
  const d = ensureDay(tk);
  src.items.forEach(it => { if (!d.items.some(i => i.exId === it.exId)) d.items.push({ exId: it.exId, sets: it.sets }); });
  src.workouts.forEach(w => { if (!d.workouts.some(x => x.id === w.id)) d.workouts.push({ id: w.id, name: w.name }); });
  delete d.rest;
  if (k > tk) delete data.days[k];          // moved, not copied
  if (isFinished(tk)) delete d.session.end;  // today was already finished: carry on
  state.selected = tk; state.weekStart = startOfWeek(new Date());
  save(); haptic('impact');
  go('day');
  toast(`<span class="tic" style="background:var(--tint-soft);color:var(--tint)">${svg('<path d="M4 12h13M13 7l5 5-5 5"/>', 18, 2.2)}</span><span>${esc(name)} is on today</span>`);
}

function renderDay() {
  const logged = loggedDays();
  const tk = todayKey();
  const showToday = dk(state.weekStart) !== dk(startOfWeek(new Date())) || state.selected !== tk;
  const weekHTML = ws => `<div class="week">${Array.from({ length: 7 }, (_, i) => {
    const k = dk(addDays(ws, i));
    const cls = ['day', k === tk && 'today', k === state.selected && 'sel'].filter(Boolean).join(' ');
    return `<button class="${cls}" data-k="${k}"><span class="wd">${wd()[i]}</span><span class="num">${parse(k).getDate()}</span><span class="dot ${dotCls(k, logged)}"></span></button>`;
  }).join('')}</div>`;

  // Everything below the week strip, for any day (also drawn for the neighbouring days while you swipe)
  const dayBodyHTML = k => {
    const day = dayOf(k);
    const pd = planDayFor(k);
    const st = data.days[k];
    const untouched = !logged.has(k) && !day.session;
    const canRest = pd && pd.workout && k >= tk && untouched && !(st && !st.plan && st.items.length) && !(st && st.pinned);
    const canUnrest = k >= tk && st && st.rest && !st.items.length && !logged.has(k);
    const canUnpin = k >= tk && st && st.pinned && untouched;
    const nx = k === tk && todayIsFree() && pd && !pd.workout && !pd.extra ? upNext() : null;   // rest day today: offer the next workout
    const rows = day.items.map(it => {
      const ex = exById(it.exId); if (!ex) return '';
      const s = setsFor(it.exId, k);
      const total = Math.max(it.sets || 0, s.length);
      const sub = s.length ? setsCompact(s) + (s.length < total ? ` · ${total - s.length} to go` : '') : plural(total, 'set');
      const confirm = k === state.selected && state.pending === 'trash:' + it.exId;
      return `<div class="cell-wrap drag-row" data-row="${it.exId}">
        <button class="grip" aria-label="Drag to reorder ${esc(ex.name)}">${ICON_GRIP}</button>
        <button class="cell" data-ex="${it.exId}" style="padding-left:0">${ringHTML(s.length, total)}<span class="main"><div>${esc(ex.name)}</div><div class="sub">${sub}</div></span></button>
        <button class="trash ${confirm ? 'confirm' : ''}" data-trash="${it.exId}" aria-label="Remove ${esc(ex.name)}">${confirm ? 'Delete' : ICON_TRASH}</button>
      </div>`;
    }).join('');
    return `
    <div class="day-title">${fmtLong(k)}</div>
    <div class="day-sub">${day.items.length && day.workouts.length ? day.workouts.map(w => esc(w.name)).join(' + ') : day.items.length ? 'Custom workout'
      : pd && pd.extra ? 'Rest day (moved)' : pd && pd.workout ? `${esc(pd.workout.name)} (no exercises yet)` : pd ? 'Rest day' : k < tk ? 'Nothing logged' : 'No workout planned'}${day.items.length && k < tk && !logged.has(k) && !day.session ? ' · not trained' : ''}${pd ? ` · ${esc(pd.plan.name)}${pd.index >= 0 ? `, day ${pd.index + 1} of ${pd.plan.days.length}` : ''}` : ''}${day.session ? ` · ${day.session.end ? 'Finished in ' + fmtMins(day.session.end - day.session.start) : 'In progress'}` : ''}</div>
    ${isFinished(k) && hasSets(k) ? `<button class="capsule glass move-btn" id="sumBtn">${svg('<path d="M5 19V11M12 19V5M19 19v-6"/>', 16, 2.4)} Workout summary</button>` : ''}
    ${nx ? `<button class="capsule glass move-btn" id="pullNext">${svg('<path d="M7 5l11 7-11 7z"/>', 15, 2.2)} Do ${esc(nx.workout.name)} today</button>` : ''}
    ${canDoToday(k) ? `<button class="capsule glass move-btn" id="doToday">${svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 16, 2.4)} Do it today</button>` : ''}
    ${canRest ? `<button class="capsule glass move-btn" id="restDay">${svg('<path d="M4 12h13M13 7l5 5-5 5"/>', 15, 2.2)} ${k === tk ? "Can't make it today" : 'Move back a day'}</button>` : ''}
    ${canUnrest ? `<button class="capsule glass move-btn" id="unrestDay">${svg('<path d="M4 12a8 8 0 1 0 2.3-5.7M4 4v5h5"/>', 15, 2.2)} Undo move</button>` : ''}
    ${canUnpin ? `<button class="capsule glass move-btn" id="unpinDay">${svg('<path d="M4 12a8 8 0 1 0 2.3-5.7M4 4v5h5"/>', 15, 2.2)} Undo</button>` : ''}
    ${(() => {
      if (!day.items.length || !(day.session || logged.has(k))) return '';
      const total = day.items.reduce((a, it) => a + Math.max(it.sets || 0, setsFor(it.exId, k).length), 0), done = day.items.reduce((a, it) => a + setsFor(it.exId, k).length, 0);
      return total ? `<div class="dprog ${done >= total ? 'full' : ''}" role="progressbar" aria-label="Sets done" aria-valuemin="0" aria-valuemax="${total}" aria-valuenow="${done}"><i style="width:${Math.round(100 * done / total)}%"></i></div>` : '';
    })()}
    ${day.items.length ? `<div class="group" id="dayList">${rows}</div>` : `<div class="day-empty"><span class="de-ic">${pd && !pd.workout
        ? svg('<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>', 26, 1.8) : svg('<path d="M6.5 6.5v11M17.5 6.5v11M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/>', 26, 1.8)}</span>
      <b>${pd && !pd.workout ? 'Rest day' : k < tk ? 'Nothing logged' : 'Nothing planned'}</b>
      <span>${pd && !pd.workout ? 'Recovery is part of the plan.' : k < tk ? 'You can still add what you did.' : 'Add an exercise or a workout to get going.'}</span></div>`}
    ${day.items.length && canFinish(k) ? `<button class="primary" id="finishDay">${svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 18, 2.6)}&nbsp;Finish workout</button>` : ''}
    <button class="btn-tinted" id="addEx">${ICON_PLUS} Add exercise / workout</button>`;
  };
  const k = state.selected;

  app.innerHTML = `
    <header class="weekhead">
      <span class="title">${weekLabel(state.weekStart, showToday && monthName(state.weekStart).length > 5)}</span>
      <span class="spacer"></span>
      ${showToday ? '<button class="capsule glass" id="today">Today</button>' : ''}
      <span class="pair glass"><button id="prevW" aria-label="Previous week">${ICON_PREV}</button><button id="nextW" aria-label="Next week">${ICON_NEXT}</button></span>
      <button class="circle glass" id="calBtn" aria-label="Calendar">${ICON_CAL}</button>
    </header>
    <div class="week-wrap" id="weekWrap"><div class="week-track ${state.weekSlide ? 'from-' + state.weekSlide : ''}" id="weekTrack">${weekHTML(state.weekStart)}</div></div>
    <div class="swipe-area day-swipe" id="daySwipe"><div class="pager" id="dayPager"><div class="slide-wrap ${state.daySlide ? 'from-' + state.daySlide : ''}">${dayBodyHTML(k)}</div></div></div>`;
  state.daySlide = null; state.weekSlide = null;

  // The arrow buttons slide the new week in from the side it comes from (a swipe has already moved it there)
  const shift = (n, slide) => { state.weekStart = addDays(state.weekStart, 7 * n); if (slide) { state.weekSlide = n > 0 ? 'right' : 'left'; haptic(); } render(); };
  $('prevW').onclick = () => shift(-1, true);
  $('nextW').onclick = () => shift(1, true);
  const pickDay = k2 => { if (k2 === state.selected) return; state.daySlide = k2 > state.selected ? 'right' : 'left'; state.selected = k2; state.pending = null; render(); };
  if ($('today')) $('today').onclick = () => { state.weekStart = startOfWeek(new Date()); if (tk !== state.selected) pickDay(tk); else render(); };
  $('calBtn').onclick = () => { const d = parse(state.selected); go('calendar', { calMonth: new Date(d.getFullYear(), d.getMonth(), 1) }); };
  $('addEx').onclick = () => go('picker', { pickerQuery: '', pickerMode: data.workouts.length ? 'workouts' : 'exercises' });
  app.querySelectorAll('.day').forEach(b => b.onclick = () => pickDay(b.dataset.k));
  app.querySelectorAll('[data-ex]').forEach(b => b.onclick = () => go('log', { logExId: b.dataset.ex }));
  if ($('finishDay')) $('finishDay').onclick = () => openFinish(state.selected);
  if ($('restDay')) $('restDay').onclick = () => openSheet({ type: 'moveBack', k });
  if ($('unpinDay')) $('unpinDay').onclick = () => { unpin(k); render(); };
  if ($('unrestDay')) $('unrestDay').onclick = () => { unrest(k); render(); };
  if ($('pullNext')) $('pullNext').onclick = () => pinToday();
  if ($('doToday')) $('doToday').onclick = () => doToday(state.selected);
  if ($('sumBtn')) $('sumBtn').onclick = () => go('summary', { sumDate: state.selected });
  app.querySelectorAll('[data-trash]').forEach(b => b.onclick = () => {
    const exId = b.dataset.trash, k = state.selected;
    const hasSets = setsFor(exId, k).length > 0;
    if (hasSets && state.pending !== 'trash:' + exId) { haptic('warn'); state.pending = 'trash:' + exId; return render(); }
    haptic('impact');
    collapseOut(b.closest('.cell-wrap'), () => {
      const d = ensureDay(k);
      d.items = d.items.filter(i => i.exId !== exId);
      data.sets = data.sets.filter(x => !(x.exId === exId && x.date === k));
      delete state.drafts[exId + '|' + k];
      if (rest && rest.date === k && rest.exId === exId) stopRest();
      if (!d.items.length) clearEmptyDay(k, true);
      save(); state.pending = null; render();
    });
  });
  if ($('dayList')) makeSortable($('dayList'), (from, to) => {
    const items = ensureDay(state.selected).items;
    items.splice(to, 0, items.splice(from, 1)[0]);
    save(); render();
  });

  // Swipe the day itself left/right to go to the next/previous day (the week strip follows)
  swipePager($('daySwipe'), $('dayPager'), {
    peek: dir => dayBodyHTML(dk(addDays(parse(k), dir))),
    commit: dir => { const k2 = dk(addDays(parse(k), dir)); state.selected = k2; state.weekStart = startOfWeek(parse(k2)); state.pending = null; render(); },
  });
  swipePager($('weekWrap'), $('weekTrack'), {
    peek: dir => weekHTML(addDays(state.weekStart, 7 * dir)),
    commit: dir => shift(dir),
  });
}

/* ================= TODAY: log sets ================= */
function logModel(k, idx) {
  const day = dayOf(k);
  const item = day.items[idx];
  const ex = item && exById(item.exId);
  if (!ex) return null;
  const today = setsFor(ex.id, k);
  const bySlot = {};
  today.forEach(s => { bySlot[s.slot] = s; });
  const maxSlot = today.reduce((m, s) => Math.max(m, s.slot), -1);
  const n = Math.max(item.sets || 0, maxSlot + 1);
  const dkey = ex.id + '|' + k;
  const drafts = (state.drafts[dkey] = state.drafts[dkey] || {});
  const prevK = prevDateOf(ex.id, k);
  const prevSets = prevK ? setsOf(ex.id, prevK) : [];
  return { day, item, ex, today, bySlot, n, dkey, drafts, prevK, prevSets, idx, total: day.items.length };
}

// Suggested values for a row that isn't done yet:
// what you typed → the closest finished set above it today → same set last time → last set last time
function suggest(m, i) {
  if (m.drafts[i]) return m.drafts[i];
  for (let j = i - 1; j >= 0; j--) if (m.bySlot[j]) return { w: W(m.bySlot[j].weight), r: String(m.bySlot[j].reps) };
  const p = m.prevSets[i] || m.prevSets[m.prevSets.length - 1];
  return p ? { w: W(p.weight), r: String(p.reps) } : { w: '', r: '' };
}

function logBodyHTML(m) {
  const { ex, bySlot, n, prevK, prevSets } = m;
  const pr = prFor(ex.id, state.selected);
  let rows = '';
  for (let i = 0; i < n; i++) {
    const s = bySlot[i];
    const v = s ? { w: W(s.weight), r: String(s.reps) } : suggest(m, i);
    const just = s && state.justTicked === s.id;
    rows += `<div class="setrow ${s ? 'done' : ''} ${just ? 'just' : ''} ${state.newRow === i ? 'new' : ''} ${!s && state.justUnticked === i ? 'unjust' : ''}" data-i="${i}">
      <span class="sn">${i + 1}${s && pr && pr.set.id === s.id ? '<span class="pr-mini">PR</span>' : ''}</span>
      <input class="w" readonly inputmode="none" tabindex="-1" autocomplete="off" aria-label="Set ${i + 1} weight in ${U()}" value="${esc(v.w)}" placeholder="${U()}">
      <input class="r" readonly inputmode="none" tabindex="-1" autocomplete="off" aria-label="Set ${i + 1} reps" value="${esc(v.r)}" placeholder="reps">
      <button class="check" aria-label="${s ? 'Undo' : 'Complete'} set ${i + 1}"><span class="ring">${s ? ICON_CHECK : ''}</span></button>
    </div>`;
  }
  const canMinus = n > 0 && !bySlot[n - 1];
  const vid = ytId(ex.video);
  return `
    <div class="eyebrow">Exercise ${m.idx + 1} of ${m.total}</div>
    <div class="large-title">${esc(ex.name)}</div>
    <button class="lastbar" id="history">
      <span class="main"><span class="lb-label">${prevK ? `Last time · ${fmtShort(prevK)}` : 'Last time'}</span>
      <span class="lb-sets">${prevK ? setsCompact(prevSets) : 'No earlier sessions'}</span></span>
      <span class="lb-more">History <span class="chev">${ICON_CHEV}</span></span>
    </button>
    ${ex.note ? `<button class="note-row" id="noteBtn" aria-label="Note: ${esc(ex.note)}. Tap to edit">${ICON_NOTE}<span class="note-t">${esc(ex.note)}</span></button>`
      : `<button class="note-add" id="noteBtn">${ICON_NOTE}Add a note</button>`}
    ${ex.instructions || vid ? `<details class="instr"><summary>Instructions</summary>
      ${ex.instructions ? `<div class="instr-text">${esc(ex.instructions)}</div>` : ''}
      ${vid ? `<a href="https://www.youtube.com/watch?v=${vid}" target="_blank" rel="noopener">Watch video on YouTube ↗</a>` : ''}
    </details>` : ''}
    <div class="group">
      <div class="sets-head"><span>Set</span><span>${U()}</span><span>Reps</span><span></span></div>
      ${rows || '<div class="empty">No sets planned.</div>'}
    </div>

    <div class="stepper glass">
      <button id="minus" aria-label="Remove a set" ${canMinus ? '' : 'disabled'}>−</button>
      <span>${plural(n, 'set')}</span>
      <button id="plus" aria-label="Add a set">+</button>
    </div>
    ${(canFinish(state.selected) || (state.selected === todayKey() && !isFinished(state.selected))) && (m.idx === m.total - 1 || setsLeft(state.selected) === 0)
      ? `<button class="primary finish-btn" id="finishHere">${svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 18, 2.6)}&nbsp;Finish workout</button>` : ''}
    ${m.idx === m.total - 1 ? `<button class="btn-tinted" id="addMore" ${isFinished(state.selected) ? 'style="margin-top:22px"' : ''}>${ICON_PLUS} Add exercise</button>` : ''}`;
}

// Page dots: one per exercise. Tap one to jump there.
function dotsHTML(k, current) {
  const items = dayOf(k).items;
  if (items.length < 2) return '';
  return `<div class="pdots glass" role="tablist">${items.map((it, i) => `<button class="pdot ${i === current ? 'on' : ''}" data-page="${i}" aria-label="Exercise ${i + 1}"></button>`).join('')}</div>`;
}
function pageHTML(k, i) {
  const items = dayOf(k).items;
  if (i < 0 || i >= items.length) return null;   // nothing past the last exercise: it just bounces
  return logBodyHTML(logModel(k, i));
}
function goPage(k, i, slide) {
  const items = dayOf(k).items;
  if (i < 0 || i >= items.length) return;
  go('log', { logExId: items[i].exId, slide });
}
function pagerShell(k, i, body) {
  return `
    <header class="nav">${backBtn(fmtShort(k))}<span class="spacer"></span>${timerHTML(k)}</header>
    <div class="swipe-area" id="swipeArea"><div class="pager" id="pager"><div class="slide-wrap ${state.slide ? 'from-' + state.slide : ''}">${body}</div></div></div>
    ${dotsHTML(k, i)}`;
}
function wirePager(k, i) {
  state.slide = null;
  $('back').onclick = () => go('day');
  wireTimer(k);
  app.querySelectorAll('[data-page]').forEach(b => b.onclick = () => { const j = Number(b.dataset.page); if (j !== i) goPage(k, j, j > i ? 'right' : 'left'); });
  const pager = $('pager');
  swipePager($('swipeArea'), pager, {
    peek: dir => pageHTML(k, i + dir),
    peekTop: () => Math.max(0, -pager.getBoundingClientRect().top + 56),
    commit: dir => goPage(k, i + dir, null),
  });
}

function renderLog() {
  const k = state.selected;
  const idx = dayOf(k).items.findIndex(it => it.exId === state.logExId);
  const m = idx >= 0 && logModel(k, idx);
  if (!m) return go('day');
  const { ex, bySlot, n, drafts } = m;
  const item = new Proxy({}, { get: (_, p) => realItem()[p], set: (_, p, v) => { realItem()[p] = v; return true; } });
  function realItem() { return ensureDay(k).items.find(it => it.exId === ex.id); }
  app.innerHTML = pagerShell(k, idx, logBodyHTML(m));
  wirePager(k, idx);

  const changed = () => { save(); state.pending = null; render(); };
  if ($('finishHere')) $('finishHere').onclick = () => openFinish(k);
  if ($('addMore')) $('addMore').onclick = () => go('picker', { pickerQuery: '', pickerMode: 'exercises', anim: 'up' });
  $('history').onclick = () => go('history', { stat: 'e1rm' });
  $('noteBtn').onclick = () => openSheet({ type: 'note', exId: ex.id });
  $('plus').onclick = () => { haptic(); item.sets = n + 1; state.newRow = n; changed(); };   // the new row grows in
  $('minus').onclick = () => {
    if (!(n > 0 && !bySlot[n - 1])) return;
    haptic();
    collapseOut(app.querySelector(`#pager .setrow[data-i="${n - 1}"]`), () => { item.sets = n - 1; delete drafts[n - 1]; changed(); });   // the last row folds away first
  };

  app.querySelectorAll('#pager .setrow').forEach(row => {
    const i = Number(row.dataset.i);
    const wIn = row.querySelector('.w'), rIn = row.querySelector('.r');
    const done = bySlot[i];
    [wIn, rIn].forEach(inp => {
      // Tapping a field opens the app's number pad (the field itself never takes focus, so no iPhone keyboard)
      inp.addEventListener('pointerdown', e => { e.preventDefault(); padOpen(ex.id, i, inp === wIn ? 'w' : 'r'); });
      inp.addEventListener('focus', () => { inp.blur(); padOpen(ex.id, i, inp === wIn ? 'w' : 'r'); });
      inp.addEventListener('input', () => {
        inp.classList.remove('bad');
        if (!done) drafts[i] = { w: wIn.value, r: rIn.value };
      });
      // Editing a finished set saves the change when you leave the field
      if (done) inp.addEventListener('change', () => {
        const w = parseW(wIn.value), r = parseR(rIn.value);
        if (isNaN(w) || isNaN(r)) { render(); return; }
        done.weight = fromU(w); done.reps = r; save();
      });
    });
    row.querySelector('.check').onclick = () => {
      if (np) { padCommit(); if (np.i === i) { np.fresh = true; if (!done) { const nx = i + 1; np = nx < n ? { ...np, i: nx, field: 'w' } : null; if (!np) padClose(); } } }
      if (done) {
        haptic();
        drafts[i] = { w: W(done.weight), r: String(done.reps) };
        data.sets = data.sets.filter(s => s.id !== done.id);
        state.justUnticked = i;
        changed(); return;
      }
      const w = parseW(wIn.value), r = parseR(rIn.value);
      if (isNaN(w)) wIn.classList.add('bad');
      if (isNaN(r)) rIn.classList.add('bad');
      if (isNaN(w) || isNaN(r)) return haptic('error');
      haptic('impact');
      const prBefore = prFor(ex.id, k);
      const newSet = { id: uid(), exId: ex.id, date: k, slot: i, weight: fromU(w), reps: r, ts: Date.now() };
      data.sets.push(newSet);
      state.justTicked = newSet.id;
      delete drafts[i];
      if (i + 1 > (item.sets || 0)) item.sets = i + 1;
      const d = ensureDay(k);
      if (!d.session && k === todayKey()) d.session = { start: Date.now() }; // first set logged today starts the timer
      const prNow = prFor(ex.id, k);
      const newPR = prNow && prNow.set.id === newSet.id && (!prBefore || prBefore.set.id !== newSet.id);
      if (newPR) setTimeout(() => haptic('success'), 140);
      if (newPR) toast(`<span class="tic">${ICON_TROPHY}</span><span>New personal record<small>${esc(ex.name)} · est. 1RM ${fmtStat(toU(prNow.now), 'e1rm')} ${U()}</small></span>`);
      if (k === todayKey() && !isFinished(k)) {
        const total = Math.max(item.sets || 0, n), doneNow = setsFor(ex.id, k).length;
        if (total >= 2 && doneNow < total) startRest(ex.id); else stopRest();   // last set of this exercise: off
        if (setsLeft(k) === 0 && !newPR) setTimeout(() => haptic('success'), 140);
        if (setsLeft(k) === 0 && !newPR) toast(`<span class="tic" style="background:var(--green-soft);color:var(--green)">${ICON_OK}</span><span>All planned sets done<small>Finish the workout when you're ready</small></span>`);
      }
      changed();
    };
  });
}

/* ================= Number pad for weight and reps =================
   The iPhone keyboard in a web app always comes with a bar of arrows and ✓, and guesses at AutoFill.
   So the set fields don't open it: tapping one slides up this pad instead. The fields stay real <input>s
   (readonly, never focused), and every change goes through their normal 'input' / 'change' events. */
let np = null;   // { exId, i, field: 'w' | 'r', fresh }
const padInput = () => np && app.querySelector(`#pager .setrow[data-i="${np.i}"] .${np.field}`);
const padRows = () => app.querySelectorAll('#pager .setrow').length;
function padEl() {
  let el = $('numpad');
  if (!el) {
    el = document.createElement('div'); el.id = 'numpad'; el.className = 'glass'; el.setAttribute('role', 'dialog'); el.setAttribute('aria-label', 'Number pad');
    document.body.appendChild(el);
    el.addEventListener('pointerdown', e => e.preventDefault());       // keeps taps on the pad from stealing anything
    // (the path, not e.target: on iPhone the tap lands on a haptic label that steps out of the key while it's handled)
    el.addEventListener('click', e => { const b = e.composedPath().find(n => n.dataset && n.dataset.k); if (b) padKey(b.dataset.k); });
  }
  return el;
}
function padOpen(exId, i, field) {
  const was = np;
  if (was && (was.i !== i || was.field !== field)) padCommit();
  np = { exId, i, field, fresh: true };
  if (!was) haptic();
  padDraw();
  const el = padEl();
  if (!el.classList.contains('on')) { el.classList.remove('off'); void el.offsetWidth; el.classList.add('on'); document.body.classList.add('np-open'); }
  padReveal();
}
function padClose() {
  if (!np) return;
  padCommit();
  np = null;
  document.body.classList.remove('np-open');
  const el = $('numpad'); if (el) { el.classList.remove('on'); el.classList.add('off'); }
  app.querySelectorAll('.setrow input.active').forEach(x => x.classList.remove('active', 'fresh'));
}
// Leaving a field: a finished set saves its edited numbers (the field's own 'change' handler)
function padCommit() { const inp = padInput(); if (inp && inp.dataset.dirty) { delete inp.dataset.dirty; inp.dispatchEvent(new Event('change')); } }
// Keep the field you're typing in visible above the pad
function padReveal() {
  const inp = padInput(), el = $('numpad'); if (!inp || !el) return;
  const row = inp.closest('.setrow').getBoundingClientRect(), limit = window.innerHeight - el.offsetHeight - 14;
  if (row.bottom > limit) window.scrollBy({ top: row.bottom - limit, behavior: reduceMotion() ? 'auto' : 'smooth' });
  else if (row.top < 70) window.scrollBy({ top: row.top - 70, behavior: reduceMotion() ? 'auto' : 'smooth' });
}
const STEP = () => (isImp() ? 5 : 2.5);
function padSet(v) {
  const inp = padInput(); if (!inp) return;
  inp.value = v; inp.dataset.dirty = '1';
  inp.classList.remove('bad');
  inp.dispatchEvent(new Event('input'));
}
function padKey(k) {
  const inp = padInput(); if (!np || !inp) return padClose();
  const isW = np.field === 'w';
  let v = np.fresh ? '' : inp.value;
  if (k === 'done') return padClose();
  if (k === 'next') return padNext();
  if (k === 'w' || k === 'r') return padOpen(np.exId, np.i, k);
  haptic();
  if (k === 'plus' || k === 'minus') {
    const cur = isW ? parseW(inp.value) : parseR(inp.value), base = isNaN(cur) ? 0 : cur;
    const next = Math.max(0, base + (k === 'plus' ? 1 : -1) * (isW ? STEP() : 1));
    padSet(isW ? String(Math.round(next * 100) / 100) : String(Math.max(isW ? 0 : 1, Math.round(next))));
    np.fresh = false; return padDraw();
  }
  if (k === 'back') v = v.slice(0, -1);
  else if (k === '.') { if (!isW || v.includes('.')) return; v = (v || '0') + '.'; }
  else { if (v === '0') v = ''; if (v.replace('.', '').length >= (isW ? 5 : 3) || (v.includes('.') && v.split('.')[1].length >= 2)) return; v += k; }
  np.fresh = false;
  padSet(v);
  padDraw();
}
// Weight → reps of the same set → weight of the next set → … → done
function padNext() {
  if (np.field === 'w') return padOpen(np.exId, np.i, 'r');
  if (np.i + 1 < padRows()) return padOpen(np.exId, np.i + 1, 'w');
  padClose();
}
function padDraw() {
  if (!np) return;
  const el = padEl(), inp = padInput(), isW = np.field === 'w';
  app.querySelectorAll('.setrow input.active').forEach(x => x.classList.remove('active', 'fresh'));
  if (inp) inp.classList.add('active'), inp.classList.toggle('fresh', np.fresh && !!inp.value);
  const last = np.field === 'r' && np.i + 1 >= padRows();
  const shown = inp && inp.value ? `${esc(inp.value)}<small>${isW ? U() : (inp.value === '1' ? 'rep' : 'reps')}</small>` : `<span class="ph">${isW ? U() : 'reps'}</span>`;
  // Typing only changes the number shown; the keys are redrawn only when the field (or what Next does) changes
  const sig = `${np.i}|${np.field}|${last}|${U()}`, num = el.querySelector('.np-num');
  if (el.dataset.sig === sig && num) { num.innerHTML = shown; return; }
  el.dataset.sig = sig;
  const key = (k, label, cls = '') => `<button class="npk ${cls}" data-k="${k}" aria-label="${label}">${label}</button>`;
  el.innerHTML = `
    <div class="np-top"><span class="np-where">Set ${np.i + 1}</span>
      <span class="np-seg" role="tablist"><button class="${isW ? 'on' : ''}" data-k="w" role="tab" aria-selected="${isW}">${U()}</button><button class="${isW ? '' : 'on'}" data-k="r" role="tab" aria-selected="${!isW}">Reps</button></span>
      <button class="np-next" data-k="next">${last ? 'Done' : np.field === 'w' ? 'Reps ›' : 'Next set ›'}</button></div>
    <div class="np-val"><button class="np-step" data-k="minus" aria-label="Minus ${isW ? STEP() + ' ' + U() : '1 rep'}">−${isW ? STEP() : 1}</button>
      <span class="np-num" aria-live="polite">${shown}</span>
      <button class="np-step" data-k="plus" aria-label="Plus ${isW ? STEP() + ' ' + U() : '1 rep'}">+${isW ? STEP() : 1}</button></div>
    <div class="np-keys">${['1', '2', '3', '4', '5', '6', '7', '8', '9'].map(d => key(d, d)).join('')}
      ${isW ? key('.', '.', 'fn') : `<button class="npk fn" data-k="done" aria-label="Hide number pad">${svg('<path d="M6 9l6 6 6-6"/>', 22, 2.4)}</button>`}${key('0', '0')}
      <button class="npk fn" data-k="back" aria-label="Delete">${svg('<path d="M21 6H9l-6 6 6 6h12z"/><path d="M17 10l-4 4M13 10l4 4"/>', 22, 1.9)}</button></div>`;
}
// Called after every screen draw: the pad follows the redrawn fields, or closes if you left the exercise
function padAfterRender() {
  if (!np) return;
  if (state.tab !== 'today' || state.views.today !== 'log' || state.logExId !== np.exId || state.sheet || !padInput()) {
    padClose(); return;
  }
  padDraw();
}
// Tapping anywhere outside the pad and the set fields puts the pad away
document.addEventListener('pointerdown', e => {
  if (!np || e.target.closest('#numpad, .setrow input, .check, #sheet')) return;
  padClose();
}, true);
// A hardware keyboard still works
document.addEventListener('keydown', e => {
  if (!np || e.metaKey || e.ctrlKey) return;
  const map = { Backspace: 'back', Enter: 'next', Tab: 'next', Escape: 'done', ',': '.', '.': '.', ArrowUp: 'plus', ArrowDown: 'minus' };
  const k = /^[0-9]$/.test(e.key) ? e.key : map[e.key];
  if (k) { e.preventDefault(); padKey(k); }
});

/* ================= Personal records ================= */
// A day's best set is a PR when its estimated 1RM beats every earlier day for that exercise.
// (Your very first session of an exercise doesn't count, otherwise everything would be a PR.)
function prevBest(exId, k, src = data.sets) {
  let b = null;
  for (const s of exSets(exId, src)) { if (s.date >= k) break; b = Math.max(b || 0, e1rm(s)); }   // oldest first, so stop at day k
  return b;
}
function prFor(exId, k, src = data.sets) {
  const ss = setsOf(exId, k, src); if (!ss.length) return null;
  const pb = prevBest(exId, k, src); if (pb === null) return null;
  const best = ss.reduce((a, b) => (e1rm(b) > e1rm(a) ? b : a));
  return e1rm(best) > pb + 1e-6 ? { set: best, prev: pb, now: e1rm(best) } : null;
}
const ICON_TROPHY = svg('<path d="M8 4h8v5a4 4 0 0 1-8 0V4z"/><path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8.5 20h7M10 17h4v3h-4z"/>', 18, 2);

/* ================= Rows leaving =================
   A removed row folds shut (height, fade, a slight shrink) before the screen is redrawn without it, instead of vanishing. */
let collapsing = false;
function collapseOut(el, done) {
  if (collapsing) return;
  if (!el || reduceMotion()) return done();
  collapsing = true;
  el.style.height = el.offsetHeight + 'px'; el.style.overflow = 'hidden';
  void el.offsetHeight;
  el.classList.add('collapsing'); el.style.height = '0px';
  setTimeout(() => { collapsing = false; done(); }, 300);
}

/* ================= Toast ================= */
function toast(html) {
  let t = $('toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'glass'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
  t.innerHTML = html;
  void t.offsetWidth;
  t.classList.add('show');
  clearTimeout(t._h);
  t._h = setTimeout(() => t.classList.remove('show'), 2800);
}

/* ================= Rest stopwatch ================= */
// Ticking a set of an exercise with 2+ sets starts a stopwatch that counts up, so you can see how long you've rested.
// The next ticked set restarts it; ticking that exercise's last set turns it off.
let rest = (() => { try { return JSON.parse(localStorage.getItem('tt.rest')); } catch (e) { return null; } })();
let restTick = null;
const saveRest = () => { try { rest ? localStorage.setItem('tt.rest', JSON.stringify(rest)) : localStorage.removeItem('tt.rest'); } catch (e) {} };
function startRest(exId) { rest = { start: Date.now(), exId, date: todayKey() }; saveRest(); renderRest(); }
function stopRest() { rest = null; saveRest(); renderRest(); }
function renderRest() {
  let el = $('rest');
  if (!el) { el = document.createElement('div'); el.id = 'rest'; document.body.appendChild(el); }
  clearInterval(restTick);
  document.body.classList.toggle('rest-on', !!rest);
  if (!rest) { el.classList.remove('on'); return; }
  const ex = exById(rest.exId);
  el.innerHTML = `<div class="rest-in glass"><div class="rest-mid"><span class="lbl">Rest</span><span class="t" id="restT"></span>${ex ? `<span class="rest-ex">${esc(ex.name)}</span>` : ''}</div>
    <button id="rSkip" aria-label="Stop rest stopwatch">${ICON_X}</button></div>`;
  el.classList.add('on');
  $('rSkip').onclick = () => stopRest();
  const tick = () => { const t = $('restT'); if (!rest || !t) return; const v = fmtDur(Date.now() - rest.start); if (t.textContent !== v) t.textContent = v; };
  tick();
  restTick = setInterval(tick, 500);
}

/* ================= Workout summary ================= */
function renderSummary() {
  const k = state.sumDate || state.selected;
  const d = dayOf(k), ss = setsOn(k).slice().sort((a, b) => a.ts - b.ts);
  if (!ss.length && !(d.session && d.session.end)) return go('day');
  const order = d.items.map(i => i.exId);
  const exIds = [...new Set([...order.filter(id => ss.some(s => s.exId === id)), ...ss.map(s => s.exId)])].filter(exById);
  const vol = ss.reduce((a, s) => a + s.weight * s.reps, 0);
  const title = d.workouts.length ? d.workouts.map(w => esc(w.name)).join(' + ') : 'Custom workout';
  const prs = exIds.map(id => ({ id, pr: prFor(id, k) })).filter(x => x.pr);
  const rows = exIds.map(id => {
    const mine = setsOf(id, k), best = mine.reduce((a, b) => (e1rm(b) > e1rm(a) ? b : a));
    const pk = prevDateOf(id, k);
    let delta = '<span class="delta same">First time</span>';
    if (pk) {
      const pb = Math.max(...setsOf(id, pk).map(e1rm));
      const pct = Math.round(((e1rm(best) - pb) / pb) * 100);
      delta = pct > 0 ? `<span class="delta up">▲ ${pct}%</span>` : pct < 0 ? `<span class="delta down">▼ ${-pct}%</span>` : '<span class="delta same">Same</span>';
    }
    return cell({ attrs: `data-sx="${id}"`, main: esc(exById(id).name), sub: `${plural(mine.length, 'set')} · best ${setTxt(best)}`, detail: delta });
  }).join('');
  const isToday = k === todayKey();
  app.innerHTML = `
    <header class="nav">${backBtn('Day')}</header>
    <div class="sum-hero">
      <div class="sum-check">${svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 38, 2.8)}</div>
      <div class="large-title">${isToday ? 'Workout complete' : 'Workout summary'}</div>
      <div class="day-sub">${title} · ${fmtLong(k)}</div>
    </div>
    <div class="stat-row two-by-two">
      <div class="stat"><div class="stat-n">${d.session && d.session.end ? fmtMins(d.session.end - d.session.start) : '–'}</div><div class="stat-l">duration</div></div>
      <div class="stat"><div class="stat-n">${ss.length}</div><div class="stat-l">sets</div></div>
      <div class="stat"><div class="stat-n">${Math.round(toU(vol)).toLocaleString('en-GB')}</div><div class="stat-l">${U()} lifted</div></div>
      <div class="stat"><div class="stat-n">${exIds.length}</div><div class="stat-l">${exIds.length === 1 ? 'exercise' : 'exercises'}</div></div>
    </div>
    ${prs.length ? `<div class="section">Personal records</div><div class="group">${prs.map(({ id, pr }) => `<button class="cell" data-sx="${id}"><span class="lead-ic">${ICON_TROPHY}</span>
      <span class="main"><div>${esc(exById(id).name)}</div><div class="sub">Est. 1RM ${fmtStat(toU(pr.now), 'e1rm')} ${U()} · up ${fmtStat(toU(pr.now - pr.prev), 'e1rm')} ${U()}</div></span>
      <span class="detail">${setTxt(pr.set)}</span><span class="chev">${ICON_CHEV}</span></button>`).join('')}</div>` : ''}
    ${exIds.length ? `<div class="section">Exercises</div><div class="group">${rows}</div>
      <div class="footnote">Arrows compare each exercise's best set (estimated 1RM) with the last time you did it.</div>` : ''}
    <button class="primary" id="sumDone" style="margin-top:24px">Done</button>`;
  $('back').onclick = () => go('day');
  $('sumDone').onclick = () => go('day');
  app.querySelectorAll('[data-sx]').forEach(b => b.onclick = () => { state.selected = k; go('log', { logExId: b.dataset.sx }); });
}

/* ================= Finger-following swipe ================= */
// The target moves with your finger (you can pause mid-swipe); the neighbouring page peeks in from the side.
// Let go past ~30% of the width, or flick, to turn the page; otherwise it springs back.
function swipePager(surface, target, opts) {
  let s = null;
  const ease = 'transform .5s var(--ease-soft)';
  const clearPeek = () => { if (s && s.peek) { s.peek.remove(); s.peek = null; } };
  // The neighbouring pages are built ahead of time, once the screen has settled, so a swipe starts moving on its
  // very first frame (building a page takes a few milliseconds, which would otherwise land right as your finger moves)
  const ready = {};
  const prep = dir => {
    if (dir in ready) return ready[dir];
    const html = opts.peek(dir);
    let p = null;
    if (html != null) {
      p = document.createElement('div');
      p.className = 'peek';
      p.setAttribute('aria-hidden', 'true');
      p.innerHTML = html;
      p.querySelectorAll('[id]').forEach(el => el.removeAttribute('id'));
    }
    return (ready[dir] = p);
  };
  const later = f => { const run = () => { if (!surface.isConnected || s) return; if (touching || performance.now() - lastScroll < 200) return setTimeout(run, 250); f(); }; setTimeout(run, 300); };
  later(() => { prep(1); later(() => prep(-1)); });   // only while nothing is moving
  surface.addEventListener('touchstart', e => {
    if (e.touches.length > 1 || e.target.closest('input, textarea, .chart, .grip')) { s = null; return; }
    const t = e.touches[0];
    s = { x: t.clientX, y: t.clientY, axis: null, dir: 0, dx: 0, peek: null, lx: t.clientX, lt: performance.now(), v: 0 };
    target.style.transition = 'none';
  }, { passive: true });
  surface.addEventListener('touchmove', e => {
    if (!s) return;
    const t = e.touches[0];
    const dx = t.clientX - s.x, dy = t.clientY - s.y;
    if (!s.axis) {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      s.axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
    }
    if (s.axis !== 'x') return;
    e.preventDefault();
    const now = performance.now();
    s.v = (t.clientX - s.lx) / Math.max(1, now - s.lt); s.lx = t.clientX; s.lt = now;
    const dir = dx < 0 ? 1 : -1;
    if (dir !== s.dir) {
      s.dir = dir;
      clearPeek();
      const p = prep(dir);
      if (p) {
        p.style.left = dir > 0 ? 'calc(100% + 16px)' : 'calc(-100% - 16px)';
        p.style.top = (opts.peekTop ? opts.peekTop() : 0) + 'px';
        target.appendChild(p);
        s.peek = p;
      }
    }
    s.dx = s.peek ? dx : dx * 0.25; // rubber-band when there's nothing on that side
    target.style.transform = `translateX(${s.dx}px)`;
  }, { passive: false });
  const end = () => {
    if (!s || s.axis !== 'x') { s = null; return; }
    const w = target.offsetWidth;
    const flick = Math.abs(s.v) > 0.45 && Math.sign(-s.v) === s.dir && Math.abs(s.dx) > 50;
    const st = s;
    s = null;
    target.style.transition = ease;
    if (st.peek && (Math.abs(st.dx) > w * 0.3 || flick)) {
      target.style.transform = `translateX(${-st.dir * (w + 16)}px)`;
      haptic();
      setTimeout(() => opts.commit(st.dir), SWIPE_MS);
    } else {
      target.style.transform = '';
      setTimeout(() => { if (st.peek && !(s && s.peek === st.peek)) st.peek.remove(); }, 520);
    }
  };
  surface.addEventListener('touchend', end);
  surface.addEventListener('touchcancel', end);
}

/* ================= Session timer ================= */
let timerTick = null;
const fmtDur = ms => {
  const t = Math.max(0, Math.floor(ms / 1000)), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, s = t % 60;
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
};
const fmtMins = ms => { const m = Math.round(ms / 60000), h = Math.floor(m / 60); return h ? `${h} h ${m % 60} min` : `${m} min`; };
const setsLeft = k => dayOf(k).items.reduce((a, it) => a + Math.max(0, (it.sets || 0) - setsFor(it.exId, k).length), 0);

// The timer runs until "Finish workout" (button, or tapping the running timer).
function timerHTML(k) {
  const s = dayOf(k).session;
  if (!s && k !== todayKey()) return canDoToday(k) ? `<button class="capsule glass" id="doTodayHdr">Do it today</button>` : '';   // no timer when filling in another day
  if (!s) return `<button class="capsule glass timer" id="timer" aria-label="Start session timer">${ICON_TIMER}<span>Start</span></button>`;
  if (s.end) return `<button class="capsule glass timer ended" id="timer" aria-label="Workout finished, tap to change duration">${ICON_OK}<span>${fmtMins(s.end - s.start)}</span></button>`;
  return `<button class="capsule glass timer running" id="timer" aria-label="Session time, tap to finish"><span class="rec"></span><span id="timerText">${fmtDur(Date.now() - s.start)}</span></button>`;
}
function wireTimer(k) {
  if ($('doTodayHdr')) $('doTodayHdr').onclick = () => doToday(k);
  if (!$('timer')) return;
  $('timer').onclick = () => {
    const day = ensureDay(k);
    const s = day.session;
    if (!s) { haptic('impact'); day.session = { start: Date.now() }; save(); return render(); }
    if (s.end) return openSheet({ type: 'duration', k });
    openFinish(k);
  };
  const s = dayOf(k).session;
  if (s && !s.end) timerTick = setInterval(() => { const t = $('timerText'); if (t) t.textContent = fmtDur(Date.now() - s.start); }, 1000);
}

/* Duration sheet: confirm/adjust the workout length to the minute */
const HOUR_OPTS = Array.from({ length: 10 }, (_, i) => ({ v: i, label: String(i) }));
const MIN_OPTS = Array.from({ length: 60 }, (_, i) => ({ v: i, label: pad(i) }));
/* Finish workout: confirm the duration to the minute, and offer to log sets that were filled in but not ticked */
function untickedSets(k) {
  const out = [];
  dayOf(k).items.forEach((it, idx) => {
    const m = logModel(k, idx); if (!m) return;
    for (let i = 0; i < m.n; i++) {
      if (m.bySlot[i]) continue;
      const v = suggest(m, i), w = parseW(v.w), r = parseR(v.r);
      out.push({ exId: m.ex.id, slot: i, w, r, ok: !isNaN(w) && !isNaN(r) });
    }
  });
  return out;
}
const isFinished = k => { const s = dayOf(k).session; return !!(s && s.end); };
const isRunning = k => { const s = dayOf(k).session; return !!(s && s.start && !s.end); };
// Finish workout is offered for a workout that's running, or for today once something is logged.
// (Past days you're just filling in afterwards don't get a timer or a Finish button.)
const canFinish = k => !isFinished(k) && (isRunning(k) || (k === todayKey() && hasSets(k)));
const openFinish = k => openSheet({ type: 'duration', k });
const LONG_GAP = 15 * 60000;   // a last set longer ago than this means the timer ran on after the workout
function sheetDuration(el) {
  const st = state.sheet, k = st.k;
  const day = dayOf(k);
  const s = day.session;
  const editing = s && s.end;
  const loggedToday = setsOn(k).slice();
  const unticked = editing ? [] : untickedSets(k);
  const okUnticked = unticked.filter(u => u.ok);
  if (st.logRest === undefined) st.logRest = okUnticked.length > 0;
  // Default duration: the timer, or (if it never ran) the time since the first logged set.
  // Forgot to press Finish? If the last ticked set was a while ago, the workout ends at that set instead of now.
  const firstTs = loggedToday.length ? Math.min(...loggedToday.map(x => x.ts)) : null;
  const lastTs = loggedToday.length ? Math.max(...loggedToday.map(x => x.ts)) : null;
  const ranLong = !editing && lastTs && Date.now() - lastTs > LONG_GAP && (!s || lastTs > s.start);
  const endAt = editing ? s.end : ranLong ? lastTs : Date.now();
  const ms = s ? endAt - s.start : firstTs && (k === todayKey() || ranLong) ? endAt - firstTs : 0;
  const mins = Math.max(0, Math.round(ms / 60000));
  const hm = t => new Date(t).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const nothing = !loggedToday.length && !(st.logRest && okUnticked.length);
  el.innerHTML = sheetOpen('Finish workout',
    `${closeBtn('sCancel')}<b>${editing ? 'Duration' : 'Finish workout'}</b>${okBtn('sSave', editing ? 'Save duration' : 'Finish workout')}`,
    `${!editing ? `
      <div class="finish-summary">${plural(loggedToday.length, 'set')} logged${unticked.length ? ` · ${plural(unticked.length, 'set')} not ticked` : ''}</div>
      ${okUnticked.length ? `
        <div class="group"><label class="set-row"><span class="lbl">Log the ${plural(okUnticked.length, 'unticked set')} as shown</span><input type="checkbox" switch class="switch" id="logRest" ${st.logRest ? 'checked' : ''}></label></div>
        <div class="footnote">Uses the weight and reps shown in each row.${unticked.length > okUnticked.length ? ` ${plural(unticked.length - okUnticked.length, 'set')} without numbers will be skipped.` : ''}</div>` : ''}
      ${nothing ? `<div class="footnote" style="color:var(--red)">No sets are logged, so this workout will show as empty. ${okUnticked.length ? 'Tick the sets you did, or log them above.' : 'Tick the sets you did first.'}</div>` : ''}
      <div class="section">Duration</div>` : ''}
     <div class="finish-sub" style="margin:0 6px 4px">${ranLong
       ? `${s ? `Started ${hm(s.start)} · ` : ''}ends at your last set, ${hm(lastTs)}`
       : `${s ? `Started ${hm(s.start)}` : "The timer wasn't running"} · adjust if needed`}</div>
     <div class="group"><div class="wheels dur">
       ${wheelHTML('wH', HOUR_OPTS)}<span class="unit">h</span>${wheelHTML('wM', MIN_OPTS)}<span class="unit">min</span>
     </div></div>
     ${editing && k === todayKey() ? `<button class="btn-tinted" id="sResume">${svg('<path d="M7 5l11 7-11 7z"/>', 16, 2.2)} Resume workout</button>
       <div class="footnote" style="text-align:center">Pressed Finish too early, or training again later today? The timer carries on from where it was.</div>` : ''}`);
  initWheel('wH', Math.min(9, Math.floor(mins / 60)));
  initWheel('wM', mins % 60);
  if ($('logRest')) $('logRest').onchange = e => { st.logRest = e.target.checked; st.h = wheelIndex('wH'); st.m = wheelIndex('wM'); renderSheet(); initWheel('wH', st.h); initWheel('wM', st.m); };
  $('sCancel').onclick = () => closeSheet();
  if ($('sResume')) $('sResume').onclick = () => { delete ensureDay(k).session.end; save(); closeSheet(); render(); };
  $('sSave').onclick = () => {
    const total = (HOUR_OPTS[wheelIndex('wH')].v * 60 + MIN_OPTS[wheelIndex('wM')].v) * 60000;
    const d = ensureDay(k);
    if (!editing && st.logRest) {
      let ts = ranLong ? lastTs + 1 : Date.now();
      okUnticked.forEach(u => {
        data.sets.push({ id: uid(), exId: u.exId, date: k, slot: u.slot, weight: fromU(u.w), reps: u.r, ts: ts++ });
        delete (state.drafts[u.exId + '|' + k] || {})[u.slot];
      });
    }
    // A running timer keeps its start and the duration sets the end; otherwise the duration counts back from the end
    if (s && !editing) d.session = { start: s.start, end: s.start + total };
    else { const end = editing ? s.end : endAt; d.session = { start: end - total, end }; }
    save();
    state.sheet = null;
    if (editing) { haptic(); return render(); }
    haptic('success');
    stopRest();
    if (hasSets(k)) go('summary', { sumDate: k }); else go('day');
  };
}

/* ================= TODAY: add exercise / workout ================= */
function renderPicker() {
  const mode = state.pickerMode;
  app.innerHTML = `
    <header class="nav">${backBtn(fmtShort(state.selected))}</header>
    <div class="eyebrow">${fmtLong(state.selected)}</div>
    <div class="large-title">Add to workout</div>
    <div class="seg"><button data-m="workouts" class="${mode === 'workouts' ? 'on' : ''}">Workouts</button><button data-m="exercises" class="${mode === 'exercises' ? 'on' : ''}">Exercises</button></div>
    ${mode === 'exercises' ? searchHTML('q', 'Search exercises') : ''}
    <div id="results"></div>`;
  $('back').onclick = () => go('day');
  app.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { if (state.pickerMode !== b.dataset.m) state.soft = true; state.pickerMode = b.dataset.m; render(); });
  const results = $('results');
  const inDay = dayOf(state.selected).items.map(i => i.exId);

  if (mode === 'workouts') {
    const list = data.workouts.slice().sort(byName);
    results.innerHTML = `<div class="group">${list.length
      ? list.map(w => cell({ attrs: `data-w="${w.id}"`, main: esc(w.name), sub: `${plural(w.items.length, 'exercise')} · ${plural(w.items.reduce((a, i) => a + i.sets, 0), 'set')}`, chev: false })).join('')
      : '<div class="empty">No workouts yet. Make one in the Workouts tab.</div>'}</div>`;
    results.querySelectorAll('[data-w]').forEach(b => b.onclick = () => addWorkoutToDay(b.dataset.w));
    return;
  }
  const q = $('q');
  q.value = state.pickerQuery;
  const draw = () => {
    state.pickerQuery = q.value;
    const term = q.value.trim().toLowerCase();
    const matches = data.exercises.filter(e => e.name.toLowerCase().includes(term)).sort(byName);
    const fromLib = term ? libAll().filter(x => normName(x.name).includes(normName(term)) && !mineFor(x)).slice(0, 5) : [];
    results.innerHTML = `<div class="group"><button class="cell action" data-browse="1">${plusLead}Browse exercise database</button><button class="cell action" data-new="1">${plusLead}New exercise${q.value.trim() ? ` “${esc(q.value.trim())}”` : ''}</button></div>
      ${matches.length ? `<div class="group">${matches.map(e => inDay.includes(e.id)
        ? `<button class="cell" disabled><span class="main">${esc(e.name)}</span><span class="detail">Added</span></button>`
        : cell({ attrs: `data-id="${e.id}"`, main: esc(e.name), chev: false })).join('')}</div>` : ''}
      ${fromLib.length ? `<div class="section">From the database</div><div class="group">${fromLib.map(x => libRowHTML(x, 'day')).join('')}</div>` : ''}`;
    results.querySelectorAll('[data-id]').forEach(b => b.onclick = () => addExerciseToDay(b.dataset.id, null));
    wireLibRows(results, 'day', draw);
    results.querySelector('[data-browse]').onclick = () => go('lib', { libBack: 'picker', libEdit: false, libFilter: { q: q.value.trim(), muscle: '', equip: '' } });
    results.querySelector('[data-new]').onclick = () => openSheet({ type: 'exForm', exId: null, name: q.value.trim(), onSave: id => addExerciseToDay(id, null) });
  };
  q.oninput = draw;
  draw();
}
// Makes a day real (stored). A planned day that hasn't been touched yet is filled in from the plan.
function ensureDay(k) { return (data.days[k] = data.days[k] || virtualDay(k) || { items: [], workouts: [] }); }
function addExerciseToDay(exId, sets) {
  const day = ensureDay(state.selected);
  if (!day.items.some(i => i.exId === exId)) day.items.push({ exId, sets: sets || data.settings.defaultSets });
  save(); go('log', { logExId: exId });
}
function addWorkoutToDay(wId) {
  const w = woById(wId); if (!w) return;
  const day = ensureDay(state.selected);
  w.items.forEach(it => { if (!day.items.some(i => i.exId === it.exId)) day.items.push({ exId: it.exId, sets: it.sets }); });
  if (!day.workouts.some(x => x.id === w.id)) day.workouts.push({ id: w.id, name: w.name });
  save(); go('day');
}

/* ================= TODAY: calendar ================= */
function renderCalendar() {
  const m = state.calMonth;
  const logged = loggedDays();
  const tk = todayKey();
  const start = startOfWeek(m);
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const d = addDays(start, i);
    if (i >= 35 && d.getMonth() !== m.getMonth()) break;
    const k = dk(d);
    const cls = [d.getMonth() !== m.getMonth() && 'out', k === tk && 'today', k === state.selected && 'sel'].filter(Boolean).join(' ');
    cells.push(`<button class="${cls}" data-k="${k}"><span class="num">${d.getDate()}</span><span class="dot ${dotCls(k, logged)}"></span></button>`);
  }
  app.innerHTML = `
    <header class="nav">${backBtn('day view')}<span class="spacer"></span>
      <span class="pair glass"><button id="prevM" aria-label="Previous month">${ICON_PREV}</button><button id="nextM" aria-label="Next month">${ICON_NEXT}</button></span></header>
    <div class="large-title">${monthName(m)} <span style="color:var(--label2);font-weight:600">${m.getFullYear()}</span></div>
    <div class="cal-card">
      <div class="cal-head">${wd().map(w => `<div>${w}</div>`).join('')}</div>
      <div class="cal ${state.calSlide ? 'from-' + state.calSlide : ''}">${cells.join('')}</div>
    </div>`;
  state.calSlide = null;
  $('back').onclick = () => go('day');
  $('prevM').onclick = () => { haptic(); state.calMonth = new Date(m.getFullYear(), m.getMonth() - 1, 1); state.calSlide = 'left'; render(); };
  $('nextM').onclick = () => { haptic(); state.calMonth = new Date(m.getFullYear(), m.getMonth() + 1, 1); state.calSlide = 'right'; render(); };
  app.querySelectorAll('.cal [data-k]').forEach(b => b.onclick = () => go('day', { selected: b.dataset.k, weekStart: startOfWeek(parse(b.dataset.k)) }));
}

/* ================= Progress + history (shared) ================= */
const STATS = [
  { key: 'e1rm', label: 'Est. 1RM', get unit() { return U(); } },
  { key: 'heaviest', label: 'Heaviest', get unit() { return U(); } },
  { key: 'volume', label: 'Volume', get unit() { return U(); } },
  { key: 'reps', label: 'Reps', unit: 'reps' },
];
function seriesFor(exId, key) {
  const src = state.statSrc || data.sets;
  return exDates(exId, src).map(k => {
    const ss = setsOf(exId, k, src);
    let v, note;
    if (key === 'e1rm') { const best = ss.reduce((a, s) => (e1rm(s) > e1rm(a) ? s : a)); v = toU(e1rm(best)); note = `from ${W(+best.weight)} × ${best.reps | 0}`; }
    else if (key === 'heaviest') { v = toU(Math.max(...ss.map(s => s.weight))); note = plural(ss.length, 'set'); }
    else if (key === 'volume') { v = toU(ss.reduce((a, s) => a + s.weight * s.reps, 0)); note = plural(ss.length, 'set'); }
    else { v = ss.reduce((a, s) => a + s.reps, 0); note = plural(ss.length, 'set'); }
    return { k, t: parse(k).getTime(), v, note };
  });
}
const fmtStat = (v, key) => key === 'volume' || key === 'reps' ? Math.round(v).toLocaleString('en-GB') : (Math.round(v * 10) / 10).toFixed(1);

function progressHTML(exId) {
  const stat = STATS.find(s => s.key === state.stat);
  const pts = seriesFor(exId, stat.key);
  const last = pts[pts.length - 1];
  const best = pts.length ? Math.max(...pts.map(p => p.v)) : 0;
  const diff = pts.length > 1 ? last.v - pts[0].v : 0;
  return `
    <div class="seg">${STATS.map(s => `<button data-s="${s.key}" class="${s.key === stat.key ? 'on' : ''}">${s.label}</button>`).join('')}</div>
    <div class="card">
      ${pts.length ? `
        <div class="hsub">Latest · ${fmtShort(last.k)}</div>
        <div class="headline">${fmtStat(last.v, stat.key)}<small>${stat.unit}</small></div>
        ${pts.length > 1 ? `<div class="hsub"><span class="${diff > 0 ? 'hsub up' : ''}">${diff >= 0 ? '+' : '−'}${fmtStat(Math.abs(diff), stat.key)} ${stat.unit}</span> since ${fmtTiny(pts[0].k)} · Best ${fmtStat(best, stat.key)}</div>` : ''}` : ''}
      <div class="chart" id="chart"></div>
    </div>
    ${stat.key === 'e1rm' && pts.length ? '<div class="footnote">Best set of each session, estimated with the Wathan formula. Most accurate for sets of about 10 reps or fewer.</div>' : ''}`;
}
function wireProgress(exId) {
  app.querySelectorAll('[data-s]').forEach(b => b.onclick = () => { state.stat = b.dataset.s; render(); });
  drawChart($('chart'), seriesFor(exId, state.stat), STATS.find(s => s.key === state.stat));
  wireHistory();
}
// History cards are drawn a screenful at a time: the first ones right away, more as you scroll near the end
// (years of sessions would otherwise mean thousands of rows to build and lay out before the screen can open)
const HIST_CHUNK = 12;
let hist = null, histObs = null;
function histCardHTML(h, k) {
  const ss = setsOf(h.exId, k, h.src);
  const best = Math.max(...ss.map(e1rm)), prId = h.prSet[k];
  return `<div class="hcard"><div class="hcard-head"><b>${relDay(k)}</b><span>e1RM ${fmtStat(toU(best), 'e1rm')} ${U()}</span></div>
    ${ss.map((s, i) => `<div class="hset"><span class="n">${i + 1}</span><span class="v">${W(+s.weight)} ${U()} × ${s.reps | 0}${prId === s.id ? '<span class="pr-badge">PR</span>' : ''}</span></div>`).join('')}</div>`;
}
function historyHTML(exId) {
  const src = state.statSrc || data.sets;
  const dates = exDates(exId, src);
  // Each day's PR set (best estimated 1RM beating every earlier day), worked out oldest → newest in one pass
  const prSet = {}; let runBest = null;
  for (const k of dates) {
    const top = setsOf(exId, k, src).reduce((a, b) => (e1rm(b) > e1rm(a) ? b : a));
    if (runBest !== null && e1rm(top) > runBest + 1e-6) prSet[k] = top.id;
    runBest = Math.max(runBest || 0, e1rm(top));
  }
  // Redrawing the same screen (e.g. another stat) keeps as many cards as were already showing, so nothing jumps
  const key = `${state.tab}:${state.views[state.tab]}:${exId}:${src === data.sets ? 'me' : 'f'}`;
  const shown = hist && hist.key === key ? Math.max(hist.shown, HIST_CHUNK) : HIST_CHUNK;
  hist = { key, exId, src, prSet, dates: dates.slice().reverse(), shown };
  if (!dates.length) return '<div class="section">History</div><div class="group"><div class="empty">No sets logged yet.</div></div>';
  return `<div class="section">History</div><div id="hlist">${hist.dates.slice(0, shown).map(k => histCardHTML(hist, k)).join('')}</div>${shown < hist.dates.length ? '<div id="hmore" class="hmore" aria-hidden="true"></div>' : ''}`;
}
function wireHistory() {
  if (histObs) { histObs.disconnect(); histObs = null; }
  const more = $('hmore'), h = hist;
  if (!more || !h || !('IntersectionObserver' in window)) return;
  histObs = new IntersectionObserver(es => {
    if (!es.some(e => e.isIntersecting) || hist !== h || !more.isConnected) return;
    const next = h.dates.slice(h.shown, h.shown + HIST_CHUNK);
    h.shown += next.length;
    $('hlist').insertAdjacentHTML('beforeend', next.map(k => histCardHTML(h, k)).join(''));
    if (h.shown >= h.dates.length) { histObs.disconnect(); more.remove(); }
  }, { rootMargin: '0px 0px 900px 0px' });
  histObs.observe(more);
}

function renderHistory() {
  const ex = exById(state.logExId);
  if (!ex) return go('day');
  app.innerHTML = `
    <header class="nav">${backBtn(ex.name)}</header>
    <div class="eyebrow">${esc(ex.name)}</div>
    <div class="large-title">History</div>
    ${progressHTML(ex.id)}
    ${historyHTML(ex.id)}`;
  $('back').onclick = () => go('log');
  wireProgress(ex.id);
}

function niceTicks(lo, hi, n) {
  const raw = (hi - lo) / n;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const norm = raw / mag;
  const step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 5 ? 5 : 10) * mag;
  const out = [];
  for (let v = Math.floor(lo / step) * step; ; v += step) { out.push(+v.toFixed(6)); if (v >= hi - 1e-9) break; }
  return out;
}
function drawChart(box, pts, stat) {
  if (!pts.length) { box.style.height = 'auto'; box.style.margin = '0'; box.innerHTML = '<div style="color:var(--label2);padding:20px 0;text-align:center">Log some sets to see your progress here.</div>'; return; }
  const tint = 'var(--tint)', gridC = 'var(--grid)', axis = 'var(--label2)', ring = 'var(--card)';
  const W = box.clientWidth || Math.min(app.clientWidth, 600) - 64, H = 210, L = 38, R = 8, T = 34, B = 22;
  const vals = pts.map(p => p.v);
  let lo = Math.min(...vals), hi = Math.max(...vals);
  if (lo === hi) { const p = Math.max(1, Math.abs(lo) * 0.05); lo -= p; hi += p; }
  const ticks = niceTicks(lo, hi, 4), y0 = ticks[0], y1 = ticks[ticks.length - 1];
  const t0 = pts[0].t, t1 = pts[pts.length - 1].t;
  const x = t => t1 === t0 ? L + (W - L - R) / 2 : L + ((t - t0) / (t1 - t0)) * (W - L - R);
  const y = v => T + (1 - (v - y0) / (y1 - y0)) * (H - T - B);
  const tickFmt = v => stat.key === 'volume' && y1 >= 10000 ? `${Math.round(v / 1000)}k` : fmtW(v);
  const grid = ticks.map(v => `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" style="stroke:${gridC}"/><text x="${L - 6}" y="${y(v) + 4}" text-anchor="end" font-size="11" style="fill:${axis}">${tickFmt(v)}</text>`).join('');
  const xl = pts.length > 1
    ? `<text x="${L}" y="${H - 4}" font-size="11" style="fill:${axis}">${fmtTiny(pts[0].k)}</text><text x="${W - R}" y="${H - 4}" text-anchor="end" font-size="11" style="fill:${axis}">${fmtTiny(pts[pts.length - 1].k)}</text>`
    : `<text x="${x(t0)}" y="${H - 4}" text-anchor="middle" font-size="11" style="fill:${axis}">${fmtTiny(pts[0].k)}</text>`;
  const d = smoothPath(pts.map(p => [x(p.t), y(p.v)]));
  const lastP = pts[pts.length - 1];
  const dots = pts.length > 24 ? '' : pts.slice(0, -1).map(p => `<circle cx="${x(p.t)}" cy="${y(p.v)}" r="3" stroke-width="1.5" style="fill:${tint};stroke:${ring}"/>`).join('');
  const end = `<circle class="halo" cx="${x(lastP.t)}" cy="${y(lastP.v)}" r="9" opacity=".18" style="fill:${tint}"/><circle cx="${x(lastP.t)}" cy="${y(lastP.v)}" r="4.5" stroke-width="2" style="fill:${tint};stroke:${ring}"/>`;
  const animKey = `${state.tab}:${state.views[state.tab]}:${stat.key}:${pts.length}:${W}`;
  const still = animKey === drawChart.last || reduceMotion();
  drawChart.last = animKey;
  box.innerHTML = `<svg class="${still ? 'still' : 'draw'}" width="${W}" height="${H}" role="img" aria-label="${stat.label} over time">
      ${grid}${xl}
      <defs><linearGradient id="fillG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-opacity=".26" style="stop-color:${tint}"/><stop offset=".65" stop-opacity=".05" style="stop-color:${tint}"/><stop offset="1" stop-opacity="0" style="stop-color:${tint}"/></linearGradient></defs>
      ${pts.length > 1 ? `<path class="c-area" d="${d}L${x(t1).toFixed(1)},${H - B}L${x(t0).toFixed(1)},${H - B}Z" fill="url(#fillG)"/>` : ''}
      <path class="c-line" pathLength="1" d="${d}" fill="none" stroke-width="2.75" stroke-linejoin="round" stroke-linecap="round" style="stroke:${tint}"/>
      <g class="c-dots">${dots}</g><g class="c-end">${end}</g>
      <line id="cross" y1="${T - 4}" y2="${H - B}" stroke-opacity=".5" visibility="hidden" style="stroke:${axis}"/>
      <circle id="focus" r="6" stroke-width="2" visibility="hidden" style="fill:${tint};stroke:${ring}"/>
      <rect id="hit" x="0" y="0" width="${W}" height="${H}" fill="transparent"/>
    </svg><div class="tip glass" id="tip" hidden></div>`;
  const hit = box.querySelector('#hit'), cross = box.querySelector('#cross'), focus = box.querySelector('#focus'), tip = box.querySelector('#tip');
  const show = e => {
    const mx = e.clientX - hit.getBoundingClientRect().left;
    let p = pts[0];
    for (const q of pts) if (Math.abs(x(q.t) - mx) < Math.abs(x(p.t) - mx)) p = q;
    if (show.last !== p) { if (show.last) haptic(); show.last = p; }   // a light tick as you scrub from point to point
    const px = x(p.t), py = y(p.v);
    cross.setAttribute('x1', px); cross.setAttribute('x2', px); cross.setAttribute('visibility', 'visible');
    focus.setAttribute('cx', px); focus.setAttribute('cy', py); focus.setAttribute('visibility', 'visible');
    tip.hidden = false;
    tip.innerHTML = `<b>${fmtStat(p.v, stat.key)} ${stat.unit}</b> · ${fmtTiny(p.k)} · ${p.note}`;
    const half = tip.offsetWidth / 2;
    tip.style.left = Math.max(half, Math.min(W - half, px)) + 'px';
  };
  hit.addEventListener('pointerdown', show);
  hit.addEventListener('pointermove', show);
}
window.addEventListener('resize', () => { if (!state.sheet && ['eDetail', 'history'].includes(state.views[state.tab])) render(); });

/* ================= EXERCISES tab ================= */
function renderExerciseList() {
  app.innerHTML = `
    <header class="nav"></header>
    <div class="large-title">Exercises</div>
    ${lib.error === 'rules' ? LIB_RULES_HELP : ''}
    ${searchHTML('q', 'Search')}
    <div id="results"></div>
    <button class="btn-tinted" id="newEx">${ICON_PLUS} Add exercise</button>`;
  const q = $('q');
  q.value = state.exQuery;
  const draw = () => {
    state.exQuery = q.value;
    const term = q.value.trim().toLowerCase();
    const list = data.exercises.filter(e => e.name.toLowerCase().includes(term)).sort(byName);
    const fromLib = term ? libAll().filter(x => normName(x.name).includes(normName(term)) && !mineFor(x)).slice(0, 5) : [];
    $('results').innerHTML = (list.length || !fromLib.length ? `<div class="group">${list.length ? list.map(e => {
      const dates = exDates(e.id);
      return cell({ attrs: `data-id="${e.id}"`, main: esc(e.name), sub: dates.length ? `Last logged ${fmtShort(dates[dates.length - 1])}` : 'Never logged' });
    }).join('') : `<div class="empty">${data.exercises.length ? 'None of your exercises match.' : 'No exercises yet. Tap Add exercise to pick from the database.'}</div>`}</div>` : '')
      + (fromLib.length ? `<div class="section">From the database</div><div class="group">${fromLib.map(x => libRowHTML(x, 'list')).join('')}</div>` : '');
    $('results').querySelectorAll('[data-id]').forEach(b => b.onclick = () => go('eDetail', { detailExId: b.dataset.id, stat: 'e1rm' }));
    wireLibRows($('results'), 'list', draw);
  };
  q.oninput = draw;
  draw();
  $('newEx').onclick = () => go('lib', { libBack: 'eList', libEdit: false, libFilter: { q: q.value.trim(), muscle: '', equip: '' } });
}

function renderExerciseDetail() {
  const ex = exById(state.detailExId);
  if (!ex) return go('eList');
  const vid = ytId(ex.video);
  app.innerHTML = `
    <header class="nav">${backBtn('Exercises')}<span class="spacer"></span><button class="capsule glass" id="edit">Edit</button></header>
    <div class="large-title">${esc(ex.name)}</div>
    ${progressHTML(ex.id)}
    ${ex.note ? `<div class="section">Note</div><div class="group"><div class="instr-text" style="padding:12px 16px">${esc(ex.note)}</div></div>` : ''}
    <div class="section">Instructions</div>
    <div class="group">
      ${ex.instructions ? `<div class="instr-text" style="padding:12px 16px">${esc(ex.instructions)}</div>` : ''}
      ${vid ? `<div class="video"><iframe src="https://www.youtube-nocookie.com/embed/${vid}" title="Exercise video" allow="encrypted-media; picture-in-picture; fullscreen" allowfullscreen loading="lazy"></iframe></div>
               <a class="cell action" style="justify-content:center" href="https://www.youtube.com/watch?v=${vid}" target="_blank" rel="noopener">Open in YouTube</a>` : ''}
      ${!ex.instructions && !vid ? '<div class="empty">No instructions yet. Tap Edit to add some.</div>' : ''}
    </div>
    ${historyHTML(ex.id)}`;
  $('back').onclick = () => go('eList');
  $('edit').onclick = () => openSheet({ type: 'exForm', exId: ex.id });
  wireProgress(ex.id);
}

/* ================= Plans (rotation) ================= */
// A plan is an ORDER of days (Day 1, Day 2, …; rest days count) that repeats, laid out on the calendar from its start.
// The schedule is worked out by walking day by day from the start:
//  • Rest days pass with time. A planned workout you don't do waits for you (everything after it moves along).
//  • Training the workout that's due moves the plan on. Training a different plan workout (e.g. on a rest day) does that
//    one early: its next turn is skipped, so the rest of the week stays the same.
//  • "Move back a day" stores an extra rest day ({ rest: true, absorb }) where absorb says how far the change reaches:
//    'next' = the next rest day is used up, 'round' = the round's (week's) last rest day is used up, none = from now on.
//  • "Do it today" on a rest day stores today's copy of the next workout ({ pinned: true }).
// Planned days are read from the schedule until you touch them; then the day keeps its own copy.
const daysBetween = (a, b) => Math.round((parse(b) - parse(a)) / 86400000);
const planById = id => data.plans.find(p => p.id === id);
const activePlan = () => (data.activePlan && planById(data.activePlan.planId)) ? data.activePlan : null;
const planEnd = (ap, plan) => plan.weeks ? dk(addDays(parse(ap.begin), plan.weeks * 7)) : null;
const isPlanWorkout = (plan, i) => !!(plan.days[i] && woById(plan.days[i].workoutId));
// Which day of the plan a (stored) day was
function planIndexOf(d, plan) {
  if (!d) return null;
  if (d.plan && d.plan.id === plan.id && d.plan.index >= 0 && d.plan.index < plan.days.length) return d.plan.index;
  const ids = (d.workouts || []).map(w => w.id);
  const j = plan.days.findIndex(x => x.workoutId && ids.includes(x.workoutId));
  return j >= 0 ? j : null;
}
/* The schedule is reused until something it depends on changes. Its fingerprint covers exactly what it reads:
   today, the active plan and its days, which workouts exist, and each stored day's rest/pinned/plan/workout/trained
   markers. (Ticking another set on a day that's already trained changes none of that.)
   The walk through past days is also kept: changes from today on (moving a workout, the previews of those moves,
   today's first set) only redo today onwards. */
let schedCache = null, sigMemo = null, pastWalk = null;
function schedSig() {
  if (sigMemo !== null) return sigMemo;   // worked out once per task (a screen draw asks for many days in a row)
  queueMicrotask(() => { sigMemo = null; });
  return (sigMemo = schedSigNow());
}
function schedSigNow() {
  const ap = data.activePlan, plan = ap && planById(ap.planId), tk = todayKey();
  if (!plan) return { all: tk + '|none', past: '' };
  const wi = new Map(), trained = ix().byDate;
  plan.days.forEach((d, i) => { if (d.workoutId && !wi.has(d.workoutId)) wi.set(d.workoutId, i); });
  let past = `${tk}|${ap.planId}|${ap.begin}|${ap.start}|${plan.weeks}|${plan.days.map(d => d.workoutId && woById(d.workoutId) ? d.workoutId : '-').join(',')}|`, fut = '';
  for (const k in data.days) {
    if (k < ap.begin) continue;
    const d = data.days[k];
    let e = k;
    if (d.rest) e += 'r' + (d.absorb || '');
    if (d.pinned) e += 'p';
    if (d.items.length) e += 'i';
    if (d.plan) e += d.plan.id === ap.planId ? 'P' + d.plan.index : 'x';
    if (d.workouts) for (const w of d.workouts) { const i = wi.get(w.id); e += i === undefined ? '?' : 'w' + i; }
    if (trained.has(k)) e += 't';
    if (k < tk) past += e + ';'; else fut += e + ';';
  }
  return { past, all: past + '|' + fut };
}
function planSchedule() {
  const tk = todayKey(), sig = schedSig();
  if (schedCache && schedCache.sig === sig.all && schedCache.sets === data.sets) return schedCache;
  const out = schedCache = { tk, sig: sig.all, sets: data.sets, map: {}, plan: null, ap: null };
  const ap = activePlan(); if (!ap) return out;
  const plan = planById(ap.planId), len = plan.days.length;
  const isW = plan.days.map((_, i) => isPlanWorkout(plan, i));   // looked up once, not on every day
  out.plan = plan; out.ap = ap;
  if (!len || !isW.some(Boolean)) return out;
  const trained = ix().byDate;
  const end = planEnd(ap, plan);
  const restIdx = plan.days.map((_, i) => i).filter(i => !isW[i]);
  let pos = ((daysBetween(ap.start, ap.begin) % len) + len) % len;
  let skips = [], absorbs = [], n = 0;
  if (pastWalk && pastWalk.sig === sig.past) { pos = pastWalk.pos; skips = pastWalk.skips.slice(); absorbs = pastWalk.absorbs.slice(); n = pastWalk.n; }
  // The entry that's due now (after skipping workouts done early and rest days used up by a move)
  const due = () => {
    for (let guard = 0; guard < len * 4; guard++) {
      const i = pos % len, si = skips.indexOf(i);
      if (si >= 0) { skips.splice(si, 1); pos++; continue; }
      if (!isW[i]) { const ai = absorbs.findIndex(a => a === null || a === i); if (ai >= 0) { absorbs.splice(ai, 1); pos++; continue; } }
      return i;
    }
    return pos % len;
  };
  const addAbsorb = mode => {
    if (mode === 'next') absorbs.push(null);
    else if (mode === 'round') { const i = pos % len, r = restIdx.filter(x => x > i); absorbs.push(r.length ? r[r.length - 1] : null); }
  };
  // A plan workout done (or put) on a day: in turn moves the plan on; out of turn skips its next turn
  const place = j => { const i = due(); if (i === j) pos++; else skips.push(j); };
  const horizon = dk(addDays(parse(tk), 400)), d0 = parse(ap.begin), y0 = d0.getFullYear(), m0 = d0.getMonth(), n0 = d0.getDate();
  let atToday = false;
  for (; ; n++) {
    const k = dk(new Date(y0, m0, n0 + n));
    if (k > horizon || (end && k >= end)) break;
    if (!atToday && k >= tk) { atToday = true; pastWalk = { sig: sig.past, pos, skips: skips.slice(), absorbs: absorbs.slice(), n }; }
    const st = data.days[k], tr = trained.has(k);
    if (st && st.rest && !st.items.length && !tr) { addAbsorb(st.absorb); if (k >= tk) out.map[k] = { extra: true, absorb: st.absorb || null }; continue; }
    if (k < tk) {
      const j = tr ? planIndexOf(st, plan) : null;
      if (j !== null) { place(j); continue; }
      if (!isW[due()]) pos++;          // a rest day passes; a missed workout keeps waiting
      continue;
    }
    // today and later
    const own = st && (tr || st.pinned || (!st.plan && st.items.length));
    const j = own ? planIndexOf(st, plan) : null;
    if (j !== null) { place(j); out.map[k] = { index: j, own: true }; continue; }
    if (own) { out.map[k] = { other: true }; if (!isW[due()]) pos++; continue; }   // you're doing something else that day
    out.map[k] = { index: due() }; pos++;
  }
  return out;
}
function planDayFor(k) {
  const sc = planSchedule(), e = sc.map[k];
  if (!e || e.other) return null;
  if (e.extra) return { plan: sc.plan, ap: sc.ap, index: -1, workout: null, extra: true };
  return { plan: sc.plan, ap: sc.ap, index: e.index, workout: woById(sc.plan.days[e.index].workoutId) || null };
}
// The next planned workout from today on: { k, index, workout }
function upNext() {
  const sc = planSchedule();
  for (const k of Object.keys(sc.map).sort()) { const pd = planDayFor(k); if (pd && pd.workout) return { k, index: pd.index, workout: pd.workout }; }
  return null;
}
// Stored copies of planned days that no longer match the schedule (the workout moved) are dropped,
// unless you've trained, started a timer, or pinned them.
function purgeStalePlanDays() {
  const sc = planSchedule(), tk = todayKey();
  if (!sc.plan) return;
  let changed = false;
  for (const k in data.days) {
    const d = data.days[k];
    if (k < tk || !d.plan || d.pinned || d.rest || d.session || hasSets(k)) continue;
    const e = sc.map[k];
    if (!e || e.index !== d.plan.index) { delete data.days[k]; changed = true; }
  }
  if (changed) save();
}
function virtualDay(k) {
  const pd = planDayFor(k);
  if (!pd || !pd.workout) return null;
  return { items: pd.workout.items.filter(i => exById(i.exId)).map(i => ({ exId: i.exId, sets: i.sets })),
           workouts: [{ id: pd.workout.id, name: pd.workout.name }], plan: { id: pd.plan.id, index: pd.index } };
}
const planDayLabel = (plan, i) => { const w = woById(plan.days[i].workoutId); return w ? w.name : 'Rest'; };
const planSummary = p => `${p.days.length}-day rotation · ${plural(p.days.filter(d => woById(d.workoutId)).length, 'workout')} · ${p.weeks ? plural(p.weeks, 'week') : 'ongoing'}`;
// Where a plan workout lands from a date on (for feedback after moving things)
function whereIs(index, from) {
  const sc = planSchedule();
  return Object.keys(sc.map).sort().find(k => k >= from && sc.map[k].index === index) || null;
}
// Move a planned workout back a day: an extra rest day there, and how far the change reaches
function moveBack(k, absorb) {
  const pd = planDayFor(k);
  data.days[k] = { items: [], workouts: [], rest: true };
  if (absorb) data.days[k].absorb = absorb;
  save();
  if (pd && pd.workout) { const to = whereIs(pd.index, k); if (to) toast(`<span class="tic" style="background:var(--tint-soft);color:var(--tint)">${svg('<path d="M4 12h13M13 7l5 5-5 5"/>', 18, 2.2)}</span><span>${esc(pd.workout.name)} moves to ${to === dk(addDays(parse(k), 1)) && k === todayKey() ? 'tomorrow' : fmtShort(to)}<small>${absorb ? 'Then your plan is back on track' : 'Everything after it moves a day too'}</small></span>`); }
}
function unrest(k) {
  const d = data.days[k];
  if (d && d.rest && !d.items.length && !hasSets(k)) delete data.days[k];
  save();
}
// On a rest day: do the next workout today (the rest days it jumped over come after it)
function pinToday() {
  const nx = upNext(); const tk = todayKey(); if (!nx || nx.k === tk) return;
  const sc = planSchedule();
  data.days[tk] = { items: nx.workout.items.filter(i => exById(i.exId)).map(i => ({ exId: i.exId, sets: i.sets })),
                    workouts: [{ id: nx.workout.id, name: nx.workout.name }], plan: { id: sc.plan.id, index: nx.index }, pinned: true };
  state.selected = tk; state.weekStart = startOfWeek(new Date());
  save(); haptic('impact');
  go('day');
  toast(`<span class="tic" style="background:var(--tint-soft);color:var(--tint)">${svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 18, 2.4)}</span><span>${esc(nx.workout.name)} is on today<small>The rest of your plan stays the same</small></span>`);
}
const unpin = k => { const d = data.days[k]; if (d && d.pinned && !hasSets(k) && !d.session) delete data.days[k]; save(); };

/* Sheet: move a planned workout back a day, with a preview of each choice */
const dayLabelFor = k => { const st = data.days[k], pd = planDayFor(k);
  return st && st.items.length && !st.rest && !st.plan ? (st.workouts.length ? st.workouts.map(w => w.name).join(' + ') : 'Custom') : pd && pd.workout ? pd.workout.name : 'Rest'; };
function previewDays(from, absorb, n = 7) {
  const saved = data.days[from];
  data.days[from] = { items: [], workouts: [], rest: true };
  if (absorb) data.days[from].absorb = absorb;
  schedCache = null; sigMemo = null;
  const out = Array.from({ length: n }, (_, i) => { const k = dk(addDays(parse(from), i)); return { k, name: dayLabelFor(k) }; });
  if (saved) data.days[from] = saved; else delete data.days[from];
  schedCache = null; sigMemo = null;
  return out;
}
function sheetMoveBack(el) {
  const s = state.sheet, k = s.k, pd = planDayFor(k);
  if (!pd || !pd.workout) { closeSheet(); return; }
  const base = Array.from({ length: 7 }, (_, i) => dayLabelFor(dk(addDays(parse(k), i))));
  const week = pd.plan.days.length === 7;
  const opts = [
    { v: 'next', t: 'Just this workout', d: 'It takes the next rest day. Everything after that stays the same.' },
    { v: 'round', t: week ? 'The rest of the week' : 'The rest of this round', d: `Everything moves a day later and the ${week ? "week's" : "round's"} last rest day is dropped.` },
    { v: '', t: 'Everything from here', d: 'The whole plan moves a day later, from now on.' },
  ].map(o => ({ ...o, days: previewDays(k, o.v) }));
  // A choice that comes out exactly the same as an earlier one isn't shown
  const seen = new Set(), shown = opts.filter(o => { const key = o.days.map(d => d.name).join('|') + (o.v ? '' : '*'); if (seen.has(key)) return false; seen.add(key); return true; });
  if (s.pick === undefined || !shown.some(o => o.v === s.pick)) s.pick = shown[0].v;
  const chip = (d, i) => `<span class="pv ${d.name !== base[i] ? 'chg' : ''} ${d.name === 'Rest' ? 'rest' : ''}"><b>${parse(d.k).toLocaleDateString('en-GB', { weekday: 'short' })}</b>${esc(d.name)}</span>`;
  el.innerHTML = sheetOpen('Move back a day', `${closeBtn('sCancel')}<b>Move ${esc(pd.workout.name)}</b><span></span>`, `
    <div class="finish-sub" style="margin:0 8px 12px">${k === todayKey() ? 'Today' : fmtLong(k)} becomes a rest day and ${esc(pd.workout.name)} moves back a day. How far should the change reach?</div>
    ${shown.map(o => `<button class="mv-opt ${s.pick === o.v ? 'on' : ''}" data-pick="${o.v}">
      <span class="mv-radio"></span><span class="mv-body"><b>${o.t}</b><span class="mv-d">${o.d}</span>
      <span class="pv-row">${o.days.map(chip).join('')}</span></span></button>`).join('')}
    <button class="primary" id="sGo">Move</button>`);
  $('sCancel').onclick = () => closeSheet();
  el.querySelectorAll('[data-pick]').forEach(b => b.onclick = () => { if (s.pick !== b.dataset.pick) haptic(); s.pick = b.dataset.pick; renderSheet(); });
  $('sGo').onclick = () => { const pick = s.pick; haptic('impact'); closeSheet(); moveBack(k, pick || undefined); render(); };
}

function renderPlanList() {
  const ap = activePlan();
  const list = data.plans.slice().sort((a, b) => (ap && a.id === ap.planId ? -1 : ap && b.id === ap.planId ? 1 : a.name.localeCompare(b.name)));
  return `${list.length ? `<div class="group">${list.map(p => cell({ attrs: `data-plan="${p.id}"`, main: esc(p.name), sub: planSummary(p),
      detail: ap && ap.planId === p.id ? '<span class="pill-active">Active</span>' : '' })).join('')}</div>` : ''}
    <button class="btn-tinted" id="newP">${ICON_PLUS} Create a new plan</button>
    ${!list.length ? '<div class="footnote" style="text-align:center">A plan is a rotation of your workouts and rest days that fills in your calendar.</div>' : ''}`;
}

function renderPlanView() {
  const p = planById(state.planId);
  if (!p) return go('wList');
  const ap = activePlan();
  const isActive = ap && ap.planId === p.id;
  const tk = todayKey();
  const nx = isActive ? upNext() : null;
  const end = isActive ? planEnd(ap, p) : null;
  const coming = isActive ? Array.from({ length: 10 }, (_, i) => dk(addDays(parse(tk), i))).filter(k => !end || k < end) : [];
  const pend = state.pending;
  app.innerHTML = `
    <header class="nav">${backBtn('Workouts')}<span class="spacer"></span><button class="capsule glass" id="editP">Edit</button></header>
    <div class="large-title">${esc(p.name)}</div>
    <div class="day-sub" style="margin-top:-8px">${isActive
      ? `Active since ${fmtTiny(ap.begin)}${end ? ` · ends ${fmtTiny(end)}` : ''}`
      : planSummary(p)}</div>
    <div class="section">Rotation</div>
    <div class="group">${p.days.map((d, i) => {
      const w = woById(d.workoutId), now = nx && nx.index === i;
      return `<div class="set-row"><span class="main"><span class="daynum ${now ? 'now' : ''}">${i + 1}</span>${w ? esc(w.name) : '<span style="color:var(--label2)">Rest</span>'}</span>
        <span class="detail" style="color:${now ? 'var(--tint)' : 'var(--label2)'};font-weight:${now ? 600 : 400}">${now ? 'Up next' : w ? plural(w.items.length, 'exercise') : ''}</span></div>`;
    }).join('') || '<div class="empty">No days yet. Tap Edit to build the rotation.</div>'}</div>
    <div class="footnote">After the last day it starts again from day 1.${p.weeks ? ` Runs for ${plural(p.weeks, 'week')}.` : ' Runs until you end it.'}</div>
    <div class="group" style="margin-top:14px"><button class="cell action" id="sendP" ${p.days.length ? '' : 'disabled'}>${ICON_GIFT}Send to a friend</button></div>
    ${isActive ? `
      <div class="section">Coming up</div>
      <div class="group">${coming.map(k => {
        const d = dayOf(k), pd = planDayFor(k), done = hasSets(k);
        const label = d.items.length ? (d.workouts.length ? d.workouts.map(w => esc(w.name)).join(' + ') : 'Custom workout') : pd && pd.extra ? 'Rest (moved)' : 'Rest';
        return cell({ attrs: `data-goday="${k}"`, main: `${k === tk ? 'Today' : k === dk(addDays(parse(tk), 1)) ? 'Tomorrow' : fmtShort(k)}`,
          detail: `<span style="color:${d.items.length ? 'var(--label)' : 'var(--label2)'}">${label}${done ? ' ✓' : ''}</span>` });
      }).join('')}</div>
      <div class="footnote">Missed a workout? It waits for you and the rest moves along. Can't make a day? Open it in Today and tap “Move back a day” to choose how far the change reaches. On a rest day you can do your next workout early.</div>
      <div class="group" style="margin-top:24px"><button class="cell destructive ${pend === 'endP' ? 'confirm' : ''}" id="endP">${pend === 'endP' ? 'Tap again to end this plan' : 'End plan'}</button></div>`
    : `<button class="primary" id="startP" ${p.days.length ? '' : 'disabled'}>Start plan</button>`}`;
  $('back').onclick = () => go('wList');
  $('editP').onclick = () => go('pEdit', { pdraft: { id: p.id, name: p.name, weeks: p.weeks, days: p.days.map(d => ({ ...d })) } });
  if ($('startP')) $('startP').onclick = () => openSheet({ type: 'planStart', planId: p.id });
  $('sendP').onclick = () => openSheet({ type: 'sendTo', kind: 'plan', id: p.id });
  app.querySelectorAll('[data-goday]').forEach(b => b.onclick = () => { const k = b.dataset.goday; state.tab = 'today'; state.views.today = 'day'; state.selected = k; state.weekStart = startOfWeek(parse(k)); render(); window.scrollTo(0, 0); });
  if ($('endP')) $('endP').onclick = () => {
    if (state.pending !== 'endP') { haptic('warn'); state.pending = 'endP'; return render(); }
    // Keep days already filled in; future planned days disappear
    for (const k in data.days) if (k >= tk && (data.days[k].plan || data.days[k].rest) && !hasSets(k) && !data.days[k].session) delete data.days[k];
    data.activePlan = null; save(); state.pending = null; render();
  };
}

function renderPlanEdit() {
  const dr = state.pdraft;
  if (!dr) return go('wList');
  const rows = dr.days.map((d, i) => {
    const w = woById(d.workoutId);
    return `<div class="cell-wrap drag-row" style="display:flex;align-items:center">
      <button class="circle" data-rmday="${i}" aria-label="Remove day ${i + 1}" style="color:var(--red);margin-left:8px;width:36px;height:36px">${svg('<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="M8 12h8" stroke="#fff" stroke-width="2.2"/>', 22)}</button>
      ${cell({ attrs: `data-day="${i}" style="padding-left:4px;padding-right:4px"`, main: `<span class="daynum">${i + 1}</span>${w ? esc(w.name) : '<span style="color:var(--label2)">Rest</span>'}`, detail: w ? plural(w.items.length, 'exercise') : '' })}
      <button class="grip" aria-label="Drag to reorder">${ICON_GRIP}</button>
    </div>`;
  }).join('');
  app.innerHTML = `
    <header class="nav">${closeBtn('cancel')}<span class="spacer"></span><b class="title">${dr.id ? 'Edit Plan' : 'New Plan'}</b><span class="spacer"></span>${okBtn('saveP')}</header>
    <div class="group" style="margin-top:8px"><input class="field-input" id="pName" placeholder="Plan name, e.g. Push pull legs" autocomplete="off" style="font-size:20px;font-weight:600"></div>
    <div class="section">Rotation</div>
    <div class="group"><div id="dayRows">${rows}</div>
      <div class="cell-wrap"><button class="cell action" id="addDay">${plusLead}Add workout day</button></div>
      <div class="cell-wrap"><button class="cell action" id="addRest">${plusLead}Add rest day</button></div></div>
    <div class="footnote">The days repeat in this order. Tap a day to change it, drag ≡ to reorder.</div>
    <div class="section">Length</div>
    <div class="group"><div class="set-row"><span class="lbl">Run for</span>
      <div class="mini-stepper"><button id="wkMinus" aria-label="Shorter">−</button><span style="min-width:84px">${dr.weeks ? plural(dr.weeks, 'week') : 'Ongoing'}</span><button id="wkPlus" aria-label="Longer">+</button></div></div></div>
    <div class="err" id="pErr"></div>
    ${dr.id ? `<div class="group" style="margin-top:28px"><button class="cell destructive ${state.pending === 'delP' ? 'confirm' : ''}" id="delP">${state.pending === 'delP' ? 'Tap again to delete' : 'Delete Plan'}</button></div>` : ''}`;
  const name = $('pName');
  name.value = dr.name;
  name.oninput = () => { dr.name = name.value; };
  const back = () => go(dr.id ? 'pView' : 'wList', { pdraft: null });
  $('cancel').onclick = back;
  $('addDay').onclick = () => openSheet({ type: 'planDay', index: dr.days.length, isNew: true });
  $('addRest').onclick = () => { dr.days.push({ workoutId: null }); render(); };
  app.querySelectorAll('[data-day]').forEach(b => b.onclick = () => openSheet({ type: 'planDay', index: Number(b.dataset.day) }));
  app.querySelectorAll('[data-rmday]').forEach(b => b.onclick = () => { haptic('impact'); collapseOut(b.closest('.cell-wrap'), () => { dr.days.splice(Number(b.dataset.rmday), 1); render(); }); });
  makeSortable($('dayRows'), (from, to) => { dr.days.splice(to, 0, dr.days.splice(from, 1)[0]); render(); });
  $('wkMinus').onclick = () => { haptic(); dr.weeks = Math.max(0, (dr.weeks || 0) - 1); render(); };
  $('wkPlus').onclick = () => { haptic(); dr.weeks = Math.min(52, (dr.weeks || 0) + 1); render(); };
  $('saveP').onclick = () => {
    const nm = dr.name.trim();
    if (!nm) { $('pErr').textContent = 'Give the plan a name.'; name.focus(); return; }
    if (!dr.days.some(d => woById(d.workoutId))) { $('pErr').textContent = 'Add at least one workout day.'; return; }
    let id = dr.id;
    if (id) Object.assign(planById(id), { name: nm, weeks: dr.weeks, days: dr.days });
    else { id = uid(); data.plans.push({ id, name: nm, weeks: dr.weeks, days: dr.days }); }
    save(); go('pView', { pdraft: null, planId: id });
  };
  if ($('delP')) $('delP').onclick = () => {
    if (state.pending !== 'delP') { haptic('warn'); state.pending = 'delP'; return render(); }
    if (data.activePlan && data.activePlan.planId === dr.id) data.activePlan = null;
    data.plans = data.plans.filter(p => p.id !== dr.id);
    save(); go('wList', { pdraft: null });
  };
}

/* Sheet: pick what a rotation day is */
function sheetPlanDay(el) {
  const s = state.sheet, dr = state.pdraft;
  const cur = dr.days[s.index];
  const list = data.workouts.slice().sort(byName);
  el.innerHTML = sheetOpen('Choose day', `${closeBtn('sCancel')}<b>Day ${s.index + 1}</b><span></span>`, `
    <div class="group">
      <button class="cell" data-w="">${'<span class="main" style="color:var(--label2)">Rest</span>'}${cur && !cur.workoutId && !s.isNew ? `<span class="chev" style="color:var(--tint)">${ICON_OK}</span>` : ''}</button>
    </div>
    <div class="section">Workouts</div>
    ${list.length ? `<div class="group">${list.map(w => `<button class="cell" data-w="${w.id}"><span class="main"><div>${esc(w.name)}</div><div class="sub">${plural(w.items.length, 'exercise')}</div></span>${cur && cur.workoutId === w.id ? `<span class="chev" style="color:var(--tint)">${ICON_OK}</span>` : ''}</button>`).join('')}</div>`
      : '<div class="group"><div class="empty">No workouts yet. Switch to Workouts at the top of this tab and create some first.</div></div>'}`);
  $('sCancel').onclick = () => closeSheet();
  el.querySelectorAll('[data-w]').forEach(b => b.onclick = () => {
    const v = { workoutId: b.dataset.w || null };
    if (s.isNew) dr.days.push(v); else dr.days[s.index] = v;
    closeSheet(); render();
  });
}

/* Sheet: start a plan (date + which day to start on) */
function sheetPlanStart(el) {
  const s = state.sheet, p = planById(s.planId), ap = activePlan();
  const replacing = ap && ap.planId !== p.id ? planById(ap.planId) : null;
  s.date = s.date || todayKey();
  el.innerHTML = sheetOpen('Start plan', `${closeBtn('sCancel')}<b>Start ${esc(p.name)}</b><span></span>`, `
    <div class="group">
      <div class="set-row"><span class="lbl">First day</span><input type="date" id="pDate" class="date-input" value="${s.date}"></div>
    </div>
    <div class="section">Start with</div>
    <div class="group"><div class="wheels">${wheelHTML('wDay', p.days.map((d, i) => ({ v: i, label: `Day ${i + 1} · ${planDayLabel(p, i)}` })))}</div></div>
    ${replacing ? `<div class="footnote" style="color:var(--red)">This ends ${esc(replacing.name)}. Days you've already trained are kept.</div>` : ''}
    <button class="primary" id="sGo">${replacing ? 'Replace and start' : 'Start plan'}</button>`);
  initWheel('wDay', 0);
  $('pDate').onchange = e => { s.date = e.target.value || todayKey(); };
  $('sCancel').onclick = () => closeSheet();
  $('sGo').onclick = () => {
    const first = s.date, startIdx = wheelIndex('wDay');
    for (const k in data.days) if (k >= todayKey() && (data.days[k].plan || data.days[k].rest) && !hasSets(k) && !data.days[k].session) delete data.days[k];
    data.activePlan = { planId: p.id, begin: first, start: dk(addDays(parse(first), -startIdx)) };
    haptic('success'); save(); state.sheet = null;
    render();
  };
}

/* ================= WORKOUTS tab ================= */
function renderWorkoutList() {
  const list = data.workouts.slice().sort(byName);
  const seg = state.wSeg || 'plans';
  const head = `
    <header class="nav"></header>
    <div class="large-title">Workouts</div>
    <div class="seg"><button data-wseg="plans" class="${seg === 'plans' ? 'on' : ''}">Plans</button><button data-wseg="workouts" class="${seg === 'workouts' ? 'on' : ''}">Workouts</button></div>`;
  if (seg === 'plans') {
    app.innerHTML = head + renderPlanList();
    app.querySelectorAll('[data-wseg]').forEach(b => b.onclick = () => { if (state.wSeg !== b.dataset.wseg) state.soft = true; state.wSeg = b.dataset.wseg; render(); });
    $('newP').onclick = () => go('pEdit', { pdraft: { id: null, name: '', weeks: 8, days: [] } });
    app.querySelectorAll('[data-plan]').forEach(b => b.onclick = () => go('pView', { planId: b.dataset.plan }));
    return;
  }
  app.innerHTML = head + `
    ${list.length ? `<div class="group">${list.map(w => cell({ attrs: `data-id="${w.id}"`, main: esc(w.name),
      sub: `${plural(w.items.length, 'exercise')} · ${plural(w.items.reduce((a, i) => a + i.sets, 0), 'set')}` })).join('')}</div>` : ''}
    <button class="btn-tinted" id="newW">${ICON_PLUS} Create a new workout</button>`;
  const create = () => go('wEdit', { draft: { id: null, name: '', items: [] } });
  $('newW').onclick = create;
  app.querySelectorAll('[data-wseg]').forEach(b => b.onclick = () => { if ((state.wSeg || 'plans') !== b.dataset.wseg) state.soft = true; state.wSeg = b.dataset.wseg; render(); });
  app.querySelectorAll('[data-id]').forEach(b => b.onclick = () => {
    const w = woById(b.dataset.id);
    go('wEdit', { draft: { id: w.id, name: w.name, items: w.items.map(i => ({ ...i })) } });
  });
}

function renderWorkoutEdit() {
  const dr = state.draft;
  if (!dr) return go('wList');
  const usedIn = dr.id ? data.plans.filter(p => p.days.some(d => d.workoutId === dr.id)) : [];
  const rows = dr.items.map((it, i) => {
    const ex = exById(it.exId);
    return `<div class="cell-wrap drag-row" style="display:flex;align-items:center">
      <button class="circle" data-rm="${i}" aria-label="Remove" style="color:var(--red);margin-left:8px;width:36px;height:36px">${svg('<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="M8 12h8" stroke="#fff" stroke-width="2.2"/>', 22)}</button>
      ${cell({ attrs: `data-sets="${i}" style="padding-left:4px;padding-right:4px"`, main: esc(ex ? ex.name : 'Deleted exercise'), detail: plural(it.sets, 'set') })}
      <button class="grip" aria-label="Drag to reorder">${ICON_GRIP}</button>
    </div>`;
  }).join('');
  app.innerHTML = `
    <header class="nav">${closeBtn('cancel')}<span class="spacer"></span><b class="title">${dr.id ? 'Edit Workout' : 'New Workout'}</b><span class="spacer"></span>${okBtn('saveW')}</header>
    <div class="group" style="margin-top:8px"><input class="field-input" id="wName" placeholder="Workout name, e.g. Push day" autocomplete="off" style="font-size:20px;font-weight:600"></div>
    <div class="section">Exercises</div>
    <div class="group"><div id="wList">${rows}</div><div class="cell-wrap"><button class="cell action" id="addToW">${plusLead}Add exercise</button></div></div>
    <div class="err" id="wErr"></div>
    ${dr.id ? `<div class="group" style="margin-top:28px"><button class="cell action" id="sendW" ${dr.items.length ? '' : 'disabled'}>${ICON_GIFT}Send to a friend</button></div>
      <div class="group" style="margin-top:14px"><button class="cell destructive ${state.pending === 'delW' ? 'confirm' : ''}" id="delW">${state.pending === 'delW' ? 'Tap again to delete' : 'Delete Workout'}</button></div>
      ${state.pending === 'delW' && usedIn.length ? `<div class="footnote" style="color:var(--red)">Used in ${usedIn.map(p => esc(p.name)).join(', ')}. Those days will become rest days.</div>` : ''}` : ''}`;
  const name = $('wName');
  name.value = dr.name;
  name.oninput = () => { dr.name = name.value; };
  $('cancel').onclick = () => go('wList', { draft: null });
  $('addToW').onclick = () => openSheet({ type: 'addToWorkout', step: 'pick', q: '' });
  if ($('sendW')) $('sendW').onclick = () => openSheet({ type: 'sendTo', kind: 'workout', id: dr.id, draft: { name: dr.name.trim() || 'Workout', items: dr.items.map(i => ({ ...i })) } });
  app.querySelectorAll('[data-sets]').forEach(b => b.onclick = () => openSheet({ type: 'setCount', index: Number(b.dataset.sets) }));
  app.querySelectorAll('[data-rm]').forEach(b => b.onclick = () => { haptic('impact'); collapseOut(b.closest('.cell-wrap'), () => { dr.items.splice(Number(b.dataset.rm), 1); render(); }); });
  makeSortable($('wList'), (from, to) => { dr.items.splice(to, 0, dr.items.splice(from, 1)[0]); render(); });
  $('saveW').onclick = () => {
    const nm = dr.name.trim();
    if (!nm) { $('wErr').textContent = 'Give the workout a name.'; name.focus(); return; }
    if (dr.id) Object.assign(woById(dr.id), { name: nm, items: dr.items });
    else data.workouts.push({ id: uid(), name: nm, items: dr.items });
    save(); go('wList', { draft: null });
  };
  if ($('delW')) $('delW').onclick = () => {
    if (state.pending !== 'delW') { haptic('warn'); state.pending = 'delW'; return render(); }
    data.workouts = data.workouts.filter(w => w.id !== dr.id);
    save(); go('wList', { draft: null });
  };
}

/* ================= Cloud: accounts + sync (Firebase) ================= */
// Local-first: the app always reads and writes the copy on this device. When you're signed in,
// every change is sent to your account, and changes from your other devices are merged in.
// Each record is its own document; a record is newer when its `u` (updated) time is higher.
const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyCvoT-mdnLPmgy33VbsBNngtGHsJ6KoNOc',
  authDomain: 'workout-tracker-705ae.firebaseapp.com',
  projectId: 'workout-tracker-705ae',
  storageBucket: 'workout-tracker-705ae.firebasestorage.app',
  messagingSenderId: '366945347041',
  appId: '1:366945347041:web:64698c9f5e6232efad9ea0',
};
const cloud = { fb: null, auth: null, db: null, user: null, status: 'off', error: '', unsubs: [], timer: null, sync: null, ready: false };

// How each part of the data maps to a Firestore collection under users/{uid}/
const COLS = {
  exercises: { get: () => Object.fromEntries(data.exercises.map(e => [e.id, e])), set: m => { data.exercises = Object.values(m); } },
  workouts: { get: () => Object.fromEntries(data.workouts.map(w => [w.id, w])), set: m => { data.workouts = Object.values(m); } },
  days: { get: () => ({ ...data.days }), set: m => { data.days = m; } },
  sets: { get: () => Object.fromEntries(data.sets.map(s => [s.id, s])), set: m => { data.sets = Object.values(m); } },
  plans: { get: () => Object.fromEntries(data.plans.map(p => [p.id, p])), set: m => { data.plans = Object.values(m); } },
  meta: {
    get: () => ({ settings: data.settings, active: data.activePlan || { planId: null } }),
    set: m => {
      if (m.settings) data.settings = migrate({ exercises: [], days: {}, sets: [], settings: m.settings }).settings;
      if (m.active) data.activePlan = m.active.planId ? m.active : null;
    },
  },
};
const hash = str => { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return (h >>> 0).toString(36); };
const syncKey = uid => 'tt.sync.' + uid;
const loadSync = uid => { try { return JSON.parse(localStorage.getItem(syncKey(uid))) || null; } catch (e) { return null; } };
// What was last synced is written a moment later (it's large and changes in bursts); always before the app is put away
const saveSyncNow = () => { clearTimeout(saveSyncNow.t); saveSyncNow.t = null; try { if (cloud.user && cloud.sync) localStorage.setItem(syncKey(cloud.user.uid), JSON.stringify(cloud.sync)); } catch (e) {} };
const saveSync = () => { if (!saveSyncNow.t) saveSyncNow.t = setTimeout(saveSyncNow, 1500); };
// A set only ever changes its weight, reps or slot, so its hash is remembered until one of those changes
const recHashes = new WeakMap();
function recHash(col, rec) {
  if (col !== 'sets') return hash(JSON.stringify(rec));
  const c = recHashes.get(rec);
  if (c && c.w === rec.weight && c.r === rec.reps && c.s === rec.slot) return c.h;
  const h = hash(JSON.stringify(rec)); recHashes.set(rec, { w: rec.weight, r: rec.reps, s: rec.slot, h }); return h;
}
const stripRec = d => { const r = { ...d }; delete r.u; delete r.deleted; return r; };

function setCloudStatus(s, err = '') {
  cloud.status = s; cloud.error = err;
  const el = document.getElementById('syncStatus');
  if (el) el.textContent = cloudStatusText();
}
function cloudStatusText() {
  return { off: 'Not signed in', connecting: 'Connecting…', syncing: 'Syncing…', synced: 'Backed up', offline: 'Offline — will sync later', error: 'Sync problem: ' + cloud.error }[cloud.status] || '';
}

async function initCloud() {
  try {
    const fb = cloud.fb = await import('./firebase-346e04e6.js'); // file name changes with its contents, so an old cached copy is never used
    const app = fb.initializeApp(FIREBASE_CONFIG);
    cloud.auth = fb.initializeAuth(app, { persistence: [fb.indexedDBLocalPersistence, fb.browserLocalPersistence], popupRedirectResolver: fb.browserPopupRedirectResolver });
    cloud.db = fb.initializeFirestore(app, { localCache: fb.persistentLocalCache({ tabManager: fb.persistentSingleTabManager() }) });
    fb.getRedirectResult(cloud.auth).catch(e => { cloud.authError = friendlyAuthError(e); render(); });
    fb.onAuthStateChanged(cloud.auth, user => {
      stopListening();
      stopFriends();
      stopLibrary();
      cloud.user = user;
      if (user) startSync(); else setCloudStatus('off');
      if (!state.sheet || state.sheet.type !== 'signin') bgRender();
    });
    cloud.ready = true;
  } catch (e) {
    cloud.ready = false;
    setCloudStatus('error', 'could not load sign-in (are you offline?)');
  }
  window.addEventListener('online', () => { if (cloud.user) pushChanges(); });
}

// The data on this device belongs to one account. If a different account signs in here,
// put the previous person's data aside (kept on this device) instead of uploading it to the new account.
function claimLocalData(uid) {
  let owner = null;
  try { owner = localStorage.getItem('tt.owner'); } catch (e) {}
  if (owner && owner !== uid) {
    try {
      localStorage.setItem('tt.v1.' + owner, JSON.stringify(data));
      const mine = JSON.parse(localStorage.getItem('tt.v1.' + uid) || 'null');
      data = migrate(mine || { exercises: [], days: {}, sets: [], workouts: [], settings: data.settings });
      state.drafts = {};
    } catch (e) {}
  }
  try { localStorage.setItem('tt.owner', uid); } catch (e) {}
}

async function startSync() {
  const fb = cloud.fb, uid = cloud.user.uid;
  claimLocalData(uid);
  if (!data.settings.name && cloud.user.displayName) { data.settings.name = cloud.user.displayName; save(); }
  cloud.sync = loadSync(uid);
  setCloudStatus('connecting');
  try {
    if (!cloud.sync) {
      // First time this device signs in to this account: download everything once and merge it in
      cloud.sync = { since: 0, maps: {} };
      for (const col of Object.keys(COLS)) {
        cloud.sync.maps[col] = {};
        const snap = await fb.getDocs(fb.collection(cloud.db, 'users', uid, col));
        const local = COLS[col].get();
        snap.forEach(d => {
          const v = d.data();
          cloud.sync.since = Math.max(cloud.sync.since, v.u || 0);
          if (v.deleted) { delete local[d.id]; return; }
          const rec = stripRec(v);
          local[d.id] = rec;                                   // the account's copy wins on a clash
          cloud.sync.maps[col][d.id] = hash(JSON.stringify(rec));
        });
        COLS[col].set(local);
      }
      saveSync();
      saveLocal();
      if (!state.sheet) bgRender();
    }
    listen();
    startFriends();
    startLibrary();
    await pushChanges();                                       // upload anything only this device has
  } catch (e) {
    setCloudStatus(navigator.onLine ? 'error' : 'offline', e.code || e.message);
  }
}

// Live updates from your other devices
function listen() {
  const fb = cloud.fb, uid = cloud.user.uid;
  // The query stays the same from one launch to the next (it moves on about once a month): Firestore can then answer it
  // from its last answer plus what changed, instead of reading every record kept on the phone to work it out again.
  // (Records it returns that haven't changed are skipped below, so starting a bit further back costs very little.)
  if (!cloud.sync.from || (cloud.sync.since || 0) - cloud.sync.from > 30 * 864e5) {
    cloud.sync.from = Math.max(0, (cloud.sync.since || 0) - 5 * 60 * 1000);   // small margin for clock differences
    saveSync();
  }
  const since = cloud.sync.from;
  for (const col of Object.keys(COLS)) {
    const q = fb.query(fb.collection(cloud.db, 'users', uid, col), fb.where('u', '>', since));
    cloud.unsubs.push(fb.onSnapshot(q, snap => {
      let changed = false;
      const local = COLS[col].get();
      const map = cloud.sync.maps[col] = cloud.sync.maps[col] || {};
      snap.docChanges().forEach(ch => {
        if (ch.doc.metadata.hasPendingWrites || ch.type === 'removed') return; // our own write echoing back
        const v = ch.doc.data();
        cloud.sync.since = Math.max(cloud.sync.since, v.u || 0);
        if (v.deleted) { if (local[ch.doc.id]) { delete local[ch.doc.id]; changed = true; } delete map[ch.doc.id]; return; }
        const rec = stripRec(v), h = hash(JSON.stringify(rec));
        if (map[ch.doc.id] === h && local[ch.doc.id]) return;
        local[ch.doc.id] = rec; map[ch.doc.id] = h; changed = true;
      });
      saveSync();
      if (changed) {
        COLS[col].set(local);
        if (col === 'meta') applyTheme();
        saveLocal();
        const typing = document.activeElement && /INPUT|TEXTAREA/.test(document.activeElement.tagName);
        if (!typing && !state.sheet) bgRender();
      }
      if (!snap.metadata.fromCache && cloud.status !== 'syncing') setCloudStatus('synced');
    }, e => setCloudStatus('error', e.code || e.message)));
  }
}
function stopListening() { cloud.unsubs.forEach(u => u()); cloud.unsubs = []; }

// Send local changes (compares each record with what was last synced)
function scheduleSync() { if (!cloud.user || !cloud.sync) return; clearTimeout(cloud.timer); cloud.timer = setTimeout(pushChanges, 600); }
// Records that differ from what was last synced (and deleted ones)
function syncOps(now) {
  const ops = [];
  for (const col of Object.keys(COLS)) {
    const local = COLS[col].get();
    const map = cloud.sync.maps[col] = cloud.sync.maps[col] || {};
    for (const id in local) {
      const h = recHash(col, local[id]);
      if (map[id] !== h) ops.push({ col, id, body: { ...JSON.parse(JSON.stringify(local[id])), u: now }, h });
    }
    for (const id in map) if (!(id in local)) ops.push({ col, id, body: { deleted: true, u: now }, h: null });
  }
  return ops;
}
// A save the cloud turned down is tried again later: sooner at first, then every few minutes
function retryPush() {
  clearTimeout(cloud.retryT);
  cloud.retryWait = Math.min(300000, (cloud.retryWait || 7500) * 2);
  cloud.retryT = setTimeout(() => { cloud.retryT = null; pushChanges(); }, cloud.retryWait);
}
async function pushChanges() {
  clearTimeout(cloud.timer); cloud.timer = null;
  clearTimeout(cloud.retryT); cloud.retryT = null;
  if (!cloud.user || !cloud.sync || cloud.deleting) return;
  const fb = cloud.fb, uid = cloud.user.uid, sync = cloud.sync;
  const ops = syncOps(Date.now());
  if (!ops.length) { if (cloud.status !== 'error') setCloudStatus(navigator.onLine ? 'synced' : 'offline'); return; }
  setCloudStatus('syncing');
  try {
    for (let i = 0; i < ops.length; i += 400) {
      const part = ops.slice(i, i + 400), batch = fb.writeBatch(cloud.db);
      part.forEach(o => batch.set(fb.doc(cloud.db, 'users', uid, o.col, o.id), o.body));
      // Marked as synced right away (Firestore keeps queued writes and sends them when back online, and nothing is sent
      // twice). If the cloud turns the save down, the marks are taken back, so the records are sent again later.
      const before = part.map(o => sync.maps[o.col][o.id]);
      part.forEach(o => { if (o.h) sync.maps[o.col][o.id] = o.h; else delete sync.maps[o.col][o.id]; });
      saveSync();
      const undo = () => {
        if (cloud.sync !== sync) return;
        part.forEach((o, j) => {
          const m = sync.maps[o.col];
          if (o.h ? m[o.id] !== o.h : o.id in m) return;           // sent again since: that send counts
          if (before[j] === undefined) delete m[o.id]; else m[o.id] = before[j];
        });
        saveSync(); retryPush();
      };
      const sent = batch.commit();
      if (navigator.onLine) await sent.catch(e => { undo(); throw e; }); else sent.catch(e => { undo(); setCloudStatus('error', e.code || e.message); });
    }
    cloud.retryWait = 0;
    setCloudStatus(navigator.onLine ? 'synced' : 'offline');
  } catch (e) {
    setCloudStatus(navigator.onLine ? 'error' : 'offline', e.code || e.message);
  }
}

function friendlyAuthError(e) {
  const c = (e && e.code) || '';
  if (c.includes('invalid-credential') || c.includes('wrong-password') || c.includes('user-not-found')) return 'Wrong email or password.';
  if (c.includes('email-already-in-use')) return 'There is already an account with that email. Sign in instead.';
  if (c.includes('weak-password')) return 'Use at least 6 characters for the password.';
  if (c.includes('invalid-email')) return "That email address doesn't look right.";
  if (c.includes('popup-closed') || c.includes('cancelled-popup')) return '';
  if (c.includes('network')) return "Couldn't reach the server. Check your connection.";
  if (c.includes('unauthorized-domain')) return 'This web address is not allowed yet (add it under Authentication → Settings → Authorized domains).';
  if (c.includes('operation-not-allowed')) return 'This sign-in method is turned off in Firebase.';
  if (c.includes('too-many-requests')) return 'Too many attempts. Wait a moment and try again.';
  return 'Sign-in failed (' + (c || e.message || 'unknown error') + ').';
}

/* Sign-in sheet */
const ICON_GOOGLE = `<svg width="18" height="18" viewBox="0 0 48 48" aria-hidden="true"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3.1l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>`;
function sheetSignin(el) {
  const s = state.sheet;
  s.mode = s.mode || 'signin';
  const create = s.mode === 'create';
  el.innerHTML = sheetOpen('Sign in', `${closeBtn('sCancel')}<b>${create ? 'Create account' : 'Sign in'}</b><span></span>`, `
    <div class="finish-sub" style="margin:0 8px 14px">Back up your workouts, use them on all your devices, and add friends.</div>
    <button class="google-btn" id="gBtn">${ICON_GOOGLE}<span>Continue with Google</span></button>
    <div class="or"><span>or use email</span></div>
    <div class="group">
      <input class="field-input" id="aEmail" type="email" inputmode="email" autocomplete="email" placeholder="Email" value="${esc(s.email || '')}">
      <div style="border-top:.5px solid var(--sep);margin:0 18px"></div>
      <input class="field-input" id="aPass" type="password" autocomplete="${create ? 'new-password' : 'current-password'}" placeholder="${create ? 'Choose a password (6+ characters)' : 'Password'}">
    </div>
    <div class="err" id="aErr">${esc(s.err || cloud.authError || '')}</div>
    ${s.msg ? `<div class="finish-sub" style="margin:10px 8px 0;color:var(--green)">${esc(s.msg)}</div>` : ''}
    <button class="primary" id="aGo">${create ? 'Create account' : 'Sign in'}</button>
    <div class="auth-links">
      <button class="tint" id="aMode">${create ? 'I already have an account' : 'Create an account'}</button>
      ${create ? '' : '<button class="tint" id="aForgot">Forgot password?</button>'}
    </div>`);
  cloud.authError = '';
  const email = $('aEmail'), pass = $('aPass');
  email.oninput = () => { s.email = email.value; };
  const busy = on => { ['gBtn', 'aGo'].forEach(id => { const b = $(id); if (b) b.disabled = on; }); };
  const fail = e => { busy(false); s.err = friendlyAuthError(e); s.msg = ''; renderSheet(); };
  $('sCancel').onclick = () => closeSheet();
  $('aMode').onclick = () => { s.mode = create ? 'signin' : 'create'; s.err = ''; s.msg = ''; renderSheet(); };
  if (!cloud.ready) { $('aErr').textContent = 'Sign-in is still loading — check your connection and try again.'; }
  $('gBtn').onclick = async () => {
    if (!cloud.ready) return;
    busy(true);
    const provider = new cloud.fb.GoogleAuthProvider();
    try { await cloud.fb.signInWithPopup(cloud.auth, provider); closeSheet(); }
    catch (e) {
      if ((e.code || '').includes('popup-blocked') || (e.code || '').includes('operation-not-supported')) {
        try { await cloud.fb.signInWithRedirect(cloud.auth, provider); } catch (e2) { fail(e2); }
      } else fail(e);
    }
  };
  $('aGo').onclick = async () => {
    if (!cloud.ready) return;
    s.err = ''; busy(true);
    try {
      if (create) await cloud.fb.createUserWithEmailAndPassword(cloud.auth, email.value.trim(), pass.value);
      else await cloud.fb.signInWithEmailAndPassword(cloud.auth, email.value.trim(), pass.value);
      closeSheet(); render();
    } catch (e) { fail(e); }
  };
  if ($('aForgot')) $('aForgot').onclick = async () => {
    if (!email.value.trim()) { s.err = 'Type your email above first.'; return renderSheet(); }
    try { await cloud.fb.sendPasswordResetEmail(cloud.auth, email.value.trim()); s.err = ''; s.msg = 'Password reset email sent. Check your inbox.'; renderSheet(); }
    catch (e) { fail(e); }
  };
}

/* ================= SETTINGS tab ================= */
const APP_VERSION = '0.29.1';
function applyTheme() {
  document.documentElement.dataset.theme = data.settings.theme;
  const dark = data.settings.theme === 'dark' || (data.settings.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  const m = $('themeColor'); if (m) m.content = dark ? '#000000' : '#f2f2f7';
}
const segHTML = (key, opts) => `<div class="seg sm" data-set="${key}">${opts.map(([v, l]) =>
  `<button data-v="${v}" class="${String(data.settings[key]) === String(v) ? 'on' : ''}">${l}</button>`).join('')}</div>`;

// Save a backup file of all your data (share sheet on phones, download elsewhere)
async function exportBackup() {
  const json = JSON.stringify(data, null, 2);
  const fname = `training-backup-${todayKey()}.json`;
  try {
    const file = new File([json], fname, { type: 'application/json' });
    if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], title: 'Training backup' }); return; }
  } catch (e) { if (e && e.name === 'AbortError') return; }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
  a.download = fname;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}

function renderSettings() {
  const st = data.settings;
  const nSets = data.sets.length, nEx = data.exercises.length;
  const initial = (st.name.trim()[0] || '?').toUpperCase();
  const pend = state.pending;
  app.innerHTML = `
    <header class="nav"></header>
    <div class="large-title">Settings</div>
    <div class="group">
      <div class="profile"><div class="avatar">${esc(initial)}</div><input id="pName" placeholder="Your name" autocomplete="off" value="${esc(st.name)}" aria-label="Your name"></div>
      ${cloud.user ? `
        <div class="set-row"><span class="main" style="min-width:0"><div class="lbl">Account</div><div class="sub" style="font-size:14px;color:var(--label2);overflow:hidden;text-overflow:ellipsis">${esc(cloud.user.email || cloud.user.displayName || 'Signed in')}</div></span>
          <span class="badge" id="syncStatus">${esc(cloudStatusText())}</span></div>
        <button class="cell destructive" id="signOutBtn" style="justify-content:flex-start">Sign out</button>`
      : `<button class="cell action" id="signIn">${plusLead}Sign in to back up and sync</button>`}
    </div>
    ${cloud.status === 'error' && cloud.user ? `<div class="err">${esc(cloudStatusText())}</div>` : ''}

    <div class="section">Preferences</div>
    <div class="group">
      <div class="set-row"><span class="lbl">Units</span>${segHTML('units', [['metric', 'kg'], ['imperial', 'lb']])}</div>
      <div class="set-row"><span class="lbl">Appearance</span>${segHTML('theme', [['system', 'Auto'], ['light', 'Light'], ['dark', 'Dark']])}</div>
      <div class="set-row"><span class="lbl">Week starts on</span>${segHTML('weekStart', [[1, 'Mon'], [0, 'Sun']])}</div>
      <div class="set-row"><span class="lbl">Default sets</span>
        <div class="mini-stepper"><button id="dsMinus" ${st.defaultSets <= 1 ? 'disabled' : ''} aria-label="Fewer default sets">−</button><span>${st.defaultSets}</span><button id="dsPlus" ${st.defaultSets >= 10 ? 'disabled' : ''} aria-label="More default sets">+</button></div></div>
    </div>
    <div class="footnote">Default sets is used when you add a single exercise to a day or to a workout.</div>
    <div class="section">Data</div>
    <div class="group">
      <button class="cell action" id="export">Export backup</button>
      <button class="cell action" id="import">Import backup</button>
      ${pend && pend.startsWith('import') ? `<button class="cell destructive confirm" id="importOk">Replace everything with this backup?</button>` : ''}
    </div>
    <div class="group"><button class="cell destructive ${pend === 'erase' ? 'confirm' : ''}" id="erase">${pend === 'erase' ? `Tap again to erase ${plural(nSets, 'set')} and ${plural(nEx, 'exercise')}${cloud.user ? ' on all your devices' : ''}` : 'Erase all workout data'}</button></div>
    <div class="footnote">${cloud.user ? 'Your workouts are backed up to your account and synced between your devices.' : "You're not signed in, so your workouts are stored only on this device. Sign in above, or export a backup now and then."}</div>
    <div class="err" id="setErr"></div>
    ${cloud.user ? `<div class="group" style="margin-top:28px"><button class="cell destructive" id="delAcct">Delete account</button></div>
      <div class="footnote">Permanently deletes your account and everything stored about you in the cloud.</div>` : ''}

    <div class="section">About</div>
    <div class="group">
      <div class="set-row"><span class="lbl">Version</span><span class="detail" style="color:var(--label2)">${APP_VERSION}</span></div>
      <a class="cell" href="https://github.com/lukaslundmark1/Workout-Tracker" target="_blank" rel="noopener"><span class="main">Source code</span><span class="detail" style="color:var(--label2)">GitHub</span><span class="chev">${ICON_CHEV}</span></a>
    </div>
    <input type="file" id="importFile" accept="application/json,.json" hidden>`;

  if ($('signIn')) $('signIn').onclick = () => openSheet({ type: 'signin' });
  const name = $('pName');
  name.oninput = () => { st.name = name.value; save(); syncMyNameSoon(); app.querySelector('.avatar').textContent = (name.value.trim()[0] || '?').toUpperCase(); };
  app.querySelectorAll('[data-set]').forEach(g => g.querySelectorAll('button').forEach(b => b.onclick = () => {
    const key = g.dataset.set;
    const v = key === 'weekStart' ? Number(b.dataset.v) : b.dataset.v;
    if (st[key] === v) return;
    st[key] = v;
    if (key === 'units') state.drafts = {};            // typed-but-unsaved numbers were in the old unit
    if (key === 'theme') applyTheme();
    if (key === 'weekStart') state.weekStart = startOfWeek(parse(state.selected));
    save(); state.pending = null; render();
  }));
  $('dsMinus').onclick = () => { haptic(); st.defaultSets = Math.max(1, st.defaultSets - 1); save(); render(); };
  $('dsPlus').onclick = () => { haptic(); st.defaultSets = Math.min(10, st.defaultSets + 1); save(); render(); };

  $('export').onclick = () => exportBackup();
  $('import').onclick = () => $('importFile').click();
  $('signOutBtn') && ($('signOutBtn').onclick = () => openSheet({ type: 'signout' }));
  $('delAcct') && ($('delAcct').onclick = () => openSheet({ type: 'deleteAccount' }));
  $('importFile').onchange = e => {
    const f = e.target.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = () => {
      try {
        const d = JSON.parse(r.result);
        if (!d || !Array.isArray(d.exercises) || !Array.isArray(d.sets)) throw new Error('bad');
        state.importData = d; state.pending = 'import'; haptic('warn'); render();
      } catch (err) { $('setErr').textContent = "That file isn't a Training backup."; }
    };
    r.readAsText(f);
  };
  if ($('importOk')) $('importOk').onclick = () => {
    data = migrate(cleanBackup(state.importData)); state.importData = null; state.drafts = {};
    save(); applyTheme(); state.pending = null; render();
  };
  $('erase').onclick = () => {
    if (state.pending !== 'erase') { haptic('warn'); state.pending = 'erase'; return render(); }
    data = migrate({ exercises: [], days: {}, sets: [], workouts: [], settings: data.settings });
    state.drafts = {}; save(); state.pending = null; render();
  };
}

/* ================= FRIENDS ================= */
// Friends are a symmetric link between two people (links/{uidA_uidB}). Each person controls their own
// switches on the link: share[myUid] = whether the other person can see my training (read-only).
// Invites use a short code (codes/{CODE} → uid + name) or a link to the app with #add-CODE.
const friends = { links: [], unsub: null, cache: {}, exCache: {}, error: '', nameTimer: null, gifts: { in: [], out: [], seen: null, error: '' }, giftUnsubs: [] };
const pairId = (a, b) => (a < b ? a + '_' + b : b + '_' + a);
const CODE_ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const fmtCode = c => (c ? c.slice(0, 3) + '-' + c.slice(3) : '');
const cleanCode = s => String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
const myName = () => (data.settings.name || '').trim() || (cloud.user && (cloud.user.displayName || (cloud.user.email || '').split('@')[0])) || 'Someone';
const otherOf = l => l.members.find(m => m !== cloud.user.uid);
const nameOf = l => (l.names && l.names[otherOf(l)]) || 'Friend';
const inviteUrl = () => location.origin + location.pathname + '#add-' + data.settings.code;
const isPerm = e => String((e && (e.code || e.message)) || '').includes('permission');
const initialOf = n => (String(n).trim()[0] || '?').toUpperCase();

function startFriends() {
  const fb = cloud.fb, uid = cloud.user.uid;
  friends.error = '';
  ensureCode();
  friends.unsub = fb.onSnapshot(fb.query(fb.collection(cloud.db, 'links'), fb.where('members', 'array-contains', uid)), snap => {
    friends.links = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    friends.links.forEach(l => { if (!l.names || l.names[uid] !== myName()) fb.updateDoc(fb.doc(cloud.db, 'links', l.id), { ['names.' + uid]: myName(), u: Date.now() }).catch(() => {}); });
    renderDock();
    if (['friends', 'friend'].includes(state.views.friends) && state.tab === 'friends' && !state.sheet) bgRender();
  }, e => { friends.error = isPerm(e) ? 'rules' : (e.code || e.message); if (state.tab === 'friends') bgRender(); });
  startGifts();
  if (state.inviteCode) openSheet({ type: 'addFriend', code: state.inviteCode, auto: true }), (state.inviteCode = null);
}
function stopFriends() { if (friends.unsub) friends.unsub(); friends.unsub = null; friends.links = []; friends.cache = {}; friends.exCache = {}; stopGifts(); }

// Each account gets one friend code, reserved in codes/{CODE}
// Your code is worked out from your account id, so every device shows the same code and it never changes.
// (If that code is ever taken by someone else, the next variant is used.)
function codeFor(uid, variant) {
  const h = (str, seed) => { let x = seed >>> 0; for (let i = 0; i < str.length; i++) { x ^= str.charCodeAt(i); x = Math.imul(x, 16777619) >>> 0; } return x; };
  const a = h(uid + ':' + variant, 2166136261), b = h(variant + ':' + uid, 374761393);
  let out = '';
  for (let i = 0; i < 6; i++) out += CODE_ABC[((i < 3 ? a >>> (i * 5) : b >>> ((i - 3) * 5))) & 31];
  return out;
}
async function ensureCode() {
  const fb = cloud.fb, uid = cloud.user.uid;
  try {
    for (let v = 0; v < 6; v++) {
      const code = codeFor(uid, v);
      const ref = fb.doc(cloud.db, 'codes', code);
      const ex = await fb.getDoc(ref);
      if (ex.exists() && ex.data().uid !== uid) continue;   // taken by someone else
      await fb.setDoc(ref, { uid, name: myName() });
      const old = data.settings.code;
      if (old !== code) {
        // Release an older random code from before this fix, if it's ours
        if (old) fb.getDoc(fb.doc(cloud.db, 'codes', old)).then(d => { if (d.exists() && d.data().uid === uid) fb.deleteDoc(d.ref || fb.doc(cloud.db, 'codes', old)); }).catch(() => {});
        data.settings.code = code; save();
      }
      if (state.tab === 'friends') bgRender();
      return;
    }
  } catch (e) {
    friends.error = isPerm(e) ? 'rules' : (e.code || e.message);
    if (state.tab === 'friends') bgRender();
  }
}
function syncMyNameSoon() {
  if (!cloud.user || !friends.unsub) return;
  clearTimeout(friends.nameTimer);
  friends.nameTimer = setTimeout(() => {
    const fb = cloud.fb, uid = cloud.user.uid;
    if (data.settings.code) fb.setDoc(fb.doc(cloud.db, 'codes', data.settings.code), { uid, name: myName() }).catch(() => {});
    friends.links.forEach(l => fb.updateDoc(fb.doc(cloud.db, 'links', l.id), { ['names.' + uid]: myName(), u: Date.now() }).catch(() => {}));
  }, 1500);
}

async function lookupCode(code) {
  const snap = await cloud.fb.getDoc(cloud.fb.doc(cloud.db, 'codes', code));
  return snap.exists() ? snap.data() : null;
}
async function sendFriendRequest(other, otherName, share) {
  const fb = cloud.fb, me = cloud.user.uid, id = pairId(me, other), ref = fb.doc(cloud.db, 'links', id);
  const ex = await fb.getDoc(ref);
  if (ex.exists()) {
    const l = { id, ...ex.data() };
    if (l.status === 'pending' && l.from === other) return acceptFriend(l, share);   // they already asked you
    throw new Error(l.status === 'accepted' ? "You're already friends." : 'Request already sent.');
  }
  await fb.setDoc(ref, { members: [me, other].sort(), from: me, status: 'pending', share: { [me]: !!share }, names: { [me]: myName(), [other]: otherName || 'Friend' }, u: Date.now() });
}
const acceptFriend = (l, share) => cloud.fb.updateDoc(cloud.fb.doc(cloud.db, 'links', l.id), { status: 'accepted', ['share.' + cloud.user.uid]: !!share, ['names.' + cloud.user.uid]: myName(), u: Date.now() });
const setShare = (l, on) => cloud.fb.updateDoc(cloud.fb.doc(cloud.db, 'links', l.id), { ['share.' + cloud.user.uid]: on, u: Date.now() });
const removeLink = l => cloud.fb.deleteDoc(cloud.fb.doc(cloud.db, 'links', l.id));

// A friend's training (read-only): exercises + the last 120 days of sets and days
async function loadFriend(uid, force) {
  const c = friends.cache[uid];
  if (c && !force && Date.now() - c.at < 60 * 1000) return c;
  const fb = cloud.fb, col = n => fb.collection(cloud.db, 'users', uid, n);
  const cutoff = dk(addDays(new Date(), -120));
  const [ex, sets, days] = await Promise.all([
    fb.getDocs(col('exercises')),
    fb.getDocs(fb.query(col('sets'), fb.where('date', '>=', cutoff))),
    fb.getDocs(fb.query(col('days'), fb.where(fb.documentId(), '>=', cutoff))),
  ]);
  // Their data is written by them, so it's cleaned before use (see "Cleaning data that comes from outside this phone")
  const live = s => s.docs.map(d => ({ ...d.data(), id: d.id })).filter(x => !x.deleted);
  const out = { exercises: live(ex).map(cleanExercise).filter(Boolean), sets: live(sets).map(cleanSet).filter(Boolean),
    days: cleanDays(Object.fromEntries(live(days).map(d => [d.id, d]))), at: Date.now() };
  friends.cache[uid] = out;
  return out;
}
async function loadFriendExercise(uid, exId) {
  const key = uid + '|' + exId;
  if (friends.exCache[key] && Date.now() - friends.exCache[key].at < 60 * 1000) return friends.exCache[key].sets;
  const fb = cloud.fb;
  const snap = await fb.getDocs(fb.query(fb.collection(cloud.db, 'users', uid, 'sets'), fb.where('exId', '==', exId)));
  const sets = snap.docs.map(d => ({ ...d.data(), id: d.id })).filter(x => !x.deleted).map(cleanSet).filter(Boolean);
  friends.exCache[key] = { sets, at: Date.now() };
  return sets;
}

const RULES_HELP = `<div class="group hero" style="text-align:left">
  <h2 style="text-align:center">One more Firebase step</h2>
  <p>Friends needs updated security rules. In the Firebase console, open Firestore → Rules, replace them with the new rules from Claude, and click Publish. Then reopen the app.</p></div>`;

function renderFriends() {
  const head = `<header class="nav"><span class="spacer"></span>${cloud.user ? `<button class="circle glass" id="addF" aria-label="Add friend">${svg('<path d="M12 5v14M5 12h14"/>', 20, 2.4)}</button>` : ''}</header>
    <div class="large-title">Friends</div>`;
  const meCell = `<div class="group"><button class="cell me-cell" id="meCell"><span class="avatar">${esc(initialOf(myLabel()))}</span>
    <span class="main"><div>${esc(myLabel())}</div><div class="sub">Your profile</div></span><span class="chev">${ICON_CHEV}</span></button></div>`;
  const wireMe = () => { $('meCell').onclick = () => go('me', { prof: 'me' }); };
  if (!cloud.user) {
    app.innerHTML = head + meCell + `
      <div class="group hero">
        <div class="hero-icon">${svg('<circle cx="9" cy="8.5" r="3.2"/><path d="M3 19.5c.6-3.3 3-5 6-5s5.4 1.7 6 5"/><circle cx="17" cy="9.5" r="2.6"/><path d="M16.5 14.6c2.4.2 4 1.7 4.5 4.4"/>', 40, 1.8)}</div>
        <h2>Train together</h2>
        <p>Add friends, share your training, and follow each other's progress. Sign in to get started.</p>
      </div>
      <button class="primary" id="fSignIn">Sign in</button>`;
    $('fSignIn').onclick = () => openSheet({ type: 'signin' });
    wireMe();
    return;
  }
  if (friends.error === 'rules') { app.innerHTML = head + meCell + RULES_HELP; wireMe(); return; }
  const me = cloud.user.uid;
  const incoming = friends.links.filter(l => l.status === 'pending' && l.from !== me);
  const outgoing = friends.links.filter(l => l.status === 'pending' && l.from === me);
  const accepted = friends.links.filter(l => l.status === 'accepted').sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
  const avatar = n => `<span class="avatar sm">${esc(initialOf(n))}</span>`;
  const inbox = pendingGifts();
  app.innerHTML = head + meCell + `
    ${inbox.length ? `<div class="section">Inbox</div><div class="group">${inbox.map(g => `<button class="cell" data-gift="${g.id}"><span class="inbox-ic">${ICON_GIFT}</span>
      <span class="main"><div>${esc(g.name)}</div><div class="sub">From ${esc(g.fromName || 'a friend')} · ${giftSummary(g.kind, g.payload || {})}</div></span><span class="chev">${ICON_CHEV}</span></button>`).join('')}</div>` : ''}
    ${friends.gifts.error === 'rules' ? `<div class="err">Sending workouts and plans needs the new Firebase rules. Open Firestore → Rules, paste the rules from Claude and click Publish.</div>` : ''}
    <div class="group code-card">
      <div class="lb-label">Your friend code</div>
      <div class="code">${data.settings.code ? esc(fmtCode(data.settings.code)) : '<span style="color:var(--label3)">······</span>'}</div>
      <div class="code-btns">
        <button class="capsule glass" id="shareInv" ${data.settings.code ? '' : 'disabled'}>${svg('<path d="M12 3v12M7 8l5-5 5 5M5 14v5h14v-5"/>', 17, 2)} Share invite</button>
        <button class="capsule glass" id="copyCode" ${data.settings.code ? '' : 'disabled'}>${svg('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>', 17, 2)} <span id="copyLbl">Copy code</span></button>
      </div>
    </div>
    ${friends.error ? `<div class="err">${esc(friends.error)}</div>` : ''}
    ${incoming.length ? `<div class="section">Requests</div><div class="group">${incoming.map(l => `
      <div class="set-row"><span class="main">${avatar(nameOf(l))}${esc(nameOf(l))}</span>
        <span style="display:flex;gap:6px"><button class="capsule tint-fill" data-acc="${l.id}">Accept</button><button class="circle" data-dec="${l.id}" aria-label="Decline" style="width:36px;height:36px;color:var(--label2)">${ICON_X}</button></span></div>`).join('')}</div>` : ''}
    <div class="section">Friends</div>
    ${accepted.length ? `<div class="group">${accepted.map(l => {
      const o = otherOf(l), theyShare = l.share && l.share[o], iShare = l.share && l.share[me];
      return `<button class="cell" data-friend="${l.id}"><span class="avatar sm">${esc(initialOf(nameOf(l)))}</span><span class="main"><div>${esc(nameOf(l))}</div>
        <div class="sub">${theyShare ? 'Shares their training' : 'Not sharing'}${iShare ? ' · you share yours' : ''}</div></span><span class="chev">${ICON_CHEV}</span></button>`;
    }).join('')}</div>` : `<div class="group"><div class="empty">No friends yet. Share your code, or tap + to add someone by their code.</div></div>`}
    ${outgoing.length ? `<div class="section">Sent</div><div class="group">${outgoing.map(l => `
      <div class="set-row"><span class="main">${avatar(nameOf(l))}${esc(nameOf(l))}</span>
        <span style="display:flex;align-items:center;gap:8px"><span class="badge">Waiting</span><button class="circle" data-dec="${l.id}" aria-label="Cancel request" style="width:36px;height:36px;color:var(--label2)">${ICON_X}</button></span></div>`).join('')}</div>` : ''}`;

  wireMe();
  $('addF').onclick = () => openSheet({ type: 'addFriend', code: '' });
  $('shareInv').onclick = async () => {
    const text = `Add me on Training tracker — my friend code is ${fmtCode(data.settings.code)}`;
    try { if (navigator.share) { await navigator.share({ title: 'Training tracker', text, url: inviteUrl() }); return; } } catch (e) { if (e.name === 'AbortError') return; }
    try { await navigator.clipboard.writeText(text + '\n' + inviteUrl()); $('copyLbl').textContent = 'Copied'; } catch (e) {}
  };
  $('copyCode').onclick = async () => { try { await navigator.clipboard.writeText(fmtCode(data.settings.code)); $('copyLbl').textContent = 'Copied'; setTimeout(() => { const c = $('copyLbl'); if (c) c.textContent = 'Copy code'; }, 1500); } catch (e) {} };
  app.querySelectorAll('[data-acc]').forEach(b => b.onclick = () => openSheet({ type: 'acceptFriend', id: b.dataset.acc }));
  app.querySelectorAll('[data-gift]').forEach(b => b.onclick = () => openSheet({ type: 'gift', id: b.dataset.gift }));
  app.querySelectorAll('[data-dec]').forEach(b => b.onclick = () => { const l = friends.links.find(x => x.id === b.dataset.dec); if (l) removeLink(l).catch(e => { friends.error = e.code || e.message; render(); }); });
  app.querySelectorAll('[data-friend]').forEach(b => b.onclick = () => go('friend', { friendLink: b.dataset.friend, prof: b.dataset.friend }));
}

function renderFriend() {
  const l = friends.links.find(x => x.id === state.friendLink && x.status === 'accepted');
  if (!l) return go('friends');
  state.prof = l.id;
  const me = cloud.user.uid, o = otherOf(l), name = nameOf(l);
  const theyShare = l.share && l.share[o], iShare = !!(l.share && l.share[me]);
  if (friends.cache[o] && Date.now() - friends.cache[o].at > 60 * 1000 && !state.friendLoading) delete friends.cache[o];
  const c = friends.cache[o];
  let body = '';
  if (!theyShare) body = `<div class="group"><div class="empty">${esc(name)} isn't sharing their training with you.</div></div>`;
  else if (state.friendErr) body = `<div class="err">${esc(state.friendErr)}</div>`;
  else if (!c) body = SKELETON;
  else body = profileBodyHTML(c, true);
  app.innerHTML = `
    <header class="nav">${backBtn('Friends')}<span class="spacer"></span>${theyShare ? `<button class="circle glass" id="fRefresh" aria-label="Refresh">${svg('<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>', 18, 2.2)}</button>` : ''}</header>
    <div class="friend-head"><span class="avatar">${esc(initialOf(name))}</span><div class="large-title" style="margin:0">${esc(name)}</div></div>
    ${body}
    ${giftHistoryHTML(l)}
    <div class="section">Your sharing</div>
    <div class="group"><label class="set-row"><span class="lbl">Share my training with ${esc(name)}</span>
      <input type="checkbox" switch class="switch" id="shareSw" ${iShare ? 'checked' : ''}></label></div>
    <div class="footnote">${esc(name)} can see your workouts, sets and progress, but can't change anything.</div>
    <div class="group" style="margin-top:28px"><button class="cell destructive ${state.pending === 'unfriend' ? 'confirm' : ''}" id="unfriend">${state.pending === 'unfriend' ? 'Tap again to remove' : 'Remove friend'}</button></div>`;
  $('back').onclick = () => go('friends');
  $('shareSw').onchange = e => setShare(l, e.target.checked).catch(err => { friends.error = err.code || err.message; });
  $('unfriend').onclick = () => {
    if (state.pending !== 'unfriend') { haptic('warn'); state.pending = 'unfriend'; return render(); }
    state.pending = null; removeLink(l).then(() => go('friends'));
  };
  if ($('fRefresh')) $('fRefresh').onclick = () => { delete friends.cache[o]; render(); };
  wireProfileBody();
  wireGiftHistory(l);
  if (theyShare && !c && !state.friendLoading) {
    state.friendLoading = true; state.friendErr = '';
    loadFriend(o).then(() => { state.friendLoading = false; if (state.views.friends === 'friend') bgRender(); })
      .catch(e => { state.friendLoading = false; state.friendErr = isPerm(e) ? "Couldn't load — check that the new Firebase rules are published." : (e.code || e.message); if (state.views.friends === 'friend') render(); });
  }
}

/* ================= Sending workouts and plans to friends =================
   A sent item is a document gifts/{id}: { from, to, fromName, toName, kind: 'workout'|'plan', name, payload, status, u }.
   The payload is self-contained (exercises by name, with their details), so it doesn't depend on the sender's ids.
   The recipient sees it in their Inbox and can Add (copies it in) or Decline; the sender sees the status.
   Firestore rules: only friends can send, only the recipient can change the status. */
const GIFT_MAX = { name: 60, instr: 2000, items: 60, days: 120 };   // safety limits on what's accepted from someone else
const str = (v, n) => String(v == null ? '' : v).trim().slice(0, n);

// What gets sent
function exPayload(id) {
  const e = exById(id); if (!e) return null;
  return { name: e.name, track: e.track, muscle: e.muscle || '', equip: e.equip || '', lib: e.lib || '', instructions: e.instructions || '', video: e.video || '' };
}
function workoutPayload(w) {
  return { name: w.name, items: w.items.map(i => ({ ex: exPayload(i.exId), sets: i.sets })).filter(i => i.ex) };
}
function planPayload(p) {
  const ids = [...new Set(p.days.map(d => d.workoutId).filter(id => woById(id)))];
  return { name: p.name, weeks: p.weeks || 0, workouts: ids.map(id => workoutPayload(woById(id))), days: p.days.map(d => ({ w: ids.indexOf(d.workoutId) })) };
}
// Short description of an item, e.g. "Plan · 7-day rotation · 2 workouts" or "Workout · 5 exercises"
function giftSummary(kind, payload) {
  if (kind === 'plan') {
    const days = Array.isArray(payload.days) ? payload.days.length : 0, wo = Array.isArray(payload.workouts) ? payload.workouts.length : 0;
    const weeks = cl.int(payload.weeks, 0, 52);
    return `Plan · ${days}-day rotation · ${plural(wo, 'workout')}${weeks ? ` · ${plural(weeks, 'week')}` : ''}`;
  }
  return `Workout · ${plural(Array.isArray(payload.items) ? payload.items.length : 0, 'exercise')}`;
}

// Bringing a received item in. Everything from the other person is cleaned up first (lengths, numbers, known values).
const TRACK_OK = [TRACK_A.map(t => t.v), TRACK_B.map(t => t.v)];
function importExercise(x) {
  const name = str(x && x.name, GIFT_MAX.name) || 'Exercise';
  const lib = str(x.lib, 80);
  const have = (lib && data.exercises.find(e => e.lib === lib)) || data.exercises.find(e => normName(e.name) === normName(name));
  if (have) return have.id;
  const track = Array.isArray(x.track) && TRACK_OK[0].includes(x.track[0]) && TRACK_OK[1].includes(x.track[1]) ? [x.track[0], x.track[1]] : ['weight', 'reps'];
  const id = uid();
  const rec = { id, name, track, instructions: str(x.instructions, GIFT_MAX.instr), video: ytId(x.video) ? str(x.video, 200) : '',
    muscle: MUSCLES.some(m => m[0] === x.muscle) ? x.muscle : '', equip: EQUIP.some(m => m[0] === x.equip) ? x.equip : '' };
  if (lib && libById(lib)) rec.lib = lib;
  data.exercises.push(rec);
  return id;
}
const uniqueName = (name, list, from) => list.some(x => x.name.toLowerCase() === name.toLowerCase()) ? `${name} (${from})` : name;
function importWorkout(wp, from) {
  const items = (Array.isArray(wp && wp.items) ? wp.items : []).slice(0, GIFT_MAX.items)
    .filter(i => i && i.ex).map(i => ({ exId: importExercise(i.ex), sets: Math.max(1, Math.min(10, parseInt(i.sets, 10) || 3)) }));
  const id = uid();
  data.workouts.push({ id, name: uniqueName(str(wp && wp.name, GIFT_MAX.name) || 'Workout', data.workouts, from), items });
  return id;
}
function importPlan(pp, from) {
  const wids = (Array.isArray(pp.workouts) ? pp.workouts : []).slice(0, GIFT_MAX.days).map(w => importWorkout(w, from));
  const days = (Array.isArray(pp.days) ? pp.days : []).slice(0, GIFT_MAX.days).map(d => ({ workoutId: d && wids[d.w] ? wids[d.w] : null }));
  const id = uid();
  data.plans.push({ id, name: uniqueName(str(pp.name, GIFT_MAX.name) || 'Plan', data.plans, from), weeks: Math.max(0, Math.min(52, parseInt(pp.weeks, 10) || 0)), days: days.length ? days : [{ workoutId: null }] });
  return id;
}

// Live lists of what you've received and sent
function startGifts() {
  const fb = cloud.fb, uid = cloud.user.uid;
  friends.gifts = { in: [], out: [], seen: null, error: '' };
  const onErr = e => { friends.gifts.error = isPerm(e) ? 'rules' : (e.code || e.message); if (state.tab === 'friends') bgRender(); };
  const col = fb.collection(cloud.db, 'gifts');
  friends.giftUnsubs = [
    fb.onSnapshot(fb.query(col, fb.where('to', '==', uid)), snap => {
      const list = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      const g = friends.gifts;
      // Something new arrived while the app is open: say so
      if (g.seen) list.filter(x => x.status === 'pending' && !g.seen.has(x.id)).forEach(x =>
        toast(`<span class="tic" style="background:var(--tint-soft);color:var(--tint)">${ICON_GIFT}</span><span>${esc(x.fromName || 'A friend')} sent you ${esc(x.name)}<small>Open Friends to add it</small></span>`));
      g.seen = new Set(list.map(x => x.id));
      g.in = list; g.error = '';
      giftsChanged();
    }, onErr),
    fb.onSnapshot(fb.query(col, fb.where('from', '==', uid)), snap => {
      friends.gifts.out = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      giftsChanged();
    }, onErr),
  ];
}
function stopGifts() { (friends.giftUnsubs || []).forEach(u => u()); friends.giftUnsubs = []; friends.gifts = { in: [], out: [], seen: null, error: '' }; }
const pendingGifts = () => (friends.gifts ? friends.gifts.in.filter(g => g.status === 'pending').sort((a, b) => b.u - a.u) : []);
function giftsChanged() {
  renderDock();
  const v = state.views.friends;
  if (state.tab === 'friends' && (v === 'friends' || v === 'friend') && !state.sheet) bgRender();
  else if (state.sheet && state.sheet.type === 'gift') renderSheet();
}

// Send one item to one or more friends
async function sendGift(kind, item, links) {
  const fb = cloud.fb, me = cloud.user.uid;
  const payload = kind === 'plan' ? planPayload(item) : workoutPayload(item);
  const sends = links.map(l => fb.setDoc(fb.doc(cloud.db, 'gifts', uid()), {
    from: me, to: otherOf(l), fromName: str(myName(), 60), toName: str(nameOf(l), 60), kind, name: str(item.name, GIFT_MAX.name) || (kind === 'plan' ? 'Plan' : 'Workout'),
    payload, status: 'pending', u: Date.now(),
  }));
  await Promise.all(sends);
}
const whenSent = u => { const r = relDay(dk(new Date(u || Date.now()))); return r === 'Today' || r === 'Yesterday' ? r.toLowerCase() : `on ${r}`; };
const sentToast = (name, links) => haptic('success') || toast(`<span class="tic" style="background:var(--green-soft);color:var(--green)">${ICON_OK}</span><span>Sent ${esc(name)}<small>To ${links.map(l => esc(nameOf(l))).join(', ')}</small></span>`);
const sendErrText = e => isPerm(e) ? 'Sending needs the new Firebase rules. Open Firestore → Rules, paste the rules from Claude and click Publish.' : `Couldn't send (${esc(e.code || e.message)}).`;

function acceptGift(g) {
  const from = str(g.fromName, 40) || 'friend';
  let target;
  if (g.kind === 'plan') target = { view: 'pView', planId: importPlan(g.payload || {}, from) };
  else target = { view: 'wEdit', workoutId: importWorkout(g.payload || {}, from) };
  save();
  g.status = 'added';
  cloud.fb.updateDoc(cloud.fb.doc(cloud.db, 'gifts', g.id), { status: 'added', u: Date.now() }).catch(() => {});
  closeSheet();
  // Open what was added in the Workouts tab
  state.tab = 'workouts';
  if (target.view === 'pView') { state.views.workouts = 'wList'; state.wSeg = 'plans'; go('pView', { planId: target.planId }); }
  else { state.views.workouts = 'wList'; state.wSeg = 'workouts'; render(); }
  toast(`<span class="tic" style="background:var(--green-soft);color:var(--green)">${ICON_OK}</span><span>${esc(g.name)} added<small>${g.kind === 'plan' ? 'Start it whenever you like' : 'It\'s in your workouts'}</small></span>`);
}
function declineGift(g) {
  g.status = 'declined';
  cloud.fb.updateDoc(cloud.fb.doc(cloud.db, 'gifts', g.id), { status: 'declined', u: Date.now() }).catch(() => {});
  closeSheet();
  render();
}
function unsendGift(g) {
  friends.gifts.out = friends.gifts.out.filter(x => x.id !== g.id);
  cloud.fb.deleteDoc(cloud.fb.doc(cloud.db, 'gifts', g.id)).catch(() => {});
  render();
}

/* Sheet: pick friends to send a workout or plan to */
function sheetSendTo(el) {
  const s = state.sheet;
  const item = s.kind === 'plan' ? planById(s.id) : (s.draft || woById(s.id));
  if (!item) { closeSheet(); return; }
  const accepted = cloud.user ? friends.links.filter(l => l.status === 'accepted').sort((a, b) => nameOf(a).localeCompare(nameOf(b))) : [];
  s.picked = s.picked || [];
  const body = !cloud.user
    ? `<div class="group hero" style="margin-top:0"><p>Sign in and add a friend to send them ${s.kind === 'plan' ? 'plans' : 'workouts'}.</p></div><button class="primary" id="sSignIn">Sign in</button>`
    : !accepted.length
      ? `<div class="group"><div class="empty">No friends yet. Add someone in the Friends tab first.</div></div>`
      : `<div class="group">${accepted.map(l => { const on = s.picked.includes(l.id); return `<button class="cell pick-row ${on ? 'on' : ''}" data-pick="${l.id}">
          <span class="avatar sm">${esc(initialOf(nameOf(l)))}</span><span class="main">${esc(nameOf(l))}</span>
          <span class="pick-dot" aria-hidden="true">${on ? ICON_CHECK : ''}</span></button>`; }).join('')}</div>
        <div class="footnote">They get their own copy${s.kind === 'plan' ? ', with its workouts and exercises' : ' with its exercises'}. Changes you make later won't affect it.</div>
        <div class="err" id="sendErr">${s.err || ''}</div>
        <button class="primary" id="sGo" ${s.picked.length && !s.busy ? '' : 'disabled'}>${s.busy ? 'Sending…' : s.picked.length > 1 ? `Send to ${s.picked.length} friends` : 'Send'}</button>`;
  el.innerHTML = sheetOpen('Send to a friend', `${closeBtn('sCancel')}<b>Send ${esc(item.name || (s.kind === 'plan' ? 'plan' : 'workout'))}</b><span></span>`, `
    <div class="finish-sub" style="margin:0 8px 12px">${giftSummary(s.kind, s.kind === 'plan' ? planPayload(item) : workoutPayload(item))}</div>${body}`);
  $('sCancel').onclick = () => closeSheet();
  if ($('sSignIn')) $('sSignIn').onclick = () => openSheet({ type: 'signin' });
  el.querySelectorAll('[data-pick]').forEach(b => b.onclick = () => {
    const id = b.dataset.pick; s.picked = s.picked.includes(id) ? s.picked.filter(x => x !== id) : [...s.picked, id]; s.err = ''; haptic(); renderSheet();
  });
  if ($('sGo')) $('sGo').onclick = () => {
    const links = friends.links.filter(l => s.picked.includes(l.id));
    s.busy = true; renderSheet();
    sendGift(s.kind, item, links).then(() => { if (state.sheet === s) closeSheet(); sentToast(item.name, links); render(); })
      .catch(e => { s.busy = false; s.err = sendErrText(e); if (state.sheet === s) renderSheet(); });
  };
}

/* Sheet: from a friend's page, pick a plan or workout to send them */
function sheetSendPick(el) {
  const s = state.sheet, l = friends.links.find(x => x.id === s.link);
  if (!l) { closeSheet(); return; }
  const row = (kind, x, sub) => `<div class="set-row"><span class="main" style="display:block;min-width:0"><div>${esc(x.name)}</div><div class="sub">${sub}</div></span>
    <button class="capsule tint-fill" data-send="${kind}:${x.id}" ${s.busy ? 'disabled' : ''}>Send</button></div>`;
  el.innerHTML = sheetOpen('Send to ' + nameOf(l), `${closeBtn('sCancel')}<b>Send to ${esc(nameOf(l))}</b><span></span>`, `
    ${data.plans.length ? `<div class="section">Plans</div><div class="group">${data.plans.map(p => row('plan', p, planSummary(p))).join('')}</div>` : ''}
    ${data.workouts.length ? `<div class="section">Workouts</div><div class="group">${[...data.workouts].sort(byName).map(w => row('workout', w, plural(w.items.length, 'exercise'))).join('')}</div>` : ''}
    ${!data.plans.length && !data.workouts.length ? '<div class="group"><div class="empty">You have no workouts or plans yet. Make some in the Workouts tab.</div></div>' : ''}
    <div class="err">${s.err || ''}</div>`);
  $('sCancel').onclick = () => closeSheet();
  el.querySelectorAll('[data-send]').forEach(b => b.onclick = () => {
    const [kind, id] = b.dataset.send.split(':');
    const item = kind === 'plan' ? planById(id) : woById(id);
    if (!item) return;
    s.busy = true; renderSheet();
    sendGift(kind, item, [l]).then(() => { if (state.sheet === s) closeSheet(); sentToast(item.name, [l]); render(); })
      .catch(e => { s.busy = false; s.err = sendErrText(e); if (state.sheet === s) renderSheet(); });
  });
}

/* Sheet: something a friend sent you — see what's in it, then Add or Decline */
function sheetGift(el) {
  const g = friends.gifts && friends.gifts.in.find(x => x.id === state.sheet.id);
  if (!g) { closeSheet(); return; }
  const p = g.payload || {};
  const exLine = i => {
    const nm = str(i.ex && i.ex.name, GIFT_MAX.name), isNew = !data.exercises.some(e => (i.ex.lib && e.lib === i.ex.lib) || normName(e.name) === normName(nm));
    return `<div class="set-row"><span class="main">${esc(nm)}${isNew ? '<span class="badge" style="margin-left:8px">New</span>' : ''}</span><span class="detail" style="color:var(--label2)">${plural(parseInt(i.sets, 10) || 3, 'set')}</span></div>`;
  };
  const items = w => (Array.isArray(w.items) ? w.items : []).filter(i => i && i.ex);
  let content;
  if (g.kind === 'plan') {
    const ws = Array.isArray(p.workouts) ? p.workouts : [];
    content = `<div class="section">Rotation</div><div class="group">${(p.days || []).map((d, i) => { const w = ws[d.w];
        return `<div class="set-row"><span class="main"><span class="daynum">${i + 1}</span>${w ? esc(str(w.name, GIFT_MAX.name)) : '<span style="color:var(--label2)">Rest</span>'}</span></div>`; }).join('')}</div>
      ${ws.map(w => `<div class="section">${esc(str(w.name, GIFT_MAX.name))}</div><div class="group">${items(w).map(exLine).join('') || '<div class="empty">No exercises</div>'}</div>`).join('')}`;
  } else content = `<div class="section">Exercises</div><div class="group">${items(p).map(exLine).join('') || '<div class="empty">No exercises</div>'}</div>`;
  const newCount = new Set((g.kind === 'plan' ? (p.workouts || []).flatMap(items) : items(p)).map(i => i.ex)
    .filter(x => !data.exercises.some(e => (x.lib && e.lib === x.lib) || normName(e.name) === normName(x.name))).map(x => normName(x.name))).size;
  el.innerHTML = sheetOpen(g.name, `${closeBtn('sCancel')}<b>From ${esc(g.fromName || 'a friend')}</b><span></span>`, `
    <div class="gift-head"><div class="gift-ic">${ICON_GIFT}</div><div class="large-title" style="margin:0;font-size:28px">${esc(g.name)}</div>
      <div class="finish-sub">${giftSummary(g.kind, p)}<br>Sent ${whenSent(g.u)}</div></div>
    ${content}
    <div class="footnote">${newCount ? `${plural(newCount, 'exercise')} you don't have yet will be added to your exercises. ` : ''}Exercises you already have are reused.</div>
    <button class="primary" id="gAdd">${g.kind === 'plan' ? 'Add plan' : 'Add to my workouts'}</button>
    <button class="btn-tinted" id="gDecline" style="color:var(--red);background:var(--red-soft)">Decline</button>`);
  $('sCancel').onclick = () => closeSheet();
  $('gAdd').onclick = () => { haptic('success'); acceptGift(g); };
  $('gDecline').onclick = () => declineGift(g);
}

// What you've sent to / received from one friend (friend page)
function giftHistoryHTML(l) {
  if (!friends.gifts) return '';
  const o = otherOf(l);
  const sent = friends.gifts.out.filter(g => g.to === o).sort((a, b) => b.u - a.u).slice(0, 8);
  const got = friends.gifts.in.filter(g => g.from === o && g.status !== 'pending').sort((a, b) => b.u - a.u).slice(0, 5);
  const badge = st => st === 'added' ? '<span class="badge ok">Added</span>' : st === 'declined' ? '<span class="badge">Declined</span>' : '<span class="badge">Waiting</span>';
  return `<div class="section">Send to ${esc(nameOf(l))}</div>
    <div class="group"><button class="cell action" id="sendPick">${svg('<path d="M4 12l16-8-6 16-2-7-8-1z"/>', 18, 2)}Send a workout or plan</button></div>
    ${sent.length ? `<div class="group" style="margin-top:10px">${sent.map(g => `<div class="set-row"><span class="main" style="display:block;min-width:0"><div>${esc(g.name)}</div>
      <div class="sub">${g.kind === 'plan' ? 'Plan' : 'Workout'} · sent ${whenSent(g.u)}</div></span>
      <span style="display:flex;align-items:center;gap:6px">${badge(g.status)}${g.status === 'pending' ? `<button class="circle" data-unsend="${g.id}" aria-label="Unsend ${esc(g.name)}" style="width:32px;height:32px;color:var(--label2)">${ICON_X}</button>` : ''}</span></div>`).join('')}</div>` : ''}
    ${got.length ? `<div class="footnote">From ${esc(nameOf(l))}: ${got.map(g => `${esc(g.name)} (${g.status === 'added' ? 'added' : 'declined'})`).join(', ')}.</div>` : ''}`;
}
function wireGiftHistory(l) {
  if ($('sendPick')) $('sendPick').onclick = () => openSheet({ type: 'sendPick', link: l.id });
  app.querySelectorAll('[data-unsend]').forEach(b => b.onclick = () => { const g = friends.gifts.out.find(x => x.id === b.dataset.unsend); if (g) unsendGift(g); });
}

/* ================= Cleaning data that comes from outside this phone =================
   Friends' training, shared database entries, received plans and imported backups are written by other people
   (or come from a file), so every value is checked before the app uses it: text is cut to a sane length,
   numbers must be real numbers in a sensible range, dates must look like dates, ids are plain, unknown fields are dropped.
   (Text is also escaped whenever it's shown, and the Content-Security-Policy blocks any injected script.) */
const cl = {
  text: (v, n = 80) => (typeof v === 'string' ? v : v == null ? '' : String(v)).slice(0, n),
  id: v => cl.text(v, 64).replace(/[^\w:.-]/g, ''),
  num: (v, min, max, dflt = 0) => { const n = Number(v); return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : dflt; },
  int: (v, min, max, dflt = 0) => Math.round(cl.num(v, min, max, dflt)),
  date: v => (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null),
  oneOf: (v, list, dflt = '') => (list.includes(v) ? v : dflt),
};
const cleanTrack = t => Array.isArray(t) && t.length === 2 && TRACK_A.some(x => x.v === t[0]) && TRACK_B.some(x => x.v === t[1]) ? [t[0], t[1]] : ['weight', 'reps'];
function cleanSet(s) {
  const date = cl.date(s && s.date);
  if (!date || !s.id || !s.exId) return null;
  return { id: cl.id(s.id), exId: cl.id(s.exId), date, slot: cl.int(s.slot, 0, 50), weight: cl.num(s.weight, 0, 2000), reps: cl.int(s.reps, 0, 1000), ts: cl.num(s.ts, 0, 9e15) };
}
function cleanExercise(e) {
  if (!e || !e.id) return null;
  const out = { id: cl.id(e.id), name: cl.text(e.name, 60).trim() || 'Exercise', track: cleanTrack(e.track), instructions: cl.text(e.instructions, 2000),
    video: ytId(e.video) ? cl.text(e.video, 200) : '', muscle: cl.oneOf(e.muscle, MUSCLES.map(m => m[0])), equip: cl.oneOf(e.equip, EQUIP.map(m => m[0])) };
  if (e.lib) out.lib = cl.text(e.lib, 80);
  if (e.note) out.note = cl.text(e.note, NOTE_MAX);
  return out;
}
function cleanDay(d) {
  if (!d || typeof d !== 'object') return null;
  const out = {
    items: (Array.isArray(d.items) ? d.items : []).slice(0, 60).filter(i => i && i.exId).map(i => ({ exId: cl.id(i.exId), sets: i.sets == null ? null : cl.int(i.sets, 0, 50) })),
    workouts: (Array.isArray(d.workouts) ? d.workouts : []).slice(0, 10).filter(w => w && w.id).map(w => ({ id: cl.id(w.id), name: cl.text(w.name, 60) })),
  };
  if (d.session && typeof d.session === 'object') { out.session = { start: cl.num(d.session.start, 0, 9e15) }; if (d.session.end != null) out.session.end = cl.num(d.session.end, 0, 9e15); }
  if (d.plan && typeof d.plan === 'object') out.plan = { id: cl.id(d.plan.id), index: cl.int(d.plan.index, 0, 500) };
  if (d.pinned) out.pinned = true;
  if (d.rest) out.rest = true;
  if (d.absorb === 'next' || d.absorb === 'round') out.absorb = d.absorb;
  return out;
}
const cleanDays = days => Object.fromEntries(Object.entries(days && typeof days === 'object' ? days : {}).filter(([k]) => cl.date(k)).map(([k, d]) => [k, cleanDay(d)]).filter(([, d]) => d));
function cleanWorkout(w) {
  if (!w || !w.id) return null;
  return { id: cl.id(w.id), name: cl.text(w.name, 60).trim() || 'Workout', items: (Array.isArray(w.items) ? w.items : []).slice(0, 60).filter(i => i && i.exId).map(i => ({ exId: cl.id(i.exId), sets: cl.int(i.sets, 1, 10, 3) })) };
}
function cleanPlan(p) {
  if (!p || !p.id) return null;
  return { id: cl.id(p.id), name: cl.text(p.name, 60).trim() || 'Plan', weeks: cl.int(p.weeks, 0, 52),
    days: (Array.isArray(p.days) ? p.days : []).slice(0, 120).map(d => ({ workoutId: d && d.workoutId ? cl.id(d.workoutId) : null })) };
}
// A whole backup file (Settings → Import)
function cleanBackup(d) {
  const settings = d.settings && typeof d.settings === 'object' ? d.settings : {};
  const ap = d.activePlan && typeof d.activePlan === 'object' && cl.date(d.activePlan.begin) && cl.date(d.activePlan.start)
    ? { planId: cl.id(d.activePlan.planId), begin: d.activePlan.begin, start: d.activePlan.start } : null;
  return {
    exercises: d.exercises.map(cleanExercise).filter(Boolean),
    sets: d.sets.map(cleanSet).filter(Boolean),
    days: cleanDays(d.days),
    workouts: (Array.isArray(d.workouts) ? d.workouts : []).map(cleanWorkout).filter(Boolean),
    plans: (Array.isArray(d.plans) ? d.plans : []).map(cleanPlan).filter(Boolean),
    activePlan: ap,
    settings: { units: cl.oneOf(settings.units, ['metric', 'imperial'], 'metric'), theme: cl.oneOf(settings.theme, ['system', 'light', 'dark'], 'system'),
      weekStart: cl.oneOf(settings.weekStart, [0, 1], 1), defaultSets: cl.int(settings.defaultSets, 1, 10, 3), name: cl.text(settings.name, 40),
      ...(settings.code ? { code: cl.text(settings.code, 8).replace(/[^A-Z0-9]/g, '') } : {}) },
  };
}
// A shared database entry (written by any user)
function cleanLibEntry(docId, d) {
  const name = cl.text(d && d.name, 60).trim();
  if (!name) return null;
  return { id: 's:' + cl.id(docId), docId: cl.id(docId), name, muscle: cl.oneOf(d.muscle, MUSCLES.map(m => m[0])), equip: cl.oneOf(d.equip, EQUIP.map(m => m[0])),
    track: cleanTrack(d.track), by: cl.id(d.by), byName: cl.text(d.byName, 40), u: cl.num(d.u, 0, 9e15) };
}

/* ================= Leaving: sign out, delete account ================= */
// Remove your training from this phone (your cloud copy is untouched unless you deleted your account)
async function wipeDevice(uid) {
  clearTimeout(saveSyncNow.t); saveSyncNow.t = null; cloud.sync = null;   // nothing may be written back after this
  const keep = { units: data.settings.units, theme: data.settings.theme, weekStart: data.settings.weekStart, defaultSets: data.settings.defaultSets };
  try {
    ['tt.v1', 'tt.owner', 'tt.rest', 'tt.lib', 'tt.sync.' + uid, 'tt.v1.' + uid].forEach(k => localStorage.removeItem(k));
    Object.keys(localStorage).filter(k => k.startsWith(SKEY)).forEach(k => localStorage.removeItem(k));   // the sets, kept per month
    localStorage.setItem('tt.v1', JSON.stringify(migrate({ exercises: [], days: {}, sets: [], workouts: [], settings: keep })));
  } catch (e) {}
  // Firestore keeps its own offline copy on the phone too
  try { await cloud.fb.terminate(cloud.db); await cloud.fb.clearIndexedDbPersistence(cloud.db); } catch (e) {}
  location.reload();
}
async function signOutNow(removeHere) {
  const uid = cloud.user && cloud.user.uid;
  try { await pushChanges(); } catch (e) {}
  stopListening(); stopFriends(); stopLibrary();
  saveSyncNow();
  await cloud.fb.signOut(cloud.auth);
  if (removeHere && uid) await wipeDevice(uid);
}
// Deletes everything about you in the cloud, then the account itself, then this phone's copy
async function deleteAccount(password, progress) {
  const fb = cloud.fb, user = cloud.user, uid = user.uid;
  const google = (user.providerData || []).some(p => p.providerId === 'google.com') && !(user.providerData || []).some(p => p.providerId === 'password');
  progress('Confirming it\'s you…');
  if (google) await fb.reauthenticateWithPopup(user, new fb.GoogleAuthProvider());
  else await fb.reauthenticateWithCredential(user, fb.EmailAuthProvider.credential(user.email, password));
  cloud.deleting = true;
  stopListening(); stopFriends(); stopLibrary();
  const delDocs = async (snap, path) => {
    const refs = snap.docs.map(d => fb.doc(cloud.db, ...path, d.id));
    for (let i = 0; i < refs.length; i += 50) await Promise.all(refs.slice(i, i + 50).map(r => fb.deleteDoc(r)));
  };
  progress('Deleting your training…');
  for (const col of Object.keys(COLS)) await delDocs(await fb.getDocs(fb.collection(cloud.db, 'users', uid, col)), ['users', uid, col]);
  progress('Deleting friends and shared items…');
  const where = (col, f, op, v) => fb.getDocs(fb.query(fb.collection(cloud.db, col), fb.where(f, op, v)));
  await delDocs(await where('links', 'members', 'array-contains', uid), ['links']);
  await delDocs(await where('gifts', 'to', '==', uid), ['gifts']);
  await delDocs(await where('gifts', 'from', '==', uid), ['gifts']);
  await delDocs(await where('library', 'by', '==', uid), ['library']);
  for (let v = 0; v < 6; v++) await fb.deleteDoc(fb.doc(cloud.db, 'codes', codeFor(uid, v))).catch(() => {});   // your friend code (only yours can be deleted)
  progress('Deleting your account…');
  await fb.deleteUser(user);
  await wipeDevice(uid);
}

/* Sheet: sign out (optionally removing your training from this phone) */
function sheetSignOut(el) {
  const s = state.sheet;
  if (s.remove === undefined) s.remove = navigator.onLine !== false;
  el.innerHTML = sheetOpen('Sign out', `${closeBtn('sCancel')}<b>Sign out</b><span></span>`, `
    <div class="group"><label class="set-row"><span class="lbl">Remove my training from this phone</span><input type="checkbox" switch class="switch" id="soRemove" ${s.remove ? 'checked' : ''}></label></div>
    <div class="footnote">${navigator.onLine === false ? "You're offline, so your latest changes may not be backed up yet. Keep them on this phone until you're back online. "
      : ''}Your training stays safe in your account either way. Removing it is a good idea on a phone other people use.</div>
    <button class="primary destructive-fill" id="soGo" ${s.busy ? 'disabled' : ''}>${s.busy ? 'Signing out…' : 'Sign out'}</button>`);
  $('sCancel').onclick = () => closeSheet();
  $('soRemove').onchange = e => { s.remove = e.target.checked; };
  $('soGo').onclick = async () => { s.busy = true; renderSheet(); const rm = s.remove; await signOutNow(rm); if (!rm) closeSheet(); };
}

/* Sheet: delete account */
function sheetDeleteAccount(el) {
  const s = state.sheet, u = cloud.user;
  if (!u) { closeSheet(); return; }
  const google = (u.providerData || []).some(p => p.providerId === 'google.com') && !(u.providerData || []).some(p => p.providerId === 'password');
  el.innerHTML = sheetOpen('Delete account', `${closeBtn('sCancel')}<b>Delete account</b><span></span>`, `
    <div class="finish-sub" style="margin:0 8px 14px;text-align:left">This permanently deletes your account and everything stored about you in the cloud: your training, plans, exercises, friend code, friendships, things you've sent or received, and exercises you shared to the database. It also removes your training from this phone. <b>This can't be undone.</b></div>
    <div class="group"><button class="cell action" id="daExport">${svg('<path d="M12 3v12M7 10l5 5 5-5M5 19h14"/>', 18, 2.2)}Export a copy first</button></div>
    ${google ? '<div class="footnote">To confirm it\'s you, Google will ask you to sign in again.</div>'
      : `<div class="section">Confirm with your password</div><div class="group"><input class="field-input" id="daPass" type="password" autocomplete="current-password" placeholder="Password"></div>`}
    <div class="err" id="daErr">${esc(s.err || '')}</div>
    ${s.busy ? `<div class="footnote" style="text-align:center">${esc(s.busy)}</div>` : ''}
    <button class="primary destructive-fill" id="daGo" ${s.busy ? 'disabled' : ''}>${s.armed ? 'Tap again to delete everything' : 'Delete account'}</button>`);
  $('sCancel').onclick = () => { if (!s.busy) closeSheet(); };
  $('daExport').onclick = () => exportBackup();
  if ($('daPass')) { $('daPass').value = s.pass || ''; $('daPass').oninput = e => { s.pass = e.target.value; }; }
  $('daGo').onclick = async () => {
    if (!google && !(s.pass || '').length) { s.err = 'Enter your password.'; return renderSheet(); }
    if (!s.armed) { haptic('warn'); s.armed = true; s.err = ''; return renderSheet(); }
    s.err = '';
    try { await deleteAccount(s.pass, msg => { s.busy = msg; if (state.sheet === s) renderSheet(); }); }
    catch (e) {
      cloud.deleting = false; s.busy = ''; s.armed = false;
      const c = (e && e.code) || '';
      s.err = /wrong-password|invalid-credential|invalid-login/.test(c) ? "That password isn't right."
        : /popup-closed|cancelled/.test(c) ? 'Cancelled. Nothing was deleted.'
        : /network/.test(c) ? "You're offline. Connect to the internet and try again."
        : `Something went wrong (${c || e.message}). If some of your data was already removed, try again to finish.`;
      if (state.sheet === s) renderSheet();
      if (cloud.user && !cloud.sync) startSync();
    }
  };
}

/* ================= Profiles (yours and friends') =================
   Same layout for both: stats and the last 3 workouts.
   "See all" opens every workout; a workout opens its sets; an exercise in it opens its graph + history. */
const myLabel = () => (data.settings.name || '').trim() || (cloud.user && (cloud.user.displayName || (cloud.user.email || '').split('@')[0])) || 'You';
const profRoot = () => state.prof === 'me' ? 'me' : 'friend';
// Where "back" (or pulling down) goes from a profile screen
function backOf(v) {
  if (v === 'pWorkouts') return profRoot();
  if (v === 'pWorkout') return state.pwBack || profRoot();
  if (v === 'fEx') return state.fExBack || profRoot();
  if (v === 'lib') return state.libBack || 'eList';
  return PULL_BACK[v];
}
// The training shown on the current profile: your own data, or the friend's cached copy
function profSrc() {
  if (state.prof === 'me') return { exercises: data.exercises, sets: data.sets, days: data.days, mine: true };
  const l = friends.links.find(x => x.id === state.friendLink);
  return l && friends.cache[otherOf(l)] ? friends.cache[otherOf(l)] : null;
}
const profName = () => { if (state.prof === 'me') return myLabel(); const l = friends.links.find(x => x.id === state.friendLink); return l ? nameOf(l) : 'Friend'; };
// Days that count as a workout: sets logged, or a finished (or today's running) session
function profDates(c) {
  const tk = todayKey();
  const sess = Object.keys(c.days).filter(k => k <= tk && c.days[k].session && (c.days[k].session.end || k === tk));
  return [...new Set([...[...ix(c.sets).byDate.keys()].filter(k => k <= tk), ...sess])].sort().reverse();
}
const relDay = k => {
  const n = daysBetween(k, todayKey());
  if (n === 0) return 'Today';
  if (n === 1) return 'Yesterday';
  return parse(k).getFullYear() === new Date().getFullYear() ? fmtShort(k) : fmtDayYear(k);
};
const setTxt = s => +s.weight > 0 ? `${W(+s.weight)} ${U()} × ${s.reps | 0}` : `${s.reps | 0} reps`;
const workoutTitle = (c, k) => { const d = c.days[k]; return d && d.workouts && d.workouts.length ? d.workouts.map(w => esc(w.name)).join(' + ') : 'Custom workout'; };
function workoutRowHTML(c, k) {
  const ss = setsOn(k, c.sets), d = c.days[k];
  const nEx = new Set(ss.map(s => s.exId)).size;
  const bits = [relDay(k)];
  if (nEx) bits.push(plural(nEx, 'exercise'), plural(ss.length, 'set')); else bits.push('No sets logged');
  if (d && d.session) bits.push(d.session.end ? fmtMins(d.session.end - d.session.start) : '<span style="color:var(--green)">in progress</span>');
  return cell({ attrs: `data-pw="${k}"`, main: workoutTitle(c, k), sub: bits.join(' · ') });
}
function lastTrainedLabel(k) {
  if (!k) return '–';
  const n = daysBetween(k, todayKey());
  return n === 0 ? 'Today' : n === 1 ? 'Yesterday' : n < 7 ? `${n} days` : parse(k).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}
function profileBodyHTML(c, isFriend) {
  const dates = profDates(c), since30 = dk(addDays(new Date(), -30)), wk = dk(startOfWeek(new Date()));
  return `
    <div class="stat-row three">
      <div class="stat"><div class="stat-n">${dates.filter(d => d >= since30).length}</div><div class="stat-l">in 30 days</div></div>
      <div class="stat"><div class="stat-n">${dates.filter(d => d >= wk).length}</div><div class="stat-l">this week</div></div>
      <div class="stat"><div class="stat-n">${lastTrainedLabel(dates[0])}</div><div class="stat-l">last workout</div></div>
    </div>
    <div class="section sec-link"><span>Recent workouts</span>${dates.length > 3 ? '<button id="seeW">See all</button>' : ''}</div>
    ${dates.length ? `<div class="group">${dates.slice(0, 3).map(k => workoutRowHTML(c, k)).join('')}</div>`
      : `<div class="group"><div class="empty">${isFriend ? 'No workouts in the last 4 months.' : 'No workouts logged yet.'}</div></div>`}
`;
}
// Taps inside a profile body, a workout page or the full lists
function wireProfileBody(from) {
  const here = state.views[state.tab];
  if ($('seeW')) $('seeW').onclick = () => go('pWorkouts');
  app.querySelectorAll('[data-pw]').forEach(b => b.onclick = () => go('pWorkout', { pwDate: b.dataset.pw, pwBack: here }));
  app.querySelectorAll('[data-pe]').forEach(b => b.onclick = () => go('fEx', { friendEx: b.dataset.pe, fExBack: here, stat: 'e1rm' }));
}

function renderMe() {
  state.prof = 'me';
  const c = profSrc();
  app.innerHTML = `
    <header class="nav">${backBtn('Friends')}</header>
    <div class="friend-head"><span class="avatar">${esc(initialOf(myLabel()))}</span><div class="large-title" style="margin:0">${esc(myLabel())}</div></div>
    ${profileBodyHTML(c, false)}
    <div class="footnote" style="margin-top:22px">${cloud.user ? 'This is what friends you share with see. ' : ''}Change your name in Settings.</div>`;
  $('back').onclick = () => go('friends');
  wireProfileBody();
}

function profHeader(title) {
  return `<header class="nav">${backBtn('Back')}</header>
    <div class="eyebrow">${esc(profName())}</div>
    <div class="large-title">${title}</div>`;
}
function renderProfWorkouts() {
  const c = profSrc(); if (!c) return go(profRoot());
  const dates = profDates(c);
  const months = [];
  for (const k of dates) { const m = k.slice(0, 7); if (!months.length || months[months.length - 1].m !== m) months.push({ m, ks: [] }); months[months.length - 1].ks.push(k); }
  app.innerHTML = profHeader('Workouts') + months.map(({ m, ks }) => `
    <div class="section">${parse(m + '-01').toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })}</div>
    <div class="group">${ks.map(k => workoutRowHTML(c, k)).join('')}</div>`).join('')
    + (c.mine ? '' : '<div class="footnote">The last 4 months.</div>');
  $('back').onclick = () => go(backOf('pWorkouts'));
  wireProfileBody();
}
function renderProfWorkout() {
  const c = profSrc(); if (!c) return go(profRoot());
  const k = state.pwDate, d = c.days[k], ss = setsOn(k, c.sets);
  const exIds = [...new Set(ss.slice().sort((a, b) => a.ts - b.ts).map(s => s.exId))];
  const exName = id => { const e = c.exercises.find(x => x.id === id); return e ? e.name : 'Exercise'; };
  const dur = d && d.session ? (d.session.end ? ` · ${fmtMins(d.session.end - d.session.start)}` : ' · in progress') : '';
  app.innerHTML = `
    <header class="nav">${backBtn('Back')}</header>
    <div class="eyebrow">${esc(profName())} · ${fmtLong(k)}${dur}</div>
    <div class="large-title">${workoutTitle(c, k)}</div>
    ${exIds.length ? `<div class="group">${exIds.map(id => cell({ attrs: `data-pe="${id}"`, main: esc(exName(id)),
        sub: setsOf(id, k, c.sets).map(setTxt).join(' · ') })).join('')}</div>
      <div class="footnote">${plural(ss.length, 'set')} logged. Tap an exercise to see its progress.</div>`
      : '<div class="group"><div class="empty">No sets logged.</div></div>'}`;
  $('back').onclick = () => go(backOf('pWorkout'));
  wireProfileBody();
}
/* ================= Exercise database =================
   Built-in starter list (in the app, works offline) + exercises people chose to share (Firestore library/{id}).
   Picking one copies it into your own exercises; your own variations can stay private. */
const MUSCLES = [['chest', 'Chest'], ['back', 'Back'], ['shoulders', 'Shoulders'], ['arms', 'Arms'], ['legs', 'Legs'], ['glutes', 'Glutes'], ['core', 'Core'], ['full', 'Full body']];
const EQUIP = [['barbell', 'Barbell'], ['dumbbell', 'Dumbbell'], ['machine', 'Machine'], ['cable', 'Cable'], ['bodyweight', 'Bodyweight'], ['kettlebell', 'Kettlebell'], ['other', 'Other']];
const muscleName = k => (MUSCLES.find(m => m[0] === k) || [, ''])[1];
const equipName = k => (EQUIP.find(m => m[0] === k) || [, ''])[1];
const normMemo = new Map();
const normName = n => { const k = String(n || ''); let v = normMemo.get(k); if (v === undefined) { v = k.toLowerCase().replace(/[^a-z0-9]/g, ''); if (normMemo.size > 5000) normMemo.clear(); normMemo.set(k, v); } return v; };
const LIB_RAW = 'Bench press|chest|barbell\nIncline bench press|chest|barbell\nDecline bench press|chest|barbell\nClose-grip bench press|arms|barbell\nDumbbell bench press|chest|dumbbell\nIncline dumbbell press|chest|dumbbell\nDumbbell fly|chest|dumbbell\nIncline dumbbell fly|chest|dumbbell\nMachine chest press|chest|machine\nIncline machine press|chest|machine\nPec deck|chest|machine\nCable fly|chest|cable\nLow-to-high cable fly|chest|cable\nSmith machine bench press|chest|machine\nPush-up|chest|bodyweight\nDip|chest|bodyweight\nDeadlift|back|barbell\nSumo deadlift|back|barbell\nBarbell row|back|barbell\nPendlay row|back|barbell\nT-bar row|back|barbell\nRack pull|back|barbell\nDumbbell row|back|dumbbell\nChest-supported dumbbell row|back|dumbbell\nDumbbell pullover|back|dumbbell\nPull-up|back|bodyweight\nChin-up|back|bodyweight\nInverted row|back|bodyweight\nLat pulldown|back|cable\nClose-grip lat pulldown|back|cable\nStraight-arm pulldown|back|cable\nSeated cable row|back|cable\nSingle-arm cable row|back|cable\nMachine row|back|machine\nAssisted pull-up|back|machine\nBack extension|back|bodyweight\nShrug|back|barbell\nDumbbell shrug|back|dumbbell\nOverhead press|shoulders|barbell\nPush press|shoulders|barbell\nSeated dumbbell shoulder press|shoulders|dumbbell\nArnold press|shoulders|dumbbell\nLateral raise|shoulders|dumbbell\nFront raise|shoulders|dumbbell\nRear delt fly|shoulders|dumbbell\nUpright row|shoulders|barbell\nMachine shoulder press|shoulders|machine\nMachine lateral raise|shoulders|machine\nReverse pec deck|shoulders|machine\nCable lateral raise|shoulders|cable\nFace pull|shoulders|cable\nCable rear delt fly|shoulders|cable\nBarbell curl|arms|barbell\nEZ-bar curl|arms|barbell\nPreacher curl|arms|barbell\nDumbbell curl|arms|dumbbell\nHammer curl|arms|dumbbell\nIncline dumbbell curl|arms|dumbbell\nConcentration curl|arms|dumbbell\nCable curl|arms|cable\nMachine preacher curl|arms|machine\nSkull crusher|arms|barbell\nOverhead dumbbell triceps extension|arms|dumbbell\nDumbbell kickback|arms|dumbbell\nTriceps pushdown|arms|cable\nRope pushdown|arms|cable\nOverhead cable triceps extension|arms|cable\nMachine triceps extension|arms|machine\nBench dip|arms|bodyweight\nWrist curl|arms|dumbbell\nReverse curl|arms|barbell\nBack squat|legs|barbell\nFront squat|legs|barbell\nBox squat|legs|barbell\nRomanian deadlift|legs|barbell\nGood morning|legs|barbell\nBarbell lunge|legs|barbell\nGoblet squat|legs|dumbbell\nBulgarian split squat|legs|dumbbell\nDumbbell lunge|legs|dumbbell\nWalking lunge|legs|dumbbell\nDumbbell Romanian deadlift|legs|dumbbell\nStep-up|legs|dumbbell\nLeg press|legs|machine\nHack squat|legs|machine\nSmith machine squat|legs|machine\nLeg extension|legs|machine\nLying leg curl|legs|machine\nSeated leg curl|legs|machine\nStanding calf raise|legs|machine\nSeated calf raise|legs|machine\nLeg press calf raise|legs|machine\nPendulum squat|legs|machine\nBelt squat|legs|machine\nNordic curl|legs|bodyweight\nBodyweight squat|legs|bodyweight\nHip thrust|glutes|barbell\nGlute bridge|glutes|barbell\nDumbbell hip thrust|glutes|dumbbell\nSingle-leg hip thrust|glutes|bodyweight\nMachine hip thrust|glutes|machine\nHip abduction|glutes|machine\nHip adduction|legs|machine\nGlute kickback machine|glutes|machine\nCable kickback|glutes|cable\nCable pull-through|glutes|cable\nFrog pump|glutes|bodyweight\nKettlebell swing|glutes|kettlebell\nPlank|core|bodyweight\nCrunch|core|bodyweight\nHanging leg raise|core|bodyweight\nHanging knee raise|core|bodyweight\nLying leg raise|core|bodyweight\nAb wheel rollout|core|other\nRussian twist|core|bodyweight\nDead bug|core|bodyweight\nCable crunch|core|cable\nPallof press|core|cable\nCable woodchopper|core|cable\nMachine crunch|core|machine\nDecline sit-up|core|bodyweight\nSide plank|core|bodyweight\nKettlebell goblet squat|legs|kettlebell\nKettlebell deadlift|legs|kettlebell\nTurkish get-up|full|kettlebell\nFarmer\'s carry|full|dumbbell\nPower clean|full|barbell\nClean and jerk|full|barbell\nSnatch|full|barbell\nThruster|full|barbell';
const LIB_BUILTIN = LIB_RAW.split('\n').map(l => { const [name, muscle, equip] = l.split('|'); return { id: 'b:' + normName(name), name, muscle, equip, builtin: true }; });
const lib = { shared: (() => { try { return (JSON.parse(localStorage.getItem('tt.lib')) || []).map(x => cleanLibEntry(x.docId, x)).filter(Boolean); } catch (e) { return []; } })(), unsub: null, admin: false, error: '' };
const LIB_NAMES = new Set(LIB_BUILTIN.map(b => normName(b.name)));
let libAllMemo = null;   // the combined list is rebuilt only when the shared entries change
const libAll = () => {
  if (libAllMemo && libAllMemo.src === lib.shared && libAllMemo.n === lib.shared.length) return libAllMemo.list;
  const list = [...LIB_BUILTIN, ...lib.shared.filter(x => !LIB_NAMES.has(normName(x.name)))].sort(byName);
  libAllMemo = { src: lib.shared, n: lib.shared.length, list };
  return list;
};
const libById = id => libAll().find(x => x.id === id);
const libByName = n => libAll().find(x => normName(x.name) === normName(n));
const mineFor = entry => data.exercises.find(e => e.lib === entry.id || normName(e.name) === normName(entry.name));
const canDeleteLib = entry => !entry.builtin && cloud.user && (entry.by === cloud.user.uid || lib.admin);
const libSub = x => [muscleName(x.muscle), equipName(x.equip)].filter(Boolean).join(' · ') + (x.builtin ? '' : ` · added by ${x.by && cloud.user && x.by === cloud.user.uid ? 'you' : esc(x.byName || 'someone')}`);

function startLibrary() {
  const fb = cloud.fb, me = cloud.user.uid;
  lib.unsub = fb.onSnapshot(fb.collection(cloud.db, 'library'), snap => {
    lib.shared = snap.docs.map(d => cleanLibEntry(d.id, d.data())).filter(Boolean);
    try { localStorage.setItem('tt.lib', JSON.stringify(lib.shared)); } catch (e) {}
    lib.error = '';
    const v = state.views[state.tab];
    if (!state.sheet && (v === 'lib' || v === 'eList' || v === 'picker') && !(document.activeElement && document.activeElement.tagName === 'INPUT')) bgRender();
  }, e => { lib.error = isPerm(e) ? 'rules' : (e.code || e.message); });
  fb.getDoc(fb.doc(cloud.db, 'admins', me)).then(d => { lib.admin = d.exists(); }).catch(() => {});
}
function stopLibrary() { if (lib.unsub) lib.unsub(); lib.unsub = null; lib.admin = false; }

// Copy a database exercise into your own list (or find the one you already have)
function addFromLib(entry) {
  const have = mineFor(entry);
  if (have) { if (!have.lib) { have.lib = entry.id; have.muscle = have.muscle || entry.muscle; have.equip = have.equip || entry.equip; save(); } return have.id; }
  const id = uid();
  data.exercises.push({ id, name: entry.name, track: entry.track || ['weight', 'reps'], instructions: '', video: '', lib: entry.id, muscle: entry.muscle || '', equip: entry.equip || '' });
  save();
  return id;
}
// Existing exercises with a common name get linked to the database once (adds muscle group + equipment)
function linkExistingToLib() {
  let changed = false;
  for (const e of data.exercises) {
    if (e.lib) continue;
    const b = LIB_BUILTIN.find(x => normName(x.name) === normName(e.name));
    if (b) { e.lib = b.id; e.muscle = e.muscle || b.muscle; e.equip = e.equip || b.equip; changed = true; }
  }
  if (changed) save();
}
function shareToLib(ex) {
  const fb = cloud.fb, docId = uid();
  ex.lib = 's:' + docId;
  const rec = { name: ex.name, muscle: ex.muscle || '', equip: ex.equip || '', track: ex.track, by: cloud.user.uid, byName: myName(), u: Date.now() };
  lib.shared.push({ id: ex.lib, docId, ...rec });
  fb.setDoc(fb.doc(cloud.db, 'library', docId), rec).catch(e => {
    lib.shared = lib.shared.filter(x => x.docId !== docId);
    if (ex.lib === 's:' + docId) { delete ex.lib; save(); }
    lib.error = isPerm(e) ? 'rules' : (e.code || e.message); render();
  });
}
function removeFromLib(entry) {
  lib.shared = lib.shared.filter(x => x.id !== entry.id);
  cloud.fb.deleteDoc(cloud.fb.doc(cloud.db, 'library', entry.docId)).catch(e => { lib.error = isPerm(e) ? 'rules' : (e.code || e.message); render(); });
}
const LIB_RULES_HELP = `<div class="err">The shared database needs updated Firebase rules. Open Firestore → Rules, paste the new rules from Claude and click Publish.</div>`;

// Rows for database results. mode 'day' = adding to the selected day's workout.
function libRowHTML(x, mode) {
  const mine = mineFor(x);
  const added = mode === 'day' ? (mine && dayOf(state.selected).items.some(i => i.exId === mine.id)) : !!mine;
  const armed = state.pending === 'libdel:' + x.id;
  const lead = state.libEdit && canDeleteLib(x) ? `<span class="del-dot" data-libdel="${x.id}" role="button" aria-label="Remove ${esc(x.name)} from the database">−</span>` : '';
  return `<button class="cell ${armed ? 'armed' : ''}" data-lib="${x.id}">${lead}<span class="main"><div>${armed ? 'Tap − again to remove' : esc(x.name)}</div><div class="sub">${libSub(x)}</div></span>
    ${state.libEdit ? '' : added ? `<span class="detail">${mode === 'day' ? 'Added' : 'In your list'}</span>` : `<span class="add-dot" aria-hidden="true">${svg('<path d="M12 5v14M5 12h14"/>', 16, 2.6)}</span>`}</button>`;
}
function wireLibRows(root, mode, after) {
  root.querySelectorAll('[data-libdel]').forEach(b => b.onclick = ev => {
    ev.stopPropagation();
    const x = libById(b.dataset.libdel); if (!x) return;
    if (state.pending !== 'libdel:' + x.id) { haptic('warn'); state.pending = 'libdel:' + x.id; return after(); }
    state.pending = null; removeFromLib(x); after();
  });
  root.querySelectorAll('[data-lib]').forEach(b => b.onclick = () => {
    const x = libById(b.dataset.lib); if (!x || state.libEdit) return;
    const id = addFromLib(x);
    if (mode === 'day') return addExerciseToDay(id, null);
    after();
  });
}

function renderLibrary() {
  const mode = state.libBack === 'picker' ? 'day' : 'list';
  const f = state.libFilter = state.libFilter || { q: '', muscle: '', equip: '' };
  const deletable = libAll().some(canDeleteLib);
  if (!deletable) state.libEdit = false;
  app.innerHTML = `
    <header class="nav">${backBtn('Back')}<span class="spacer"></span>${deletable ? `<button class="capsule glass" id="libEdit">${state.libEdit ? 'Done' : 'Edit'}</button>` : ''}</header>
    ${mode === 'day' ? `<div class="eyebrow">Adding to ${fmtLong(state.selected)}</div>` : ''}
    <div class="large-title">Exercise database</div>
    ${lib.error === 'rules' ? LIB_RULES_HELP : ''}
    ${searchHTML('lq', 'Search exercises')}
    <div class="chips" id="mChips">${MUSCLES.map(([k, n]) => `<button class="chip ${f.muscle === k ? 'on' : ''}" data-m="${k}">${n}</button>`).join('')}</div>
    <div class="chips" id="eChips">${EQUIP.map(([k, n]) => `<button class="chip ${f.equip === k ? 'on' : ''}" data-e="${k}">${n}</button>`).join('')}</div>
    <div class="group"><button class="cell action" id="libNew">${plusLead}Create your own exercise</button></div>
    <div id="libRes"></div>`;
  const q = $('lq'); q.value = f.q;
  const draw = () => {
    f.q = q.value;
    const term = normName(f.q);
    const list = libAll().filter(x => (!term || normName(x.name).includes(term)) && (!f.muscle || x.muscle === f.muscle) && (!f.equip || x.equip === f.equip));
    $('libRes').innerHTML = list.length
      ? `<div class="group">${list.map(x => libRowHTML(x, mode)).join('')}</div><div class="footnote">${plural(list.length, 'exercise')}${lib.shared.length ? ` · ${lib.shared.length} shared by people using the app` : ''}. Tap one to add it to your exercises.</div>`
      : `<div class="group"><div class="empty">Nothing matches${f.q.trim() ? ` “${esc(f.q.trim())}”` : ''}. Create your own above.</div></div>`;
    wireLibRows($('libRes'), mode, draw);
  };
  q.oninput = draw;
  draw();
  app.querySelectorAll('[data-m]').forEach(b => b.onclick = () => { f.muscle = f.muscle === b.dataset.m ? '' : b.dataset.m; state.soft = '#libRes'; render(); });
  app.querySelectorAll('[data-e]').forEach(b => b.onclick = () => { f.equip = f.equip === b.dataset.e ? '' : b.dataset.e; state.soft = '#libRes'; render(); });
  $('back').onclick = () => { state.libEdit = false; go(backOf('lib')); };
  if ($('libEdit')) $('libEdit').onclick = () => { state.libEdit = !state.libEdit; state.pending = null; render(); };
  $('libNew').onclick = () => openSheet({ type: 'exForm', exId: null, name: f.q.trim(), muscle: f.muscle, equip: f.equip,
    onSave: id => mode === 'day' ? addExerciseToDay(id, null) : go('eDetail', { detailExId: id, stat: 'e1rm' }) });
}

// A friend's exercise: same graph and history as your own, read-only
function renderFriendExercise() {
  if (state.prof === 'me') {
    const ex = data.exercises.find(e => e.id === state.friendEx);
    if (!ex) return go('me');
    state.statSrc = null;
    app.innerHTML = `
      <header class="nav">${backBtn('Back')}</header>
      <div class="eyebrow">${esc(myLabel())}</div>
      <div class="large-title">${esc(ex.name)}</div>
      ${progressHTML(ex.id) + historyHTML(ex.id)}`;
    $('back').onclick = () => go(backOf('fEx'));
    wireProgress(ex.id);
    return;
  }
  const l = friends.links.find(x => x.id === state.friendLink);
  if (!l) return go('friends');
  const o = otherOf(l), c = friends.cache[o];
  const ex = c && c.exercises.find(e => e.id === state.friendEx);
  if (!ex) return go('friend');
  const key = o + '|' + ex.id, cached = friends.exCache[key];
  app.innerHTML = `
    <header class="nav">${backBtn('Back')}</header>
    <div class="eyebrow">${esc(nameOf(l))}</div>
    <div class="large-title">${esc(ex.name)}</div>
    ${cached ? (state.statSrc = cached.sets, progressHTML(ex.id) + historyHTML(ex.id)) : SKELETON}`;
  $('back').onclick = () => go(backOf('fEx'));
  if (cached) { wireProgress(ex.id); state.statSrc = null; }
  else loadFriendExercise(o, ex.id).then(() => { if (state.views.friends === 'fEx') bgRender(); }).catch(() => {});
}

/* Sheet: add a friend by code */
function sheetAddFriend(el) {
  const s = state.sheet;
  if (s.share === undefined) s.share = true;
  el.innerHTML = sheetOpen('Add friend', `${closeBtn('sCancel')}<b>Add friend</b><span></span>`, `
    <div class="finish-sub" style="margin:0 8px 12px">Ask your friend for their code. It's at the top of their Friends tab.</div>
    <div class="group"><input class="field-input code-input" id="fCode" placeholder="ABC-123" autocomplete="off" autocapitalize="characters" spellcheck="false" value="${esc(fmtCode(cleanCode(s.code)))}"></div>
    ${s.found ? `
      <div class="group" style="margin-top:14px"><div class="profile"><span class="avatar">${esc(initialOf(s.found.name))}</span><div><div style="font-weight:600;font-size:18px">${esc(s.found.name)}</div><div class="sub" style="color:var(--label2);font-size:14px">${esc(fmtCode(cleanCode(s.code)))}</div></div></div>
        <label class="set-row"><span class="lbl">Share my training with them</span><input type="checkbox" switch class="switch" id="fShare" ${s.share ? 'checked' : ''}></label></div>
      <div class="footnote">You can change this any time on their page.</div>` : ''}
    <div class="err" id="fErr">${esc(s.err || '')}</div>
    <button class="primary" id="fGo">${s.found ? 'Send friend request' : 'Find'}</button>`);
  const inp = $('fCode');
  inp.oninput = () => { const c = cleanCode(inp.value); inp.value = c.length > 3 ? fmtCode(c) : c; if (c !== cleanCode(s.code)) { s.code = c; if (s.found) { s.found = null; s.err = ''; renderSheet(); $('fCode').focus(); } } };
  if ($('fShare')) $('fShare').onchange = e => { s.share = e.target.checked; };
  $('sCancel').onclick = () => closeSheet();
  const find = async () => {
    const code = cleanCode(s.code);
    if (code.length !== 6) { s.err = 'Codes have 6 characters.'; return renderSheet(); }
    if (code === data.settings.code) { s.err = "That's your own code."; return renderSheet(); }
    $('fGo').disabled = true;
    try {
      const f = await lookupCode(code);
      if (!f) { s.err = 'No one has that code. Check it and try again.'; s.found = null; }
      else if (f.uid === cloud.user.uid) { s.err = "That's your own code."; }
      else { s.found = f; s.err = ''; }
    } catch (e) { s.err = isPerm(e) ? 'Friends needs the new Firebase rules first.' : "Couldn't look that up. Check your connection."; }
    renderSheet();
  };
  $('fGo').onclick = async () => {
    if (!s.found) return find();
    $('fGo').disabled = true;
    try { await sendFriendRequest(s.found.uid, s.found.name, s.share); haptic('success'); closeSheet(); render(); }
    catch (e) { s.err = isPerm(e) ? 'Friends needs the new Firebase rules first.' : (e.message || e.code); renderSheet(); }
  };
  if (s.auto) { s.auto = false; find(); }
}

/* Sheet: accept a request (choose whether to share back) */
function sheetAcceptFriend(el) {
  const s = state.sheet, l = friends.links.find(x => x.id === s.id);
  if (!l) { closeSheet(); return; }
  if (s.share === undefined) s.share = true;
  const name = nameOf(l);
  el.innerHTML = sheetOpen('Accept', `${closeBtn('sCancel')}<b>Friend request</b><span></span>`, `
    <div class="group"><div class="profile"><span class="avatar">${esc(initialOf(name))}</span><div style="font-weight:600;font-size:18px">${esc(name)}</div></div>
      <label class="set-row"><span class="lbl">Share my training with ${esc(name)}</span><input type="checkbox" switch class="switch" id="aShare" ${s.share ? 'checked' : ''}></label></div>
    <div class="footnote">${l.share && l.share[l.from] ? `${esc(name)} is sharing their training with you.` : `${esc(name)} isn't sharing their training yet.`}</div>
    <div class="err" id="aErr">${esc(s.err || '')}</div>
    <button class="primary" id="aOk">Accept</button>`);
  $('aShare').onchange = e => { s.share = e.target.checked; };
  $('sCancel').onclick = () => closeSheet();
  $('aOk').onclick = async () => { $('aOk').disabled = true; try { await acceptFriend(l, s.share); haptic('success'); closeSheet(); render(); } catch (e) { s.err = isPerm(e) ? 'Friends needs the new Firebase rules first.' : (e.code || e.message); renderSheet(); } };
}

/* ================= Swipe down to close ================= */
// Pull a slid-up screen (or a sheet) down from the top to close it. It follows your finger,
// the screen underneath grows back into place, and letting go early springs it back.
let pullSync = () => {};
const PULL_BACK = { summary: 'day', log: 'day', picker: 'day', calendar: 'day', history: 'log', eDetail: 'eList', pView: 'wList', friend: 'friends', me: 'friends',
                    pWorkouts: 1, pWorkout: 1, fEx: 1, lib: 1 };   // 1 = depends on where you came from (backOf)
(function pullToClose() {
  let p = null;
  const ease = '.6s var(--ease-sheet)';
  document.addEventListener('touchstart', e => {
    if (p && p.axis === 'down') return;   // a second finger mid-pull doesn't restart it
    unhook(p); p = null;
    if (e.touches.length > 1) return;
    const t = e.target, touch = e.touches[0];
    if (t.closest('input, textarea, .wheel, .grip, .chart, #dock, .pdots, .ghost')) return;
    const base = { x: touch.clientX, y: touch.clientY, axis: null, dy: 0, ly: touch.clientY, lt: performance.now(), v: 0 };
    const sheetEl = t.closest('.sheet');
    if (sheetEl) { if (sheetEl.scrollTop <= 0) p = { ...base, kind: 'sheet', el: sheetEl }; return; }
    if (state.sheet || !backOf(state.views[state.tab]) || window.scrollY > 0) return;
    p = { ...base, kind: 'screen' };
    // The screen under your finger is swapped out as the pull starts. Touch events keep going to the element the finger
    // first touched, and once it's gone from the page they no longer reach the document, so the rest of the pull (and
    // letting go) would be lost. Listening on that element too keeps the gesture whole.
    p.tgt = t;
    t.addEventListener('touchmove', move, { passive: false });
    t.addEventListener('touchend', end); t.addEventListener('touchcancel', end);
  }, { passive: true });
  const unhook = q => { if (q && q.tgt) { q.tgt.removeEventListener('touchmove', move, { passive: false }); q.tgt.removeEventListener('touchend', end); q.tgt.removeEventListener('touchcancel', end); q.tgt = null; } };

  // This handler can cancel scrolling, so while it's attached iOS waits for it on every finger move. It's only attached
  // where pulling down can close something (deeper screens, open sheets); on the main tabs scrolling never waits for it.
  function move(e) {
    if (!p || e._pull) return;
    e._pull = true;   // the same event can reach both the touched element and the document: handle it once
    const t = e.touches[0];
    const dx = t.clientX - p.x, dy = t.clientY - p.y;
    if (!p.axis) {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      p.axis = dy > 0 && Math.abs(dy) > Math.abs(dx) ? 'down' : 'other';
      if (p.axis !== 'down') { p = null; return; }
      start();
    }
    e.preventDefault();
    const now = performance.now();
    p.v = (t.clientY - p.ly) / Math.max(1, now - p.lt); p.ly = t.clientY; p.lt = now;
    p.dy = Math.max(0, dy);
    // A tick as you pull past the point where letting go closes it (and again if you pull back above it)
    const past = p.dy > 110;
    if (past !== !!p.past) { p.past = past; haptic(past ? 'impact' : 'select'); }
    p.layer.style.transform = `translateY(${p.dy}px)`;
    const k = Math.min(1, p.dy / window.innerHeight);
    if (p.kind === 'screen') { app.style.transform = `scale(${.94 + .06 * k})`; app.style.opacity = .5 + .5 * k; }
    else if (p.backdrop) p.backdrop.style.opacity = 1 - k * 1.5;
  }
  let attached = false;
  pullSync = () => {
    const need = !!state.sheet || !!backOf(state.views[state.tab]);
    if (need === attached || (!need && p)) return;   // never taken away in the middle of a pull
    if (need) document.addEventListener('touchmove', move, { passive: false }); else document.removeEventListener('touchmove', move, { passive: false });
    attached = need;
  };

  function start() {
    if (p.kind === 'sheet') {
      p.layer = p.el; p.backdrop = document.querySelector('#sheet .backdrop');
      p.layer.style.animation = 'none'; p.layer.style.transition = 'none';
      return;
    }
    // Put the screen underneath in place now, and keep a snapshot of this one on top to drag
    p.saved = { views: { ...state.views }, logExId: state.logExId, detailExId: state.detailExId };
    p.layer = ghost(true);
    p.layer.style.transition = 'none';
    state.views[state.tab] = backOf(state.views[state.tab]);
    state.pending = null;
    render();
    app.classList.remove('enter-up', 'under');
    app.style.transition = 'none'; app.style.transformOrigin = '50% 0';
    app.style.transform = 'scale(.94)'; app.style.opacity = '.5';
  }

  function end(e) {
    if (e && e._pull) return;
    if (e) e._pull = true;
    unhook(p);
    if (!p || p.axis !== 'down') { p = null; pullSync(); return; }
    const q = p; p = null;
    setTimeout(pullSync, PULL_MS + 40);
    const flung = q.v > 0.5 && performance.now() - q.lt < 100;   // a finger that stopped before lifting isn't a flick
    const close = q.dy > 110 || (flung && q.dy > 40);
    q.layer.style.transition = `transform ${ease}`;
    if (q.kind === 'sheet') {
      if (q.backdrop) q.backdrop.style.transition = `opacity ${ease}`;
      if (close) { q.layer.style.transform = 'translateY(110%)'; if (q.backdrop) q.backdrop.style.opacity = 0; setTimeout(closeSheet, 440); }
      else { q.layer.style.transform = ''; if (q.backdrop) q.backdrop.style.opacity = ''; }
      return;
    }
    app.style.transition = `transform ${ease}, opacity ${ease}`;
    if (close) {
      q.layer.style.transform = 'translateY(100vh)';
      app.style.transform = ''; app.style.opacity = '';
      setTimeout(() => { q.layer.remove(); app.style.transition = app.style.transformOrigin = ''; }, PULL_MS);
    } else {
      q.layer.style.transform = 'translateY(0)';
      app.style.transform = 'scale(.94)'; app.style.opacity = '.5';
      setTimeout(() => {
        Object.assign(state, { logExId: q.saved.logExId, detailExId: q.saved.detailExId });
        state.views = q.saved.views;
        app.style.transition = app.style.transform = app.style.opacity = app.style.transformOrigin = '';
        render();
        q.layer.remove();
      }, PULL_MS);
    }
  };
  document.addEventListener('touchend', end);
  document.addEventListener('touchcancel', end);
})();

/* ================= Bottom sheets ================= */
function openSheet(s) { state.sheet = s; state.pending = null; renderSheet(); }
function closeSheet() { state.sheet = null; state.pending = null; renderSheet(); }
function renderSheet() {
  const el = $('sheet');
  if (!state.sheet) {
    // The sheet slides away instead of vanishing (unless it was already pulled down by hand)
    const sh = el.querySelector('.sheet');
    if (!el.hidden && sh && !sh.style.transform && !reduceMotion()) {
      const g = document.createElement('div'); g.className = 'sheet-ghost'; g.setAttribute('aria-hidden', 'true'); g.inert = true;
      const top = sh.scrollTop, wheels = [...el.querySelectorAll('.wheel-scroll')].map(w => w.scrollTop);
      while (el.firstChild) g.appendChild(el.firstChild);              // the real nodes, so nothing visibly resets
      g.querySelectorAll('[id]').forEach(x => x.removeAttribute('id'));
      document.body.appendChild(g);
      const gs = g.querySelector('.sheet'); if (gs) gs.scrollTop = top;
      g.querySelectorAll('.wheel-scroll').forEach((w, i) => { w.scrollTop = wheels[i]; });
      setTimeout(() => g.remove(), SHEET_OUT_MS);
    }
    el.hidden = true; el.innerHTML = ''; document.body.classList.remove('locked'); pullSync(); return;
  }
  el.hidden = false; document.body.classList.add('locked');
  pullSync();
  ({ exForm: sheetExForm, addToWorkout: sheetAddToWorkout, setCount: sheetSetCount, duration: sheetDuration, signin: sheetSignin,
     note: sheetNote, planDay: sheetPlanDay, planStart: sheetPlanStart, moveBack: sheetMoveBack, sendTo: sheetSendTo, sendPick: sheetSendPick, gift: sheetGift, signout: sheetSignOut, deleteAccount: sheetDeleteAccount,
     addFriend: sheetAddFriend, acceptFriend: sheetAcceptFriend })[state.sheet.type](el);
  animateSegs(el);
}
const sheetOpen = (label, head, body) => `<div class="backdrop"></div><div class="sheet" role="dialog" aria-label="${esc(label)}"><div class="sheet-head">${head}</div>${body}</div>`;

function sheetExForm(el) {
  const s = state.sheet;
  const ex = s.exId ? exById(s.exId) : null;
  if (s.instructions === undefined) {
    s.name = s.name || (ex ? ex.name : '');
    s.instructions = ex ? ex.instructions : '';
    s.note = ex ? ex.note || '' : '';
    s.video = ex ? ex.video : '';
    s.muscle = ex ? ex.muscle || '' : s.muscle || '';
    s.equip = ex ? ex.equip || '' : s.equip || '';
    const own = ex && ex.lib && lib.shared.find(x => x.id === ex.lib);
    s.sharedOwn = !!(own && cloud.user && own.by === cloud.user.uid);
    s.share = s.sharedOwn;
  }
  const linked = ex && ex.lib ? libById(ex.lib) : null;                 // copied from the database
  const fromDb = linked && !s.sharedOwn;
  const dupe = !fromDb && s.name.trim() && libByName(s.name) && !(ex && ex.lib === libByName(s.name).id) ? libByName(s.name) : null;
  const setCount = ex ? exSets(ex.id).length : 0;
  const title = ex ? 'Edit Exercise' : 'New Exercise';
  el.innerHTML = sheetOpen(title,
    `${closeBtn('sCancel')}<b>${title}</b>${okBtn('sSave')}`,
    `<div class="group"><input class="field-input" id="fName" placeholder="Name" autocomplete="off"></div>
     <div class="section">Muscle group</div>
     <div class="chips wrap">${MUSCLES.map(([k, n]) => `<button class="chip ${s.muscle === k ? 'on' : ''}" data-fm="${k}">${n}</button>`).join('')}</div>
     <div class="section">Equipment</div>
     <div class="chips wrap">${EQUIP.map(([k, n]) => `<button class="chip ${s.equip === k ? 'on' : ''}" data-fe="${k}">${n}</button>`).join('')}</div>
     <div class="section">Instructions <span class="opt">· optional</span></div>
     <div class="group"><textarea class="field-input" id="fInstr" rows="4" placeholder="Setup, cues, things to remember…"></textarea></div>
     <div class="section">Note <span class="opt">· shows when you log it</span></div>
     <div class="group"><textarea class="field-input" id="fNote" rows="2" maxlength="${NOTE_MAX}" placeholder="E.g. seat on 4"></textarea></div>
     <div class="section">Video <span class="opt">· optional</span></div>
     <div class="group"><input class="field-input" id="fVideo" inputmode="url" autocomplete="off" placeholder="YouTube link"></div>
     <div class="section">Exercise database</div>
     ${fromDb ? `<div class="group"><div class="empty">From the exercise database. Your notes, video and changes stay private to you.</div></div>`
      : cloud.user ? `<div class="group"><label class="set-row"><span class="lbl">${s.sharedOwn ? 'Shared in the database' : 'Add to the database'}</span>
          <input type="checkbox" switch class="switch" id="fShare" ${s.share ? 'checked' : ''} ${dupe && !s.sharedOwn ? 'disabled' : ''}></label></div>
        <div class="footnote" id="fShareNote">${dupe && !s.sharedOwn ? `“${esc(dupe.name)}” is already in the database. Pick it from there instead, or keep this one private.`
          : 'Everyone using the app can find and add it (only the name, muscle group and equipment are shared). Leave it off for your own variations, like “Bench press, 2 s pause”.'}</div>`
      : `<div class="group"><div class="empty">Sign in to share exercises with the database. This one stays private.</div></div>`}
     <div class="err" id="fErr"></div>
     ${ex ? `<div class="group" style="margin-top:28px"><button class="cell destructive ${state.pending === 'delEx' ? 'confirm' : ''}" id="sDel">${state.pending === 'delEx'
        ? `Tap again to delete${setCount ? ` (and ${plural(setCount, 'logged set')})` : ''}` : 'Delete Exercise'}</button></div>` : ''}`);
  const fName = $('fName'), fInstr = $('fInstr'), fVideo = $('fVideo'), fNote = $('fNote');
  fName.value = s.name; fInstr.value = s.instructions; fVideo.value = s.video; fNote.value = s.note;
  fNote.oninput = () => s.note = fNote.value;
  fName.oninput = () => {
    const before = !!(s.name.trim() && libByName(s.name)), now = !!(fName.value.trim() && libByName(fName.value));
    s.name = fName.value;
    if (before !== now && !fromDb) { if (now) s.share = s.sharedOwn; renderSheet(); const f = $('fName'); f.focus(); f.setSelectionRange(f.value.length, f.value.length); }
  };
  el.querySelectorAll('[data-fm]').forEach(b => b.onclick = () => { s.muscle = s.muscle === b.dataset.fm ? '' : b.dataset.fm; renderSheet(); });
  el.querySelectorAll('[data-fe]').forEach(b => b.onclick = () => { s.equip = s.equip === b.dataset.fe ? '' : b.dataset.fe; renderSheet(); });
  if ($('fShare')) $('fShare').onchange = e => { s.share = e.target.checked; };
  fInstr.oninput = () => s.instructions = fInstr.value;
  fVideo.oninput = () => s.video = fVideo.value;
  if (!ex && !s.name) setTimeout(() => fName.focus(), 50);

  $('sCancel').onclick = () => closeSheet();
  $('sSave').onclick = () => {
    const name = s.name.trim();
    const err = $('fErr');
    if (!name) { err.textContent = 'Give the exercise a name.'; return; }
    if (data.exercises.some(e => e.name.toLowerCase() === name.toLowerCase() && e.id !== s.exId)) { err.textContent = 'An exercise with that name already exists.'; return; }
    const video = s.video.trim();
    if (video && !ytId(video)) { err.textContent = "That doesn't look like a YouTube link."; return; }
    const track = ex ? cleanTrack(ex.track) : ['weight', 'reps'];   // weight × reps is the only kind for now
    const sharing = cloud.user && !fromDb && s.share && !(dupe && !s.sharedOwn);
    if (sharing && !s.muscle) { err.textContent = 'Pick a muscle group so others can find it in the database.'; return; }
    let id = s.exId;
    const fields = { name, track, instructions: s.instructions.trim(), video, muscle: s.muscle, equip: s.equip };
    if (ex) Object.assign(ex, fields);
    else { id = uid(); data.exercises.push({ id, ...fields }); }
    const rec = exById(id), note = s.note.trim().slice(0, NOTE_MAX);
    if (note) rec.note = note; else delete rec.note;
    if (s.sharedOwn && !sharing) { const own = lib.shared.find(x => x.id === rec.lib); if (own) removeFromLib(own); delete rec.lib; }
    else if (s.sharedOwn && sharing) {
      const own = lib.shared.find(x => x.id === rec.lib);
      if (own) { Object.assign(own, { name, muscle: s.muscle, equip: s.equip, track }); cloud.fb.updateDoc(cloud.fb.doc(cloud.db, 'library', own.docId), { name, muscle: s.muscle, equip: s.equip, track, byName: myName(), u: Date.now() }).catch(() => {}); }
    } else if (sharing) shareToLib(rec);
    else if (!fromDb && rec.lib && dupe === null && !libById(rec.lib)) delete rec.lib;
    if (fromDb && normName(name) !== normName(linked.name)) delete rec.lib;   // renamed into your own variation
    save();
    const after = s.onSave;
    state.sheet = null;
    if (after) after(id); else render();
  };
  if ($('sDel')) $('sDel').onclick = () => {
    if (state.pending !== 'delEx') { haptic('warn'); state.pending = 'delEx'; return renderSheet(); }
    data.exercises = data.exercises.filter(e => e.id !== ex.id);
    data.sets = data.sets.filter(x => x.exId !== ex.id);
    data.workouts.forEach(w => { w.items = w.items.filter(i => i.exId !== ex.id); });
    for (const k in data.days) {
      const d = data.days[k];
      if (!d.items.some(i => i.exId === ex.id)) continue;      // only days that had this exercise
      d.items = d.items.filter(i => i.exId !== ex.id);
      if (!d.items.length) clearEmptyDay(k);
    }
    if (rest && rest.exId === ex.id) stopRest();
    if (state.draft) state.draft.items = state.draft.items.filter(i => i.exId !== ex.id);
    save(); state.sheet = null; go('eList');
  };
}

/* Sheet: an exercise's note ("seat on 4"), shown every time you log that exercise. Private: never sent to friends. */
const NOTE_MAX = 200;
function sheetNote(el) {
  const s = state.sheet, ex = exById(s.exId);
  if (!ex) { closeSheet(); return; }
  if (s.text === undefined) s.text = ex.note || '';
  el.innerHTML = sheetOpen('Note', `${closeBtn('sCancel')}<b>Note</b>${okBtn('sSave', 'Save note')}`, `
    <div class="finish-sub" style="margin:0 8px 12px">${esc(ex.name)} · shows every time you do it</div>
    <div class="group"><textarea class="field-input" id="nText" rows="4" maxlength="${NOTE_MAX}" placeholder="E.g. seat on 4, grip just outside the rings"></textarea></div>
    ${ex.note ? `<button class="btn-tinted" id="nDel" style="color:var(--red);background:var(--red-soft)">Delete note</button>` : ''}`);
  const t = $('nText');
  t.value = s.text;
  t.oninput = () => { s.text = t.value; };
  t.focus(); t.setSelectionRange(t.value.length, t.value.length);   // straight away, so the iPhone keyboard comes up
  const done = text => { const v = text.trim().slice(0, NOTE_MAX); if (v) ex.note = v; else delete ex.note; save(); closeSheet(); render(); };
  $('sCancel').onclick = () => closeSheet();
  $('sSave').onclick = () => done(s.text);
  if ($('nDel')) $('nDel').onclick = () => done('');
}

const SET_OPTIONS = Array.from({ length: 10 }, (_, i) => ({ v: i + 1, label: `${i + 1}` }));
const setsStep = (title, backLabel, button) => sheetOpen(title,
  `${backLabel === 'Back' ? `<button class="circle glass" id="sBack" aria-label="Back">${ICON_BACK}</button>` : closeBtn('sBack')}<b>${esc(title)}</b><span></span>`,
  `<div class="section" style="text-align:center;margin-top:4px">Number of sets</div>
   <div class="group" style="max-width:200px;margin:0 auto"><div class="wheels">${wheelHTML('wSets', SET_OPTIONS)}</div></div>
   <button class="primary" id="sOk">${button}</button>`);

function sheetAddToWorkout(el) {
  const s = state.sheet;
  const dr = state.draft;
  if (s.step === 'sets') {
    const ex = exById(s.exId);
    el.innerHTML = setsStep(ex.name, 'Back', 'Add to Workout');
    initWheel('wSets', data.settings.defaultSets - 1); // default from Settings
    $('sBack').onclick = () => { s.step = 'pick'; renderSheet(); };
    $('sOk').onclick = () => { dr.items.push({ exId: ex.id, sets: SET_OPTIONS[wheelIndex('wSets')].v }); closeSheet(); render(); };
    return;
  }
  el.innerHTML = sheetOpen('Add Exercise',
    `${closeBtn('sCancel')}<b>Add Exercise</b><span></span>`,
    `${searchHTML('sq', 'Search exercises')}<div id="sres"></div>`);
  const q = $('sq');
  q.value = s.q;
  const inW = dr.items.map(i => i.exId);
  const draw = () => {
    s.q = q.value;
    const term = q.value.trim().toLowerCase();
    const list = data.exercises.filter(e => e.name.toLowerCase().includes(term)).sort(byName);
    $('sres').innerHTML = `<div class="group"><button class="cell action" data-new="1">${plusLead}New exercise${q.value.trim() ? ` “${esc(q.value.trim())}”` : ''}</button></div>
      ${list.length ? `<div class="group">${list.map(e => inW.includes(e.id)
        ? `<button class="cell" disabled><span class="main">${esc(e.name)}</span><span class="detail">Added</span></button>`
        : cell({ attrs: `data-id="${e.id}"`, main: esc(e.name) })).join('')}</div>` : ''}`;
    $('sres').querySelectorAll('[data-id]').forEach(b => b.onclick = () => { s.exId = b.dataset.id; s.step = 'sets'; renderSheet(); });
    $('sres').querySelector('[data-new]').onclick = () => openSheet({
      type: 'exForm', exId: null, name: q.value.trim(),
      onSave: id => { state.sheet = { type: 'addToWorkout', step: 'sets', exId: id, q: '' }; render(); },
    });
  };
  q.oninput = draw;
  draw();
  $('sCancel').onclick = () => closeSheet();
}
function sheetSetCount(el) {
  const it = state.draft.items[state.sheet.index];
  const ex = exById(it.exId);
  el.innerHTML = setsStep(ex ? ex.name : 'Exercise', 'Cancel', 'Save');
  initWheel('wSets', it.sets - 1);
  $('sBack').onclick = () => closeSheet();
  $('sOk').onclick = () => { it.sets = SET_OPTIONS[wheelIndex('wSets')].v; closeSheet(); render(); };
}

// Opening an invite link (…#add-ABC123) jumps to Friends and looks the code up once you're signed in
if (/^#add-/i.test(location.hash)) {
  state.inviteCode = cleanCode(location.hash.slice(5));
  state.tab = 'friends';
  try { history.replaceState(null, '', location.pathname); } catch (e) {}
}
// A workout left running on an earlier day (forgot to press Finish) is closed at its last logged set,
// so it doesn't stay "In progress" forever. One that's still active (a set or a start in the last 3 hours, e.g. training
// past midnight) is left running.
const ACTIVE_MS = 3 * 3600e3;
const lastActivity = k => { const s = dayOf(k).session; let t = s ? s.start : 0; for (const x of setsOn(k)) if (x.ts > t) t = x.ts; return t; };
const stillActive = k => isRunning(k) && Date.now() - lastActivity(k) < ACTIVE_MS;
function closeStaleSessions() {
  const tk = todayKey(); let changed = false;
  for (const k in data.days) {
    const s = data.days[k].session;
    if (!s || s.end || k >= tk || stillActive(k)) continue;
    const ts = setsOn(k).map(x => x.ts);
    if (ts.length) s.end = Math.max(s.start + 60000, ...ts); else delete data.days[k].session;
    changed = true;
  }
  if (changed) save();
  return changed;
}
closeStaleSessions();
// The app is often resumed rather than reopened (iPhone keeps it in memory), so it can wake up on a new day.
// Then "today" moves on: the day you were looking at follows to the new today. If you're still in the middle of
// last night's workout, you stay on it until it's finished (or has been idle for 3 hours).
// Checked when the app comes back to the foreground, and every minute while it's open.
let lastDay = todayKey(), heldDay = null;
function checkNewDay() {
  if (document.visibilityState === 'hidden') return;
  const tk = todayKey();
  let redraw = false;
  if (tk !== lastDay) {
    if (state.selected === lastDay) heldDay = lastDay;
    lastDay = tk; redraw = true;
    schedCache = null; sigMemo = null; pastWalk = null;
  } else if (!heldDay) return;
  if (closeStaleSessions()) redraw = true;
  if (rest && rest.date !== tk && !stillActive(rest.date)) stopRest();
  if (heldDay && !stillActive(heldDay)) {
    if (state.selected === heldDay) {
      state.selected = tk; state.weekStart = startOfWeek(new Date()); redraw = true;
      // Screens that show the selected day's exercises go back to the day (a workout summary stays open)
      if (['log', 'picker'].includes(state.views.today) && !state.sheet) { padClose(); state.views.today = 'day'; }
    }
    heldDay = null;
  }
  if (redraw) bgRender();
}
setInterval(checkNewDay, 60000);
linkExistingToLib();
if (rest && rest.start && (rest.date === todayKey() || stillActive(rest.date)) && !isFinished(rest.date)) renderRest(); else if (rest) stopRest();
applyTheme();
render();
// Sign-in and sync load just after the first screen is on the glass, at a moment your finger isn't moving
// (starting them is a burst of work that would otherwise land on your first scroll or tap), and within 2 seconds at most
requestAnimationFrame(() => {
  const t0 = performance.now();
  const start = () => { if ((touching || performance.now() - lastScroll < 200) && performance.now() - t0 < 2000) return setTimeout(start, 150); initCloud(); };
  setTimeout(start, 120);
});
// When the app is put away: anything not yet written or sent goes now (iOS may close it without warning after this)
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') { checkNewDay(); if (cloud.retryT) pushChanges(); return; }
  if (cloud.timer) { clearTimeout(cloud.timer); cloud.timer = null; pushChanges(); }
  saveSyncNow();
});
try { matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { applyTheme(); if (!state.sheet) bgRender(); }); } catch (e) {}

/* ================= Offline support ================= */
// The app opens from its own cache (instant, works offline). A new version installs in the background; if it's ready
// within the first seconds after opening, before you've touched anything, the app reloads into it right away.
// Otherwise it's used the next time the app is opened.
if ('serviceWorker' in navigator) {
  const sw = navigator.serviceWorker, hadController = !!sw.controller, opened = Date.now();
  let touched = false;
  const touch = () => { touched = true; };
  addEventListener('pointerdown', touch, { capture: true, once: true });
  addEventListener('keydown', touch, { capture: true, once: true });
  sw.addEventListener('controllerchange', () => {
    if (hadController && !touched && Date.now() - opened < 20000 && !state.sheet && !np) location.reload();
  });
  window.addEventListener('load', () => { sw.register('sw.js').catch(() => {}); });
  // Coming back to the app: check for a new version
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') sw.getRegistration().then(r => r && r.update()).catch(() => {});
  });
}

// Makes TrainingTests/Fixtures/schedule-fuzz.json: random plan changes run through app.js's OWN plan code (node),
// recording the schedule after every step, so the Swift port can replay the same steps and must agree exactly.
//   node ios-native/dev/schedule-fixtures.js            (from the repo root)
// Steps are the same kinds as dev/fuzz-schedule.py: move back (all three choices), undo moves, do workouts early,
// tick / remove sets on random days, pin the next workout to today, undo pins, put one-off workouts on days. After each step the web app redraws,
// which drops stale plan days (purgeStalePlanDays), so that runs too.
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..', '..');
const src = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const lines = src.split('\n');
const range = (from, to) => { const a = lines.findIndex(l => l.startsWith(from)); const b = lines.findIndex((l, i) => i > a && l.startsWith(to)); if (a < 0 || b < 0) throw new Error(`missing ${from} … ${to}`); return lines.slice(a, b).join('\n') + '\n'; };
let code = `
let data, uidN = 0, rest = null; const state = { drafts: {} };
const save = () => {}, toast = () => {}, haptic = () => {}, go = () => {}, render = () => {}, svg = () => '', stopRest = () => {};
const uid = () => 'id' + (uidN++);
`;
code += range('/* ================= Dates', '/* ================= Icons');
code += range('function clearEmptyDay', 'function renderDay');
code += range('const isFinished', 'const canFinish');
code += range('function ensureDay', 'function addExerciseToDay');
code += range('/* ================= Plans (rotation)', 'function sheetMoveBack');
code += 'module.exports = { get data() { return data; }, set data(v) { data = v; }, migrate: d => d, dk, parse, addDays, todayKey, planSchedule, planDayFor, upNext, purgeStalePlanDays, moveBack, unrest, pinToday, unpin, canDoToday, doToday, todayIsFree, dayOf, ensureDay, setsFor, previewDays, resetCache: () => { schedCache = null; sigMemo = null; pastWalk = null; } };';
const tmp = path.join(require('os').tmpdir(), 'tt-plan-mod.js');
fs.writeFileSync(tmp, code);
const A = require(tmp);

function seedData(variant) {
  const tk = A.todayKey(), D = n => A.dk(A.addDays(new Date(), n));
  const d = { exercises: [], days: {}, sets: [], workouts: [], plans: [], activePlan: null, settings: { units: 'metric', theme: 'system', weekStart: 1, defaultSets: 3, name: '' }, version: 3 };
  [['bp', 'Bench press'], ['ohp', 'Overhead press'], ['row', 'Barbell row'], ['sq', 'Back squat'], ['rdl', 'Romanian deadlift'], ['cu', 'Cable curl']]
    .forEach(([id, name]) => d.exercises.push({ id, name, track: ['weight', 'reps'], instructions: '', video: '' }));
  d.workouts.push({ id: 'wu', name: 'Upper', items: [{ exId: 'bp', sets: 3 }, { exId: 'ohp', sets: 3 }, { exId: 'row', sets: 3 }, { exId: 'cu', sets: 2 }] },
                  { id: 'wl', name: 'Lower', items: [{ exId: 'sq', sets: 3 }, { exId: 'rdl', sets: 3 }] },
                  { id: 'wf', name: 'Full', items: [{ exId: 'bp', sets: 2 }, { exId: 'sq', sets: 2 }] });
  const rot = [
    ['wu', 'wl', null, 'wu', 'wl', null, null],          // a week
    ['wu', null, 'wl', null, 'wf'],                      // a 5-day round
    ['wu', 'wl', 'wf', null],                            // short round, weeks-limited below
  ][variant];
  d.plans.push({ id: 'p1', name: 'Plan', weeks: variant === 2 ? 8 : 0, days: rot.map(w => ({ workoutId: w })) });
  const b = D(-21 - variant * 3);
  d.activePlan = { planId: 'p1', begin: b, start: variant === 1 ? D(-23) : b };
  let n = 0;
  for (let off = -21; off < 0; off++) {
    const i = (((off + 21) % rot.length) + rot.length) % rot.length, wid = rot[i];
    if (!wid || (off % 5 === 0)) continue;              // some missed workouts too
    const w = d.workouts.find(x => x.id === wid), k = D(off);
    d.days[k] = { items: w.items.map(x => ({ ...x })), workouts: [{ id: w.id, name: w.name }], plan: { id: 'p1', index: i }, session: { start: 1, end: 2 } };
    w.items.forEach(it => { for (let sl = 0; sl < it.sets; sl++) d.sets.push({ id: 's' + (n++), exId: it.exId, date: k, slot: sl, weight: 50, reps: 5, ts: n }); });
  }
  return d;
}

function check() {
  const sc = A.planSchedule(), tk = A.todayKey(), horizon = A.dk(A.addDays(A.parse(tk), 45));
  const map = {};
  for (const k of Object.keys(sc.map).sort()) if (k <= horizon) map[k] = sc.map[k];
  const nx = A.upNext();
  const days30 = Array.from({ length: 30 }, (_, i) => { const k = A.dk(A.addDays(new Date(), i - 10)); const pd = A.planDayFor(k); return [k, pd ? pd.index : null, A.dayOf(k).items.length, A.canDoToday(k)]; });
  return { map, upNext: nx ? nx.k : null, days30, todayIsFree: A.todayIsFree() };
}

function run(variant, steps, seed) {
  let x = seed;
  const R = () => ((x = (x * 1103515245 + 12345) % 2147483648) / 2147483648);
  A.data = seedData(variant); A.resetCache();
  const start = JSON.parse(JSON.stringify(A.data));
  const out = [];
  for (let s = 0; s < steps; s++) {
    const D = n => A.dk(A.addDays(new Date(), n)), pick = a => a[Math.floor(R() * a.length)];
    const op = Math.floor(R() * 9), n = Math.floor(R() * 16) - 5, k = D(n);
    const step = { op, k, done: false };
    if (op === 0) { const absorb = pick([undefined, 'next', 'round']); const pd = A.planDayFor(k); if (pd && pd.workout && n >= 0 && !A.data.sets.some(z => z.date === k)) { A.moveBack(k, absorb); step.done = true; step.absorb = absorb || null; step.preview = ['next', 'round', ''].map(v => A.previewDays(k, v).map(p => p.name)); } }
    else if (op === 1) { A.unrest(k); step.done = true; }
    else if (op === 2) { if (A.canDoToday(k)) { A.doToday(k); step.done = true; } }
    else if (op === 3) { const d = A.dayOf(k); if (d.items.length && n <= 0) { const it = pick(d.items); A.ensureDay(k); const set = { id: 'f' + s, exId: it.exId, date: k, slot: A.setsFor(it.exId, k).length, weight: 50, reps: 5, ts: 1000 + s }; A.data.sets.push(set); step.set = set; step.done = true; } }
    else if (op === 4) { A.data.sets = A.data.sets.filter(z => z.date !== k); step.done = true; }
    else if (op === 5) { if (A.todayIsFree()) { A.pinToday(); step.done = true; } }
    else if (op === 6) { A.unpin(k); step.done = true; }
    else if (op === 7) { const nx = A.upNext(); if (nx && A.canDoToday(nx.k)) { step.k = nx.k; A.doToday(nx.k); step.done = true; } }
    else {   // a one-off workout put on a day (Today → Add → workout), like addWorkoutToDay
      const w = pick(A.data.workouts), day = A.ensureDay(k);
      w.items.forEach(it => { if (!day.items.some(i => i.exId === it.exId)) day.items.push({ exId: it.exId, sets: it.sets }); });
      if (!day.workouts.some(z => z.id === w.id)) day.workouts.push({ id: w.id, name: w.name });
      step.workout = w.id; step.done = true;
    }
    A.resetCache(); A.purgeStalePlanDays(); A.resetCache();
    step.expect = check();
    step.days = JSON.parse(JSON.stringify(A.data.days));
    out.push(step);
  }
  return { variant, today: A.todayKey(), start, steps: out };
}

const fixture = [run(0, 500, 777), run(1, 500, 4242), run(2, 500, 99)];
const dest = path.join(root, 'ios-native', 'TrainingTests', 'Fixtures', 'schedule-fuzz.json');
fs.writeFileSync(dest, JSON.stringify(fixture));
const done = fixture.flatMap(f => f.steps).filter(s => s.done && s.op !== 1 && s.op !== 4 && s.op !== 6).length;
console.log(`wrote ${dest}: ${fixture.length} runs, ${fixture.reduce((a, f) => a + f.steps.length, 0)} steps (${done} moves / early workouts / pins / ticks)`);

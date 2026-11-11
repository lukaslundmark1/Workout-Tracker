"""Random plan changes in two versions of the app, comparing the schedule after every step.

    python3 dev/fuzz-schedule.py OLD_PORT NEW_PORT [steps]

Moves workouts back (all three choices), undoes moves, does workouts early, ticks and removes sets on random days
(today, past, future), and checks both versions agree on the schedule, Up next and the day labels each time.
"""
import asyncio, sys
from playwright.async_api import async_playwright

OLD, NEW = int(sys.argv[1]), int(sys.argv[2])
STEPS = int(sys.argv[3]) if len(sys.argv) > 3 else 300
SEED = open(__file__.rsplit('/', 1)[0] + '/screenshots.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]
RNG = "(()=>{ let x = 777; window.R = () => ((x = (x * 1103515245 + 12345) % 2147483648) / 2147483648); let n = 0; crypto.randomUUID = () => 'id' + (n++); })()"
STEP = """(() => {
  const D = n => dk(addDays(new Date(), n)), pick = a => a[Math.floor(R() * a.length)];
  const op = Math.floor(R() * 7), n = Math.floor(R() * 16) - 5, k = D(n);
  if (op === 0) { const pd = planDayFor(k); if (pd && pd.workout && n >= 0 && !data.sets.some(s => s.date === k)) moveBack(k, pick([undefined, 'next', 'round'])); }
  else if (op === 1) unrest(k);
  else if (op === 2) { if (canDoToday(k)) doToday(k); }
  else if (op === 3) { const d = dayOf(k); if (d.items.length && n <= 0) { const it = pick(d.items); ensureDay(k); data.sets.push({ id: uid(), exId: it.exId, date: k, slot: setsFor(it.exId, k).length, weight: 50, reps: 5, ts: Date.now() }); save(); } }
  else if (op === 4) { data.sets = data.sets.filter(s => s.date !== k); save(); }
  else if (op === 5) { const tk = todayKey(); if (todayIsFree()) pinToday(); }
  else { unpin(k); }
  state.tab = 'today'; state.views.today = 'day'; render();
  return op + ':' + n;
})()"""
CHECK = """JSON.stringify([planSchedule().map, upNext() && upNext().k, Array.from({length: 30}, (_, i) => { const k = dk(addDays(new Date(), i - 10)); const pd = planDayFor(k); return k + (pd ? pd.index : '-') + dayOf(k).items.length; })])"""

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        pages = []
        for port in (OLD, NEW):
            ctx = await b.new_context(service_workers='block', reduced_motion='reduce')
            pg = await ctx.new_page(); errs = []
            pg.on('pageerror', lambda e, errs=errs: errs.append(str(e)))
            await pg.goto(f'http://localhost:{port}/'); await pg.wait_for_timeout(300)
            await pg.evaluate(RNG); await pg.evaluate(SEED); await pg.evaluate("toast=()=>{}")
            pages.append((pg, errs))
        bad = 0
        for i in range(STEPS):
            ops = [await pg.evaluate(STEP) for pg, _ in pages]
            res = [await pg.evaluate(CHECK) for pg, _ in pages]
            if res[0] != res[1]:
                bad += 1
                print(f'step {i} op {ops}: DIFFERENT');
                if bad > 3: break
        for (pg, errs), port in zip(pages, (OLD, NEW)):
            if errs: print(port, 'errors:', errs[:3])
        print(f'{STEPS} random steps: ' + ('schedules always the same' if not bad else f'{bad} differences'))
        await b.close()

asyncio.run(main())

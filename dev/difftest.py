"""Compares two versions of the app screen by screen with identical data (catches behaviour changes from refactors).

    python3 dev/difftest.py OLD_PORT NEW_PORT

Serve the old version (e.g. `git show HEAD:app.js`) on OLD_PORT and the working copy on NEW_PORT. For several datasets
it draws every main screen in both and compares the HTML (ignoring known, intended differences: history cards are
drawn in chunks, chart colours are CSS variables), plus the plan schedule and the day labels for 400 days.
"""
import asyncio, re, sys
from playwright.async_api import async_playwright

OLD, NEW = int(sys.argv[1]), int(sys.argv[2])
RNG = "(()=>{ let x = 12345; Math.random = () => ((x = (x * 1103515245 + 12345) % 2147483648) / 2147483648); let n = 0; crypto.randomUUID = () => 'id' + (n++); })()"
HEAVY = open(__file__.rsplit('/', 1)[0] + '/perf.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]
LIGHT = open(__file__.rsplit('/', 1)[0] + '/crawl.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]
# Plan edge cases: moved days, pinned days, a missed workout, a workout done early, absorb modes
EDGE = HEAVY.replace("data.settings.name='Lukas';", """data.settings.name='Lukas';
  const T=todayKey(), D=n=>dk(addDays(new Date(),n));
  delete data.days[D(-3)]; data.sets=data.sets.filter(s=>s.date!==D(-3));
  data.days[D(1)]={items:[],workouts:[],rest:true,absorb:'round'}; data.days[D(4)]={items:[],workouts:[],rest:true};
  data.days[D(6)]={items:[],workouts:[],rest:true,absorb:'next'};
  data.days[D(9)]={items:[{exId:'bp',sets:3}],workouts:[{id:'w1',name:'Workout 1'}]};""")
SEEDS = [('light', LIGHT), ('heavy', HEAVY), ('edge', EDGE)]
VIEWS = [("today", "day", "{}"), ("today", "log", "{logExId:'bp'}"), ("today", "log", "{logExId:'row'}"), ("today", "history", "{logExId:'bp',stat:'e1rm'}"),
         ("today", "history", "{logExId:'bp',stat:'volume'}"), ("today", "calendar", "{calMonth:new Date(new Date().getFullYear(), new Date().getMonth(), 1)}"),
         ("today", "summary", "{sumDate:dk(addDays(new Date(),-2))}"), ("today", "summary", "{sumDate:dk(addDays(new Date(),-4))}"),
         ("today", "picker", "{pickerMode:'exercises',pickerQuery:'b'}"), ("workouts", "wList", "{wSeg:'plans'}"), ("workouts", "wList", "{wSeg:'workouts'}"),
         ("workouts", "pView", "{planId:'p1'}"), ("exercises", "eList", "{exQuery:''}"), ("exercises", "eDetail", "{detailExId:'bp',stat:'e1rm'}"),
         ("exercises", "lib", "{libBack:'eList'}"), ("friends", "me", "{prof:'me'}"), ("friends", "pWorkouts", "{prof:'me'}"),
         ("friends", "pWorkout", "{prof:'me',pwDate:dk(addDays(new Date(),-2))}"), ("settings", "settings", "{}")]
ROOT = {'today': 'day', 'workouts': 'wList', 'exercises': 'eList', 'friends': 'friends', 'settings': 'settings'}

def norm(h):
    h = re.sub(r'<svg class="(draw|still)"[\s\S]*?</svg>', '<svg chart/>', h)              # chart drawing (colours moved to CSS)
    cards = re.findall(r'<div class="hcard">[\s\S]*?</div>\s*</div>', h)
    if cards:                                                                               # history: compare the first 12 cards
        first = h.find(cards[0]); h = h[:first] + '\n'.join(c.strip() for c in cards[:12]) + '<HIST/>'
    h = re.sub(r'<div class="section">History</div><div id="hlist">', '<div class="section">History</div>', h)
    h = re.sub(r'\s+', ' ', h)
    h = re.sub(r'id="timerText">[\d:]+<', 'id="timerText">T<', h)
    h = h.replace('</div><div id="hmore" class="hmore" aria-hidden="true"></div>', '').replace('<HIST/></div>', '<HIST/>')
    return h

async def snap(pg, seed):
    await pg.evaluate(RNG); await pg.evaluate(seed); await pg.evaluate("toast=()=>{}")
    out = {}
    for tab, view, extra in VIEWS:
        await pg.evaluate(f"(()=>{{ state.tab='{tab}'; state.views[state.tab]='{ROOT[tab]}'; go('{view}', {extra}); }})()")
        out[f'{tab}/{view}{extra}'] = norm(await pg.evaluate("app.innerHTML"))
    out['schedule'] = await pg.evaluate("JSON.stringify(planSchedule().map)")
    out['labels'] = await pg.evaluate("Array.from({length:400},(_,i)=>{const k=dk(addDays(new Date(),i-200)); const d=dayOf(k); return k+':'+d.items.map(x=>x.exId+x.sets).join(',')+'/'+(planDayFor(k)?planDayFor(k).index:'-')+'/'+(canDoToday(k)?1:0);}).join('|')")
    out['upNext'] = await pg.evaluate("JSON.stringify(upNext() && {k:upNext().k,i:upNext().index})")
    out['previews'] = await pg.evaluate("JSON.stringify([0,1,2,3,5].map(n => [undefined,'next','round'].map(a => previewDays(dk(addDays(new Date(),n)), a, 10))))")
    out['coming'] = await pg.evaluate("state.tab='workouts'; state.views.workouts='wList'; go('pView',{planId:'p1'}); app.innerHTML.replace(/\\s+/g,' ')")
    out['week'] = await pg.evaluate("state.tab='today'; state.views.today='day'; state.selected=todayKey(); render(); document.querySelector('#weekTrack').innerHTML.replace(/\\s+/g,' ')")
    # actions: tick a set, move back, undo, finish
    await pg.evaluate("state.tab='today'; state.views.today='log'; state.logExId='bp'; state.selected=todayKey(); render(); const c=document.querySelector('#pager .setrow:not(.done) .check'); if(c) c.click();")
    out['afterTick'] = norm(await pg.evaluate("app.innerHTML"))
    out['afterTickSched'] = await pg.evaluate("JSON.stringify(planSchedule().map)")
    await pg.evaluate("moveBack(dk(addDays(new Date(),2)), 'round'); render()")
    out['afterMove'] = await pg.evaluate("JSON.stringify(planSchedule().map)")
    await pg.evaluate("unrest(dk(addDays(new Date(),2))); moveBack(dk(addDays(new Date(),3))); render()")
    out['afterMove2'] = await pg.evaluate("JSON.stringify(planSchedule().map)")
    await pg.evaluate("state.tab='today'; state.views.today='day'; state.selected=todayKey(); render()")
    out['dayAfter'] = norm(await pg.evaluate("app.innerHTML"))
    return out

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        bad = 0
        for name, seed in SEEDS:
            res = []
            for port in (OLD, NEW):
                ctx = await b.new_context(viewport={'width': 390, 'height': 844}, service_workers='block', reduced_motion='reduce')
                pg = await ctx.new_page(); errs = []
                pg.on('pageerror', lambda e: errs.append(str(e)))
                await pg.goto(f'http://localhost:{port}/'); await pg.wait_for_timeout(300)
                res.append(await snap(pg, seed))
                if errs: print(f'  {name} port {port} errors:', errs[:3]); bad += 1
                await ctx.close()
            for k in res[0]:
                if res[0][k] != res[1][k]:
                    bad += 1
                    a, c = res[0][k], res[1][k]
                    i = next((i for i in range(min(len(a), len(c))) if a[i] != c[i]), min(len(a), len(c)))
                    print(f'DIFF {name} {k}\n   old: …{a[max(0, i - 80):i + 120]}\n   new: …{c[max(0, i - 80):i + 120]}')
            print(f'{name}: {len(res[0])} checks done')
        print('ALL SAME' if not bad else f'{bad} differences')
        await b.close()

asyncio.run(main())

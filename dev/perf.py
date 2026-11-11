"""Performance benchmark: times screen draws, common actions and startup with a heavy, realistic dataset.

    python3 dev/perf.py [port] [cpu_throttle] [days]   # defaults: 8765, 4 (4x slower CPU), 728 days of history

Needs the app served on the port (python3 -m http.server 8765 from the repo root).
Seeds ~2 years of training (4 workouts a week, ~10,000 sets), then reports the median time of each step in ms.
"""
import asyncio, json, statistics, sys
from playwright.async_api import async_playwright

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
THROTTLE = float(sys.argv[2]) if len(sys.argv) > 2 else 4
DAYS = int(sys.argv[3]) if len(sys.argv) > 3 else 728
URL = f'http://localhost:{PORT}/'

SEED = """(()=>{ localStorage.clear(); data = migrate({exercises:[],days:{},sets:[]});
  const EX=[['bp','Bench press','chest','barbell',70],['ohp','Overhead press','shoulders','barbell',42.5],['row','Barbell row','back','barbell',60],['cu','Cable curl','arms','cable',22.5],
    ['lat','Lat pulldown','back','cable',55],['dip','Dips','chest','bodyweight',0],['sq','Back squat','legs','barbell',95],['rdl','Romanian deadlift','legs','barbell',85],
    ['lp','Leg press','legs','machine',140],['lc','Leg curl','legs','machine',40],['ca','Calf raise','legs','machine',60],['pl','Plank','core','bodyweight',0]];
  EX.forEach(([id,name,muscle,equip])=>data.exercises.push({id,name,track:['weight','reps'],instructions:'Keep tight.',video:'',muscle,equip}));
  for (let i=0;i<40;i++) data.exercises.push({id:'x'+i,name:'Extra exercise '+i,track:['weight','reps'],instructions:'',video:'',muscle:'arms',equip:'dumbbell'});
  data.workouts.push({id:'wu',name:'Upper',items:['bp','ohp','row','cu','lat','dip'].map(exId=>({exId,sets:4}))},{id:'wl',name:'Lower',items:['sq','rdl','lp','lc','ca','pl'].map(exId=>({exId,sets:4}))});
  for (let i=0;i<6;i++) data.workouts.push({id:'w'+i,name:'Workout '+i,items:[{exId:'bp',sets:3},{exId:'sq',sets:3}]});
  data.plans.push({id:'p1',name:'Upper Lower',weeks:0,days:[{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:null}]});
  const base={}; EX.forEach(e=>base[e[0]]=e[4]);
  const DAYS=(window.PERF_DAYS||728), b=dk(addDays(new Date(),-DAYS)); data.activePlan={planId:'p1',begin:b,start:b};
  let n=0; for (let d=-DAYS; d<0; d++) { const i=((d+DAYS)%7); const wid=['wu','wl',null,'wu','wl',null,null][i]; if(!wid) continue; const w=woById(wid); const k=dk(addDays(new Date(),d));
    data.days[k]={items:w.items.map(x=>({...x})),workouts:[{id:w.id,name:w.name}],plan:{id:'p1',index:i},session:{start:Date.now()+d*864e5,end:Date.now()+d*864e5+3.6e6}};
    w.items.forEach((it,j)=>{ for(let sl=0;sl<it.sets;sl++) data.sets.push({id:'s'+(n++)+'-'+Math.random().toString(36).slice(2,10),exId:it.exId,date:k,slot:sl,weight:base[it.exId]+Math.floor((d+DAYS)/14)*1.25,reps:8-sl+(n%3),ts:Date.now()+d*864e5+j*1000+sl}); }); }
  const t=ensureDay(todayKey()); const wu=woById('wu'); t.items=wu.items.map(x=>({...x})); t.workouts=[{id:'wu',name:'Upper'}]; t.session={start:Date.now()-14*6e4};
  data.sets.push({id:'t1',exId:'bp',date:todayKey(),slot:0,weight:82.5,reps:8,ts:Date.now()-5e5});
  data.settings.name='Lukas'; saveLocal(); state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); go('day');
  return data.sets.length; })()"""

# name, setup js (run untimed), timed js
STEPS = [
  ('render Today',        "state.tab='today'; state.views.today='day'",                         "render()"),
  ('render Log page',     "state.tab='today'; state.views.today='log'; state.logExId='bp'",       "render()"),
  ('render History',      "state.tab='today'; state.views.today='history'; state.logExId='bp'; state.stat='e1rm'", "render()"),
  ('render Calendar',     "state.tab='today'; state.views.today='calendar'; state.calMonth=new Date(new Date().getFullYear(), new Date().getMonth(), 1)", "render()"),
  ('render Summary',      "state.tab='today'; state.views.today='summary'; state.sumDate=dk(addDays(new Date(),-3))", "render()"),
  ('render Plans list',   "state.tab='workouts'; state.views.workouts='wList'; state.wSeg='plans'", "render()"),
  ('render Plan view',    "state.tab='workouts'; state.views.workouts='pView'; state.planId='p1'", "render()"),
  ('render Workouts',     "state.tab='workouts'; state.views.workouts='wList'; state.wSeg='workouts'", "render()"),
  ('render Exercises',    "state.tab='exercises'; state.views.exercises='eList'; state.exQuery=''", "render()"),
  ('render Exercise detail', "state.tab='exercises'; state.views.exercises='eDetail'; state.detailExId='bp'; state.stat='e1rm'", "render()"),
  ('render Database',     "state.tab='exercises'; state.views.exercises='lib'; state.libBack='eList'", "render()"),
  ('render My profile',   "state.tab='friends'; state.views.friends='me'; state.prof='me'", "render()"),
  ('render Settings',     "state.tab='settings'; state.views.settings='settings'", "render()"),
  ('tap week day',        "state.tab='today'; state.views.today='day'; state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); render()",                "[...document.querySelectorAll('#weekTrack .day')].find(b => b.dataset.k !== todayKey()).click()"),
  ('switch tab',          "state.tab='today'; state.views.today='day'; render()",                "document.querySelector('#dock [data-tab=exercises]').click()"),
  ('open exercise (go)',  "state.tab='today'; state.views.today='day'; state.selected=todayKey(); render()", "document.querySelector('#dayList [data-ex]').click()"),
  ('tick a set',          "state.tab='today'; state.views.today='log'; state.logExId='ohp'; state.selected=todayKey(); data.sets=data.sets.filter(s=>!(s.date===todayKey()&&s.exId==='ohp')); render()",
                          "document.querySelector('#pager .setrow:not(.done) .check').click()"),
  ('number pad key',      "state.tab='today'; state.views.today='log'; state.logExId='ohp'; render(); padOpen('ohp',1,'w')", "padKey('5')"),
  ('open sheet',          "state.tab='today'; state.views.today='day'; closeSheet(); document.querySelectorAll('.sheet-ghost').forEach(g => g.remove()); render()",  "openSheet({type:'moveBack', k: dk(addDays(new Date(),1))})"),
  ('save()',              "",                                                                     "saveLocal()"),
  ('sync diff (push check)', "cloud.user={uid:'perf'}; cloud.sync={since:0,maps:{}}; for (const col of Object.keys(COLS)) { cloud.sync.maps[col]={}; const l=COLS[col].get(); for (const id in l) cloud.sync.maps[col][id]=hash(JSON.stringify(l[id])); }; cloud.fb=null",
                          "typeof syncOps === 'function' ? syncOps(1).length : (()=>{ let c=0; for (const col of Object.keys(COLS)) { const l=COLS[col].get(), m=cloud.sync.maps[col]; for (const id in l) if (m[id]!==hash(JSON.stringify(l[id]))) c++; } return c; })()"),
]

TIMED = """async (js) => {
  const t0 = performance.now();
  (0, eval)(js);
  void document.body.offsetHeight;            // include style + layout of what was drawn
  const t1 = performance.now();
  await new Promise(r => requestAnimationFrame(() => setTimeout(r, 0)));   // next frame painted
  return [t1 - t0, performance.now() - t0];
}"""

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}), args=['--disable-extensions'])
        ctx = await b.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=3, has_touch=True, service_workers='block')
        pg = await ctx.new_page()
        errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto(URL); await pg.wait_for_timeout(500)
        await pg.evaluate(f'window.PERF_DAYS={DAYS}'); n = await pg.evaluate(SEED)
        await pg.evaluate("toast=()=>{}")   # keep toasts from piling up
        cdp = await ctx.new_cdp_session(pg)
        await cdp.send('Emulation.setCPUThrottlingRate', {'rate': THROTTLE})
        print(f'{n} sets, CPU throttle {THROTTLE}x\n')
        print(f'{"step":28} {"js+layout":>10} {"to frame":>10}')
        res = {}
        for name, setup, js in STEPS:
            a, f = [], []
            for _ in range(7):
                if setup: await pg.evaluate(f"(()=>{{ {setup} }})()")
                await pg.wait_for_timeout(60)
                x, y = await pg.evaluate(TIMED, js)
                a.append(x); f.append(y)
            res[name] = (statistics.median(a), statistics.median(f))
            print(f'{name:28} {res[name][0]:10.1f} {res[name][1]:10.1f}')
        await cdp.send('Emulation.setCPUThrottlingRate', {'rate': 1})
        # Startup: reload with the heavy data already saved, time until the first screen is drawn
        times = []
        for _ in range(5):
            await pg.goto(URL + '?perf')
            await cdp.send('Emulation.setCPUThrottlingRate', {'rate': THROTTLE})
            await pg.reload()
            t = await pg.evaluate("""() => new Promise(r => { const go = () => { const nav = performance.getEntriesByType('navigation')[0];
                const fcp = (performance.getEntriesByName('first-contentful-paint')[0] || {}).startTime || 0;
                r([nav.domContentLoadedEventEnd, fcp, nav.loadEventEnd]); }; if (document.readyState === 'complete') setTimeout(go, 50); else addEventListener('load', () => setTimeout(go, 50)); })""")
            await cdp.send('Emulation.setCPUThrottlingRate', {'rate': 1})
            times.append(t)
        med = [statistics.median(x[i] for x in times) for i in range(3)]
        print(f'\nstartup  DOMContentLoaded {med[0]:.0f} ms · first paint {med[1]:.0f} ms · load {med[2]:.0f} ms')
        if errs: print('\nERRORS:', *errs[:5], sep='\n  ')
        await b.close()
        json.dump(res, open('/tmp/perf-last.json', 'w'))

asyncio.run(main())

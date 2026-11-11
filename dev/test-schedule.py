import asyncio
from playwright.async_api import async_playwright
SETUP = """([beginOff, startIdx]) => { localStorage.clear(); data = migrate({exercises:[],days:{},sets:[]});
  ['a','b'].forEach(id=>data.exercises.push({id,name:id,track:['weight','reps'],instructions:'',video:''}));
  data.workouts.push({id:'wu',name:'Upper',items:[{exId:'a',sets:2}]},{id:'wl',name:'Lower',items:[{exId:'b',sets:2}]});
  data.plans.push({id:'p1',name:'UL R UL RR',weeks:0,days:[{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:null}]});
  const b=dk(addDays(new Date(),beginOff)); data.activePlan={planId:'p1',begin:b,start:dk(addDays(parse(b),-startIdx))};
  state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); save(); go('day'); }"""
SCHED = "(a)=>{ const from=(a&&a[0])||0, n=(a&&a[1])||8; schedCache=null; return Array.from({length:n},(_,i)=>{const k=dk(addDays(new Date(),from+i)); const d=dayOf(k); const pd=planDayFor(k); const nm=d.items.length?(d.workouts[0]||{name:'custom'}).name:'R'; return parse(k).toLocaleDateString('en-GB',{weekday:'short'})+':'+(nm==='Upper'?'U':nm==='Lower'?'L':nm)}).join(' ') }"
TRAIN = "([off, wid, idx]) => { const k=dk(addDays(new Date(),off)); const w=woById(wid); data.days[k]={items:w.items.map(i=>({...i})),workouts:[{id:w.id,name:w.name}],plan:{id:'p1',index:idx}}; data.sets.push({id:uid(),exId:w.items[0].exId,date:k,slot:0,weight:50,reps:5,ts:Date.now()}); save(); render(); }"
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2)
        errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
        W=lambda t=300: pg.wait_for_timeout(t)
        await pg.goto('http://localhost:8765/'); await W()
        setup = lambda *a: pg.evaluate(SETUP, list(a)); sched = lambda *a: pg.evaluate(SCHED, list(a)); train = lambda *a: pg.evaluate(TRAIN, list(a))
        # today = Tue 10 Nov; plan began Mon 9 Nov, trained Upper Monday
        await setup(-1,0); await train(-1,'wu',0)
        print('T1 base       :', await sched(0,7))
        print('   button:', await pg.locator('.move-btn').all_inner_texts())
        await pg.click('#restDay'); await W()
        print('T8 options:', await pg.locator('.mv-opt b').all_inner_texts())
        for i,t in enumerate(await pg.locator('.pv-row').all_inner_texts()): print('   ', i, t.replace('\n',' '))
        await pg.screenshot(path='shots/o1-sheet.png')
        await pg.click('[data-pick=next]'); await pg.click('#sGo'); await W(400)
        print('T2 just this  :', await sched(0,8), '| toast:', (await pg.locator('#toast').inner_text()).replace('\n',' | '))
        print('   buttons:', await pg.locator('.move-btn').all_inner_texts())
        await pg.click('#unrestDay'); await W(); print('T9 undo       :', await sched(0,7))
        await pg.click('#restDay'); await W(); await pg.click('[data-pick=round]'); await pg.click('#sGo'); await W(400)
        print('T3 rest of wk :', await sched(0,8))
        await pg.click('#unrestDay'); await W()
        await pg.click('#restDay'); await W(); await pg.click('[data-pick=""]'); await pg.click('#sGo'); await W(400)
        print('T4 forever    :', await sched(0,9))
        # T5 missed: began previous Monday (-8), trained Upper that Monday only
        await setup(-8,0); await train(-8,'wu',0)
        print('T5 missed wk  :', await sched(0,7), '(Lower has waited since last Tue)')
        # T6 pull on rest day: today is index 5 (rest), tomorrow 6 rest, then U L R ...
        await setup(0,5)
        print('T6 before     :', await sched(0,7))
        print('   buttons:', await pg.locator('.move-btn').all_inner_texts())
        await pg.click('#pullNext'); await W(400)
        print('   after pull :', await sched(0,7), '| buttons:', await pg.locator('.move-btn').all_inner_texts())
        await pg.evaluate("data.sets.push({id:'x',exId:'a',date:todayKey(),slot:0,weight:50,reps:5,ts:1}); save(); render()")
        print('T7 trained it :', await sched(0,7))
        # 4-day rotation round label
        await pg.evaluate("""(()=>{ data.plans[0].days=[{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:null}]; data.sets=[]; data.days={}; data.activePlan.start=todayKey(); data.activePlan.begin=todayKey(); save(); render(); })()""")
        await pg.click('#restDay'); await W(); print('T10 options:', await pg.locator('.mv-opt b').all_inner_texts()); await pg.evaluate("closeSheet()")
        await pg.evaluate("data.settings.theme='dark'; applyTheme(); render()"); await setup(-1,0); await train(-1,'wu',0)
        await pg.evaluate("data.settings.theme='dark'; applyTheme(); render()"); await pg.click('#restDay'); await W()
        await pg.screenshot(path='shots/o2-sheet-dark.png')
        print('errors', errs)
        await b.close()
asyncio.run(main())

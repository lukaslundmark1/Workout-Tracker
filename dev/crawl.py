import asyncio, json
from playwright.async_api import async_playwright
SEED = """(()=>{ localStorage.clear(); data = migrate({exercises:[],days:{},sets:[]});
  [['bp','Bench press','chest','barbell'],['sq','Squat','legs','barbell'],['row','Barbell row','back','barbell'],['cu','Cable curl','arms','cable']].forEach(([id,name,muscle,equip])=>data.exercises.push({id,name,track:['weight','reps'],instructions:'Keep tight',video:'https://youtu.be/dQw4w9WgXcQ',muscle,equip}));
  data.workouts.push({id:'wu',name:'Upper',items:[{exId:'bp',sets:3},{exId:'row',sets:3}]},{id:'wl',name:'Lower',items:[{exId:'sq',sets:3}]});
  data.plans.push({id:'p1',name:'UL',weeks:0,days:[{workoutId:'wu'},{workoutId:'wl'},{workoutId:null}]});
  const b=dk(addDays(new Date(),-20)); data.activePlan={planId:'p1',begin:b,start:b};
  for (let d=-20; d<0; d+=3) { const k=dk(addDays(new Date(),d)); data.days[k]={items:[{exId:'bp',sets:3},{exId:'row',sets:3}],workouts:[{id:'wu',name:'Upper'}],plan:{id:'p1',index:0},session:{start:Date.now()+d*864e5,end:Date.now()+d*864e5+3e6}};
    [0,1,2].forEach(sl=>{ data.sets.push({id:uid(),exId:'bp',date:k,slot:sl,weight:60+(d+20)*1.5,reps:8-sl,ts:Date.now()+d*864e5+sl}); data.sets.push({id:uid(),exId:'row',date:k,slot:sl,weight:50,reps:10,ts:Date.now()+d*864e5+10+sl}); }); }
  data.settings.name='Lukas'; save(); state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); go('day'); })()"""
VIEWS = [("today","day",{}),("today","log",{"logExId":"bp"}),("today","history",{"logExId":"bp","stat":"e1rm"}),("today","picker",{"pickerMode":"exercises","pickerQuery":"b"}),
  ("today","picker",{"pickerMode":"workouts"}),("today","calendar",{"calMonth":"__month__"}),("today","summary",{"sumDate":"__past__"}),
  ("workouts","wList",{"wSeg":"plans"}),("workouts","wList",{"wSeg":"workouts"}),("workouts","pView",{"planId":"p1"}),
  ("workouts","pEdit",{"pdraft":{"id":"p1","name":"UL","weeks":0,"days":[{"workoutId":"wu"},{"workoutId":None}]}}),
  ("workouts","wEdit",{"draft":{"id":"wu","name":"Upper","items":[{"exId":"bp","sets":3}]}}),
  ("exercises","eList",{"exQuery":"pull"}),("exercises","eDetail",{"detailExId":"bp","stat":"e1rm"}),("exercises","lib",{"libBack":"eList"}),
  ("friends","friends",{}),("friends","me",{"prof":"me"}),("friends","pWorkouts",{"prof":"me"}),("friends","pWorkout",{"prof":"me","pwDate":"__past__"}),("friends","fEx",{"prof":"me","friendEx":"bp","stat":"e1rm"}),
  ("settings","settings",{})]
SHEETS = ["{type:'exForm', exId:'bp'}","{type:'exForm', exId:null, name:'New one'}","{type:'addToWorkout', q:''}","{type:'duration', k: todayKey()}","{type:'signin'}",
  "{type:'planDay', index:0}","{type:'planStart', planId:'p1'}","{type:'moveBack', k: dk(addDays(new Date(),1))}","{type:'setCount', index:0}","{type:'sendTo', kind:'plan', id:'p1'}","{type:'sendTo', kind:'workout', id:'wu'}","{type:'note', exId:'bp'}"]
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        errs=[]
        for theme in ['light','dark']:
            pg = await b.new_page(viewport={'width':390,'height':844}, has_touch=True)
            pg.on('pageerror', lambda e, t=theme: errs.append(f'{t}: {e}'))
            pg.on('response', lambda r, t=theme: errs.append(f'{t} 404: {r.url}') if r.status==404 else None)
            await pg.goto('http://localhost:8765/'); await pg.wait_for_timeout(400)
            await pg.evaluate(SEED); await pg.evaluate(f"data.settings.theme='{theme}'; applyTheme()")
            past = await pg.evaluate("dk(addDays(new Date(),-2))")
            for tab, view, extra in VIEWS:
                ex = json.dumps(extra).replace('"__past__"', f'"{past}"').replace('"__month__"','new Date(new Date().getFullYear(), new Date().getMonth(), 1)')
                try:
                    root = {'today':'day','workouts':'wList','exercises':'eList','friends':'friends','settings':'settings'}[tab]
                    await pg.evaluate(f"(()=>{{ state.tab='{tab}'; state.views[state.tab]='{root}'; go('{view}', {ex}); }})()")
                    await pg.wait_for_timeout(120)
                    got = await pg.evaluate("state.views[state.tab]")
                    if got != view: errs.append(f'{theme}: {view} redirected to {got}')
                except Exception as e: errs.append(f'{theme}: {view} -> {e}')
            await pg.evaluate("state.tab='today'; go('day')")
            for sh in SHEETS:
                try:
                    if 'planDay' in sh: await pg.evaluate("state.tab='workouts'; go('pEdit',{pdraft:{id:'p1',name:'UL',weeks:0,days:[{workoutId:'wu'}]}})")
                    if 'addToWorkout' in sh or 'setCount' in sh: await pg.evaluate("state.tab='workouts'; go('wEdit',{draft:{id:'wu',name:'Upper',items:[{exId:'bp',sets:3}]}})")
                    await pg.evaluate(f"openSheet({sh})"); await pg.wait_for_timeout(100)
                    if not await pg.locator('.sheet').count(): errs.append(f'{theme}: sheet {sh} did not open')
                    await pg.evaluate("closeSheet()"); await pg.wait_for_timeout(50)
                    await pg.evaluate("state.tab='today'; go('day')")
                except Exception as e: errs.append(f'{theme}: sheet {sh} -> {e}')
            await pg.close()
        print('\n'.join(errs) if errs else 'no errors')
        await b.close()
asyncio.run(main())

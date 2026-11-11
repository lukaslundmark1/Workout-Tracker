import asyncio, sys
from playwright.async_api import async_playwright
SEED = """(()=>{ localStorage.clear(); data = migrate({exercises:[],days:{},sets:[]});
  [['bp','Bench press','chest','barbell'],['ohp','Overhead press','shoulders','barbell'],['row','Barbell row','back','barbell'],['sq','Back squat','legs','barbell'],['rdl','Romanian deadlift','legs','barbell'],['cu','Cable curl','arms','cable']].forEach(([id,name,muscle,equip])=>data.exercises.push({id,name,track:['weight','reps'],instructions:'Keep your shoulder blades tight.',video:'',muscle,equip}));
  data.workouts.push({id:'wu',name:'Upper',items:[{exId:'bp',sets:3},{exId:'ohp',sets:3},{exId:'row',sets:3},{exId:'cu',sets:2}]},{id:'wl',name:'Lower',items:[{exId:'sq',sets:3},{exId:'rdl',sets:3}]});
  data.plans.push({id:'p1',name:'Upper Lower',weeks:0,days:[{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:'wu'},{workoutId:'wl'},{workoutId:null},{workoutId:null}]});
  const b=dk(addDays(new Date(),-28)); data.activePlan={planId:'p1',begin:b,start:b};
  let n=0; for (let d=-28; d<0; d++) { const i=((d+28)%7); const wid=[ 'wu','wl',null,'wu','wl',null,null][i]; if(!wid) continue; const w=woById(wid); const k=dk(addDays(new Date(),d));
    data.days[k]={items:w.items.map(x=>({...x})),workouts:[{id:w.id,name:w.name}],plan:{id:'p1',index:i},session:{start:Date.now()+d*864e5,end:Date.now()+d*864e5+(52+i)*6e4}};
    w.items.forEach((it,j)=>{ for(let sl=0;sl<it.sets;sl++) data.sets.push({id:'s'+(n++),exId:it.exId,date:k,slot:sl,weight:({bp:70,ohp:42.5,row:60,sq:95,rdl:85,cu:22.5})[it.exId]+Math.floor((d+28)/7)*2.5,reps:8-sl,ts:Date.now()+d*864e5+j*100+sl}); }); }
  save(); schedCache=null;
  const t=ensureDay(todayKey()); t.session={start:Date.now()-14*6e4};
  data.sets.push({id:'t1',exId:'bp',date:todayKey(),slot:0,weight:82.5,reps:8,ts:Date.now()-5e5},{id:'t2',exId:'bp',date:todayKey(),slot:1,weight:82.5,reps:7,ts:Date.now()-2e5});
  data.settings.name='Lukas'; save(); state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); go('day'); })()"""
SHOTS = [("day","state.tab='today'; go('day')"),("log","state.tab='today'; go('log',{logExId:'bp'})"),("history","state.tab='today'; go('history',{logExId:'bp',stat:'e1rm'})"),
 ("calendar","state.tab='today'; state.views.today='day'; go('day'); document.querySelector('#calBtn').click()"),
 ("summary","state.tab='today'; go('summary',{sumDate:dk(addDays(new Date(),-3))})"),
 ("plans","state.tab='workouts'; state.wSeg='plans'; go('wList')"),("pview","state.tab='workouts'; go('pView',{planId:'p1'})"),
 ("exlist","state.tab='exercises'; go('eList')"),("exdetail","state.tab='exercises'; go('eDetail',{detailExId:'bp',stat:'e1rm'})"),("lib","state.tab='exercises'; go('lib',{libBack:'eList'})"),
 ("friends","state.tab='friends'; go('friends')"),("me","state.tab='friends'; go('me',{prof:'me'})"),("settings","state.tab='settings'; go('settings')")]
async def main(tag, themes):
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        for theme in themes:
            pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2)
            await pg.goto('http://localhost:8765/'); await pg.wait_for_timeout(400)
            await pg.evaluate(SEED); await pg.evaluate(f"data.settings.theme='{theme}'; applyTheme(); render()")
            for name, js in SHOTS:
                await pg.evaluate(f"(()=>{{ {js} }})()"); await pg.wait_for_timeout(750)
                await pg.screenshot(path=f'shots/{tag}-{name}-{theme}.png')
            await pg.close()
        await b.close()
asyncio.run(main(sys.argv[1], sys.argv[2].split(',')))

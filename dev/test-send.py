import asyncio, json
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        errs=[]
        pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2)
        pg.on('pageerror', lambda e: errs.append(str(e)))
        W=lambda t=650: pg.wait_for_timeout(t)
        await pg.goto('http://localhost:8767/'); await pg.evaluate("localStorage.clear()"); await pg.reload(); await W(300)
        await pg.evaluate("""(()=>{ data.settings.name='Lukas';
          [['bp','Bench press','chest','barbell','b:benchpress'],['ohp','Overhead press','shoulders','barbell','b:overheadpress'],['pp','Paused pin press','chest','barbell','']].forEach(([id,name,muscle,equip,lib])=>data.exercises.push({id,name,track:['weight','reps'],instructions:'Squeeze',video:'https://youtu.be/dQw4w9WgXcQ',muscle,equip,...(lib?{lib}:{})}));
          data.workouts.push({id:'wpush',name:'Push day',items:[{exId:'bp',sets:4},{exId:'ohp',sets:3},{exId:'pp',sets:2}]},{id:'wrest',name:'Arms',items:[{exId:'pp',sets:3}]});
          data.plans.push({id:'pl',name:'Push rest',weeks:4,days:[{workoutId:'wpush'},{workoutId:null},{workoutId:'wrest'}]}); save(); })()""")
        await pg.click('[data-tab=friends]'); await W(200); await pg.click('#fSignIn'); await W()
        await pg.fill('#aEmail','lukas@x.com'); await pg.fill('#aPass','secret1'); await pg.click('#aGo'); await W(900)
        await pg.evaluate("__put('links/u1_u2',{members:['u1','u2'],from:'u2',status:'accepted',share:{u1:true,u2:true},names:{u1:'Lukas',u2:'Anna'},u:1}); __put('links/u1_u3',{members:['u1','u3'],from:'u3',status:'accepted',share:{u1:false,u3:false},names:{u1:'Lukas',u3:'Ben'},u:1})"); await W()
        # 1. send a plan to two friends from the plan screen
        await pg.click('[data-tab=workouts]'); await W(); await pg.evaluate("go('pView',{planId:'pl'})"); await W()
        await pg.click('#sendP'); await W()
        print('send sheet friends:', await pg.locator('[data-pick]').count(), '| button:', await pg.locator('#sGo').inner_text(), 'disabled:', await pg.locator('#sGo').is_disabled())
        await pg.click('[data-pick=u1_u2]'); await pg.click('[data-pick=u1_u3]'); await W(200)
        await pg.screenshot(path='shots/r1-sendto.png')
        print('button now:', await pg.locator('#sGo').inner_text())
        await pg.click('#sGo'); await W(800)
        gifts = await pg.evaluate("[...__db.entries()].filter(([k])=>k.startsWith('gifts/')).map(([k,v])=>v)")
        print('gifts in db:', [(g['to'], g['kind'], g['name'], g['status'], g['fromName']) for g in gifts])
        print('toast:', (await pg.locator('#toast').inner_text()).replace('\n',' | '))
        planPayload = [g for g in gifts if g['kind']=='plan'][0]['payload']
        print('payload workouts:', [w['name'] for w in planPayload['workouts']], 'days:', planPayload['days'])
        # 2. send a workout from the editor
        await pg.evaluate("state.draft=JSON.parse(JSON.stringify(woById('wpush'))); go('wEdit')"); await W()
        await pg.click('#sendW'); await W(); await pg.click('[data-pick=u1_u2]'); await pg.click('#sGo'); await W(700)
        # 3. friend page: sent list + unsend
        await pg.click('[data-tab=friends]'); await W(); await pg.click('[data-friend=u1_u2]'); await W(900)
        print('friend page sent rows:', await pg.locator('[data-unsend]').count(), '(expect 2 waiting)')
        await pg.screenshot(path='shots/r2-friendpage.png', full_page=True)
        await pg.click('[data-unsend] >> nth=0'); await W(400)
        print('after unsend:', await pg.locator('[data-unsend]').count(), '| db gifts:', await pg.evaluate("[...__db.keys()].filter(k=>k.startsWith('gifts/')).length"))
        # send from friend page
        await pg.click('#sendPick'); await W()
        await pg.click('[data-send="workout:wrest"]'); await W(700)
        print('send-pick sent; db gifts:', await pg.evaluate("[...__db.keys()].filter(k=>k.startsWith('gifts/')).length"))
        # 4. receive: Anna sends Lukas a plan (reuse the real payload, with a name clash + an exercise Lukas lacks)
        rp = json.loads(json.dumps(planPayload))
        rp['workouts'][1]['items'].append({'ex':{'name':'Cable fly','track':['weight','reps'],'muscle':'chest','equip':'cable','lib':'b:cablefly','instructions':'<img src=x onerror=alert(1)>','video':'javascript:alert(1)'},'sets':3})
        await pg.click('#back'); await W()
        await pg.evaluate(f"__put('gifts/g1', {{from:'u2',to:'u1',fromName:'Anna',toName:'Lukas',kind:'plan',name:'Push rest',payload:{json.dumps(rp)},status:'pending',u:Date.now()}})"); await W(500)
        print('arrival toast:', (await pg.locator('#toast').inner_text()).replace('\n',' | '))
        print('tab badge:', await pg.locator('#dock [data-tab=friends] .tab-badge').inner_text(), '| inbox rows:', await pg.locator('[data-gift]').count())
        await pg.screenshot(path='shots/r3-inbox.png')
        await pg.click('[data-gift=g1]'); await W()
        print('gift sheet NEW badges:', await pg.locator('.sheet .badge').all_inner_texts())
        await pg.screenshot(path='shots/r4-gift.png')
        await pg.click('#gAdd'); await W(800)
        print('after add: view', await pg.evaluate("[state.tab, state.views.workouts]"), '| plans:', await pg.evaluate("data.plans.map(p=>p.name)"))
        print('workouts:', await pg.evaluate("data.workouts.map(w=>w.name)"))
        print('exercises:', await pg.evaluate("data.exercises.map(e=>e.name+(e.video?'[v]':''))"), '| cable fly video kept:', await pg.evaluate("(data.exercises.find(e=>e.name==='Cable fly')||{}).video"))
        print('new plan days:', await pg.evaluate("(()=>{const p=data.plans[data.plans.length-1]; return p.days.map(d=>d.workoutId?woById(d.workoutId).name:'rest')})()"))
        print('gift status in db:', await pg.evaluate("__db.get('gifts/g1').status"))
        # 5. decline
        await pg.evaluate("__put('gifts/g2', {from:'u3',to:'u1',fromName:'Ben',toName:'Lukas',kind:'workout',name:'Legs',payload:{name:'Legs',items:[{ex:{name:'Squat'},sets:5}]},status:'pending',u:Date.now()})"); await W(400)
        await pg.click('[data-tab=friends]'); await W()
        await pg.click('[data-gift=g2]'); await W(); await pg.click('#gDecline'); await W(500)
        print('declined status:', await pg.evaluate("__db.get('gifts/g2').status"), '| inbox now:', await pg.locator('[data-gift]').count(), '| badge:', await pg.locator('#dock .tab-badge').count())
        # 6. status shows on sender side: Anna marks the workout gift added
        wid = await pg.evaluate("[...__db.entries()].find(([k,v])=>k.startsWith('gifts/')&&v.from==='u1'&&v.kind==='workout')[0]")
        await pg.evaluate(f"(()=>{{ const d=__db.get('{wid}'); __put('{wid}', {{...d, status:'added'}}); }})()"); await W(300)
        await pg.click('[data-friend=u1_u2]'); await W(900)
        print('sender sees badges:', await pg.locator('.badge').all_inner_texts())
        print('errors', errs)
        await b.close()
asyncio.run(main())

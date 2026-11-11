import asyncio
from playwright.async_api import async_playwright
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        errs=[]
        for theme in ['dark','light']:
            pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2, has_touch=True)
            pg.on('pageerror', lambda e: errs.append(str(e)))
            W=lambda t=450: pg.wait_for_timeout(t)
            await pg.goto('http://localhost:8765/'); await pg.evaluate("localStorage.clear()"); await pg.reload(); await W(300)
            await pg.evaluate(f"data.settings.theme='{theme}'; applyTheme(); data.exercises.push({{id:'db',name:'DB Bench',track:['weight','reps'],instructions:'',video:''}},{{id:'x',name:'Row',track:['weight','reps'],instructions:'',video:''}}); const t=ensureDay(todayKey()); t.items=[{{exId:'db',sets:2}},{{exId:'x',sets:2}}]; save(); go('log',{{logExId:'db'}})")
            await W()
            await pg.tap('.setrow >> nth=0 >> .w'); await W()
            print(theme,'pad open:', await pg.locator('#numpad.on').count(), '| focused element:', await pg.evaluate("document.activeElement.tagName"))
            await pg.screenshot(path=f'shots/np-{theme}.png')
            for k in ['2','2','.','5']: await pg.tap(f'#numpad [data-k="{k}"]')
            await pg.tap('#numpad [data-k="plus"]')
            print(theme,'weight:', await pg.locator('.setrow >> nth=0 >> .w').input_value())
            await pg.tap('#numpad [data-k="next"]')
            print(theme,'now on:', await pg.evaluate("[np.i, np.field]"))
            await pg.tap('#numpad [data-k="1"]'); await pg.tap('#numpad [data-k="0"]')
            await pg.tap('.setrow >> nth=0 >> .check'); await W()
            print(theme,'logged:', await pg.evaluate("JSON.stringify(data.sets.map(s=>[s.weight,s.reps]))"), '| pad moved to', await pg.evaluate("np && [np.i, np.field]"))
            print(theme,'set 2 prefilled:', await pg.locator('.setrow >> nth=1 >> .w').input_value(), await pg.locator('.setrow >> nth=1 >> .r').input_value())
            await pg.screenshot(path=f'shots/np2-{theme}.png')
            # edit a finished set
            await pg.tap('.setrow >> nth=0 >> .r'); await pg.tap('#numpad [data-k="8"]'); await pg.tap('#numpad [data-k="done"]'); await W()
            print(theme,'edited done set:', await pg.evaluate("data.sets[0].reps"), '| pad closed:', await pg.locator('#numpad.on').count()==0)
            # tap outside closes
            await pg.tap('.setrow >> nth=1 >> .w'); await W(200); await pg.tap('.large-title'); await W()
            print(theme,'outside tap closes:', await pg.locator('#numpad.on').count()==0)
            # keyboard
            await pg.tap('.setrow >> nth=1 >> .w'); await pg.keyboard.type('30'); await pg.keyboard.press('Enter'); await pg.keyboard.type('6')
            print(theme,'hardware keys:', await pg.locator('.setrow >> nth=1 >> .w').input_value(), await pg.locator('.setrow >> nth=1 >> .r').input_value())
            await pg.keyboard.press('Escape'); await W()
            await pg.close()
        print('errors', errs); await b.close()
asyncio.run(main())

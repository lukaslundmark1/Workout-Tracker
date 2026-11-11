"""Finger gestures with simulated touches: pull down to close a screen and a sheet, swipe between exercises and days.

    python3 dev/test-gestures.py [port]
"""
import asyncio, sys
from playwright.async_api import async_playwright
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
SEED = open(__file__.rsplit('/', 1)[0] + '/screenshots.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]

async def drag(cdp, x0, y0, x1, y1, steps=12, hold=0):
    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': x0, 'y': y0}]})
    for i in range(1, steps + 1):
        await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': x0 + (x1 - x0) * i / steps, 'y': y0 + (y1 - y0) * i / steps}]})
        await asyncio.sleep(0.016)
    await asyncio.sleep(hold)
    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path='/usr/bin/google-chrome')
        ctx = await b.new_context(viewport={'width': 390, 'height': 844}, has_touch=True, is_mobile=True, service_workers='block')
        pg = await ctx.new_page(); errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto(f'http://localhost:{PORT}/'); await pg.wait_for_timeout(400)
        await pg.evaluate(SEED); await pg.wait_for_timeout(300)
        cdp = await ctx.new_cdp_session(pg)
        W = pg.wait_for_timeout
        # 1. pull down on an exercise page closes it
        await pg.evaluate("state.tab='today'; go('log',{logExId:'bp'})"); await W(700)
        await drag(cdp, 200, 300, 200, 650); await W(700)
        print('pull down log ->', await pg.evaluate("state.views.today"))
        # 2. a short pull springs back
        await pg.evaluate("go('log',{logExId:'bp'})"); await W(700)
        await drag(cdp, 200, 300, 200, 340, steps=6); await W(700)
        print('short pull stays ->', await pg.evaluate("state.views.today"))
        # 3. swipe left to the next exercise
        await drag(cdp, 330, 420, 40, 425, steps=10); await W(800)
        print('swipe to next exercise ->', await pg.evaluate("state.logExId"))
        await drag(cdp, 40, 420, 330, 425, steps=10); await W(800)
        print('swipe back ->', await pg.evaluate("state.logExId"))
        # 4. pull down a sheet closes it
        await pg.evaluate("go('day'); openSheet({type:'moveBack', k: dk(addDays(new Date(),1))})"); await W(700)
        box = await pg.evaluate("(()=>{const r=document.querySelector('#sheet .sheet').getBoundingClientRect(); return [r.left+r.width/2, r.top+30]})()")
        await drag(cdp, box[0], box[1], box[0], box[1] + 400); await W(700)
        print('pull down sheet ->', await pg.evaluate("state.sheet && state.sheet.type"))
        # 5. swipe the day
        before = await pg.evaluate("state.selected")
        await drag(cdp, 330, 500, 40, 505, steps=10); await W(800)
        print('swipe day ->', before, '→', await pg.evaluate("state.selected"))
        # 6. scrolling on a main tab still scrolls
        await pg.evaluate("state.tab='settings'; go('settings')"); await W(400)
        await drag(cdp, 200, 700, 200, 300, steps=10); await W(500)
        print('settings scrolled:', await pg.evaluate("window.scrollY") > 0)
        print('errors', errs)
        await b.close()
asyncio.run(main())

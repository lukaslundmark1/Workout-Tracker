# Fast swiping like Lukas does it (v0.30.2): catching a page while it glides, quick flicks in a row going on to further pages,
# flicking back, touching a gliding page (settles, no accidental tap), and the same on the exercise pages.
# Usage: python3 dev/test-swipe.py [port]   (serve the repo first)
import asyncio, re, sys, os
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
SEED = re.search(r'SEED = """(.*?)"""', open(os.path.join(os.path.dirname(__file__), 'screenshots.py')).read(), re.S).group(1)
from playwright.async_api import async_playwright
async def drag(cdp, x0, y0, x1, steps=6, dt=0.012, lift=True):
    await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': x0, 'y': y0}]})
    for i in range(1, steps + 1):
        await cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': x0 + (x1 - x0) * i / steps, 'y': y0}]}); await asyncio.sleep(dt)
    if lift: await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if os.path.exists('/usr/bin/google-chrome') else {}))
        ctx = await b.new_context(viewport={'width':390,'height':844}, has_touch=True, is_mobile=True, service_workers='block')
        pg = await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto(f'http://localhost:{PORT}/'); await pg.wait_for_timeout(400); await pg.evaluate(SEED); await pg.wait_for_timeout(500)
        await pg.evaluate("state.tab='today'; state.selected=todayKey(); state.weekStart=startOfWeek(new Date()); go('day')"); await pg.wait_for_timeout(900)
        cdp = await ctx.new_cdp_session(pg); sel = lambda: pg.evaluate("state.selected")
        t0 = await sel(); add = lambda n: pg.evaluate(f"dk(addDays(parse('{t0}'), {n}))")
        # A: two quick flicks to the left -> two days on, no redraw in between
        await drag(cdp, 330, 500, 120); await pg.wait_for_timeout(120)
        mid = await sel()
        await drag(cdp, 330, 500, 120); await pg.wait_for_timeout(900)
        print('A two quick flicks left :', await sel() == await add(2), '| not redrawn mid-glide:', mid == t0)
        # B: flick left, catch it, flick back right -> back where it started
        t1 = await sel()
        await drag(cdp, 330, 500, 120); await pg.wait_for_timeout(120)
        await drag(cdp, 120, 500, 330); await pg.wait_for_timeout(900)
        print('B left then back right  :', await sel() == t1)
        # C: flick left, then just touch the gliding page (no swipe) -> it settles, and the touch doesn't press a button
        await pg.evaluate("window.__clicked=0; document.addEventListener('click', e => { if (e.target.closest('#addEx')) __clicked++; }, true)")
        t2 = await sel()
        await drag(cdp, 330, 500, 120); await pg.wait_for_timeout(100)
        box = await pg.evaluate("(()=>{const r=document.querySelector('#addEx').getBoundingClientRect(); return [r.left+r.width/2, r.top+r.height/2]})()")
        await cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': 200, 'y': box[1]}]}); await asyncio.sleep(0.05)
        await cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []}); await pg.wait_for_timeout(900)
        print('C touch a gliding page  : settled on', 'next day' if await sel() == await pg.evaluate(f"dk(addDays(parse('{t2}'),1))") else await sel(), '| pressed a button by accident:', await pg.evaluate("__clicked") > 0, '| view:', await pg.evaluate("state.views.today"))
        # D: a normal tap afterwards still works
        await pg.wait_for_timeout(500); await pg.tap('#addEx'); await pg.wait_for_timeout(900)
        print('D normal tap still works:', await pg.evaluate("state.views.today") == 'picker')
        # E: exercise pages: two quick flicks
        await pg.evaluate("go('day'); state.selected=todayKey(); go('log',{logExId:'bp'})"); await pg.wait_for_timeout(900)
        await drag(cdp, 330, 190, 60); await pg.wait_for_timeout(100); await drag(cdp, 330, 190, 60); await pg.wait_for_timeout(900)
        print('E two flicks on exercises: now on', await pg.evaluate("exById(state.logExId).name"))
        print('errors', errs); await b.close()
asyncio.run(main())

# Motion regressions Lukas found on his iPhone (v0.30):
#  1. after switching tabs, opening a screen must still slide up (a leftover tab animation used to make it instant)
#  2. tapping a chip inside an open sheet must not replay its slide-in or jump it back to the top
# Usage: python3 dev/test-motion.py [port]   (serve the repo first)
import asyncio, sys
from playwright.async_api import async_playwright
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
SEED = open(__file__.rsplit('/', 1)[0] + '/screenshots.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]
SLIDE = """() => new Promise(res => { const out = []; const t0 = performance.now(); go('log', { logExId: 'bp' });
  const f = () => { const t = performance.now() - t0; out.push(Math.round(app.getBoundingClientRect().top)); if (t < 150) requestAnimationFrame(f); else res(out); }; requestAnimationFrame(f); })"""
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        pg = await b.new_page(viewport={'width': 390, 'height': 844}); errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto(f'http://localhost:{PORT}/'); await pg.wait_for_timeout(400); await pg.evaluate(SEED); await pg.wait_for_timeout(600)
        await pg.click('#dock button[data-tab="workouts"]'); await pg.wait_for_timeout(600)
        await pg.click('#dock button[data-tab="today"]'); await pg.wait_for_timeout(600)
        tops = await pg.evaluate(SLIDE)
        print('slide-up after switching tabs:', 'ok' if max(tops) > 200 else f'INSTANT {tops}')
        await pg.evaluate("go('day'); state.tab='exercises'; go('eList'); openSheet({type:'exForm', exId:null, name:''})"); await pg.wait_for_timeout(900)
        await pg.evaluate("document.querySelector('#sheet .sheet').scrollTop = 160")
        await pg.click('[data-fe="barbell"]'); await pg.wait_for_timeout(40)
        r = await pg.evaluate("(()=>{const s=document.querySelector('#sheet .sheet'); return [s.scrollTop, getComputedStyle(s).animationName]})()")
        print('sheet after tapping a chip:', 'ok' if r == [160, 'none'] else f'JUMPED scroll={r[0]} animation={r[1]}')
        print('errors', errs); await b.close()
asyncio.run(main())

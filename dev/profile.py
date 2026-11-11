"""CPU profile of one step with the heavy dataset: lists the functions that take the most time.

    python3 dev/profile.py "<setup js>" "<timed js>" [port]
"""
import asyncio, sys, collections
from playwright.async_api import async_playwright

SEED = open(__file__.rsplit('/', 1)[0] + '/perf.py').read().split('SEED = """', 1)[1].split('"""', 1)[0]

async def main(setup, js, port):
    async with async_playwright() as p:
        b = await p.chromium.launch(**({'executable_path': '/usr/bin/google-chrome'} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        ctx = await b.new_context(viewport={'width': 390, 'height': 844}, has_touch=True, service_workers='block')
        pg = await ctx.new_page()
        await pg.goto(f'http://localhost:{port}/'); await pg.wait_for_timeout(400)
        await pg.evaluate(SEED); await pg.evaluate("toast=()=>{}")
        cdp = await ctx.new_cdp_session(pg)
        await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', {'interval': 100})
        if setup: await pg.evaluate(f"(()=>{{ {setup} }})()")
        await cdp.send('Profiler.start')
        for _ in range(5):
            await pg.evaluate(f"(()=>{{ {setup}; {js}; void document.body.offsetHeight; }})()")
        prof = (await cdp.send('Profiler.stop'))['profile']
        nodes = {n['id']: n for n in prof['nodes']}
        self_t = collections.Counter()
        dt = prof['timeDeltas']
        for i, sid in enumerate(prof['samples']):
            n = nodes[sid]; cf = n['callFrame']
            self_t[f"{cf['functionName'] or '(anon)'} :{cf['lineNumber'] + 1}"] += dt[i] if i < len(dt) else 0
        # inclusive time
        parent = {}
        for n in prof['nodes']:
            for c in n.get('children', []): parent[c] = n['id']
        incl = collections.Counter()
        for i, sid in enumerate(prof['samples']):
            seen = set(); x = sid
            while x is not None:
                cf = nodes[x]['callFrame']; key = f"{cf['functionName'] or '(anon)'} :{cf['lineNumber'] + 1}"
                if key not in seen: incl[key] += dt[i] if i < len(dt) else 0; seen.add(key)
                x = parent.get(x)
        tot = sum(dt)
        print(f'total {tot/1000:.0f} ms\nSELF')
        for k, v in self_t.most_common(14): print(f'  {v/1000:7.1f}  {k}')
        print('INCLUSIVE')
        for k, v in incl.most_common(22): print(f'  {v/1000:7.1f}  {k}')
        await b.close()

asyncio.run(main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8765))

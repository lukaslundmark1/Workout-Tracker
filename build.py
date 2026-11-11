#!/usr/bin/env python3
"""Prepare the app for deploying. Run from the repo folder:  python3 build.py

- Stamps app.js with a content hash (index.html loads app.js?v=<hash>), so phones never mix
  an old script with a new page, and lists it in sw.js for offline use.
- Checks the Firebase bundle file referenced by app.js exists and is listed in sw.js.
- Checks the Content-Security-Policy is still in index.html (it blocks any script that isn't the app's own).
- Bumps the service worker cache name so installed apps pick up the new version (run it once per deploy).
"""
import hashlib, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent
index, sw, app = root / 'index.html', root / 'sw.js', root / 'app.js'
html, sws, js = index.read_text(), sw.read_text(), app.read_text()

v = hashlib.sha256(js.encode()).hexdigest()[:10]
html, n = re.subn(r'<script src="app\.js(\?v=[0-9a-f]+)?"></script>', f'<script src="app.js?v={v}"></script>', html)
if n != 1:
    sys.exit('index.html must contain exactly one <script src="app.js..."></script>')
if '<script>' in html:
    sys.exit('index.html has an inline <script>; the Content-Security-Policy would block it. Put code in app.js.')
if 'http-equiv="Content-Security-Policy"' not in html:
    sys.exit('The Content-Security-Policy meta tag is missing from index.html.')

fb = re.search(r"import\('\./(firebase-[0-9a-f]+\.js)'\)", js)
if not fb or not (root / fb.group(1)).exists():
    sys.exit('app.js must import an existing ./firebase-<hash>.js bundle')

assets = ["'./'", "'./index.html'", f"'./app.js?v={v}'", "'./manifest.webmanifest'", "'./icon-192.png'",
          "'./icon-512.png'", "'./apple-touch-icon.png'", f"'./{fb.group(1)}'"]
sws, n = re.subn(r'const ASSETS = \[[^\]]*\];', 'const ASSETS = [\n  ' + ',\n  '.join(assets) + ',\n];', sws)
if n != 1:
    sys.exit('sw.js: ASSETS list not found')
m = re.search(r"const CACHE = 'tt-v(\d+)';", sws)
if not m:
    sys.exit('sw.js: CACHE name not found')
sws = sws.replace(m.group(0), f"const CACHE = 'tt-v{int(m.group(1)) + 1}';")   # every build: installed apps pick up any change

index.write_text(html)
sw.write_text(sws)
print(f'app.js?v={v}  ·  {fb.group(1)}  ·  {re.search(r"tt-v\d+", sws).group(0)}')

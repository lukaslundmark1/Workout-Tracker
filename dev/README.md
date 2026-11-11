# Dev tools (not used by the app)

Testing helpers for working on the app. Needs Python + Playwright and Chrome (`/usr/bin/google-chrome`).

## Two local servers
```
# 1) the real app (no cloud) on :8765
python3 -m http.server 8765            # run from the repo root
# 2) the app with a fake in-memory Firebase on :8767
mkdir -p /tmp/mock && cp index.html app.js sw.js manifest.webmanifest *.png /tmp/mock/
cp dev/mock-firebase.js /tmp/mock/firebase-<hash>.js   # same name app.js imports
(cd /tmp/mock && python3 -m http.server 8767)
```
The mock signs `lukas@x.com` (password `secret1`) in as uid `u1`. In the page you can call
`__put(path, data)`, `__del(path)` and read `__db` (a Map) to play another user (e.g. `links/u1_u2`, `gifts/g1`).

## Scripts
- `crawl.py`: opens every screen and every sheet in light and dark, reports any error. **Run before every push.**
  Only expected line: `log redirected to day`.
- `scan.js`: `node dev/scan.js` (needs `npm i acorn acorn-walk`), lists identifiers used but never declared / declared but unused.
- `screenshots.py <tag> light,dark`: screenshots of all main screens with realistic seeded data into `shots/`.
- `test-send.py`: end-to-end sending/receiving of workouts and plans (mock server).
- `test-schedule.py`: Upper/Lower plan scenarios for "Move back a day".

Background servers get killed between turns in Claude sessions; start them in the same command as the test.

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
Set `window.__failCommit = true` to make batch writes fail like a rules rejection (tests the sync retry).

## Scripts
- `crawl.py`: opens every screen and every sheet in light and dark, reports any error. **Run before every push.**
  Only expected line: `log redirected to day`.
- `scan.js`: `node dev/scan.js` (needs `npm i acorn acorn-walk`), lists identifiers used but never declared / declared but unused.
- `screenshots.py <tag> light,dark`: screenshots of all main screens with realistic seeded data into `shots/`.
- `test-send.py`: end-to-end sending/receiving of workouts and plans (mock server).
- `test-schedule.py`: Upper/Lower plan scenarios for "Move back a day".
- `test-numpad.py`: the number pad (typing, ±, Next, ticking, editing a done set, hardware keys).
- `test-gestures.py [port]`: simulated finger drags: pull down to close a screen and a sheet, swipe exercises and days.

## Performance tools
- `perf.py [port] [throttle] [days]`: seeds ~2 years of training (10,000 sets; `days` sets how much), then times every
  main screen and the common actions with a 4x slower CPU, plus startup. Run it before and after a change.
- `profile.py "<setup js>" "<timed js>"`: CPU profile of one step with the same data (which functions take the time).
- `difftest.py OLD_PORT NEW_PORT`: serve the previous version (`git show HEAD:app.js` etc. into a folder) on one port and
  the working copy on another; compares every screen's HTML, the plan schedule and day labels for 3 datasets.
  Use it after any refactor that shouldn't change what the app shows.
- `fuzz-schedule.py OLD_PORT NEW_PORT [steps]`: hundreds of random plan moves/ticks/undos in both versions, comparing
  the schedule after each step.

## Performance rules (v0.26)
- Look sets up through the index (`setsOf`, `setsOn`, `hasSets`, `exSets`, `exDates`, `prevDateOf`), never by
  filtering `data.sets`. Add sets with `push`, remove them by making a new array; that's what keeps the index valid.
- Sets are stored per month (`tt.v1s.YYYY-MM`); `tt.v1` holds the rest. Only months that changed are rewritten.
- Redraws triggered by sync/sign-in/friends go through `bgRender()` (waits for fingers, scrolling and transitions).
- Long lists are drawn in chunks (history) or use `content-visibility` (database).
- The plan schedule is cached by a fingerprint of what it reads (`schedSigNow`); if it starts reading something new,
  add that to the fingerprint.

Set fields are readonly (the app has its own number pad), so Playwright `.fill()` on `.w`/`.r` fails. Set them with
`loc.evaluate("(e,v)=>{e.value=v;e.dispatchEvent(new Event('input'))}", "80")` or tap the pad keys `#numpad [data-k="8"]`.

Background servers get killed between turns in Claude sessions; start them in the same command as the test.

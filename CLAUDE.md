# Training tracker: instructions for Claude Code

Read this first, then `docs/DECISIONS.md` (the full feature and design history; every "why" is there) and `dev/README.md` (test tools and performance rules).

This project was built in claude.ai sessions up to v0.26 and moved to Claude Code on 2026-11-11. Everything you need is in this repo; nothing from those sessions (project docs, preview page) carries over.

## What this is
A workout tracker and planner for **Lukas** (the owner), his girlfriend and friends, made to look and feel like a native Apple app. **Since 2026-11-11 it is iOS first:** the main way Lukas uses it is the native iPhone app in `native/` (which loads this same web app); the web/PWA version comes second. Design, test and judge every change for the iPhone app first. Plain JavaScript with no framework and no npm dependencies for the app itself. The only build step is `build.py`. The backend is a free Firebase project.

- Repo: `lukaslundmark1/Workout-Tracker`, branch `main`, every file at the root. Pushing to `main` deploys it.
- Live site (GitHub Pages): https://lukaslundmark1.github.io/Workout-Tracker/
- Current version: **v0.30.1** (`APP_VERSION` in app.js). Bump it for every release Lukas will notice.
- Firebase project `workout-tracker-705ae`, free Spark plan. Auth is Google + email/password; Firestore is in europe-north1. Lukas changes console settings himself. Tell him exactly what to click.

## How Lukas works (important)
- **He doesn't read code.** Reply in plain language and keep it short. Say what changed and what he needs to do. Don't describe code.
- **He wants a say in features and UI.** Ask before any big UX decision and offer concrete options. Small things and bug fixes he reports: just do them.
- **Pushing:** bug fixes and small requested changes have been pushed directly. For bigger features, or whenever he says "don't push until I approve", let him try it locally first (see "Letting Lukas try a change") and push only after he says so.
- He tests on his **iPhone in dark mode**, using the installed app. After a push he fully closes and reopens it. Since v0.26 it may also reload itself a second or two after opening. He sends screenshots of problems.
- **He rejects over-engineering.** Things removed at his request: plate calculator, keep-screen-on, countdown rest timer (replaced by a stopwatch that counts up), Exercises section on profiles, an end-of-workout page. Scheduling took three tries; the current design is the one he accepted. Don't bring removed things back.
- He wants it to feel native, not "websitey". That's why the app has its own number pad (iOS adds a toolbar and AutoFill to web inputs), spring animations and haptics.
- Commit messages: short summary line like `v0.27: <what>`, then bullet points.

## Files
- `index.html`: the page, all the CSS, and the Content-Security-Policy meta tag. **No inline `<script>` and no `onclick=""`**, because the CSP blocks them. All code lives in app.js.
- `app.js`: all the code (~3,700 lines, one classic script). Rough order:
  1. storage (sets are saved per month)
  2. dates (memoised formatters)
  3. helpers and the **set index `ix()`**
  4. icons
  5. state, `render()`, `bgRender()`, `go()`, `ghost()` (screen transitions)
  6. the polish layer (glass top bar, count-up numbers)
  7. tab bar
  8. Today tab
  9. exercise log page
  10. number pad (state `np`)
  11. PRs, toasts, rest stopwatch
  12. workout summary
  13. `swipePager`
  14. timer and Finish
  15. picker and calendar
  16. progress, history and chart
  17. Exercises tab
  18. plans and scheduling (`planSchedule`, `moveBack`)
  19. Workouts tab
  20. cloud sync (`COLS`, `syncOps`, `pushChanges`)
  21. settings
  22. friends
  23. gifts (sending workouts and plans)
  24. security (`clean*` sanitizers, delete account)
  25. profiles
  26. exercise database
  27. pull-to-close
  28. sheets
  29. boot
- `firebase-346e04e6.js`: the Firebase web SDK bundled with esbuild. If you rebuild it, give it a new content-hash filename, update the `import('./firebase-….js')` in app.js, and delete the old file. A stale cached copy once caused "fb.getDoc is not a function".
- `sw.js`: the service worker. The app page is served **cache-first** from the current cache, so launch is instant and works offline. A new deploy changes sw.js, which then installs in the background. app.js reloads into the new version only if no one has touched the app yet.
- `firestore.rules`: security rules. **They only take effect when Lukas pastes them into Firebase console → Firestore → Rules → Publish.** Whenever you change them, tell him to do that, step by step. He confirmed on 2026-11-11 that the current rules are published.
- `build.py`: **run `python3 build.py` once before every commit that changes app.js, index.html or sw.js.** It stamps `app.js?v=<hash>` into index.html, rewrites the file list in sw.js, bumps the cache name so installed apps update, and checks the CSP is still there.
- `dev/`: test tools that aren't part of the app (details in `dev/README.md`).
- `native/`: the iPhone app shell (Capacitor) that loads the live site; Lukas builds it in Xcode on his MacBook and re-runs it weekly (free Apple ID). See `native/README.md`. In app.js, native-only behaviour is behind `NATIVE`; the web app must keep working without it. If you change anything in `native/`, tell Lukas to run `npx cap sync ios` and rebuild.

## Rules that keep things working
- **Logged sets:** always look them up through the index: `setsOf(exId, day)`, `setsOn(day)`, `hasSets(day)`, `exSets(exId)`, `exDates(exId)`, `prevDateOf(exId, day)`. Never filter `data.sets` in screen code. Add sets with `data.sets.push(...)`. Remove sets by assigning a new array (`data.sets = data.sets.filter(...)`). Never splice or reorder in place. Editing weight or reps of an existing set in place is fine.
- **Saving:** call `save()` after changing data. It saves on the phone and schedules a cloud sync.
- **Storage format:** `tt.v1` holds everything except sets (`sets: []` plus `setMonths`). Each month's sets live in `tt.v1s.YYYY-MM`. Old saves with sets inside tt.v1 still load. Don't break either format: people's training data is on their phones.
- **Background redraws:** anything that redraws because of sync, sign-in or friends must call `bgRender()`, not `render()`. It waits until no finger is on the screen and nothing is scrolling or animating.
- **Plan schedule:** it's cached by a fingerprint of what it reads (`schedSigNow`). If you make `planSchedule()` depend on something new, add that to the fingerprint.
- **Outside data:** anything from friends, the shared database, received gifts or imported backups goes through the `clean*` sanitizers, and all text shown is passed through `esc()`. If you add an outside service, it must be allowed in the CSP.
- **Editing app.js:** make targeted edits. Never do wide cut ranges or blind regex renames. One over-wide edit deleted helper functions and crashed the Plans tab (v0.21), and a rename once changed text in the UI.
- **Look and feel:** keep the iOS look. Movement uses the weighted springs `var(--ease-screen|sheet|soft)` with `var(--dur-…)` (see DECISIONS → Motion; app.js timeouts must match), nothing should change instantly, and actions get a `haptic(kind)` ('select', 'impact', 'success', 'warn', 'error'). Glass floating controls, and respect reduced motion. Colours: blue = actions, red = destructive/today/badges, green = done/active, orange = personal records.

## Testing
Needs Python 3 with Playwright and Node (for `dev/scan.js`). The dev scripts use Chrome at `/usr/bin/google-chrome` if it's there, otherwise Playwright's own Chromium:
```
pip install playwright && playwright install chromium
cd /tmp && npm i acorn acorn-walk          # for dev/scan.js (run it with NODE_PATH=/tmp/node_modules)
```
If these aren't installed yet, tell Lukas what you're installing and why (he may need to approve).
Before every push:
1. `node --check app.js` and `node dev/scan.js` (lists undeclared or unused names).
2. `python3 build.py`
3. Serve the repo (`python3 -m http.server 8765`) and run `python3 dev/crawl.py`. It opens every screen and sheet in light and dark mode. The only expected output is `log redirected to day`.
4. Run the scenario tests that match the change: `test-numpad.py`, `test-schedule.py`, `test-send.py` (needs the mock server on 8767, see dev/README), `test-gestures.py`.
5. For refactors, serve the previous version (`git show HEAD:app.js` etc. into a temp folder) on another port and run `python3 dev/difftest.py OLD_PORT 8765`. It compares every screen with the same data. `dev/perf.py` measures speed and `dev/fuzz-schedule.py` stress-tests plan scheduling.
6. Take screenshots (`dev/screenshots.py`) and actually look at them, in light and dark.

Start the local servers in the same command as the tests if your shell kills background processes. Make sure no old server is still holding the port, or you'll be testing stale files.

## Letting Lukas try a change before it goes live
The claude.ai sessions used a preview page; that doesn't exist here. Instead, serve the repo on this machine (`python3 -m http.server 8765 --bind 0.0.0.0`) and give him `http://<this computer's local IP>:8765` to open in Safari on his iPhone, on the same Wi-Fi. Sign-in won't work there, because only the github.io domain is authorised in Firebase, but everything else does. If he wants to test on the real installed app, push and he reopens it.

## Open items and ideas he hasn't decided on
- Ask how v0.26 (the big performance update) feels on his iPhone: opening, swiping between exercises, ticking sets.
- Not confirmed: the admin doc `admins/<his uid>` in Firestore (lets him remove anyone's shared database entries), and the account hardening steps (2-step verification on Google and GitHub, restricting the Firebase API key to the github.io site, etc.; see DECISIONS.md → Security).
- Coaching switch: a friend can add workouts to your calendar (per-friend permission, off by default).
- Muscle-group filter or labels on his own Exercises list.
- More tracking types (time, distance, bodyweight).
- What friends can see (body weight later?).

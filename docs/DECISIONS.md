# Training tracker: decisions log

The feature and design history, with the reasons. See `CLAUDE.md` (repo root) for how to work on the project and how Lukas likes to work. Add new decisions here as you make them.

## Platform
- PWA (installable web app). Works on iPhone (Safari → Add to Home Screen) and Android (Chrome → Install app).
- Code: GitHub repo `lukaslundmark1/Workout-Tracker`, branch `main`, all files at the repo root. Pushing to main deploys to GitHub Pages: `https://lukaslundmark1.github.io/Workout-Tracker/`.
- Backend: **Firebase project `workout-tracker-705ae`, free Spark plan** (free for two people, never pauses).
  - Auth: Google + email/password. Email-link sign-in is enabled in the console but not used.
  - Authorised domain: `lukaslundmark1.github.io`. Firestore is in europe-north1.
  - **Security rules live in the repo as `firestore.rules`.** Lukas pastes them into Firebase console → Firestore → Rules → Publish whenever they change. He confirmed on 2026-11-11 that the latest rules are published.
  - Admin = a doc `admins/<user id>`, created by hand in the console. It lets that account remove anyone's shared database entries. Not confirmed whether Lukas has created it.
  - Firebase web SDK bundled locally as **`firebase-<hash>.js`** (currently `firebase-346e04e6.js`).
  - Sign-in, sync and friends were confirmed working with a real friend on 2026-11-10.
- Data on the device:
  - **Since v0.26, `tt.v1` holds everything except the sets** (`sets: []`, plus `setMonths: ['YYYY-MM', …]`). Each month's sets are in `tt.v1s.YYYY-MM`. Older saves (sets inside tt.v1) still load and are split on the next save. Write order is months → tt.v1 → remove stale months, so a failure part-way never loses data.
  - `exercises: [{id, name, track, instructions, video, lib?, muscle?, equip?}]`
  - `workouts: [{id, name, items: [{exId, sets}]}]`
  - `days: { 'YYYY-MM-DD': { items, workouts: [{id, name}], plan?: {id, index}, pinned?, rest?, absorb?, session?: {start, end?} } }`
  - `sets: [{id, exId, date, slot, weight (kg), reps, ts}]`. **Only ticked sets are logged.**
  - `plans: [{id, name, weeks (0 = ongoing), days: [{workoutId | null}]}]`
  - `activePlan: {planId, begin, start} | null` (old `shifts` from v0.17 and earlier are ignored since v0.19)
  - `settings: {units, theme, weekStart, defaultSets, name, code}`
  - Other keys: `tt.lib` = cached copy of the shared database; `tt.rest` = running rest stopwatch (device only); `tt.sync.<uid>` = sync bookkeeping (includes `from`, see Performance); `tt.owner` = which account owns the data on this device.

## Build and deploy
- **Files (since v0.23):** `index.html` (page + CSS + Content-Security-Policy), `app.js` (all code; never inline `<script>` or `onclick=""`), `firebase-<hash>.js`, `sw.js`, `firestore.rules`, `build.py`.
- **Before every deploy, run `python3 build.py`.** It stamps `app.js?v=<hash>` into index.html, rewrites the sw.js ASSETS list, bumps `CACHE` on every run, and checks the CSP is present. v0.26 shipped as `tt-v36`, `app.js?v=24121872da`, commit `6bb9b86`.
- Before pushing, run the screen crawl (`dev/crawl.py`). It caught a v0.21 crash where an over-wide edit deleted helpers.
- Whenever the Firebase bundle changes, rebuild it with esbuild and **give it a new content-hash name**. Update the import in app.js and delete the old file.
- **Service worker (v0.26):**
  - The app page is served **cache-first from the service worker's own cache**: instant launch, no network wait, works offline. Other files are cache-first too.
  - A new deploy means a new sw.js, which installs in the background (skipWaiting + clients.claim).
  - app.js reloads into the new version automatically if the update lands within 20 s of opening, before the first tap, and with no sheet or number pad open. Otherwise the new version is used at the next launch.
  - `registration.update()` runs whenever the app comes back to the foreground.
  - Before v0.26 the page was network-first, so every launch waited on the network.

## Performance (v0.26)
Lukas asked on 2026-11-11 for a full performance and native-feel pass. Measured with `dev/perf.py`: 2 years of data (about 10,000 sets), CPU slowed 4x. Milliseconds until the frame is drawn, before → after:

| Screen or action | Before | After |
|---|---|---|
| History | 355 | 32 |
| Exercise detail | 331 | 35 |
| Tick a set | 91 | 35 |
| Save | 57 | 16 |
| Open exercise | 58 | 26 |
| Switch tab | 76 | 46 |
| Today | 47 | 22 |
| Database | 84 | 49 |
| Move-back sheet | 60 | 30 |
| Sync check | 73 | 38 |

With two months of data, most things are 1.3–2x faster and the move-back sheet is 8x faster.

What changed:
- **Set index `ix(src)`:** Maps by exercise, by day and by exercise+day, plus each exercise's dates. Helpers: `setsOf`, `setsOn`, `hasSets`, `exSets`, `exDates`, `prevDateOf`. The index stays valid while it's the same array with the same length; sets added with push are slotted in incrementally. Rule: add sets with push, remove them by making a new array. Editing weight or reps in place is fine.
- **Dates:** formatters are made once (Intl.DateTimeFormat) and each day's text is memoised; month names are precomputed; `dk()` is faster.
- **Plan schedule cache:** cached by a fingerprint of what it reads (`schedSigNow`): today, the plan, which workouts exist, and each stored day's rest/pinned/plan/workouts/trained markers. The fingerprint is computed once per task. The walk through past days is kept (`pastWalk`), so changes from today on only redo the future. Verified identical to v0.25 with `dev/difftest.py` and 1,200 random steps of `dev/fuzz-schedule.py`.
- **Saving:** sets are stored per month (see above), and only months that changed are rewritten. Change detection compares object identity plus weight/reps/slot, with no stringify.
- **Sync:**
  - A set's hash is remembered until its weight, reps or slot changes.
  - Sync bookkeeping is written 1.5 s later; it's flushed when the app is hidden or the user signs out, and cancelled on wipe.
  - Unsynced changes are sent immediately when the app is hidden.
  - **The listener query is stable between launches** (`cloud.sync.from`, which moves on about once a month). Firestore can then answer from its last result plus what changed, instead of reading every cached record from IndexedDB at every launch.
- **Firebase start:** it loads just after the first frame, at a moment no finger or scroll is active (2 s at most).
- **History:** drawn 12 cards at a time, with more added as you scroll near the end (IntersectionObserver). Redrawing the same screen keeps the number already shown.
- **Chart:** colours are CSS variables in style attributes (no getComputedStyle). The halo on the latest point pulses 3 times instead of forever.
- **`bgRender()`:** redraws triggered by sync, sign-in, friends or the shared database wait until no finger is down, there's been no scroll for 150 ms, no screen transition is running and the number pad is closed. Several requests become one redraw.
- **Smaller redraws:** the tab bar is only redrawn when the tab or the badge changes. The number pad only updates the number while you type.
- **Swipes:** the swipe pager builds the neighbouring pages ahead of time, while nothing is moving, so a swipe starts on its first frame.
- **Screen transitions:** the transition snapshot (`ghost`) only copies what's on screen and is a screen-sized window (`contain: strict`). Its top bar stays sticky.
- **Scrolling:** pull-to-close's non-passive touchmove handler is only attached on deeper screens and open sheets, so the main tabs scroll without waiting for JavaScript.
- **CSS:**
  - `html { touch-action: manipulation }`: no double-tap zoom delay.
  - No text selection or iOS callout on buttons, cells, chips, the week strip, the number pad, etc.
  - Glass controls that sit in the page (move buttons, set stepper) use the solid colour the blur would give (`--glass-solid`).
  - Hidden glass layers (the scrolled-header bar at the top, the toast, the rest pill) are `visibility: hidden`, so nothing is blurred while they're off screen.
  - `:has()` rules were replaced with body classes `has-pdots` and `rest-on`.
  - `content-visibility: auto` on history cards and database rows.
- **Bug fixed while testing:** count-up numbers could flash a negative value for one frame.
- **Ideas not done:** minifying app.js (small gain, adds a build dependency); a launch image.

## Cloud sync design (v0.11)
- Local-first. Firestore paths: `users/{uid}/{exercises,workouts,days,sets,plans,meta}/{id}`. `meta/settings` holds the settings and the active plan. Each doc has a `u` (updated) time; deletes are tombstones.
- Push: diff each record's hash against what was last synced, send in batches, debounced 600 ms.
- Pull: listeners on `u > from` (stable, see Performance). Last writer wins per record.
- First sign-in merges the two copies; the account's copy wins on a clash. The data on a device belongs to one account (`tt.owner`).
- Known risk: Google popup sign-in may fail in the installed iPhone app. Email + password always works.

## Security (v0.23)
- **CSP meta:** `default-src 'self'; script-src 'self' https://apis.google.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' https://*.googleapis.com https://workout-tracker-705ae.firebaseapp.com; frame-src https://workout-tracker-705ae.firebaseapp.com https://accounts.google.com https://www.youtube-nocookie.com; worker-src 'self'; manifest-src 'self'; object-src 'none'; base-uri 'none'; form-action 'self'`. Any new outside service must be allowed here.
- **XSS fix:** friend data used to go into HTML unescaped. Now all outside data is cleaned on the way in (`cleanSet`, `cleanExercise`, `cleanDay`, `cleanBackup`, `cleanLibEntry`, gift import sanitizers) and numbers in set text are coerced.
- **Rules:** only app collections under `users/{uid}/{col}/{doc}`; field whitelists and length limits on codes, library, gifts and links; creating a link can only include the creator's own share switch.
- **Sign out sheet:** "Remove my training from this phone" (on by default, off when offline). It clears the local storage keys, including the per-month `tt.v1s.*` keys since v0.26, clears Firestore's IndexedDB cache, then reloads.
- **Settings → Delete account:** re-authenticates, then deletes users/{uid}/* docs, links, gifts to and from you, your library entries and your friend codes, then the Auth user, then wipes the device.
- Deleted records are overwritten with `{deleted, u}` tombstones; no data is kept.
- **Account-side steps recommended to Lukas (2026-11-11), not yet confirmed:** 2-step verification on Google and GitHub; restrict the Firebase API key to the github.io site; email enumeration protection; a password policy; disable the unused email-link sign-in; remove `localhost` from authorised domains; optionally App Check later.

## Design direction
- Heavily inspired by Apple: modern iOS look with a glass tab bar, round glass buttons, capsules, floating sheets and rounded numerals. Appearance setting: Auto / Light / Dark.
- Colours: blue = actions; red = destructive, today, badges, warnings; green = completed-set tick, finished, active, switches on, in progress; orange = personal records.
- Navigation: deeper screens slide up, and the back button is a down chevron. Pull down to close slid-up screens and sheets (not editors). Swipe horizontally between exercises; the page follows your finger and bounces at both ends. Page dots (exercises only), no arrows.
- **Feel (v0.20, "things should have weight"):**
  - iOS spring curve `cubic-bezier(.32,.72,0,1)` for screens, sheets and swipes; sheets slide away when closed.
  - Buttons press in fast and spring back; list rows highlight under the finger.
  - The tab bar selection and segmented-control thumbs slide; switches stretch while held; wheels curve like a drum.
  - Ticking a set pops and draws the check, with a light haptic.
  - The reduced-motion setting is respected.

## Polish pass (v0.24, approved by Lukas)
- The sticky top bar turns to glass with a compact centred title after you scroll past the large title. A gradient (`#dockfade`) fades content above the tab bar.
- Today: a progress ring per exercise, a thin workout progress bar, compact set text ("77.5 kg × 8, 7, 6 · 1 to go"), and empty/rest-day states with an icon.
- The week strip's selection capsule slides; switching tabs fades in with an icon pop; scroll position is remembered on back and per tab; tapping the active tab scrolls to the top.
- Chart: smooth monotone curve, draws in once per screen open, pulsing halo on the latest point (3 pulses since v0.26), haptic tick while scrubbing.
- Numbers count up when a screen opens; card shadow in light mode; gradient primary button; sheet grabber; shimmer skeletons while loading; History dates are relative ("Yesterday").

## Tab bar
- Friends | Workouts | **Today (centre)** | Exercises | Settings. The Friends tab shows a red count badge for incoming requests and gifts.

## Number pad (v0.25)
- The weight and reps fields are readonly inputs (`inputmode="none"`). Tapping one opens the app's own pad (`#numpad`, state `np`). Lukas chose this over just suppressing AutoFill. On 2026-11-11 he said "the number pad is alright".
- Header: "Set N" · a kg/Reps switch · Next (Reps › → Next set › → Done). Value row with −/+ steps (2.5 kg / 5 lb, 1 rep). Keys 1–9, "." (weight) or hide (reps), 0, delete.
- The first key replaces the value. Ticking a set moves the pad to the next set's weight. Editing a finished set saves when you leave the field.
- The tab bar slides away while the pad is open; tapping outside closes it. Hardware keyboards work.

## During a workout (v0.18)
- **Rest stopwatch** (counts up): starts when you tick a set of an exercise with **2 or more sets** and restarts on each ticked set. It turns off on that exercise's last set, on Finish, or with ✕. Today only. A countdown rest timer, a plate calculator and keep-screen-on were tried and **removed at Lukas's request**.
- **Personal records:** a day's best set (estimated 1RM, Wathan formula) that beats every earlier day. The first-ever session doesn't count. Shown as an orange "PR" with a "New personal record" toast.
- An "All planned sets done" toast appears when the last planned set of the day is ticked.

## Finishing a workout (v0.14 → v0.18)
- Only ticked sets are logged. There's no end-of-workout page.
- The timer and Finish belong to today only. The first set ticked today starts the timer. A workout left running on an earlier day is closed automatically at its last logged set.
- **Finish sheet:** "N sets logged · M not ticked", a switch "Log the M unticked sets as shown", and duration wheels.
- **Workout summary** after Finish: stats, PRs, and each exercise's best set with ▲/▼ % compared with last time.
- Tapping the finished timer opens a Duration sheet with **Resume workout** (today only).

## Today tab
- Swipe the day left or right for the previous or next day; it follows your finger with the neighbouring day peeking in. Crossing into another week moves the week strip.

## Day labels
- Under the date: the workout name(s), "Custom workout", "Rest day", "Rest day (moved)", "Nothing logged" or "No workout planned". A past day that was planned but not trained adds "· not trained".

## Plans and scheduling (v0.19.1, Lukas's third and accepted iteration)
- Workouts tab has a **Plans | Workouts** switch. A plan is an ordered rotation of workouts and rest days, lasting N weeks or ongoing. Only one plan is active.
- The schedule is computed by walking day by day from the plan start:
  - Rest days pass with time.
  - **A missed workout waits for you.**
  - Training the due workout moves the plan on.
  - Training a different plan workout does it early, and its next turn is skipped.
- **"Can't make it today" / "Move back a day"** opens a sheet with up to 3 choices, each with a 7-day preview:
  - **Just this workout**
  - **The rest of the week/round**
  - **Everything from here**

  Stored as `{rest: true, absorb: 'next' | 'round' | undefined}`. "Undo move" removes it.
- On a rest day: **"Do <next workout> today"** (stored as a `pinned` copy), with "Undo".
- Removing all exercises from today's or a future planned day yourself counts as moving it back with 'next'.
- Plan screen: the rotation with **Up next**, **Coming up** (next 10 days), and End plan. In the calendar and week strip, a ring = planned and a dot = trained.

## Exercise database (v0.17)
- 130 built-in exercises (ids `b:<normalized name>`). Shared entries are in Firestore `library/{id}` (ids `s:<doc id>`). Picking one copies it into your own exercises, linked with `lib`. Lukas (admin) can remove anything; people can remove their own.
- Muscle groups: Chest, Back, Shoulders, Arms, Legs, Glutes, Core, Full body. Equipment: Barbell, Dumbbell, Machine, Cable, Bodyweight, Kettlebell, Other.

## Friends (v0.13) and profiles (v0.16)
- No roles: each person controls their own share switch. The friend code is derived from the account id. Firestore: `codes/{CODE}`, `links/{uidA_uidB}`.
- Profiles show stats and the last 3 workouts → See all (by month) → workout detail → exercise graph and history. Friend data is cached for 1 minute and covers the last 4 months.

## Sending workouts and plans (v0.22)
- Firestore `gifts/{id}`: `{from, to, fromName, toName, kind, name, payload, status, u}`. Only friends can send; only the recipient can change the status; either side can delete.
- An Inbox sits at the top of the Friends tab; the gift sheet has Add / Decline. Everything received is sanitized.

## Next for friends
- A **"Can add workouts to my calendar"** switch per friend (off by default): the coaching mechanic.
- No push notifications on the free plan, only the in-app badge.

## Open questions
- Has the admin doc `admins/<uid>` been set up? Have the account hardening steps been done?
- Show muscle group / equipment on your own Exercises list, or filter it by them?
- Finish sheet: suggest the last set's time when the timer clearly ran far past it?
- More tracking options (time, distance, bodyweight, etc.)
- The Today tab icon looks similar to the calendar button.
- What friends can see (body weight later?)

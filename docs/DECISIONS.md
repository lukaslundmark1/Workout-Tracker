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

## Fixes from the full review (v0.27, 2026-11-11)
Lukas asked Claude Code for a review of the whole app ("rebuild if you have to"). The verdict was **no rebuild**: the app is fast, tested and feels native, and a rebuild would risk people's data. Lukas approved fixing what the review found:
- **New day while the app is open:** iPhone often resumes the app instead of reopening it, so it used to keep showing yesterday as "today" (and sets ticked in the morning went on yesterday). Now `checkNewDay()` runs when the app comes to the foreground and every minute: the selected day follows to the new today, stale sessions are closed and the rest stopwatch stops. **Exception:** a workout that's still active (a set or start in the last 3 hours, e.g. training past midnight) keeps you on that day until it's finished or idle; `closeStaleSessions()` also leaves such a workout running.
- **Rejected cloud saves are retried:** records are still marked as synced when sent, but if Firestore turns the batch down the marks are taken back and the push is retried (15 s, doubling up to 5 min, also when the app comes back to the foreground). Before, a rejected save was never sent again until the record changed.
- **"Tracked by" removed from the exercise form:** it showed Weight × Reps but couldn't be changed. New exercises are weight × reps; existing ones keep their `track`. Bring it back if more tracking types are added.
- Review decisions: Lukas chose **exercise notes**, a **smarter finish time** and a **Today icon showing today's date** as next features. He does **not** see a white flash at launch in dark mode (no launch image needed). Not chosen for now: progress hint, muscle groups on the Exercises list.
- Longer-term note: localStorage is limited to about 5 MB; with sync bookkeeping that's several years of heavy logging. Moving sets to IndexedDB is the fix if it ever gets close.

## Notes, finish time, Today icon (v0.28, chosen by Lukas in the review)
- **Exercise notes:** `exercise.note` (up to 200 characters), e.g. "seat on 4". Shown on the exercise's log screen under Last time (tap to edit in a small sheet; "Add a note" link when empty), editable in the exercise form, shown on the exercise's page in the Exercises tab. Private: not included when sending workouts/plans or sharing to the database. Kept in backups (`cleanExercise`).
- **Smarter finish time:** if the last ticked set was more than 15 minutes ago, the Finish sheet ends the workout at that set ("Started 17:50 · ends at your last set, 18:42") instead of now. A running timer now keeps its start time and the duration sets the end (before, the end was always "now" and the start moved).
- **Today tab icon:** a page showing today's date (like the iPhone Calendar app icon) instead of a calendar with a dot, so it no longer looks like the calendar button. The tab bar redraws when the date changes.

## Motion with weight and haptics (v0.29, asked for by Lukas)
Lukas asked for slide-ups and slide-downs that are a bit slower and "feel like they have weight", nothing happening instantly, and haptics like Apple's.
- **Springs:** `--ease-screen`, `--ease-sheet` and `--ease-soft` in index.html are CSS `linear()` curves sampled from real spring physics (response/damping .52 s/.86, .48 s/.84, .42 s/.9). They accelerate, glide, go a hair past the end (about 4 px on a screen) and settle. `--dur-*` is the time to come fully to rest (.69 s, .64 s, .49 s); app.js waits the same (`SCREEN_MS`, `SHEET_OUT_MS`, `SWIPE_MS`, `PULL_MS`). Safari older than 17.2 falls back to the iOS curve. Measured: the old slide-up covered 75% of the distance in the first 0.1 s; the new one 30%, most of it by 0.3 s, at rest by 0.7 s.
- **Uses:** screens sliding up/down, sheets, the number pad, the tab bar stepping aside, the rest pill, swipes between exercises/days, pull-to-close, the week selection capsule, tab switches, rows moving while dragging.
- **No more instant changes:** a new set row grows in; removing a set, an exercise from a day, a workout row or a plan day folds it shut first (`collapseOut`); an unticked set's ring settles back; ticked set numbers fade to full; the week arrows slide the new week in from its side; calendar months slide; switching Plans/Workouts or picker segments and library filters eases the content in (`state.soft`); Instructions opening eases in; the active page dot grows.
- **Haptics (`haptic(kind)`):** 'select' light tick (tabs, segments, chips, switches, week days, page dots, wheel rows as they pass the middle, steppers, chart scrubbing, dragged row passing another, page turns), 'impact' (ticking a set, starting the timer, deleting a row, picking up a row to drag, pulling past the close point), 'success' double (finish workout, PR, all sets done, sent, friend request, plan started), 'warn' (arming any "tap again to delete"), 'error' triple (ticking a set without numbers). iPhone: ticks from a hidden system switch (iOS 18+); Android: vibration patterns. Segments, chips, switches, week days and page dots get theirs from one document-level listener.
- **iPhone haptics fixed (v0.29.1, 2026-11-11):** Lukas felt no haptics at all. Cause: iOS 26.5 stopped playing the switch haptic when the switch is toggled from code (`label.click()`), which every earlier version relied on. Now (like the ios-haptics library) each control that should tick gets an invisible `label.hx` laid over it with a hidden `<input type=checkbox switch>` inside; the real tap lands on the label, the label flips the switch with a trusted click, and iOS ticks. A MutationObserver adds the labels to whatever is drawn (`HX_SEL` lists the controls). Because most taps redraw the screen (which would remove the label before it flips its switch), the tapped label moves to `body` during that click and is removed right after. Click handlers that look at `e.target` must use `e.composedPath()` instead (the number pad does). Limits on iPhone: one tick per tap (no double/triple patterns), and no ticks for things that aren't taps (wheel rows passing, pulling past the close point, dragged rows, swipes); those still tick on Android and older iPhones. The app's own on/off switches got the `switch` attribute so they tick natively. Tested as an iPhone in the test browser: every listed tap flips its switch once and still does its job; the feel itself can only be checked on a phone. Needs iOS 18+ and Settings → Sounds & Haptics → System Haptics on.
- **Bugs found and fixed while testing:** (1) pull-to-close lost the rest of the gesture once the screen underneath was drawn (touch events go to the element first touched, and it had been removed), which left a frozen snapshot of the old screen on top; it now also listens on that element. A finger that stops before lifting no longer counts as a flick. (2) The number pad's "tab bar steps aside" CSS used `pad-open` while app.js sets `np-open`, so it never applied (since v0.25).
- dev/test-gestures.py now pulls slowly for the short-pull case, swipes from the title (a swipe starting on a set field is ignored on purpose) and checks no snapshot is left behind; before, it passed while testing the wrong thing.

## Native iPhone app (v0.30, 2026-11-11)
Lukas asked for a free way to have it as a real iOS app (for real haptics). Options discussed: stay a web app; a native shell installed with a free Apple ID (re-sign every 7 days, max 3 such apps per phone, own phones only); or the $99/year developer program (TestFlight for friends / App Store). He has a MacBook and chose the native shell. Details and build steps: `native/README.md`.
- **Capacitor 8 shell in `native/`** that loads the **live site** (`server.url`), so every push reaches it with no rebuild; Lukas only re-runs it from Xcode weekly. Offline works because the live site is an app-bound domain (`WKAppBoundDomains` + `limitsNavigationsToAppBoundDomains`), which lets the service worker run in WKWebView. `www/offline.html` is shown only if the first-ever load fails.
- **app.js:** `NATIVE` is true only inside the shell (Capacitor's injected bridge). Then `haptic()` uses the Haptics plugin (selectionChanged / impact MEDIUM / notification SUCCESS, WARNING, ERROR), the invisible haptic labels are not added, and `applyTheme()` sets the status bar style. The Google sign-in button is hidden in the app (Google blocks sign-in in embedded web views); a note explains using "Forgot password?" to add a password to a Google account. Everything else is unchanged; the web app behaves exactly as before.
- iPhone only, portrait only, plain launch screen in the system grouped background colour (matches the app in light and dark), icon redrawn at 1024 px.
- Not testable here (no Mac/iPhone): the Xcode build, real haptics, offline inside the app, sharing a backup file from inside the app. Tested in the browser with a stand-in bridge: each action calls the right native haptic, status bar follows the theme, no errors; web test suite unchanged.

## Fixes after the first days in the iPhone app (v0.30.1, 2026-11-11)
Lukas: "Works. Lots of bugs." From now on the app is **iOS first** (the native app), the web page second.
- **Slide-up became instant after switching tabs:** the tab-switch animation class (`tab-in`) was never removed, and `#app.tab-in` out-ranked `.enter-up`/`.under`, so every later screen appeared instantly. It's now removed when done, `go()` clears it, and the CSS lets a sliding screen win.
- **New Exercise sheet "shoots up, scroll down a lot":** every tap inside an open sheet (a chip, a switch) redrew it, replaying its slide-in from below and resetting its scroll to the top. An open sheet now redraws in place (`.still`, scroll kept); a different sheet replacing it starts at the top without sliding in again.
- **Keyboard:** the native app has `@capacitor/keyboard` with `resize: native` (the app shrinks above the keyboard instead of iOS shifting the page; the keyboard's toolbar is hidden). While typing, the tab bar, rest pill and page dots step away (`body.kb-open`, from focus in Safari and from the plugin's keyboard events in the app). The page behind a sheet goes back to where it was when the keyboard closes and when the sheet closes.
- **Feels less like a web page:** pressing and holding no longer selects text or pops up callouts (except in fields, instructions and the friend code); inside the app, pinch and double-tap zoom are off.
- dev/test-motion.py checks both reported bugs.
- The native project changed (new plugin), so Lukas rebuilds once: fresh ZIP → `npm install`, `npx cap sync ios`, `npx cap open ios`, set the Team again, ▶.

## Fast swiping (v0.30.2, 2026-11-11)
Lukas sent a screen recording: swiping quickly back and forth between days made everything freeze slightly and jump around.
- **Cause:** after letting go, the page glides for ~0.4 s and only then is the screen redrawn for the new day. A new swipe during the glide started on the old page, and the redraw then landed under the moving finger (jump, two days overlapping).
- **`swipePager` rebuilt like an iPhone pager:** pages are numbered from the one on screen (…, -1, 0, 1, 2, …) and built on demand as they come into view, so quick flicks in a row go on to further days/exercises. Touching while it glides catches the row exactly where it is (read from the running transform) and you carry on; the screen is redrawn only once it has come to rest. A flick settles on the next page in the flick's direction, otherwise the nearest page (30% from rest turns one). Touching a gliding page doesn't count as a tap on it. Measured: the new day's title glides in and stays put through the redraw (no backward jumps).
- **Header steadied:** the Today button only shows when you're looking at another week (in this week today is in the strip, in red). Before, it popped in and out, and the month name shortened, on every swipe away from or back to today.
- dev/test-swipe.py covers fast swiping.

## 120 Hz in the iPhone app (native shell, 2026-11-11)
Lukas: the app feels like 60 fps, not 120. Cause: WebKit draws web content inside apps at about 60 fps even on ProMotion screens (the WebKit setting `PreferPageRenderingUpdatesNear60FPSEnabled`; Safari's own feature flag doesn't apply to apps). Fix, in `native/ios/App/App/AppDelegate.swift`: `AppViewController` (a `CAPBridgeViewController` subclass, set as the custom class in Main.storyboard) switches that setting off through WebKit's private `_features` / `_setEnabled:forFeature:` before the web view is created, guarded so it does nothing if the setting is missing. Info.plist also has `CADisableMinimumFrameDurationOnPhone` (lets the app's native parts run above 60 Hz). Private API is fine here because the app is installed from Xcode, not the App Store; it would need rethinking for App Store/TestFlight. Another app measured 60 → 120 rAF/s on iOS 26.5 with the same switch. Not testable here (no Mac/iPhone): needs a rebuild in Xcode; Xcode's log prints "Training: drawing at the screen's full refresh rate" when it worked.

## Fully native app, step 0: prototype (ios-native/, 2026-11-11)
Lukas asked to see what the app would be like fully rebuilt for iOS (`docs/NATIVE-REBUILD.md`). Built on his MacBook with Claude Code, tested in the iOS Simulator.
- **New SwiftUI app in `ios-native/`** ("Training β", bundle id `io.github.lukaslundmark1.training.native`), installed next to the current app. iOS 26+, no third-party code. The web app and `native/` are untouched.
- Prototype scope: tab bar, Today (week strip, swiping days, rings, progress, Finish, Add), the exercise screen (Last time, note, instructions, ticking, the app's own number pad, add/remove set, page dots, swiping), rest stopwatch, PR and "all sets done" toasts, Finish sheet. Made-up sample data only; no Firebase yet.
- Records use the web app's exact JSON shape (backup-compatible); ticking, suggestions, PRs, the pad's typing rules, Finish and stale sessions are ported line by line and unit-tested against app.js's results.
- Native choices made for the prototype: native Liquid Glass tab bar and buttons; removing an exercise is a long-press menu instead of the trash button.
- **Exercise screen slides up from the bottom (Lukas, 2026-11-11):** "whenever you click on an exercise, it comes up from the bottom. When you click off or swipe down, it goes back down", with Apple's weight and springs. It's a real iOS sheet (large, grabber visible, ⌄ button top left), so the slide, the finger-following pull-down and the spring back are Apple's own, and pulling down works together with scrolling. The first try (a zoom out of the tapped row) was replaced. The number pad, rest stopwatch and toasts live inside that sheet.
- **Step 1 + 3 done the same day:** backup import/export (Settings) with the `clean*` sanitizers ported (`Sanitize.swift`, checked to give exactly what app.js gives on a messy file), and the plan schedule ported line by line (`Plans.swift`) with the Today plan buttons and the Move back sheet. Verified by replaying 1,500 random plan changes recorded from app.js's own plan code (`ios-native/dev/schedule-fixtures.js`): every schedule, Up next, preview and stored day matches. A deliberately planted bug makes that test fail, so it really checks. Sample data now has a Push Pull Legs plan.

## Fully native app: Workouts tab (2026-11-11, asked for by Lukas)
- Plans | Workouts switch (remembered), lists as native inset-grouped lists; the active plan first with a green "Active".
- The plan screen and the workout/plan editors slide up from the bottom as sheets (like the exercise screen). Editors close with ✕ / ✓ only (no pull-down, so a half-made workout isn't lost by accident); their lists are in edit mode, so iOS's own red ⊖ removes and ≡ reorders (the same controls the web app draws). Delete / End plan ask with an iOS confirmation instead of "tap again".
- Same rules as the web app: name required; a plan needs at least one workout day; starting on day N sets `start = first − N`; starting or ending a plan drops untouched future plan days and moved rest days but keeps trained/started ones; deleting a workout turns its plan days into rest days; deleting the active plan ends it. "Coming up" rows open that day in Today.
- Not yet: "Send to a friend" (comes with Friends) and the full exercise form ("New exercise" from a workout makes one with just its name until the Exercises tab is built).

## Fully native app: Exercises tab, page dots fix (2026-11-11, asked for by Lukas)
- **Page dots "hopped" in** when an exercise opened (Lukas). A screen recording, frame by frame, showed them starting at the top of the sliding sheet and springing down to the bottom: the page was set just after the screen appeared, and the dots' "spring when the page changes" animation moved the whole row from where the half-laid-out screen had put it. Now the page is known before the screen is drawn, and the spring only grows/shrinks the dots themselves. Re-recorded: the dots ride up with the sheet at its bottom edge and never jump.
- Exercises tab as in the web app: list with search (always visible) and database matches; the exercise database (130 built-in, chips for muscle group and equipment, "In your list"); the exercise form (chips wrap; "From the exercise database…" / "Sign in to share…" note; delete asks with the number of logged sets); the exercise page and History slide up as sheets.
- Chart: Swift Charts with the web app's look (monotone line, soft fill, dots up to 24 sessions, ringed latest point, the same "nice" axis steps, first/last date labels, "12k" for big volumes), draws in once from the left, and dragging across it shows the session's value, date and best set with a tick per point.
- Existing exercises with a common name are linked to the database at start (muscle group and equipment filled in), like the web app. Shared database entries and sharing your own come with sign-in. YouTube videos open in YouTube (no embedded player yet).

## Fully native app: Add exercise at the top, chart ranges (2026-11-11, Lukas)
- Exercises tab: **Add exercise sits right under the search field** ("once you have a lot of exercises that's too much scrolling to make a new one").
- **Chart ranges 3M / 6M / 1Y / All** (Lukas: "all time, 3 months, 6 months, 1 year"), a segmented switch under the chart, remembered between screens and launches; default All. "Latest" is always the latest session; the change ("+15.6 kg since …") and Best are for the range shown. A range with no sessions says "No sessions in the last 3 months." Native app only for now (the web app's chart has no ranges).

## Fully native app: reorder, trash, pausable timer, workout summary (2026-11-11, Lukas)
- **Reorder on Today:** drag ≡ (follows the finger at once) or press and hold a row (0.3 s), with the iPhone's haptics: a firm tap on pick-up, a tick for each row passed, a soft tap on drop. The lifted row grows slightly with a shadow; the others slide out of the way on springs; the day pages hold still while dragging. The order is stored on the day like the web app's drag.
- **Red trash on each row** (like the web app): removes the exercise from that day; with logged sets the first tap turns it into a red "Delete" (warning haptic, back after 3 s), the second removes it and its sets for that day. Emptying a planned day yourself still makes it a moved rest day. The long-press menu was dropped (long press now picks the row up).
- **Timer:** tap Start; tap to pause (orange ⏸, time frozen, grey); tap to carry on. Tapping no longer opens Finish; **only Finish workout ends a workout**. Finish workout now shows on Today whenever today has exercises (and on a day whose timer is running). Because the shared data format has no "paused" (and the web app must keep working), the pause is stored on the phone only; resuming moves the session's start later by the paused time, so the duration the web app shows is right. Finishing while paused ends the workout at the moment it was paused. The web app's timer is unchanged.
- **Workout summary** (port of the web app's): slides up after Finish, and from a "Workout summary" button on a finished day. Check pops in, numbers count up, PRs, each exercise's best set ▲/▼ % against last time (rounded like JS), tap an exercise to open it, Done. "Same" is shown as a grey = sign (Lukas: nicer than the word), between the green ▲ and the red ▼.

## Fully native app: quick deletes, workout search (2026-11-11, Lukas)
- **Bug: deleting exercises quickly made them come back.** A row that's fading out could still be tapped, so a quick tap landed on it instead of the row sliding up. Once the day was empty, that tap "emptied" it again: the moved rest day was dropped and the plan filled the day back in. Fixed twice over: removing an exercise that's no longer on the day does nothing, and a leaving row ignores taps (quick taps reach the next row). Reproduced and checked on a second simulator; test added.
- Today → Add: on the Workouts side the search says "Search workouts" and filters your workouts (typing used to jump to Exercises); the Exercises side says "Search exercises".

## Fully native app: accounts and sync (2026-11-11, step 2 of the plan)
- **Same account, same data:** email + password sign-in to the same Firebase project; every record syncs both ways in the web app's exact document format (`u` on every write, `{deleted, u}` tombstones, `meta/settings` + `meta/active`). A line-by-line port of app.js's sync (first-sign-in merge where the account wins, hash per record, stable listener query, batches of 400, retry 15 s → 5 min). Checked against the web app with both talking to Firebase's local emulators: sets, edits, deletes, workouts, days, plans (the same schedule in both after a Move back), settings and the friend code.
- **Sign-in sheet** like the web app's (email, password, Create account, Forgot password?, friendly errors; the Google note). Native password AutoFill works. No Google button (needs the GoogleSignIn SDK; only if Lukas asks).
- **Settings:** name with the initial avatar, account row with a status badge (green "Backed up", "Syncing…", orange "Offline — will sync later", red "Sync problem"), Sign out (sheet with "Remove my training from this phone", on unless offline), Default sets, Delete account (password, then an iOS confirmation instead of "tap again"; "Export a copy first").
- **The made-up sample training is never uploaded:** the first account to sign in on the phone starts from its own training. "Start over with the sample data" is only offered before any account has signed in on the phone.
- **Safer than the web app in one case:** what was last synced is only trusted if the phone's data already belonged to that account. In the web app, if person B signs out with "Remove my training" and person A (who used the phone before) signs in again, A's whole account is tombstoned. Not fixed in the web app yet (ground rule: don't touch it in the rebuild); Lukas told.
- Needs Lukas to register the iOS app in Firebase (`GoogleService-Info.plist`); until then sign-in is greyed out with a note.

## Fully native app: Finish per workout, scrolling, drag limits (2026-11-11, Lukas)
- **Each workout on a day has its own timer and Finish** (Lukas: "separate finish workouts for each of them. Even on a day where you have already worked out, you should still be able to work out"). "Finish Pull" sits under Pull's exercises; once finished, the header says "Finished in 42 min" (green) and a "Workout summary" button shows that workout's summary. The first set ticked in a workout starts that workout's timer; the exercise screen's timer is the timer of the workout on screen. Stored as `sessions` on the day (native only); the day's shared `session` spans them so the web app still shows in progress / finished. The day only reads "Finished" when every workout is.
- **Scrolling with a finger on an exercise works again:** press-and-hold to pick a row up is now the iPhone's own long press (a finger that moves first scrolls the page; a quick tap still opens the exercise). ≡ still drags straight away.
- **A dragged exercise stops at its workout's first and last place**, however far the finger goes.

## Fully native app: days hold workouts, Move replaces Move back (2026-11-11, Lukas)
- **A day's exercises are grouped by workout** (Lukas: "days to be able to have multiple workouts… exercises clustered within a workout"). Each workout is a header (arrow to fold it, open by default; folded shows "4 exercises · 3 of 12 sets") above its card. Exercises added on their own go in **"Other exercises"** at the bottom ("Exercises" when it's the only group). Reordering is within a workout. The exercise screen says which workout ("Exercise 2 of 8 · Legs").
- **The same exercise can be in two workouts on one day, with separate sets** (Lukas chose this over showing it once). History, charts, PRs and the summary still count a day's sets per exercise.
- **Move (per workout) replaces Can't make it today / Move back a day / Undo move / Do X today / Do it today.** It opens a month calendar (ring = planned, dot = trained, the workout's day in blue); tap a day and it moves there, next to whatever that day has (Lukas: add alongside). Only a workout with nothing logged can move. Moving a plan workout moves **only that workout**; every other planned day stays on its date (Lukas). Emptying a planned day yourself now skips it the same way (nothing else moves).
- **Native app only** (Lukas). Stored with small extras the web app keeps but ignores: `w` on a day's items and on sets (the workout), `moved` on a day's workout, `away` on a day. The web app will show those days differently: moved plan workouts may appear on their old days, and an exercise in two workouts shows as one with the sets merged. Days the web app moves the old way are still read correctly (the 1,500 replayed web plan changes still pass).

## Fully native app: Friends, profiles, sending workouts and plans (2026-11-12, step 6 of the plan)
- **A port of the web app's Friends in the same Firestore documents** (`codes`, `links`, `gifts`, friends' `users/…` read through the published rules), so a Training β user and a web-app user can be friends, see each other's training and send each other workouts and plans. Checked end to end against the web app on Firebase's local emulators: code reserved, request (both directions), accept (with or without sharing), the friend's profile, workouts, an exercise's graph and full history, sharing off (the rules then refuse the read), send a workout and a plan both ways, add (plan added, not started; names get "(friend)" when taken; exercises reused by database id or name), decline, unsend, remove friend, a name change reaching the code and every link.
- **Same layout as the web app,** with native pieces: the Friends tab is an inset list (your profile, Inbox, your friend code with Share invite (the iOS share sheet) and Copy code, Requests with Accept / ✕, Friends, Sent with "Waiting" / ✕), + adds a friend. The red number on the tab is requests + things sent to you. A friend's page and your own profile slide up; inside them All workouts → a workout → an exercise's graph slide in from the side (the chart and history are the Exercises tab's own, fed with the friend's sets). Pull down (or ↻) reloads a friend's training. Remove friend asks with an iOS confirmation instead of "tap again".
- **Send to a friend** is at the bottom of the workout editor (sends what's in the editor, like the web app) and the plan screen; a friend's page has "Send a workout or plan" with the history of what you've sent (Waiting / Added / Declined, ✕ to unsend). Adding something a friend sent opens the Workouts tab at it.
- Everything from another person is cleaned like the web app's (`Clean.*` for friends' training; gifts with the web app's limits: names 60, instructions 2000, 60 items, 120 days, sets 1–10). The import matches app.js exactly on a messy gift (test made from app.js's own code).
- **One fix not in the web app:** if the phone is briefly offline when Friends starts, the friend code is fetched again a few seconds later (the web app shows an error until reopened).
- Big blue buttons now look dimmed when they can't be pressed (everywhere in the β app).

## Fully native app: calendar from the month name (2026-11-12, Lukas)
- Tapping the month name at the top of Today opens a calendar sheet (a blue ⌄ next to the name shows it can be tapped; Lukas asked for an icon so it's obvious). Months scroll from the first month trained (at least a year back) to a year ahead; same marks as Move (dot = trained, ring = planned), the selected day blue, today red, a Today button. Tap a day to go there. Jumps over 14 days now land at once instead of scrolling through every day between.

## Fully native app: videos linked to sets (2026-11-12, Lukas)
- **Where videos live:** options were (1) link to the video in Photos, (2) copy into the app's own iCloud space, (3) keep inside the app. Lukas chose 1: free, no extra storage, works with the free Apple ID (2 needs the $99 account for iCloud), and with iCloud Photos the link survives a new phone because the set stores Photos' **cloud identifier** (same on every device on that iCloud account; `local:<id>` fallback when Photos can't give one). Firebase Storage was ruled out (needs the paid plan; videos are big). Deleting the video from Photos breaks the link (the player says so).
- **Per set** (Lukas). Stored as `v: [ids]` on the set document; absent when empty, so existing sets keep their sync hash. No rule change (sets have no field limits). The web app keeps the field (it stores incoming sets as they are) and doesn't show it; friends can't see videos; backups (`Clean.backup`) drop it.
- **UI:** "Link video" next to "Add a note" on the exercise screen → choose the done set(s) → Photos picker (videos only, several at once) → each chosen video goes on each chosen set. A blue video icon under the set number plays them; History shows thumbnails (with length) on those sets. The player swipes between a set's videos; ⋯ → "Unlink from this set". Untick + tick again keeps a set's videos (in memory). Needs Photos access (asked once); with "some photos only", picked videos may not play. Sound: the player switches the app to movie playback (`AVAudioSession` `.playback`) while open, so a video has sound with the phone on silent (iOS's default for apps muted it; Lukas reported no audio), and hands the sound back to other apps when it closes.

## Fully native app: History days open the exercise screen (2026-11-12, Lukas)
- Tapping a day in an exercise's History (from the exercise screen's "Last time" or the Exercises tab) opens that day's exercise screen on top, on that exercise (the workout it was logged in, if it's in two); swiping down or ⌄ goes back to History, like the summary → History. Each day card has a ›; a friend's history isn't tappable. The exercise screen now shows the date ("Thu 29 Oct · Exercise 1 of 4") when it isn't today.

## Fully native app: number pad kg ↔ Reps switch (2026-11-12, Lukas)
- Lukas: switching kg ↔ Reps was smooth with empty fields but choppy once a value was typed or logged. Cause: two animation rules on the pad (a 0.15 s fade keyed on the value, the spring keyed on the field); a switch that also changed the number shown took the fast one, so the capsule snapped across in ~4 frames. Now one rule: a switch (field, set or exercise changed) springs, typing a digit fades quickly. Checked frame by frame: the capsule now takes ~8 frames either way.
- "Next set ›" was cut to "Next..." at the standard text size on a 6.3" phone: the switch is a little narrower and the button text never truncates.

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
- More tracking options (time, distance, bodyweight, etc.)
- What friends can see (body weight later?)

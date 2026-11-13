# Handoff: Training β (native SwiftUI app), next up: more small visual changes

Updated 2026-11-12 (night) after a performance session (below, committed as `a745eb9`). **Next session (Lukas): a few
visual changes, minor things.** He'll say what; small UI changes are "just do them" (see his preferences at the end), then
verify each in the Simulator, light + dark, frame by frame if it moves, and keep the performance rules below in mind. Before that, a feature session: calendar from the month
name, videos linked to sets, History days open the exercise screen, video sound on silent, smooth kg ↔ Reps switch; and a polish session, Friends,
accounts + sync and the day overhaul. **Read in this order:** `../CLAUDE.md` (how Lukas works), this file,
`../docs/NATIVE-REBUILD.md` (the original plan and the data format), the "Fully native app" entries in
`../docs/DECISIONS.md` (every choice and why), `README.md` here. The web app (`../app.js`) is the reference: when docs and
code disagree, the code wins. `../dev/README.md` → performance rules and `../docs/DECISIONS.md` → "Performance (v0.26)"
describe how the *web* app was made fast; the same ideas (index, caches, no work during gestures) apply here.

## Dark mode: Apple's sheet colours (2026-11-12, changed back 2026-11-13)
- Tried on 2026-11-12: sheets that are full pages in the web app drawn black with #1c1c1e cards (a `BaseLevel` trait
  override). **Undone on 2026-11-13 at Lukas's request ("I want consistency").** When a sheet opens on top of another,
  iOS darkens the edge of the sheet behind to about #141415 whatever its colour (measured). On Apple's grey sheets
  (#1c1c1e) that's invisible (Calendar, Mail; Lukas checked with a recording); on black it showed as a lighter strip.
- Now every sheet uses iOS's own sheet colours in dark mode: #1c1c1e background, #2c2c2e cards (`Color.bg` / `Color.card`
  resolve that way inside sheets). The main tabs aren't sheets and stay black, like Apple's apps.
- `.pageColors()` and `.sheetColors()` (UI/Theme.swift) both just give the sheet a solid background (iOS 26 otherwise
  draws partial-height sheets as see-through glass). Keep using them on new sheets.
- Don't use `secondarySystemBackground` / `tertiarySystemBackground` for sheet backgrounds or cards (#2c2c2e / #3a3a3c
  in a sheet); use `Color.bg` / `Color.card`.
- **Finish / Duration pop-up (2026-11-12, Lukas):** a short pop-up sized to its content. Duration is one row like an iOS
  Settings row: "Started 20:36" on the left, the value in a capsule on the right ("1 h 05 min"); tapping it shows the
  hour/minute wheels inside the same card (open at first when changing a finished workout's Duration, closed when
  finishing). A footnote only when it ends at the last set or the timer wasn't running. Lukas had found the old layout
  (header + sentence + loose wheels) clunky and the wheels too low.
  Animation details (all checked frame by frame): the value text is two copies faded into each other (changing a Text's
  colour mid-animation redraws it apart from its capsule); the wheels (UIKit) jump to their place instead of moving with
  the card, so they fade in 0.22 s late and out fast.
- **Pop-ups over the exercise screen aren't sheets:** iOS pushes a sheet back and switches it to lighter (elevated) colours
  when another sheet opens on top of it, so the black exercise screen went grey behind them (Lukas's screen recording).
  SwiftUI can't turn that off (`presentationBackgroundInteraction` doesn't help). LogView draws Finish / Duration, Note and
  Link video itself with `PopUpHost` (UI/Theme.swift): slides up, pull down or tap outside to close, darkens the page
  (black 50%, like the web's backdrop), rides above the keyboard. Views inside call `popUpClose` from the environment
  instead of `dismiss` (which would close the exercise screen) and use `Color.popBg` / `Color.popCard` (pop-up colours
  that don't depend on the interface level). Finish draws its own `PopUpBar` and sizes itself (so opening the wheels is
  one movement); Note and Link video keep their NavigationStack and get a measured height (`.popUpHeight`). From Today,
  Finish is still a normal sheet. History and Add exercise from the exercise screen are still full sheets.

## Where things stand
- Built and tested in the Simulator (iPhone 17, iOS 27.2, light and dark); 69 unit tests pass. Lukas has the project
  open in Xcode with his Team set; he presses ▶ to put it on his iPhone (every native change needs ▶ again).
- `main` is at `a745eb9` "native: performance and battery" (before it: "native: polish, calendar, videos on sets, History
  → day"). Everything is committed; **nothing is pushed.** Pushing only publishes
  the folder on GitHub Pages; it doesn't change the web app. Commit style: `native: <what>` + bullets.
- `GoogleService-Info.plist` is in `Training/` (Lukas registered the iOS app in Firebase on 2026-11-11), so sign-in works.
  Whether he has signed in with his real account on the β app is unknown: ask before testing anything that would touch it.
- Lukas tests on his iPhone and reports by feel (he sent a screen recording for the kg ↔ Reps bug). He confirmed
  videos work on the phone (2026-11-12); History → day not confirmed yet.

Feature session (2026-11-12, all verified in the Simulator, light + dark; details under "Done" below):
- **Calendar** from the month name on Today; **videos on sets** (Photos links, `LoggedSet.v`); **History → day** opens
  that day's exercise screen on top; past days show their date on the exercise screen; video player plays sound on silent.
- **Number pad kg ↔ Reps:** one animation rule (`switching ? Motion.soft : .easeOut(0.15)` keyed on field + set +
  value); two rules made a switch that changed the number snap in ~4 frames. "Next set ›" no longer truncates.
- History computes PRs once per list (a per-card `prSets` slipped in with History → day; fixed).

Polish session (2026-11-12, earlier; all verified in the Simulator, light + dark, frame by frame where it moves):
- **Rest stopwatch** no longer covers content: `RestRoom` (in `UI/Common/Floating.swift`) adds bottom room to each tab's
  list while it shows. It has to sit on the List inside the NavigationStack (on the NavigationStack it does nothing).
  The pill got a solid-ish card backing like the toast.
- Plans list: "Active" sits next to the name (`Row(tag:)`). Exercise database: filter chips are a `safeAreaBar` under the
  search field, edge to edge. Exercises tab says "Last logged today / yesterday". Settings no longer says "prototype".
  Removed the unused `ComingSoon` view.
- **Workout summary:** tapping an exercise opens its History *on top* of the summary (a sheet from `SummaryView`);
  closing it returns to the summary. (It used to close the summary and open the exercise screen.)
- **Number pad:** (1) slides fully off (transition offset = its height + safe bottom + 24; `.move(edge:)` left its top row
  peeking out). (2) **Swipe down to close** (drag on the pad, follows the finger, > 70 pt or a flick closes, else springs back;
  a swipe starting on a key doesn't type it: `dragged` flag). (3) Keeps showing its last contents while it slides away
  (`lastShown`): it used to empty instantly on close, leaving only a pressed Done button to fall on its own.
- **Press animations are scoped** (`PressStyle`, `CardPressStyle`, `KeyStyle` use `.animation(_:body:)`): the old
  `.animation(value: isPressed)` also animated the button's *position* when a tap moved it away, on the press spring.
- **Ticking a set with an empty field:** the field flashes red (stroke + light fill) for 0.55 s and fades back
  (`Store.bad` cleared after a token-checked delay; `SetRow` animates it). A failed tick no longer moves the pad to the next set.
- Answered 2026-11-12: **keep the red trash icon** on every Today row (no swipe to delete). **Keep the rest stopwatch as a
  floating pill for now**; iOS's `tabViewBottomAccessory` (the Music-style strip above the tab bar) stays an option he may want later.
- Known small quirks, not fixed: the Exercises tab's title starts small (inline) and only turns large after pulling down
  (searchable drawer + iOS 26; `.navigationBarTitleDisplayMode(.large)` / `defaultScrollAnchor` didn't help). On the
  exercise screen, when the list scrolls up for the number pad, the big exercise name slides under the ✓/timer buttons.

Done (steps 0–4 of NATIVE-REBUILD §8, plus extras Lukas asked for):
- **Today:** week strip (sliding capsule), swipe days, plan-driven days and labels. **A day's workouts are foldable groups**
  (arrow, open by default), each with **Move** (month calendar; only that workout moves, the rest of the plan stays on its
  dates) and its **own timer and Finish** ("Finish Pull", then "Finished in 42 min" + "Workout summary"). Single exercises
  go in "Other exercises". The same exercise can be in two workouts with separate sets. Rings, progress bar, Add exercise /
  workout, drag to reorder within a workout (≡ or press-and-hold; stops at the workout's edge), red trash.
  Removed at Lukas's request: Can't make it today / Move back a day / Undo move / Do X today / Do it today.
  Code: `Model/Groups.swift`, `Model/Sessions.swift`, `UI/Today/` (DayExerciseList has WorkoutGroupView + LongPressDrag).
- **Exercise screen** (sheet): Last time → History, note, instructions, set rows, ticking, own number pad, add/remove
  set, page dots and swiping, rest stopwatch, toasts, the timer of the workout on screen (tap start / pause / carry on).
- **Finish sheet** and **workout summary** per workout (counts up, PRs, ▲ / ▼ / = against last time).
- **Workouts tab:** Plans | Workouts, workout editor, plan view (Up next, Coming up), plan editor, start/end plan.
- **Exercises tab:** search + Add exercise at the top, the 130-entry database with filters, exercise form, exercise page
  with Swift Charts (Est. 1RM / Heaviest / Volume / Reps; 3M / 6M / 1Y / All; scrub), history with PRs.
- **Accounts and sync:** email + password (create, forgot password), live two-way sync with the web app in its format,
  status badge, sign out with "Remove my training from this phone", delete account. Details below.
- **Settings:** name, account, units, appearance, week start, default sets, import/export backup, delete account.
- **Friends** (2026-11-12): Friends tab, friend code, requests, a friend's profile (stats, workouts, an exercise's graph),
  your own profile, sharing switch, remove friend, sending workouts/plans (inbox, add/decline, unsend, history). Details below.
- **Calendar** (2026-11-12): tap the month name on Today (blue ⌄ next to it) → a sheet of months
  (first trained month or a year back → a year ahead; dot = trained, ring = planned, selected day blue, today red, Today
  button); tap a day to go there. Jumps over 14 days land at once instead of scrolling through every day (also Today).
  `UI/Today/CalendarSheet.swift`: `MonthGrid` + `CalendarDay` are shared with MoveSheet. A lazy list needs
  `scrollPosition(id:)` for its start month (`scrollTo` on appear did nothing); `@Environment` read outside `body` crashes.
- **Videos on sets** (2026-11-12): "Link video" next to "Add a note" → pick done set(s) → Photos picker
  (videos) → linked. Stored as Photos cloud identifiers in `LoggedSet.v` (synced; web app keeps it, doesn't show it).
  Blue icon under a set's number plays; History shows thumbnails; player can unlink. Code: `Model/Videos.swift`
  (`linkVideos`/`unlinkVideo`, `VideoLibrary`: ids ↔ PHAsset, thumbnails, player items), `UI/Log/VideoViews.swift`,
  `VideoTests`. Test videos in the Simulator: record its screen with `simctl io recordVideo`, then `simctl addmedia`.
  Sound plays on silent (`VideoLibrary.movieSound`, the player sets `.playback` while open; not checkable in the Simulator).
  Not verified: a real iCloud Photos library / switching phones (the Simulator has no iCloud Photos).
- **History → day** (2026-11-12): tapping a day card in History opens that day's exercise screen as a
  sheet on top (`HistoryList.openLog`, `Store.logStart`); closing returns to History. Past days show their date above the
  exercise name. Exercise screens can stack, so `Store.logOpen` is now a count (`logDepth`).
- Not done: shared exercise database (browse shared entries, "Share to the database" on your own), embedded YouTube player, Google sign-in (only if asked), `#add-CODE` invite links opening the β app (they open
  the web app; the β app would need associated domains).

## Performance session (2026-11-12, commit `a745eb9`; details and numbers in ../docs/DECISIONS.md → "Fully native app: performance and battery")
Lukas: nothing felt slow, but "animation performance could be better"; then: optimise everything with lots of fake data.
Done, all verified in the Simulator (dark + light) and by tests; **not yet felt on his phone**: ask once how it feels
(opening, swiping days, ticking, opening an exercise). ▶ now builds Release: if Xcode shows two "Training" schemes, the
shared one is right.

Rules for UI changes that keep it fast (learned this session):
- Don't put an animation's state in the same view as something heavy (a Chart, a long list): the whole view re-renders
  every frame. Give the animation its own small view (`DrawInCover` is the example).
- No endless SwiftUI animations (phaseAnimator, repeatForever, symbol effects) on screens that stay open: they redraw every
  frame and keep the display at full refresh. Use Core Animation (`PulseDot`) or nothing.
- No lazy grids/stacks inside lazy stacks for small fixed content (calendar months are plain rows now). Don't make the Today
  pagers' ForEach range big again; their windows recentre only when scrolling is idle.
- Store lookups: use the cached helpers (`dayOf`, `setsOf`, `index`, `prevBest`); a new cache must be cleared in
  `data.didSet` and call `access(keyPath: \.data)` when it answers without reading `data`.
- After a visual change, a quick check that nothing regressed: `CONF=Release ./dev/run-sim.sh launch <UDID> -perfData 104
  -perfLog 1` + the log stream (below) shows dropped frames and which views redrew.
- **▶ builds Release** (`Training.xcodeproj/xcshareddata/xcschemes/Training.xcscheme`): the Debug build ran Swift and
  Firebase unoptimised, 2–5x slower. `dev/run-sim.sh` / `run-emu.sh` build Debug explicitly; `CONF=Release dev/run-sim.sh
  launch <UDID> [args]` builds what ▶ builds.
- **Store:** O(1) "sets changed?" (`SetsID`), set index updated in place on tick/untick/edit (`commitSets`,
  `SetIndex.insert/remove/update`), `dayMemo` (dayOf), `prevBestMemo`, integer day maths in `Day0`, memoised `Fmt` dates,
  `purgeStalePlanDays` once per burst from the store (not `onChange(of: store.data)` in TodayView), saves on a serial
  background queue (`FileWriter`, also for the sync state). Caches that skip reading `data` call
  `access(keyPath: \.data)` so views still redraw when it changes: keep that if you add another.
- **Today pagers are windowed** (`dayWin`/`weekWin`, recentred only when scrolling is idle, with `proxy.scrollTo` in the same
  no-animation transaction; far jumps get a new window). Don't recentre mid-scroll: the page jumps.
- **Charts:** `DrawInCover` (its own view: the old mask redrew every mark each frame), `thinned(_:to: 100)` (LTTB).
- **Battery:** `PulseDot` (Core Animation blink for the running timer), clocks aligned to their start second.
- Calendar months are plain rows. Left as is (see DECISIONS): calendar opening (~170 ms with 2 years: the lazy month list
  measures every month above the start), first sheet opens (system), sync push (~4 ms per change with 10k sets).

How to measure (the tools exist now):
- `CONF=Release ./dev/run-sim.sh launch <UDID> -perfData 104 -perfLog 1`, then
  `xcrun simctl spawn <UDID> log stream --style compact --predicate 'subsystem == "perf"'`: dropped frames per second, slow
  work (`Perf.measure`), and which views redrew after each burst (`let _ = Perf.body("Name")` in a body). `-perfData` uses
  `training-perf.json` and turns sync off; never use it on Lukas's phone.
- Time Profiler: `xcrun xctrace record --template 'Time Profiler' --device <UDID> --attach Training --time-limit 10s
  --output x.trace`, then `xcrun xctrace export --input x.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'`
  and sum main-thread samples (1 ms each) by frame or binary. The Simulator's frame drops vary ±150 ms run to run (the Mac
  is shared with Lukas's simulators): compare summed CPU over 3+ repeats, not single hitches.
- Idle CPU: `ps -o %cpu= -p $(pgrep -f "<UDID>.*Training.app/Training")` (Today idle = 0%, exercise screen idle ≈ 0.2%).
- Known pre-existing glitch (not fixed): tapping a day in the week strip and tapping the page again before it finishes
  scrolling can leave the page on the old day with the new day selected.

Other ideas if they come up later (don't push them): decide the β app's future (replace `../native/` for himself and/or
TestFlight, $99/year); leftovers (shared exercise database, YouTube player, Google sign-in only if asked, invite links
opening the β app); the web app's open list in `../CLAUDE.md` (coaching switch, muscle-group labels/filter, more
tracking types).

## Friends (how it works, for whoever changes it)
- `Model/Friends.swift` (Firebase-free, tested in `FriendsTests`): `FriendLink` and `Gift` parsed (and cut to size) from
  documents, gift payloads built (`exPayload` / `workoutPayload` / `planPayload`) and imported (`importExercise` /
  `importWorkout` / `importPlan` on `AppData`, a port of app.js with the same limits), `ProfileSource` (yours from the store,
  a friend's from `FriendLoad.source`, cleaned with `Clean.*`), profile stats.
- `Model/FriendsCloud.swift`: `Friends`, owned by `Cloud` (`cloud.friends`), started at sign-in and stopped at sign-out /
  delete account. Listeners on `links where members array-contains me`, `gifts where to == me`, `gifts where from == me`;
  `ensureCode` (retries every 5 s → 1 min while offline); your name goes to the code doc and every link 1.5 s after it
  changes (`nameMaybeChanged`, called from `store.onChange`); a friend's training cached 1 min, an exercise's full history
  loaded on its page. `Store.openRequest` opens an added gift in the Workouts tab.
- `ProgressCard` / `HistoryList` take an optional `ix:` (someone else's `SetIndex`); `SetIndex.series` / `prSets` hold the
  maths for both (Store's versions call them).
- UI: `UI/Friends/` (FriendsView = tab + Avatar/CapsuleButton/CircleX; ProfileViews = profile sheet with pushed pages and
  gift history; FriendSheets = add friend, accept, gift, send pick, send to). Send buttons in `WorkoutEditor` and `PlanView`.
- Gift history and a friend's page work the same for web and β friends (verified both directions, see DECISIONS).

## Accounts and sync (how it works, for whoever changes it)
- Each workout has its own timer: `sessions` on the day (`Model/Sessions.swift`); the day's `session` is kept as their span.
- Days with several workouts add `w` (items, sets), `moved` (a day's workout) and `away` (day) to the shared format;
  the web app keeps them. `Clean.backup` (a port of app.js) drops them, so a backup round trip loses the grouping
  (older-day rules then group by workout again; an exercise in two workouts merges).
- `Model/SyncCore.swift`: Firebase-free and unit-tested (`SyncTests`): FNV hash (same as app.js), `ops` (what to send:
  changed records with `u = now`, `{deleted: true, u}` tombstones for records gone since the last sync), `merge` (incoming
  documents; first sync = account wins; the listener skips unchanged hashes), `listenFrom` (stable query, moves monthly),
  `HashCache` (no re-encoding of thousands of unchanged sets on every push).
- `Model/Cloud.swift`: the Firebase side, a line-by-line port of app.js `startSync` / `listen` / `pushChanges` /
  `retryPush` / `wipeDevice` / `deleteAccount` / `friendlyAuthError`. Collections `users/{uid}/{exercises|workouts|days|sets|plans|meta}`,
  `meta/settings` + `meta/active` (`{planId: null}` when no plan). Pushes 600 ms after a change (`Store.onChange`), in
  batches of ≤ 400, marked synced at once and un-marked + retried (15 s doubling to 5 min) if refused; also on coming
  back online (`NWPathMonitor`) and to the foreground. The first download uses `source: .server` so an empty offline
  cache can't look like an empty account. What was last synced lives in `sync.<uid>.json` next to `training.json`.
- **Whose data is on the phone** (`Store.claimLocalData`, the web app's `tt.owner`): a different account signing in puts
  the previous person's data aside (`training.<uid>.json`) and loads theirs. The sample training (`tt.sample`, also
  recognised on old installs by its `sample-ppl` plan) is replaced by an empty start, never uploaded.
- **Safety fix not in the web app:** the remembered sync state is used only if the phone's data already belonged to that
  account; otherwise it does a full merge. In the web app, signing in again after another account wiped the phone would
  use the stale state, see everything as deleted and tombstone the whole account. (Web app not changed; Lukas was told.)
- Incoming changes replace `store.data` but keep the number pad and typed values; a units change (from any device)
  clears typed values, like the web app.

## Testing sync (Firebase emulators, no real accounts)
Never test against Lukas's real account. Firebase's local emulators run on this Mac:
1. `cd` to a scratch folder, `npm i firebase-tools@14`, copy `../firestore.rules` there and a `firebase.json` with
   `{"firestore":{"rules":"firestore.rules"},"emulators":{"auth":{"host":"127.0.0.1","port":9099},"firestore":{"host":"127.0.0.1","port":8080},"ui":{"enabled":false},"singleProjectMode":true}}`
   (the `host` matters: without it the Firestore emulator may listen on IPv6 only and both apps report "unavailable"),
   then `npx firebase emulators:start --only auth,firestore --project workout-tracker-705ae` (needs Java; 17 works).
2. `ios-native/dev/run-emu.sh <UDID>` builds and launches the app with `-emulator 127.0.0.1` (debug builds only: a fake
   iOS app id, the Auth and Firestore emulators, memory cache). Create throwaway accounts in the app.
3. The web app against the same emulators: copy `index.html`, `app.js`, `firebase-*.js` to a scratch folder; in app.js
   change `initializeFirestore(app, {` to add `host: '127.0.0.1:8080', ssl: false,` and set
   `cloud.auth.config.emulator = { url: 'http://127.0.0.1:9099/' }` right after `initializeAuth`; add
   `http://127.0.0.1:9099 http://127.0.0.1:8080` to the CSP's connect-src; turn off the service worker; serve it on a
   spare port. Sign in from the browser console with `cloud.fb.signInWithEmailAndPassword(cloud.auth, …)`.
   Throwaway accounts are quickest made with the Auth emulator's REST API: POST
   `http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=x` with `{email, password, returnSecureToken: true}`.
   An emulator account survives in the simulator's keychain even after uninstalling the app: sign out in Settings first.
4. Read what's stored: POST `http://127.0.0.1:8080/v1/projects/workout-tracker-705ae/databases/(default)/documents:runQuery`
   with `Authorization: Bearer owner` and a `structuredQuery` over a collection (`allDescendants: true`).
Verified this way on 2026-11-11: web → native and native → web for sets (tick, untick = tombstone, edit), exercises,
workouts, days (timer, finish), plans (create/start on web, Move back on native: both apps compute the same schedule),
settings (units switch live) and the friend code; relaunch sends nothing; sign out + remove, sign back in (all restored);
switching accounts (previous data put aside, nothing uploaded); delete account (docs + auth user gone, the other
account untouched); the stale-sync-state case above.

## How to work on it (what worked so far)
- Build + run: `ios-native/dev/run-sim.sh launch` (or `launch <UDID>` for another simulator). Drive it with the
  iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__control`).
- **Lukas sometimes uses the main Simulator himself while you work.** If the screen shows something you didn't do, stop
  tapping there and use a second simulator (e.g. iPhone 17 `E641F2E5-E089-4733-A07E-CFB29E612F7F`); shut it down after.
- Tests: `xcodebuild test -project Training.xcodeproj -scheme Training -destination 'platform=iOS Simulator,name=iPhone 17'`.
  Run them on a simulator **other** than the one you're looking at (a test run can shut that one down).
  If every run fails with "failed to launch … No such process" (no crash report), the default build folder is stale:
  add `-derivedDataPath <scratch folder>` for a fresh build (2026-11-12).
  69 tests (thousands of checks): performance (`PerformanceTests`: day maths = Calendar, in-place index and remembered days
  = a rebuild after 300 random ticks/edits, file writes in order, chart thinning), friends (`FriendsTests`: gift import = app.js on a messy gift, codes, links, profiles), per-workout timers (`SessionTests`), day groups and Move (`DayGroupsTests`), sync (`SyncTests`: what's sent, merging, web-shaped documents, hash/friend code = app.js), logic, sanitizers (must equal app.js on a messy file), schedule (replays 1,500 steps recorded from
  app.js's own plan code; regenerate with `node ios-native/dev/schedule-fixtures.js`), workouts, exercises, sessions, reorder.
  For new ported logic, get expected values from app.js itself (node) rather than by hand: two hand-written expectations
  were wrong this session.
- Animations: screenshots lag ~1 s and can't show motion. Record and look frame by frame:
  `xcrun simctl io booted recordVideo --codec=h264 --force out.mp4` (stop with `kill -INT`), then
  `swift ios-native/dev/frames.swift out.mp4 dir 30 4` and `swift ios-native/dev/montage.swift dir 0 80 2 0.5 m.png`.
  That's how the "page dots hop in" bug was found.
- The Simulator's injected drags send few touch points (a fast `touch_path` loses the start of the movement); use many
  points ~60 ms apart. Text typed with the tool can arrive after your next tap.
- Swift: default actor isolation is MainActor; model types and pure helpers are `nonisolated`. Firebase callbacks arrive
  on the main queue; they use `MainActor.assumeIsolated`. The project uses
  folder-synced groups: new files in `Training/` and `TrainingTests/` need no project-file edits.
- Gestures on list rows inside a ScrollView: SwiftUI's long-press-then-drag (and `simultaneousGesture(DragGesture)`)
  stops the page scrolling. Use `LongPressDrag` (a UIKit long press, `UI/Today/DayExerciseList.swift`), attached to the
  content *inside* a Button's label so it's asked before the button (attached outside, it never fired).
- In a `LazyVGrid`, every cell across all `ForEach`es needs a distinct id (repeated 0, 1, 2… dropped cells silently).
- Typing in the Simulator: the first keyboard use shows a "slide to type" tip that swallows the next tap. Fast injected
  text can lose characters in fields that reformat as you type (the friend-code field): type a character at a time.
- **Quick injected taps don't flip a SwiftUI Toggle**; use `tap` with `duration: 0.15`. Plain buttons and tabs are
  also more reliable with `duration: 0.15`. Tap coordinates are device points (iPhone 17: 402 × 874), not screenshot pixels.
- Right after booting a simulator, input isn't accepted for ~10 s ("input connection is still starting up"): wait, retry.
- Opening the number pad scrolls the set list up: take a screenshot before tapping a tick, or you'll hit a pad key.
- `xcrun simctl ui <UDID> appearance light|dark` switches the theme. A fresh install (`simctl uninstall` then install)
  gives the sample training, handy for tests.
- A view that's being removed with a transition is still redrawn from the store: if its body reads state that just
  became nil it goes blank instead of sliding away (keep a snapshot, as the number pad does).
- `.sheet` is the "slides up from the bottom" Lukas asked for (Apple's own springs and pull-down). Editors use
  `.interactiveDismissDisabled()` and close with ✕ / ✓.

## Code map (Training/)
- `Model/Models.swift` records (web JSON shape, lenient decoding) · `Format.swift` dates, units, number text, e1RM ·
  `Store.swift` the @Observable store: data + JSON file, set index, ticking, number pad, toasts, new day, whose data ·
  `Groups.swift` workouts on a day, Move · `Sessions.swift` each workout's timer/Finish ·
  `Plans.swift` plan schedule + moving plan days · `Workouts.swift` save/delete/start/end · `Library.swift` exercise
  database, chart series, PRs, summary · `Sanitize.swift` `Clean.*` · `SampleData.swift` · `SyncCore.swift` + `Cloud.swift`
  accounts and sync · `Friends.swift` + `FriendsCloud.swift` friends, profiles, gifts · `Perf.swift` performance tools
  (`-perfData`, `-perfLog`) · `Videos.swift` videos on sets
  (Photos ids, thumbnails, playback, movie sound).
- `UI/RootView` tabs + floating rest/toasts · `Today/` (TodayView, WeekStrip, DayExerciseList + WorkoutGroupView, MoveSheet, CalendarSheet = MonthGrid + CalendarDay) ·
  `Log/` (LogView sheet, SetRow, NumberPad, VideoViews = Link video / thumbnails / player) · `Workouts/` · `Exercises/` · `Summary/` · `Friends/` · `Common/` (Finish, Add, Note,
  Settings sheets; `AccountViews` sign in / sign out / delete account; RestPill, Toast) · `Theme.swift` colours, springs (`Motion`), haptics.

## Lukas's preferences (learned so far)
- Things slide up from the bottom and go back down; Apple's design language, springs with weight, haptics everywhere.
- He judges by feel and reports bugs precisely ("dots hop in", "quick deletes reappear"); reproduce before fixing.
- Small UI changes: just do them. He liked: sheets, grey = in the summary, chart ranges, Add exercise at the top.
- Plain language, short, no code talk. Commit messages `native: <what>` + bullets.
- He's happy to make product calls when given 2–4 concrete options with a recommendation (AskUserQuestion worked well);
  he picked the native-only route for things the web app can't represent.
- He tests by feel on the real phone and reports several issues at once; fix all, verify each in the Simulator.

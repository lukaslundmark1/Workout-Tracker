# Handoff: Training β (native SwiftUI app), next up: polish pass (step 7)

Updated 2026-11-12 at the end of the session that added Friends (friend codes, requests, profiles, sending workouts
and plans). Before that: accounts + sync and the day overhaul (workouts as groups, Move, Finish per workout). **Read in this order:** `../CLAUDE.md` (how Lukas works), this file, `../docs/NATIVE-REBUILD.md`
(the original plan and the data format), the "Fully native app" entries in `../docs/DECISIONS.md` (every choice and why),
`README.md` here. The web app (`../app.js`) is the reference: when docs and code disagree, the code wins.

## Where things stand
- Built and tested in the Simulator (iPhone 17, iOS 27.2, light and dark); 59 unit tests pass. Lukas has the project
  open in Xcode with his Team set; he presses ▶ to put it on his iPhone (every native change needs ▶ again).
- **Nothing since commit `a153241` is committed** (accounts and sync, the day overhaul, per-workout Finish, Friends, the
  `GoogleService-Info.plist`). Lukas was offered a commit several times and hasn't said yes yet: ask once at a natural point
  (commit message style `native: <what>` + bullets). Pushing only publishes the folder on GitHub Pages; it doesn't change the web app.
- `GoogleService-Info.plist` is in `Training/` (Lukas registered the iOS app in Firebase on 2026-11-11), so sign-in works.
  Commit it (not a secret, like the web config in app.js). Whether he has signed in with his real account on the
  β app is unknown: ask before testing anything that would touch it.

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
- Not done: shared exercise database (browse shared entries, "Share to the database" on your own), calendar view outside
  Move, embedded YouTube player, Google sign-in (only if asked), `#add-CODE` invite links opening the β app (they open
  the web app; the β app would need associated domains).

## Next session: polish pass (NATIVE-REBUILD §8 step 7)
All six building steps are done. Ask Lukas how Friends feels on his phone (he hasn't seen it yet: it needs ▶ in Xcode),
then go through what he reports. After the polish pass he decides: replace the Capacitor app for himself, and/or TestFlight
($99/year) so his girlfriend and friends get the β app. Smaller leftovers: shared exercise database, calendar view.

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
  59 tests (thousands of checks): friends (`FriendsTests`: gift import = app.js on a messy gift, codes, links, profiles), per-workout timers (`SessionTests`), day groups and Move (`DayGroupsTests`), sync (`SyncTests`: what's sent, merging, web-shaped documents, hash/friend code = app.js), logic, sanitizers (must equal app.js on a messy file), schedule (replays 1,500 steps recorded from
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
- **Quick injected taps don't flip a SwiftUI Toggle**; use `tap` with `duration: 0.15`.
- `.sheet` is the "slides up from the bottom" Lukas asked for (Apple's own springs and pull-down). Editors use
  `.interactiveDismissDisabled()` and close with ✕ / ✓.

## Code map (Training/)
- `Model/Models.swift` records (web JSON shape, lenient decoding) · `Format.swift` dates, units, number text, e1RM ·
  `Store.swift` the @Observable store: data + JSON file, set index, ticking, number pad, toasts, new day, whose data ·
  `Groups.swift` workouts on a day, Move · `Sessions.swift` each workout's timer/Finish ·
  `Plans.swift` plan schedule + moving plan days · `Workouts.swift` save/delete/start/end · `Library.swift` exercise
  database, chart series, PRs, summary · `Sanitize.swift` `Clean.*` · `SampleData.swift` · `SyncCore.swift` + `Cloud.swift`
  accounts and sync · `Friends.swift` + `FriendsCloud.swift` friends, profiles, gifts.
- `UI/RootView` tabs + floating rest/toasts · `Today/` (TodayView, WeekStrip, DayExerciseList + WorkoutGroupView, MoveSheet) ·
  `Log/` (LogView sheet, SetRow, NumberPad) · `Workouts/` · `Exercises/` · `Summary/` · `Friends/` · `Common/` (Finish, Add, Note,
  Settings sheets; `AccountViews` sign in / sign out / delete account; RestPill, Toast) · `Theme.swift` colours, springs (`Motion`), haptics.

## Lukas's preferences (learned so far)
- Things slide up from the bottom and go back down; Apple's design language, springs with weight, haptics everywhere.
- He judges by feel and reports bugs precisely ("dots hop in", "quick deletes reappear"); reproduce before fixing.
- Small UI changes: just do them. He liked: sheets, grey = in the summary, chart ranges, Add exercise at the top.
- Plain language, short, no code talk. Commit messages `native: <what>` + bullets.
- He's happy to make product calls when given 2–4 concrete options with a recommendation (AskUserQuestion worked well);
  he picked the native-only route for things the web app can't represent.
- He tests by feel on the real phone and reports several issues at once; fix all, verify each in the Simulator.

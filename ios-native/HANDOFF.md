# Handoff: Training β (native SwiftUI app), next up: accounts

Written 2026-11-11 at the end of the session that built everything in `ios-native/` so far.
**Read in this order:** `../CLAUDE.md` (how Lukas works), this file, `../docs/NATIVE-REBUILD.md` (the original plan and the
data format), the "Fully native app" entries in `../docs/DECISIONS.md` (every choice made and why), `README.md` here.
The web app (`../app.js`) is the reference: when docs and code disagree, the code wins.

## Where things stand
Built and tested in the Simulator (iPhone 18 Pro Max, iOS 27.2, light and dark). **Not yet on Lukas's iPhone.** He has
opened the project in Xcode and set his signing Team (`DEVELOPMENT_TEAM` in the project file), so ▶ should work.
Committed to `main` locally (not pushed; pushing only publishes the folder on GitHub Pages, it doesn't change the web app).

Done (steps 0, 1, 3, 4 of NATIVE-REBUILD §8, plus extras Lukas asked for):
- **Today:** week strip (sliding capsule), swipe days, plan-driven days and labels, Can't make it today / Move back a day
  sheet with 7-day previews, Undo move, Do X today, Do it today, rings, progress bar, Finish workout (always shown for
  today), Add exercise / workout (workouts / exercises / database / new exercise), **drag to reorder** (≡ or press-and-hold,
  lift/tick/drop haptics), **red trash** (asks with "Delete" when sets are logged).
- **Exercise screen** (a sheet that slides up; swipe down or ⌄ closes it): Last time → History, note, instructions,
  set rows, ticking, the app's own number pad, add/remove set, page dots, swiping between exercises, rest stopwatch,
  toasts, timer (**tap to start, tap to pause, tap to carry on**; only Finish ends a workout).
- **Finish sheet** and **workout summary** (counts up, PRs, ▲ / ▼ / = against last time).
- **Workouts tab:** Plans | Workouts, workout editor, plan view (Up next, Coming up), plan editor, start/end plan.
- **Exercises tab:** search + Add exercise at the top, the 130-entry database with filters, exercise form, exercise page
  with Swift Charts (Est. 1RM / Heaviest / Volume / Reps; 3M / 6M / 1Y / All; scrub with a finger), history with PRs.
- **Settings (prototype):** units, week start, appearance, import/export backup, start over with sample data.
- Not done: **accounts and sync (next)**, Friends tab and gifts, the rest of Settings (sign out, delete account, default
  sets, name), calendar, shared exercise database (needs sign-in), embedded YouTube player.

## Next session: accounts (NATIVE-REBUILD §8 step 2)
Goal: sign in with email + password to the same Firebase project, and two-way sync in the **exact** web format, so
training logged in either app shows up in the other. Then sign out ("Remove my training from this phone") and, later,
delete account. Google sign-in only if Lukas asks (needs the GoogleSignIn SDK and a URL scheme).

1. **Lukas registers the iOS app** (he does console clicks himself; tell him exactly what to click): console.firebase.google.com
   → project `workout-tracker-705ae` → ⚙ Project settings → General → Your apps → Add app → iOS → bundle id
   `io.github.lukaslundmark1.training.native` → Register → download `GoogleService-Info.plist` → save it into
   `ios-native/Training/` (the folder is synced into the project automatically). Not a secret like a password; the web
   config is in app.js already.
2. **Firebase iOS SDK** via Swift Package Manager (`https://github.com/firebase/firebase-ios-sdk`, products FirebaseAuth +
   FirebaseFirestore) added to the `Training` target. The project file is hand-written (objectVersion 77, folder-synced
   groups): add an `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` and list them in the target's
   `packageProductDependencies`, or let Lukas add it in Xcode (File → Add Package Dependencies…) if editing by hand fails.
   Then `FirebaseApp.configure()` in `TrainingApp`.
3. **Port the sync from app.js** (`COLS`, `claimLocalData`, `startSync`, `listen`, `syncOps`, `pushChanges`, `retryPush`,
   ~app.js lines 2194–2420). Key rules, read from the code:
   - Collections `users/{uid}/{exercises|workouts|days|sets|plans|meta}/{id}`; days use the date as id.
   - **meta is two docs, not one:** `meta/settings` = the settings object, `meta/active` = the active plan or `{planId: null}`
     (NATIVE-REBUILD §5 says one doc; the code says two).
   - Every written doc gets `u = now`; deletes are `{deleted: true, u}` tombstones; never `deleteDoc` a user record.
   - First sign-in on a device: download everything, the account's copy wins on a clash; remember a per-record hash of
     what was last synced (`maps[col][id]`) and `since` (max `u` seen); then push what only this device has.
   - Listener: `where('u', '>', from)` with `from = since − 5 min`, moved on only when `since − from > 30 days`
     (stable query = cheap launches). Skip `hasPendingWrites` echoes and unchanged hashes.
   - Push: compare each record's hash with `maps`; send in batches of ≤ 400; mark as synced immediately and undo the
     marks if the batch is rejected, retrying 15 s, doubling up to 5 min (and on coming back online / foreground).
   - The data on a device belongs to one account (`tt.owner` in the web app): a different account signing in puts the
     previous person's data aside instead of uploading it.
   - Store it natively: a `syncState` JSON file per uid (hashes, since, from), written a moment after changes and when
     the app goes to the background. The Store's `data` didSet is the hook for "something changed → schedule a push"
     (600 ms debounce like the web app). Incoming changes must not clobber what's on screen mid-edit (the web app waits
     for no finger/sheet: `bgRender`); in SwiftUI updating `store.data` is fine, but don't reset `pad`/drafts.
   - Run incoming records through the `Clean.*` sanitizers? The web app doesn't for your own account (only for friends,
     gifts, backups, the shared library), so decoding with the lenient `Codable` models is enough; use `Clean` for those others.
4. **Verify with the web app open at the same time**, on a **test account** (create one with email + password in the app;
   never write to Lukas's real account until he says so). Check: a set ticked on one shows on the other; a delete
   arrives as a tombstone; settings and the active plan sync; plan days moved in one app look the same in the other.
   The native timer's pause is phone-only by design (DECISIONS); resuming moves `session.start`, which syncs normally.
5. Sign-in UI: a sheet like the web app's `sheetSignin` (app.js ~2438) with email, password, Sign in / Create account,
   Forgot password?, friendly errors (`friendlyAuthError`). Settings shows the account and sync status
   ("Backed up", "Syncing…", "Offline — will sync later"). Sign out sheet with "Remove my training from this phone"
   (on by default), like `sheetSignOut` / `wipeDevice`.
6. Friend code (`codeFor`/`ensureCode`) can wait for the Friends step, but `settings.code` must be preserved when syncing.

## How to work on it (what worked in this session)
- Build + run: `ios-native/dev/run-sim.sh launch` (or `launch <UDID>` for another simulator). Drive it with the
  iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__control`).
- **Lukas sometimes uses the main Simulator himself while you work.** If the screen shows something you didn't do, stop
  tapping there and use a second simulator (e.g. iPhone 17 `E641F2E5-E089-4733-A07E-CFB29E612F7F`); shut it down after.
- Tests: `xcodebuild test -project Training.xcodeproj -scheme Training -destination 'platform=iOS Simulator,name=iPhone 17'`.
  Run them on a simulator **other** than the one you're looking at (a test run can shut that one down).
  33 tests (thousands of checks): logic, sanitizers (must equal app.js on a messy file), schedule (replays 1,500 steps recorded from
  app.js's own plan code; regenerate with `node ios-native/dev/schedule-fixtures.js`), workouts, exercises, sessions, reorder.
  For new ported logic, get expected values from app.js itself (node) rather than by hand: two hand-written expectations
  were wrong this session.
- Animations: screenshots lag ~1 s and can't show motion. Record and look frame by frame:
  `xcrun simctl io booted recordVideo --codec=h264 --force out.mp4` (stop with `kill -INT`), then
  `swift ios-native/dev/frames.swift out.mp4 dir 30 4` and `swift ios-native/dev/montage.swift dir 0 80 2 0.5 m.png`.
  That's how the "page dots hop in" bug was found.
- The Simulator's injected drags send few touch points (a fast `touch_path` loses the start of the movement); use many
  points ~60 ms apart. Text typed with the tool can arrive after your next tap.
- Swift: default actor isolation is MainActor; model types and pure helpers are `nonisolated`. The project uses
  folder-synced groups: new files in `Training/` and `TrainingTests/` need no project-file edits.
- `.sheet` is the "slides up from the bottom" Lukas asked for (Apple's own springs and pull-down). Editors use
  `.interactiveDismissDisabled()` and close with ✕ / ✓.

## Code map (Training/)
- `Model/Models.swift` records (web JSON shape, lenient decoding) · `Format.swift` dates, units, number text, e1RM ·
  `Store.swift` the @Observable store: data + JSON file, set index, ticking, number pad, timer/pause, toasts, new day ·
  `Plans.swift` plan schedule + moving plan days · `Workouts.swift` save/delete/start/end · `Library.swift` exercise
  database, chart series, PRs, summary · `Sanitize.swift` `Clean.*` · `SampleData.swift`.
- `UI/RootView` tabs + floating rest/toasts · `Today/` (TodayView, WeekStrip, DayExerciseList, MoveBackSheet) ·
  `Log/` (LogView sheet, SetRow, NumberPad) · `Workouts/` · `Exercises/` · `Summary/` · `Common/` (Finish, Add, Note,
  Settings sheets; RestPill, Toast) · `Theme.swift` colours, springs (`Motion`), haptics.

## Lukas's preferences learned this session
- Things slide up from the bottom and go back down; Apple's design language, springs with weight, haptics everywhere.
- He judges by feel and reports bugs precisely ("dots hop in", "quick deletes reappear"); reproduce before fixing.
- Small UI changes: just do them. He liked: sheets, grey = in the summary, chart ranges, Add exercise at the top.
- Plain language, short, no code talk. Commit messages `native: <what>` + bullets.

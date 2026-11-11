# Training β: the fully native iPhone app (experiment)

A from-scratch SwiftUI version of Training, to compare how a real native app feels next to the current one.
It installs **next to** the current app (different name and id: "Training β"), so nothing you have now changes.
The web app and the current iPhone app (`../native`) are untouched.

## What's in it so far

- The tab bar (Today in the middle with today's date on its icon). Friends says what's coming.
- **Today:** week strip with the sliding capsule (red on today), swipe days left and right, a ring per exercise,
  the progress bar, Finish workout, Add exercise / workout. Drag ≡ (or press and hold a row) to reorder, with haptics;
  the red trash removes an exercise from the day (asks first with "Delete" when it has logged sets).
- **Timer:** tap Start, tap to pause (orange ⏸), tap to carry on; only Finish workout ends a workout. The pause is kept on
  the phone; resuming moves the start later, so the shared data (and the web app) show the duration without the pause.
- **Workout summary** after Finish (and "Workout summary" on a finished day): duration, sets, kg lifted, exercises
  (counting up), personal records, each exercise's best set ▲ / ▼ % / = against last time.
- **Plans:** the active plan fills in the days (day labels like "Pull · Push Pull Legs, day 3 of 6", rest days),
  "Can't make it today" / "Move back a day" with the three choices and their 7-day previews, Undo move,
  "Do X today" on a rest day, "Do it today". The schedule is a line-by-line port of the web app's.
- **Exercise screen:** slides up from the bottom; swipe it down (or tap ⌄) and it slides back down. Last time,
  note, instructions, set rows with ticking, the app's own number pad, add/remove a set, page dots and swiping
  between exercises, the timer at the top right, Finish here.
- Rest stopwatch, "New personal record" and "All planned sets done", the Finish sheet with duration wheels.
- **Workouts tab:** Plans | Workouts. Create and edit workouts (exercises and sets; ⊖ removes, ≡ reorders) and plans
  (rotation of workouts and rest days, length); the plan screen shows the rotation with Up next, the next 10 days
  (tap one to open it in Today), Start plan (date and starting day) and End plan. Editors and the plan screen slide up.
- **Exercises tab:** search and Add exercise at the top, then your exercises (while searching, matches from the database too), the exercise database
  (130 built-in, muscle group and equipment filters, Create your own), the exercise form (name, muscle group, equipment,
  instructions, note, video, Delete), and each exercise's page: progress chart (Swift Charts; Est. 1RM / Heaviest /
  Volume / Reps; 3M / 6M / 1Y / All; drag across it to read any session), note, instructions, history with PRs. "Last time" on the exercise
  screen opens the same chart and history. Today's Add sheet can browse the database and make a new exercise.
- **Backups:** Settings → Import backup loads a backup exported from the web app (so you can try it with your own
  training); Export backup makes a file the web app can import. Everything stays on the phone: no sign-in or sync yet.
- Starts with made-up sample training (a Push Pull Legs plan). Settings → "Start over with the sample data" resets it.

## Put it on your iPhone

You already know these steps from the current app; this is the same, with a different project.

1. In Finder, open **Documents → Workout-Tracker → ios-native** and double-click **Training.xcodeproj**. Xcode opens.
2. In the left column click **Training** (blue icon at the top), then under TARGETS click **Training**,
   open **Signing & Capabilities** and set **Team** to *your name (Personal Team)*.
3. At the top of Xcode choose your iPhone and press **▶**.
4. If the iPhone says *Untrusted Developer*: **Settings → General → VPN & Device Management** → your Apple ID → **Trust**, then ▶ again.

"Training β" appears on your home screen. Like the current app it has to be re-run from Xcode every 7 days
(free Apple ID), and it counts as the 2nd of the 3 apps a free Apple ID can have on a phone.
**Unlike the current app, every change to this one needs ▶ again** (it doesn't load the website).

## For whoever works on this next

Start with `HANDOFF.md` (where things stand, what's next, how to build and test).

- Plan and rules: `../docs/NATIVE-REBUILD.md`. The web app (`../app.js`) is the reference; port its rules exactly.
- Xcode 26+, iOS 26+, SwiftUI + Observation, no third-party code yet. The project uses folder-synced groups,
  so new files in `Training/` or `TrainingTests/` are picked up without editing the project file.
- `Training/Model/`: `Models.swift` (records in the web app's exact JSON shape, lenient decoding), `Format.swift`
  (dates, units, number text, e1RM), `Store.swift` (the data, the set index, ticking, number pad, timer, toasts,
  stale sessions / new day), `SampleData.swift`.
- `Training/UI/`: `RootView` (tabs + floating rest stopwatch and toasts), `Today/` (incl. the Move back sheet), `Log/` (the exercise sheet with its number pad), `Common/`, `Theme.swift`
  (colours, springs, haptics).
- Data is a JSON file in Application Support (`training.json`, same shape as the web app's backup).
- `Training/Model/Plans.swift`: the plan schedule and everything that moves plan days (port of app.js "Plans (rotation)").
  `Training/Model/Sanitize.swift`: the `clean*` sanitizers for anything from outside the phone (backups now; friends,
  gifts and the shared database later).
- Tests (`TrainingTests/`): `LogicTests` (e1RM, PRs, suggestions, units, dates, number pad, backup round trip),
  `SanitizeTests` (must equal app.js's cleanBackup on a deliberately messy file), `ScheduleTests` (replays 1,500 random
  plan changes recorded from app.js's own plan code and must agree on every schedule, Up next, preview and stored day).
  The fixtures are made from app.js by `node ios-native/dev/schedule-fixtures.js`; re-run it if the web app's plan code changes.
  Run with `xcodebuild test -project Training.xcodeproj -scheme Training -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Bundle id `io.github.lukaslundmark1.training.native`; `Training-Info.plist` adds 120 Hz (`CADisableMinimumFrameDurationOnPhone`)
  and the launch background.
- `Training/Model/Workouts.swift` + `Training/UI/Workouts/`: the Workouts tab (save/delete/start/end, tested in `WorkoutsTests`).
- `Training/Model/Library.swift` + `Training/UI/Exercises/`: the exercise database (the web app's LIB_RAW, word for word),
  save/delete exercise, chart series, PRs per day (tested in `ExercisesTests` with numbers from app.js's formulas).
- Not done yet (later steps): Firebase sign-in and sync (then: exercises shared in the database, sharing your own),
  Friends tab and sending workouts/plans, the rest of Settings, calendar,
  the YouTube video playing inside the app (it opens YouTube for now).

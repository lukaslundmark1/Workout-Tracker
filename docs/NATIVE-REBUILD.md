# Handoff: rebuild Training as a fully native iOS app (SwiftUI)

Written 2026-11-11 at the end of the Claude Code session that made v0.27–v0.30.2 and the Capacitor shell.
**Read this whole file first, then `CLAUDE.md` (how Lukas works) and `docs/DECISIONS.md` (every feature and why).**
The web app (`app.js`, `index.html`) is the working reference implementation: when this file and the code disagree, the code wins.

## 1. The goal
Lukas (the owner; doesn't read code; wants a say in UI; hates over-engineering) asked:
> "I'd like to see what it would be like fully rebuilt for iOS."

So this starts as an **experiment to compare feel**, not a commitment. Build a native SwiftUI app that he can install next to the
current one and judge side by side. If he likes it, it grows into the full replacement; if not, nothing is lost.

Why: the current iPhone app (`native/`) is a Capacitor shell around the web app. It works, but web limits leak through
(60 fps cap, worked around with private API; web scrolling/keyboard quirks; everything custom-drawn). A SwiftUI app gets
120 Hz, Apple's real lists, sheets, navigation, scrolling, keyboard and haptics for free.

## 2. Ground rules (do not break)
1. **Don't touch the web app or the Capacitor shell.** `app.js`, `index.html`, `sw.js`, `native/` keep working and stay live for
   Lukas's girlfriend and friends. Put the new app in a new folder: **`ios-native/`** (Xcode project inside).
2. **Same account, same data.** The native app talks to the same Firebase project and the **same Firestore documents, in the same
   format** (section 5), so training logged in either app shows up in the other and friends keep working. Never change the format,
   never hard-delete user records (tombstones only), never write fields the web app's sanitizers would drop.
3. **Same behaviour.** Features, wording and rules match the web app unless Lukas decides otherwise. Things he removed must not
   come back: plate calculator, keep-screen-on, countdown rest timer (it's a stopwatch that counts up), Exercises section on
   profiles, an end-of-workout page.
4. **Firestore rules stay as they are** (`firestore.rules`). If a change is ever needed, tell Lukas exactly what to click (CLAUDE.md).
5. **Ask before big UX decisions**, offering concrete options. Native iOS conventions are welcome where they're better
   (e.g. real `NavigationStack`, `.sheet` with detents, swipe-to-delete), but say what changes and let him choose.
6. Plain language to Lukas, short, no code talk. Commit messages: `native: <what>` then bullets, with the session's attribution lines.

## 3. How to work on it (important: building)
- A SwiftUI app can't be compiled or run without a Mac. **Best setup: run Claude Code on Lukas's MacBook** (the Claude desktop app's
  Code tab, or `claude` in Terminal) in a clone of this repo, so it can build with `xcodebuild`, run the iOS Simulator and see
  errors itself. The Claude desktop app also has an iOS Simulator pane. Tell Lukas this at the start and help him set it up:
  `git clone https://github.com/lukaslundmark1/Workout-Tracker.git` (he has Xcode and Node already; git comes with Xcode).
- If the session runs in the cloud instead, nothing can be compiled there: write code very carefully, keep changes small, and
  have Lukas build in Xcode and send screenshots of errors. Say plainly that it's untested.
- Lukas installs on his iPhone with a **free Apple ID** from Xcode (see `native/README.md` for the exact steps he already knows:
  Team = Personal Team, Developer Mode, trust the developer, ▶, "Connect via network"). Free accounts: apps expire after 7 days
  (re-run ▶ weekly) and max **3** such apps per phone. The Capacitor app is one; this is the second.
- Use a **different bundle id** so both apps can be installed: `io.github.lukaslundmark1.training.native`, display name
  "Training β" (until he decides).
- Unlike the Capacitor app, **every native change needs a rebuild/reinstall**. Batch changes and tell him when to press ▶.

## 4. Environment and versions
- Xcode 26.x, iOS 18+ target is fine (his iPhone is on iOS 26.5; it's a ProMotion phone). SwiftUI + Observation (`@Observable`),
  Swift concurrency. No third-party UI libraries.
- Firebase iOS SDK via Swift Package Manager (`https://github.com/firebase/firebase-ios-sdk`): FirebaseAuth, FirebaseFirestore.
- Firebase project `workout-tracker-705ae` (Spark plan, Firestore in europe-north1). **Lukas must register an iOS app** in the
  console and download `GoogleService-Info.plist`. Steps to give him: console.firebase.google.com → project → ⚙ Project settings
  → General → Your apps → Add app → iOS → bundle id `io.github.lukaslundmark1.training.native` → Register → download
  `GoogleService-Info.plist` → send/put it in `ios-native/` (it's not secret in the way a password is, same as the web config in app.js).
- Auth: email + password works with no extra setup. Google sign-in natively needs the GoogleSignIn SDK plus a URL scheme from the
  plist (REVERSED_CLIENT_ID); do it later, only if he wants it. (Inside the Capacitor app Google sign-in is hidden; he may have
  given his Google account a password via "Forgot password?".)

## 5. Data: must stay compatible with the web app
Weights are always stored in **kg**; dates are local-day strings `YYYY-MM-DD`; times are ms since epoch.

### Records (see `migrate()`, the `clean*` functions and DECISIONS.md → Platform)
- exercise `{ id, name, track: ['weight','reps'], instructions, video, lib?, muscle?, equip?, note? }` (note ≤ 200 chars, private)
- workout `{ id, name, items: [{ exId, sets }] }` (sets 1–10)
- day (keyed by date) `{ items: [{ exId, sets }], workouts: [{ id, name }], plan?: { id, index }, pinned?, rest?, absorb?: 'next'|'round', session?: { start, end? } }`
- set `{ id, exId, date, slot, weight, reps, ts }` — **only ticked sets are stored**; `slot` = row number within that exercise+day.
- plan `{ id, name, weeks (0 = ongoing), days: [{ workoutId | null }] }`
- settings `{ units: 'metric'|'imperial', theme: 'system'|'light'|'dark', weekStart: 1|0, defaultSets: 3, name, code }`
- activePlan `{ planId, begin, start } | null`
- ids: `crypto.randomUUID()` style (any unique string of `[\w:.-]`, ≤ 64 chars). Built-in database exercises are `b:<normalized name>`,
  shared ones `s:<docId>`.

### Firestore layout (see `COLS`, `startSync`, `listen`, `pushChanges` in app.js)
- `users/{uid}/{exercises|workouts|days|sets|plans|meta}/{id}`; days use the date as id; meta has one doc `settings` holding
  `{ settings, active: activePlan || { planId: null } }`.
- **Every doc carries `u`** (ms timestamp of the write). Last writer wins per record by `u`.
- **Deletes are tombstones:** overwrite with `{ deleted: true, u }`. Never `deleteDoc` a user record (other devices would never hear of it).
- The web app listens with `where('u', '>', from)` and skips unchanged records, so the native app must set `u = now` on every write.
- First sign-in on a device: download everything, the account's copy wins on a clash.
- Friends: `codes/{CODE}` = `{ uid, name }`; `links/{uidA_uidB}` (sorted uids) = `{ members, from, status: 'pending'|'accepted', share: { uid: bool }, names: { uid: name }, u }`;
  a friend can read your `users/{uid}/…` only if `share[you]` is true (rules). Friend data shown = last 120 days.
- Gifts (sending workouts/plans): `gifts/{id}` = `{ from, to, fromName, toName, kind: 'workout'|'plan', name, payload, status: 'pending'|'added'|'declined', u }`;
  payload format: see `exPayload`, `workoutPayload`, `planPayload`, and import via `importExercise/importWorkout/importPlan` (with the `GIFT_MAX` limits).
- Shared exercise database: `library/{id}` = `{ name, muscle, equip, track, by, byName, u }`; admins: `admins/{uid}` exists.
- **Friend code must be computed exactly like the web app** (same account → same code on every device):
  ```js
  const CODE_ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  function codeFor(uid, variant) {   // variant 0..5; the first one free (or already yours) in codes/ is used
    const h = (str, seed) => { let x = seed >>> 0; for (let i = 0; i < str.length; i++) { x ^= str.charCodeAt(i); x = Math.imul(x, 16777619) >>> 0; } return x; };
    const a = h(uid + ':' + variant, 2166136261), b = h(variant + ':' + uid, 374761393);
    let out = '';
    for (let i = 0; i < 6; i++) out += CODE_ABC[((i < 3 ? a >>> (i * 5) : b >>> ((i - 3) * 5))) & 31];
    return out;
  }
  ```
  (`charCodeAt` = UTF-16 code units; use 32-bit unsigned wrapping multiply.)
- Everything that comes from someone else (friends' data, library entries, gifts, imported backups) must be sanitized like the
  `clean*` functions do (lengths, number ranges, known values).
- Backup file (Settings → Export/Import): the JSON of the whole data object (same shape as above, `sets` as an array). Keep it compatible.

### Local storage in the native app
Use SwiftData or a simple Codable JSON store, offline-first like the web app: the phone's copy is the truth for the UI; sync sends
changed records (compare with what was last synced) and merges incoming ones. Firestore's own offline cache can help but don't rely
on it as the only store.

## 6. Logic to port exactly (port the code, then test against the web app with the same data)
- **Estimated 1RM (Wathan):** `reps <= 1 ? weight : 100*weight / (48.8 + 53.8*exp(-0.075*reps))`.
- **PR:** a day's best set (by e1RM) that beats every earlier day for that exercise; the very first session doesn't count (`prFor`, `prevBest`).
- **Units:** shown/typed in kg or lb (`LB = 2.20462262`); weight step on the pad ±2.5 kg / ±5 lb; reps ±1.
- **Suggested values for an unticked row:** what you typed → closest finished set above it today → same set last time → last set last time (`suggest`).
- **Plan schedule** (`planSchedule`, `planDayFor`, `upNext`, `moveBack`, `pinToday`, `unrest`, `unpin`, `purgeStalePlanDays`, `virtualDay`,
  `clearEmptyDay`, `canDoToday`, `doToday`): walk day by day from `activePlan.begin`; rest days pass with time; a missed workout waits;
  training the due workout moves the plan on; training a different plan workout does it early and skips its next turn;
  "Move back a day" stores `{ rest: true, absorb }` ('next' / 'round' / none) and its sheet previews each choice for 7 days;
  "Do X today" on a rest day stores a `pinned` copy. This took Lukas three tries; **port it line by line** and verify with the same
  scenarios as `dev/test-schedule.py` and random steps like `dev/fuzz-schedule.py` (compare outputs with the web app).
- **Day labels** (DECISIONS → Day labels), **finish sheet** (log unticked sets as shown; if the last set was > 15 min ago the workout
  ends at that set; a running timer keeps its start), **stale sessions** (a session left running on an earlier day closes at its last
  set unless active in the last 3 hours), **new day while open** (`checkNewDay`), **rest stopwatch** (counts up; starts on ticking a set
  of an exercise with ≥ 2 sets; off on its last set, Finish, or ✕), **toasts** (PR, all planned sets done), **workout summary**.
- **Built-in exercise database:** the 130 entries in `LIB_RAW` (name|muscle|equip), ids `b:` + lowercase name with non-alphanumerics removed.

## 7. Look and feel
Match the current app (see the screenshots `dev/screenshots.py` produces, and `index.html` CSS), but with real native components:
- Colours (light / dark): background `#f2f2f7` / `#000`, cards white / `#1c1c1e`, tint `#007aff` / `#0a84ff`, red `#ff3b30` / `#ff453a`,
  green `#34c759` / `#30d158`, orange for personal records. Blue = actions, red = destructive / today / badges, green = done / active.
- System fonts; rounded numerals (SF Pro Rounded) for numbers; large titles.
- Tab bar: Friends | Workouts | **Today (centre)** | Exercises | Settings; Today's icon shows today's date; Friends has a red badge.
- Today: week strip with a sliding selection capsule (red on today), swipe days left/right (and quick flicks go further), a ring per
  exercise, progress bar, Finish button, "Can't make it today / Move back a day", "Do X today", Undo.
- Exercise screen: "Last time" card, note, instructions, set rows with ticking (pop + check draw + haptic), the app's **own number
  pad** (keep it: kg/Reps switch, ±step, Next → Reps → Next set → Done), page dots and swiping between exercises, Finish here.
- Motion: springs everywhere (SwiftUI `.spring(response:dampingFraction:)`, e.g. 0.52/0.86 for screens, 0.48/0.84 sheets, 0.42/0.9 small),
  nothing changes instantly, respect Reduce Motion.
- Haptics (`UISelectionFeedbackGenerator`, `UIImpactFeedbackGenerator(.medium)`, `UINotificationFeedbackGenerator`): selection ticks
  for choices/tabs/segments/wheels/steppers, impact for ticking a set/deleting/starting the timer, success for finishing/PR/sent,
  warning for arming a delete, error for ticking a set without numbers (see DECISIONS → Motion and haptics).

## 8. Suggested plan (show Lukas after each step)
0. **Prototype to compare feel (first deliverable):** Xcode project in `ios-native/`, the tab bar, the **Today** screen and the
   **exercise logging** screen with the number pad, ticking sets, rest stopwatch and swiping, using **local sample data** (no Firebase yet).
   Lukas installs it next to the current app and decides whether to continue. Ask him what he notices.
1. Local data store + the data model + backup import (so he can load his real data from an exported backup file).
2. Firebase sign-in (email/password) and two-way sync with the exact format in section 5; verify with the web app open at the same time.
3. Workouts tab (workouts, plans, plan editor) and the full plan schedule (port + compare with the web app).
4. Exercises tab, exercise database, history and chart (Swift Charts), PRs, summary.
5. Settings (units, appearance, week start, default sets, export/import, sign out with "remove from this phone", delete account).
6. Friends, profiles, sending/receiving workouts and plans.
7. Polish pass, then Lukas decides: replace the Capacitor app for himself, and/or move everyone to TestFlight ($99/year developer
   program) so his girlfriend and friends get the native app too.

## 9. Testing
- Unit-test the ported logic (schedule, PR, e1RM, suggestions, codeFor, sanitizers) with XCTest, using cases taken from the web app
  (run the same data through `app.js` in a browser with Playwright — see `dev/` — and compare).
- Build and run in the Simulator after every change; look at screenshots in light and dark mode.
- Never test against Lukas's real account in a way that could delete or rewrite his data; use a test account for sync work, and
  tell him before anything touches his real data.

## 10. Where things are in app.js (the reference)
Storage/migration (top), dates, set index `ix()`, `render()`/`go()`, Today (`renderDay`, `dayBodyHTML`), logging (`renderLog`,
`logModel`, `suggest`), number pad (`padOpen`, `padKey`), PRs (`prFor`), rest stopwatch, summary (`renderSummary`), `swipePager`,
timer and Finish (`sheetDuration`), picker, calendar, progress/history/chart (`seriesFor`, `drawChart`), Exercises tab, plans
(`planSchedule` and friends), Workouts tab, cloud sync (`COLS`, `startSync`, `listen`, `syncOps`, `pushChanges`), settings,
friends (`codeFor`, `ensureCode`, links), gifts, sanitizers (`cl`, `clean*`), delete account, profiles, exercise database (`LIB_RAW`),
pull-to-close, sheets, boot (`closeStaleSessions`, `checkNewDay`).

## 11. How Lukas starts it
In a new conversation (ideally Claude Code running on his MacBook in a clone of this repo), he says something like:
> Read docs/NATIVE-REBUILD.md and start the native iOS rebuild.

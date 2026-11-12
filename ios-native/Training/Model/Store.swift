import Foundation
import Observation

/// Index of logged sets (the web app's `ix()`): by exercise+day, by exercise (oldest first), by day,
/// and each exercise's dates. Rebuilt whenever the sets change, except for ticking, unticking and editing one set,
/// which update it in place (`insert` / `remove` / `update` give exactly what a rebuild would: PerformanceTests).
struct SetIndex: Equatable {
    var byExDate: [String: [LoggedSet]] = [:]
    var byEx: [String: [LoggedSet]] = [:]
    var byDate: [String: [LoggedSet]] = [:]
    var exDates: [String: [String]] = [:]

    private static let bySlot: (LoggedSet, LoggedSet) -> Bool = { a, b in a.slot != b.slot ? a.slot < b.slot : a.ts < b.ts }
    private static let byDateSlot: (LoggedSet, LoggedSet) -> Bool = { p, q in p.date != q.date ? p.date < q.date : bySlot(p, q) }

    init(_ sets: [LoggedSet]) {
        for s in sets {
            byExDate[s.exId + "|" + s.date, default: []].append(s)
            byEx[s.exId, default: []].append(s)
            byDate[s.date, default: []].append(s)
        }
        for k in byExDate.keys { byExDate[k]!.sort(by: SetIndex.bySlot) }
        for (id, a) in byEx {
            let sorted = a.sorted(by: SetIndex.byDateSlot)
            byEx[id] = sorted
            var ds: [String] = []
            for s in sorted where ds.last != s.date { ds.append(s.date) }
            exDates[id] = ds
        }
    }

    /// A set appended to the end of the sets (a tick)
    mutating func insert(_ s: LoggedSet) {
        SetIndex.insertSorted(&byExDate[s.exId + "|" + s.date, default: []], s, SetIndex.bySlot)
        SetIndex.insertSorted(&byEx[s.exId, default: []], s, SetIndex.byDateSlot)
        byDate[s.date, default: []].append(s)
        var ds = exDates[s.exId] ?? []
        if !ds.contains(s.date) {
            let at = ds.lastIndex { $0 < s.date }.map { $0 + 1 } ?? 0
            ds.insert(s.date, at: at)
        }
        exDates[s.exId] = ds
    }
    /// A set taken out (an untick)
    mutating func remove(_ s: LoggedSet) {
        let k = s.exId + "|" + s.date
        byExDate[k]?.removeAll { $0.id == s.id }
        if byExDate[k]?.isEmpty == true { byExDate[k] = nil }
        byEx[s.exId]?.removeAll { $0.id == s.id }
        if byEx[s.exId]?.isEmpty == true { byEx[s.exId] = nil }
        byDate[s.date]?.removeAll { $0.id == s.id }
        if byDate[s.date]?.isEmpty == true { byDate[s.date] = nil }
        if byExDate[k] == nil { exDates[s.exId]?.removeAll { $0 == s.date } }
        if exDates[s.exId]?.isEmpty == true { exDates[s.exId] = nil }
    }
    /// A set's weight or reps changed (same id, exercise, day and place)
    mutating func update(_ s: LoggedSet) {
        func put(_ a: inout [LoggedSet]?) { if let i = a?.firstIndex(where: { $0.id == s.id }) { a![i] = s } }
        put(&byExDate[s.exId + "|" + s.date]); put(&byEx[s.exId]); put(&byDate[s.date])
    }
    /// Like `sort` would place it: after every element that doesn't sort after it (new sets go last among equals)
    private static func insertSorted(_ a: inout [LoggedSet], _ s: LoggedSet, _ less: (LoggedSet, LoggedSet) -> Bool) {
        var i = a.count
        while i > 0 && less(s, a[i - 1]) { i -= 1 }
        a.insert(s, at: i)
    }
}

/// Unticked row values: what you typed (strings, like the web app's input fields).
struct Draft: Equatable { var w: String; var r: String }

enum PadField: String { case w, r }
struct PadState: Equatable {
    var day: String
    var exId: String
    var g: String = ""                             // the workout group the row is in
    var i: Int
    var field: PadField
    var fresh: Bool
}

struct ScreenMetrics: Equatable { var height: CGFloat = 852; var safeBottom: CGFloat = 34 }

struct RestState: Codable, Equatable { var start: Double; var exId: String; var date: String }

struct ToastMsg: Equatable, Identifiable {
    enum Kind { case pr, done, info, gift }
    let id = UUID()
    var kind: Kind
    var title: String
    var sub: String?
}

/// What the exercise screen needs for one exercise of a day (the web app's `logModel`).
struct LogModel {
    var k: String
    var day: Day
    var item: WorkoutItem
    var g: String                                  // the workout group (see Groups.swift)
    var ex: Exercise
    var today: [LoggedSet]
    var bySlot: [Int: LoggedSet]
    var n: Int
    var dkey: String
    var prevK: String?
    var prevSets: [LoggedSet]
    var idx: Int
    var total: Int
}

@Observable
final class Store {
    var data: AppData {
        didSet {
            // Any change to the sets makes a new array (the old value is kept here), so comparing the arrays' storage
            // tells whether they changed without comparing thousands of sets. A tick/untick/edit hands over the index
            // already updated for the new array (`nextIdx`); anything else rebuilds it when it's next needed.
            let sid = SetsID(data.sets)
            if sid != SetsID(oldValue.sets) { idx = nextIdx?.id == sid ? nextIdx!.index : nil; prevBestMemo = [:] }
            nextIdx = nil
            // Typed-but-unsaved numbers were in the old unit (here or on another device)
            if data.settings.units != oldValue.settings.units { drafts = [:]; edits = [:]; pad = nil }
            schedCache = nil; dayMemo = [:]; scheduleSave(); onChange?()
            schedulePurge()
        }
    }
    /// Planned days that no longer match the plan are dropped right after a change (once per burst of changes;
    /// it used to run from Today's view, comparing all the data on every redraw)
    @ObservationIgnored private var purgeQueued = false
    private func schedulePurge() {
        guard persist, !purgeQueued else { return }
        purgeQueued = true
        DispatchQueue.main.async { [weak self] in self?.purgeQueued = false; self?.purgeStalePlanDays() }
    }
    /// Which array of sets (its storage), to tell cheaply whether the sets changed
    private struct SetsID: Equatable {
        let base: UnsafeRawPointer?, count: Int
        init(_ a: [LoggedSet]) { base = a.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }; count = a.count }
    }
    @ObservationIgnored private var nextIdx: (id: SetsID, index: SetIndex)?
    /// Replace the sets with `new`, updating the index in place (instead of rebuilding it from every set)
    private func commitSets(_ d: AppData, _ edit: (inout SetIndex) -> Void) {
        var ix = index
        edit(&ix)
        nextIdx = (SetsID(d.sets), ix)
        data = d
    }
    /// Called after every change (cloud sync schedules a push)
    @ObservationIgnored var onChange: (() -> Void)?

    // Screen state (not saved, like the web app's `state`)
    var today: String = Day0.today { didSet { schedCache = nil; dayMemo = [:] } }
    var selected: String = Day0.today
    var drafts: [String: [Int: Draft]] = [:]      // "exId|day" → row → typed values (unticked rows)
    @ObservationIgnored var keptVideos: [String: [String]] = [:]   // "exId|day|row" → videos of an unticked set (back on re-tick)
    var edits: [String: [Int: Draft]] = [:]       // same, for a ticked set being edited (saved when you leave the field)
    var bad: Set<String> = []                      // "exId|day|row|w" fields that need a number (flash red for a moment)
    private var badFlash = 0
    var pad: PadState?
    var rest: RestState? { didSet { saveRest() } }
    var toast: ToastMsg?
    var justTicked: String?
    var justUnticked: String?                      // "exId|day|row"
    var newRow: String?                            // "exId|day|row": grows in
    var tab: AppTab = .today
    var logDepth = 0                               // exercise screens open (one can open from another's History)
    var logOpen: Bool { logDepth > 0 }
    var collapsed: Set<String> = []                // "day|group" folded on Today (open by default)
    var reordering = false                         // an exercise is being dragged on Today (the pages hold still)
    var summaryFor: GroupKey?                      // the workout whose summary should open (after Finish)
    /// Something to open in the Workouts tab (a workout or plan a friend sent, just added)
    enum OpenRequest: Equatable { case workout(String), plan(String) }
    var openRequest: OpenRequest?
    /// Paused timers: day → when it was paused (ms). Kept on this phone only: the shared data format has no pause,
    /// so resuming moves the session's start later by the paused time (the web app then shows the same duration).
    var pausedAt: [String: Double] = [:] { didSet { UserDefaults.standard.set(pausedAt, forKey: "tt.paused") } }                            // the exercise screen is up
    var screen = ScreenMetrics()                   // the phone's screen, for keeping a field above the number pad

    @ObservationIgnored private var idx: SetIndex?
    @ObservationIgnored var schedCache: Schedule?
    /// Days as shown (`dayOf`), worked out once per change of the data or the date: views ask for the same few days
    /// dozens of times per redraw (each row, ring and label), and working one out walks the plan and sorts its items.
    @ObservationIgnored private var dayMemo: [String: Day] = [:]
    /// Best estimated 1RM before a day, per exercise (`prevBest`: a walk through every earlier set), until the sets change
    @ObservationIgnored private var prevBestMemo: [String: Double?] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    @ObservationIgnored private let persist: Bool

    /// `persist: false` keeps everything in memory (tests)
    init(data: AppData? = nil, persist: Bool = true) {
        self.persist = persist
        let disk = data == nil ? Store.loadFromDisk() : nil
        self.data = data ?? disk ?? (Perf.fixture ? SampleData.make(weeks: Perf.dataWeeks, dense: true) : SampleData.make())
        if persist && data == nil && disk == nil { UserDefaults.standard.set(true, forKey: Store.sampleKey) }
        // Installed before accounts existed: the sample training is recognised by its plan
        if persist && data == nil && UserDefaults.standard.object(forKey: Store.sampleKey) == nil {
            UserDefaults.standard.set(self.data.plans.contains { $0.id == "sample-ppl" }, forKey: Store.sampleKey)
        }
        self.rest = Store.loadRest()
        if persist { self.pausedAt = (UserDefaults.standard.dictionary(forKey: "tt.paused") as? [String: Double]) ?? [:] }
        closeStaleSessions()
        linkExistingToLib()
    }

    // MARK: Saving (a JSON file in Application Support; the phone's copy is the truth)

    nonisolated static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Perf.fixture ? "training-perf.json" : "training.json")
    }
    static func loadFromDisk() -> AppData? {
        guard let d = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: d)
    }
    private func scheduleSave() {
        guard persist else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            let snapshot = self.data
            self.writer.write(Store.fileURL, wait: false) { Perf.measure("save (background)") { try? JSONEncoder().encode(snapshot) } }
        }
    }
    /// Saves right away (and waits): the app is being put away, an import, an account change
    func saveNow() {
        guard persist else { return }
        saveTask?.cancel()
        let snapshot = data
        writer.write(Store.fileURL, wait: true) { try? JSONEncoder().encode(snapshot) }
    }
    @ObservationIgnored private let writer = FileWriter()
    /// Replace everything with a backup (already cleaned by `Clean.backup`), like the web app's Import.
    func importBackup(_ d: AppData) {
        pad = nil; drafts = [:]; edits = [:]
        if let r = rest, !d.days.keys.contains(r.date) { rest = nil }
        data = d
        if persist { UserDefaults.standard.set(false, forKey: Store.sampleKey) }
        closeStaleSessions()
        saveNow()
    }
    /// The whole data object as a backup file the web app can import (same JSON shape).
    func exportBackupFile() -> URL? {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let json = try? enc.encode(data) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("training-backup-\(Day0.today).json")
        do { try json.write(to: url, options: .atomic); return url } catch { return nil }
    }

    func resetSampleData() {
        pad = nil; rest = nil; drafts = [:]; edits = [:]
        data = SampleData.make()
        if persist { UserDefaults.standard.set(true, forKey: Store.sampleKey) }
        selected = today
    }

    // MARK: Accounts (whose data is on this phone)

    static let sampleKey = "tt.sample", ownerKey = "tt.owner"
    nonisolated static func stashURL(_ uid: String) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("training.\(uid.filter { $0.isLetter || $0.isNumber }).json")
    }
    /// An empty start that keeps this phone's preferences
    private func emptyData() -> AppData {
        var d = AppData()
        d.settings.units = data.settings.units; d.settings.theme = data.settings.theme
        d.settings.weekStart = data.settings.weekStart; d.settings.defaultSets = data.settings.defaultSets
        return d
    }
    private func clearScreenState() { pad = nil; rest = nil; drafts = [:]; edits = [:]; pausedAt = [:]; selected = today }

    /// The data on this phone belongs to one account (the web app's `claimLocalData`). If a different account signs in,
    /// the previous person's data is put aside (kept on the phone) instead of being uploaded to the new account.
    /// The made-up sample training is never uploaded: the first account to sign in starts from its own data.
    /// Returns whether the data on the phone already belonged to this account (only then does what was last synced
    /// with it still describe the phone's data).
    @discardableResult
    func claimLocalData(_ uid: String) -> Bool {
        guard persist else { return true }
        let ud = UserDefaults.standard
        let owner = ud.string(forKey: Store.ownerKey)
        defer { ud.set(false, forKey: Store.sampleKey); ud.set(uid, forKey: Store.ownerKey) }
        if owner == uid { return true }
        if let owner, owner != uid {
            if let d = try? JSONEncoder().encode(data) { try? d.write(to: Store.stashURL(owner), options: .atomic) }
            let mine = (try? Data(contentsOf: Store.stashURL(uid))).flatMap { try? JSONDecoder().decode(AppData.self, from: $0) }
            clearScreenState()
            data = mine ?? emptyData()
            saveNow()
        } else if owner == nil, ud.bool(forKey: Store.sampleKey) {
            clearScreenState()
            data = emptyData()
            saveNow()
        }
        return false
    }

    /// Changes from the account (another device). What's on screen (number pad, typed values) stays as it is.
    func applyRemote(_ d: AppData) {
        data = d
        if let r = rest, !(data.days[r.date]?.items.contains { $0.exId == r.exId } ?? false) { rest = nil }
    }

    /// Sign out with "Remove my training from this phone": an empty app that keeps the preferences
    func wipeDevice(_ uid: String) {
        clearScreenState()
        data = emptyData()
        try? FileManager.default.removeItem(at: Store.stashURL(uid))
        UserDefaults.standard.removeObject(forKey: Store.ownerKey)
        saveNow()
    }
    private static func loadRest() -> RestState? {
        guard let d = UserDefaults.standard.data(forKey: "tt.rest") else { return nil }
        return try? JSONDecoder().decode(RestState.self, from: d)
    }
    private func saveRest() {
        if let r = rest, let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: "tt.rest") }
        else { UserDefaults.standard.removeObject(forKey: "tt.rest") }
    }

    // MARK: Lookups

    var units: Units { Units(imperial: data.settings.units == "imperial") }
    var index: SetIndex {
        // (a cached index doesn't read `data`: tell observation the caller depends on it, as if it had)
        if let i = idx { access(keyPath: \.data); return i }
        let i = Perf.measure("SetIndex build") { SetIndex(data.sets) }
        idx = i
        return i
    }
    func setsOf(_ exId: String, _ k: String) -> [LoggedSet] { index.byExDate[exId + "|" + k] ?? [] }
    func setsOn(_ k: String) -> [LoggedSet] { index.byDate[k] ?? [] }
    func hasSets(_ k: String) -> Bool { index.byDate[k] != nil }
    func exSets(_ exId: String) -> [LoggedSet] { index.byEx[exId] ?? [] }
    func exDates(_ exId: String) -> [String] { index.exDates[exId] ?? [] }
    func prevDateOf(_ exId: String, _ k: String) -> String? {
        let ds = exDates(exId)
        var lo = 0, hi = ds.count
        while lo < hi { let m = (lo + hi) / 2; if ds[m] < k { lo = m + 1 } else { hi = m } }
        return lo > 0 ? ds[lo - 1] : nil
    }
    func exById(_ id: String) -> Exercise? { data.exercises.first { $0.id == id } }
    func woById(_ id: String) -> Workout? { data.workouts.first { $0.id == id } }

    /// A day as shown: its stored copy, or what the plan has for it, or nothing
    func dayOf(_ k: String) -> Day {
        if let d = dayMemo[k] { access(keyPath: \.data); return d }
        let d = normalized(data.days[k] ?? virtualDay(k) ?? Day())
        dayMemo[k] = d
        return d
    }
    /// Makes a day real (stored), with its exercises in groups. A planned day that hasn't been touched yet is filled in from the plan.
    func ensureDay(_ k: String) {
        let d = normalized(data.days[k] ?? virtualDay(k) ?? Day())
        if data.days[k] != d { data.days[k] = d }
    }

    // MARK: Personal records (a day's best set beats every earlier day; the first session doesn't count)

    func prevBest(_ exId: String, _ k: String) -> Double? {
        let key = exId + "|" + k
        if let m = prevBestMemo[key] { access(keyPath: \.data); return m }
        var b: Double?
        for s in exSets(exId) { if s.date >= k { break }; b = max(b ?? 0, e1rm(s)) }
        prevBestMemo[key] = .some(b)
        return b
    }
    func prFor(_ exId: String, _ k: String) -> (set: LoggedSet, prev: Double, now: Double)? {
        let ss = setsOf(exId, k)
        guard !ss.isEmpty, let pb = prevBest(exId, k) else { return nil }
        let best = ss.dropFirst().reduce(ss[0]) { e1rm($1) > e1rm($0) ? $1 : $0 }
        return e1rm(best) > pb + 1e-6 ? (best, pb, e1rm(best)) : nil
    }

    // MARK: Exercise screen

    func logModel(_ k: String, _ i: Int) -> LogModel? {
        let day = dayOf(k)
        guard i >= 0, i < day.items.count, let ex = exById(day.items[i].exId) else { return nil }
        let item = day.items[i], g = item.w ?? otherGroup
        let today = setsOf(ex.id, k, g)
        var bySlot: [Int: LoggedSet] = [:]
        for s in today { bySlot[s.slot] = s }
        let maxSlot = today.map(\.slot).max() ?? -1
        let prevK = prevDateOf(ex.id, k)
        return LogModel(k: k, day: day, item: item, g: g, ex: ex, today: today, bySlot: bySlot, n: max(item.sets ?? 0, maxSlot + 1),
                        dkey: ex.id + "|" + k + "|" + g, prevK: prevK, prevSets: prevK.map { setsOf(ex.id, $0) } ?? [], idx: i, total: day.items.count)
    }

    /// Suggested values for a row that isn't done yet:
    /// what you typed → the closest finished set above it today → same set last time → last set last time.
    func suggest(_ m: LogModel, _ i: Int) -> Draft {
        if let d = drafts[m.dkey]?[i] { return d }
        var j = i - 1
        while j >= 0 { if let s = m.bySlot[j] { return Draft(w: units.w(s.weight), r: String(s.reps)) }; j -= 1 }
        if let p = (i < m.prevSets.count ? m.prevSets[i] : m.prevSets.last) { return Draft(w: units.w(p.weight), r: String(p.reps)) }
        return Draft(w: "", r: "")
    }
    /// What a row's fields show.
    func rowValues(_ m: LogModel, _ i: Int) -> Draft {
        if let s = m.bySlot[i] { return edits[m.dkey]?[i] ?? Draft(w: units.w(s.weight), r: String(s.reps)) }
        return suggest(m, i)
    }

    func setsLeft(_ k: String) -> Int { dayOf(k).items.reduce(0) { $0 + max(0, ($1.sets ?? 0) - setsOf($1.exId, k, $1.w ?? otherGroup).count) } }

    // MARK: Today

    /// The line under the date (DECISIONS → Day labels).
    func dayLabel(_ k: String) -> String {
        let day = dayOf(k), pd = planDayFor(k)
        var s: String
        if !day.items.isEmpty && !day.workouts.isEmpty { s = day.workouts.map(\.name).joined(separator: " + ") }
        else if !day.items.isEmpty { s = "Custom workout" }
        else if let away = data.days[k]?.away, let pd, let w = pd.workout { s = away.isEmpty ? "Rest day" : "\(w.name) moved to \(Fmt.short(away))" }
        else if let pd, pd.extra { s = "Rest day (moved)" }
        else if let pd, let w = pd.workout { s = "\(w.name) (no exercises yet)" }
        else if pd != nil { s = "Rest day" }
        else if k < today { s = "Nothing logged" }
        else { s = "No workout planned" }
        if !day.items.isEmpty && k < today && !hasSets(k) && day.session == nil { s += " · not trained" }
        if let pd { s += " · \(pd.plan.name)" + (pd.index >= 0 ? ", day \(pd.index + 1) of \(pd.plan.days.count)" : "") }
        if isRunning(k) { s += " · In progress" } else if isFinished(k) { s += " · Finished in \(Fmt.mins(dayDuration(k)))" }
        return s
    }

    // MARK: Ticking sets

    func toggle(_ k: String, _ idx: Int, _ i: Int) { Perf.measure("toggle") { toggleImpl(k, idx, i) } }
    private func toggleImpl(_ k: String, _ idx: Int, _ i: Int) {
        guard let m = logModel(k, idx) else { return }
        let done = m.bySlot[i]
        if var p = pad, p.day == k, p.exId == m.ex.id, p.g == m.g {
            padCommit()
            if p.i == i {
                p.fresh = true
                if done == nil {
                    // a tick that can't log (an empty field) keeps the pad where it is, on the field to fill in
                    let v = suggest(m, i)
                    if parseW(v.w) != nil && parseR(v.r) != nil { let nx = i + 1; pad = nx < m.n ? PadState(day: k, exId: m.ex.id, g: m.g, i: nx, field: .w, fresh: true) : nil }
                    else { pad = p }
                }
                else { pad = p }
            }
        }
        if let done {
            Haptics.select()
            drafts[m.dkey, default: [:]][i] = Draft(w: units.w(done.weight), r: String(done.reps))
            if let v = done.v { keptVideos[m.dkey + "|\(i)"] = v }      // untick + tick again keeps its videos
            var d = data
            d.sets = d.sets.filter { $0.id != done.id }
            commitSets(d) { $0.remove(done) }
            justUnticked = m.dkey + "|\(i)"
            return
        }
        let v = suggest(m, i)
        let w = parseW(v.w), r = parseR(v.r)
        guard let w, let r else {
            // the empty fields flash red, then fade back
            let keys = [w == nil ? m.dkey + "|\(i)|w" : nil, r == nil ? m.dkey + "|\(i)|r" : nil].compactMap { $0 }
            bad.formUnion(keys)                                            // (SetRow animates the red in and out)
            badFlash += 1
            let token = badFlash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, self.badFlash == token else { return }   // tapped again: that flash clears it
                self.bad.subtract(keys)
            }
            Haptics.error(); return
        }
        Haptics.impact()
        let prBefore = prFor(m.ex.id, k)?.set.id
        let newSet = LoggedSet(id: newId(), exId: m.ex.id, date: k, slot: i, weight: units.fromU(w), reps: r, ts: nowMs(), w: m.g,
                               v: keptVideos.removeValue(forKey: m.dkey + "|\(i)"))
        var d = data
        // the first set of a workout today starts its timer
        setSession(k, m.g, sessionOf(k, m.g) ?? (k == today ? Session(start: nowMs()) : nil), in: &d)
        d.sets.append(newSet)
        if let it = d.days[k]!.items.firstIndex(where: { $0.exId == m.ex.id && $0.w == m.g }), i + 1 > (d.days[k]!.items[it].sets ?? 0) {
            d.days[k]!.items[it].sets = i + 1
        }
        commitSets(d) { $0.insert(newSet) }
        justTicked = newSet.id
        drafts[m.dkey]?[i] = nil
        let prNow = prFor(m.ex.id, k)
        let newPR = prNow != nil && prNow!.set.id == newSet.id && prBefore != newSet.id
        if newPR, let prNow {
            Haptics.success(after: 0.14)
            let u = units
            showToast(.init(kind: .pr, title: "New personal record", sub: "\(m.ex.name) · est. 1RM \(String(format: "%.1f", (u.toU(prNow.now) * 10).rounded() / 10)) \(u.u)"))
        }
        if k == today && !isFinished(k, m.g) {
            let total = max(dayOf(k).items.first { $0.exId == m.ex.id && $0.w == m.g }?.sets ?? 0, m.n)
            let doneNow = setsOf(m.ex.id, k, m.g).count
            if total >= 2 && doneNow < total { rest = RestState(start: nowMs(), exId: m.ex.id, date: today) } else { rest = nil }
            if setsLeft(k, m.g) == 0 && !newPR {
                Haptics.success(after: 0.14)
                showToast(.init(kind: .done, title: "All planned sets done", sub: "Finish the workout when you're ready"))
            }
        }
    }

    func addRow(_ k: String, _ idx: Int) {
        ensureDay(k)
        guard let m = logModel(k, idx), let it = data.days[k]?.items.firstIndex(where: { $0.exId == m.ex.id && $0.w == m.g }) else { return }
        Haptics.select()
        newRow = m.dkey + "|\(m.n)"
        data.days[k]!.items[it].sets = m.n + 1
    }
    func removeRow(_ k: String, _ idx: Int) {
        ensureDay(k)
        guard let m = logModel(k, idx), m.n > 0, m.bySlot[m.n - 1] == nil,
              let it = data.days[k]?.items.firstIndex(where: { $0.exId == m.ex.id && $0.w == m.g }) else { return }
        Haptics.select()
        if pad?.exId == m.ex.id && pad?.g == m.g && pad?.i == m.n - 1 { pad = nil }
        data.days[k]!.items[it].sets = m.n - 1
        drafts[m.dkey]?[m.n - 1] = nil
    }

    func setNote(_ exId: String, _ text: String) {
        guard let i = data.exercises.firstIndex(where: { $0.id == exId }) else { return }
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        data.exercises[i].note = t.isEmpty ? nil : t
    }

    // MARK: Number pad

    func padOpen(_ k: String, _ exId: String, _ i: Int, _ field: PadField, group g: String = otherGroup) {
        let was = pad
        if let was, was.i != i || was.field != field || was.exId != exId || was.g != g { padCommit() }
        pad = PadState(day: k, exId: exId, g: g, i: i, field: field, fresh: true)
        if was == nil { Haptics.select() }
    }
    func padClose() {
        guard pad != nil else { return }
        padCommit()
        pad = nil
    }
    private func padModel() -> (LogModel, Int)? {
        guard let p = pad, let idx = dayOf(p.day).items.firstIndex(where: { $0.exId == p.exId && ($0.w ?? otherGroup) == p.g }), let m = logModel(p.day, idx), p.i < m.n else { return nil }
        return (m, p.i)
    }
    /// The value in the field being typed into.
    var padValue: String {
        guard let p = pad, let (m, i) = padModel() else { return "" }
        let v = rowValues(m, i)
        return p.field == .w ? v.w : v.r
    }
    var padRows: Int { padModel()?.0.n ?? 0 }
    /// Leaving a field: a finished set saves its edited numbers.
    func padCommit() {
        guard let (m, i) = padModel(), let s = m.bySlot[i], let e = edits[m.dkey]?[i] else { return }
        edits[m.dkey]?[i] = nil
        guard let w = parseW(e.w), let r = parseR(e.r), let at = data.sets.firstIndex(where: { $0.id == s.id }) else { return }
        var d = data
        d.sets[at].weight = units.fromU(w)
        d.sets[at].reps = r
        guard d.sets[at] != data.sets[at] else { return }
        let edited = d.sets[at]
        commitSets(d) { $0.update(edited) }
    }
    private func padSet(_ v: String) {
        guard let p = pad, let (m, i) = padModel() else { return }
        var cur = rowValues(m, i)
        if p.field == .w { cur.w = v } else { cur.r = v }
        bad.remove(m.dkey + "|\(i)|\(p.field.rawValue)")
        if m.bySlot[i] != nil { edits[m.dkey, default: [:]][i] = cur } else { drafts[m.dkey, default: [:]][i] = cur }
    }
    func padKey(_ k: String) {
        guard var p = pad, padModel() != nil else { padClose(); return }
        let isW = p.field == .w
        switch k {
        case "done": padClose(); return
        case "next": padNext(); return
        case "w", "r": padOpen(p.day, p.exId, p.i, PadField(rawValue: k)!, group: p.g); return
        default: break
        }
        Haptics.select()
        let value = padValue
        if k == "plus" || k == "minus" {
            let cur: Double = isW ? (parseW(value) ?? 0) : Double(parseR(value) ?? 0)
            let next = max(0, cur + (k == "plus" ? 1 : -1) * (isW ? units.step : 1))
            padSet(isW ? num((next * 100).rounded() / 100) : String(max(1, Int(next.rounded()))))
            p.fresh = false; pad = p; return
        }
        var v = p.fresh ? "" : value
        if k == "back" { v = String(v.dropLast()) }
        else if k == "." { if !isW || v.contains(".") { return }; v = (v.isEmpty ? "0" : v) + "." }
        else {
            if v == "0" { v = "" }
            let digits = v.replacingOccurrences(of: ".", with: "").count
            if digits >= (isW ? 5 : 3) { return }
            if let dot = v.firstIndex(of: "."), v[v.index(after: dot)...].count >= 2 { return }
            v += k
        }
        p.fresh = false; pad = p
        padSet(v)
    }
    /// Weight → reps of the same set → weight of the next set → … → done
    func padNext() {
        guard let p = pad else { return }
        if p.field == .w { padOpen(p.day, p.exId, p.i, .r, group: p.g); return }
        if p.i + 1 < padRows { padOpen(p.day, p.exId, p.i + 1, .w, group: p.g); return }
        padClose()
    }

    // MARK: Timer and Finish

    struct Unticked { var exId: String; var g: String; var slot: Int; var w: Double?; var r: Int? }
    func untickedSets(_ k: String, _ g: String) -> [Unticked] {
        var out: [Unticked] = []
        for idx in dayOf(k).items.indices {
            guard let m = logModel(k, idx), m.g == g else { continue }
            for i in 0..<m.n where m.bySlot[i] == nil {
                let v = suggest(m, i)
                out.append(Unticked(exId: m.ex.id, g: m.g, slot: i, w: parseW(v.w), r: parseR(v.r)))
            }
        }
        return out
    }

    // MARK: Toasts

    func showToast(_ t: ToastMsg) {
        toastTask?.cancel()
        toast = t
        toastTask = Task { try? await Task.sleep(for: .seconds(2.8)); if !Task.isCancelled { toast = nil } }
    }

    // MARK: New day / stale sessions (boot and coming back to the app)

    /// A session left running on an earlier day closes at its last set, unless it was active in the last 3 hours.
    func closeStaleSessions() {
        let tk = Day0.today, now = nowMs()
        for (k, d) in data.days where k < tk && d.session?.end == nil && d.session != nil {
            for (g, s) in sessions(k) where s.end == nil {
                let last = lastSetTs(k, g)
                if max(last ?? 0, s.start) > now - 3 * 3600_000 { continue }
                setSession(k, g, Session(start: s.start, end: max(last ?? s.start, s.start)))
                clearPause(k, g)
            }
        }
    }
    /// The phone often resumes the app instead of reopening it: follow the date to the new today.
    func checkNewDay() {
        let tk = Day0.today
        guard tk != today else { return }
        let old = today
        // A workout still active (training past midnight) keeps you on that day until it's finished or idle
        if sessions(old).contains(where: { g, s in s.end == nil && max(lastSetTs(old, g) ?? 0, s.start) > nowMs() - 3 * 3600_000 }) { return }
        today = tk
        if selected == old { selected = tk }
        closeStaleSessions()
        if let r = rest, r.date != tk { rest = nil }
        pausedAt = pausedAt.filter { key, _ in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            return parts[0] >= tk || (parts.count == 2 && isRunning(parts[0], parts[1]))
        }
    }
}

/// Writes files on one background queue, in the order they were asked for, so encoding thousands of sets never holds up
/// the screen; a write that a newer one (or a removal) has overtaken is skipped, so an older copy can never land on top of
/// a newer one (2026-11-12: the background save could finish after a later "save now" and write older data over it).
nonisolated final class FileWriter: @unchecked Sendable {
    private let q = DispatchQueue(label: "io.github.lukaslundmark1.training.files", qos: .utility)
    private let lock = NSLock()
    private var issued = 0
    private func next() -> Int { lock.lock(); defer { lock.unlock() }; issued += 1; return issued }
    private func isLatest(_ g: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return g == issued }

    /// `make` runs on the queue. `wait`: returns once it's written (e.g. when the app is being put away).
    func write(_ url: URL, wait: Bool, _ make: @escaping @Sendable () -> Data?) {
        let g = next()
        let job: @Sendable () -> Void = { [self] in
            guard isLatest(g), let d = make() else { return }
            try? d.write(to: url, options: .atomic)
        }
        if wait { q.sync(execute: job) } else { q.async(execute: job) }
    }
    /// Deletes a file, after anything already queued (which is then skipped)
    func remove(_ url: URL) {
        _ = next()
        q.sync { try? FileManager.default.removeItem(at: url) }
    }
}

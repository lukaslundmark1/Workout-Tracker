import Foundation
import Observation

/// Index of logged sets (the web app's `ix()`): by exercise+day, by exercise (oldest first), by day,
/// and each exercise's dates. Rebuilt whenever the sets change.
struct SetIndex {
    var byExDate: [String: [LoggedSet]] = [:]
    var byEx: [String: [LoggedSet]] = [:]
    var byDate: [String: [LoggedSet]] = [:]
    var exDates: [String: [String]] = [:]

    init(_ sets: [LoggedSet]) {
        for s in sets {
            byExDate[s.exId + "|" + s.date, default: []].append(s)
            byEx[s.exId, default: []].append(s)
            byDate[s.date, default: []].append(s)
        }
        let bySlot: (LoggedSet, LoggedSet) -> Bool = { a, b in a.slot != b.slot ? a.slot < b.slot : a.ts < b.ts }
        for k in byExDate.keys { byExDate[k]!.sort(by: bySlot) }
        for (id, a) in byEx {
            let sorted = a.sorted { p, q in p.date != q.date ? p.date < q.date : bySlot(p, q) }
            byEx[id] = sorted
            var ds: [String] = []
            for s in sorted where ds.last != s.date { ds.append(s.date) }
            exDates[id] = ds
        }
    }
}

/// Unticked row values: what you typed (strings, like the web app's input fields).
struct Draft: Equatable { var w: String; var r: String }

enum PadField: String { case w, r }
struct PadState: Equatable {
    var day: String
    var exId: String
    var i: Int
    var field: PadField
    var fresh: Bool
}

struct ScreenMetrics: Equatable { var height: CGFloat = 852; var safeBottom: CGFloat = 34 }

struct RestState: Codable, Equatable { var start: Double; var exId: String; var date: String }

struct ToastMsg: Equatable, Identifiable {
    enum Kind { case pr, done, info }
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
    var data: AppData { didSet { if data.sets != oldValue.sets { idx = nil }; schedCache = nil; scheduleSave() } }

    // Screen state (not saved, like the web app's `state`)
    var today: String = Day0.today { didSet { schedCache = nil } }
    var selected: String = Day0.today
    var drafts: [String: [Int: Draft]] = [:]      // "exId|day" → row → typed values (unticked rows)
    var edits: [String: [Int: Draft]] = [:]       // same, for a ticked set being edited (saved when you leave the field)
    var bad: Set<String> = []                      // "exId|day|row|w" fields that need a number
    var pad: PadState?
    var rest: RestState? { didSet { saveRest() } }
    var toast: ToastMsg?
    var justTicked: String?
    var justUnticked: String?                      // "exId|day|row"
    var newRow: String?                            // "exId|day|row": grows in
    var tab: AppTab = .today
    var logOpen = false
    var reordering = false                         // an exercise is being dragged on Today (the pages hold still)
    var summaryFor: String?                        // day whose workout summary should open (after Finish)
    /// Paused timers: day → when it was paused (ms). Kept on this phone only: the shared data format has no pause,
    /// so resuming moves the session's start later by the paused time (the web app then shows the same duration).
    var pausedAt: [String: Double] = [:] { didSet { UserDefaults.standard.set(pausedAt, forKey: "tt.paused") } }                            // the exercise screen is up
    var screen = ScreenMetrics()                   // the phone's screen, for keeping a field above the number pad

    @ObservationIgnored private var idx: SetIndex?
    @ObservationIgnored var schedCache: Schedule?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    @ObservationIgnored private let persist: Bool

    /// `persist: false` keeps everything in memory (tests)
    init(data: AppData? = nil, persist: Bool = true) {
        self.persist = persist
        self.data = data ?? Store.loadFromDisk() ?? SampleData.make()
        self.rest = Store.loadRest()
        if persist { self.pausedAt = (UserDefaults.standard.dictionary(forKey: "tt.paused") as? [String: Double]) ?? [:] }
        closeStaleSessions()
        linkExistingToLib()
    }

    // MARK: Saving (a JSON file in Application Support; the phone's copy is the truth)

    nonisolated static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("training.json")
    }
    static func loadFromDisk() -> AppData? {
        guard let d = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: d)
    }
    private func scheduleSave() {
        guard persist else { return }
        saveTask?.cancel()
        let snapshot = data
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: Store.fileURL, options: .atomic) }
        }
    }
    func saveNow() {
        guard persist else { return }
        saveTask?.cancel()
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: Store.fileURL, options: .atomic) }
    }
    /// Replace everything with a backup (already cleaned by `Clean.backup`), like the web app's Import.
    func importBackup(_ d: AppData) {
        pad = nil; drafts = [:]; edits = [:]
        if let r = rest, !d.days.keys.contains(r.date) { rest = nil }
        data = d
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
        selected = today
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
    private var index: SetIndex { if let i = idx { return i }; let i = SetIndex(data.sets); idx = i; return i }
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
    func dayOf(_ k: String) -> Day { data.days[k] ?? virtualDay(k) ?? Day() }
    /// Makes a day real (stored). A planned day that hasn't been touched yet is filled in from the plan.
    func ensureDay(_ k: String) { if data.days[k] == nil { data.days[k] = virtualDay(k) ?? Day() } }

    // MARK: Personal records (a day's best set beats every earlier day; the first session doesn't count)

    func prevBest(_ exId: String, _ k: String) -> Double? {
        var b: Double?
        for s in exSets(exId) { if s.date >= k { break }; b = max(b ?? 0, e1rm(s)) }
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
        let item = day.items[i]
        let today = setsOf(ex.id, k)
        var bySlot: [Int: LoggedSet] = [:]
        for s in today { bySlot[s.slot] = s }
        let maxSlot = today.map(\.slot).max() ?? -1
        let prevK = prevDateOf(ex.id, k)
        return LogModel(k: k, day: day, item: item, ex: ex, today: today, bySlot: bySlot, n: max(item.sets ?? 0, maxSlot + 1),
                        dkey: ex.id + "|" + k, prevK: prevK, prevSets: prevK.map { setsOf(ex.id, $0) } ?? [], idx: i, total: day.items.count)
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

    func setsLeft(_ k: String) -> Int { dayOf(k).items.reduce(0) { $0 + max(0, ($1.sets ?? 0) - setsOf($1.exId, k).count) } }
    func isFinished(_ k: String) -> Bool { dayOf(k).session?.end != nil }
    func isRunning(_ k: String) -> Bool { if let s = dayOf(k).session { return s.end == nil } else { return false } }
    /// Finish is offered for a workout that's running, or for today once something is logged.
    func canFinish(_ k: String) -> Bool { !isFinished(k) && (isRunning(k) || (k == today && hasSets(k))) }

    // MARK: Today

    /// The line under the date (DECISIONS → Day labels).
    func dayLabel(_ k: String) -> String {
        let day = dayOf(k), pd = planDayFor(k)
        var s: String
        if !day.items.isEmpty && !day.workouts.isEmpty { s = day.workouts.map(\.name).joined(separator: " + ") }
        else if !day.items.isEmpty { s = "Custom workout" }
        else if let pd, pd.extra { s = "Rest day (moved)" }
        else if let pd, let w = pd.workout { s = "\(w.name) (no exercises yet)" }
        else if pd != nil { s = "Rest day" }
        else if k < today { s = "Nothing logged" }
        else { s = "No workout planned" }
        if !day.items.isEmpty && k < today && !hasSets(k) && day.session == nil { s += " · not trained" }
        if let pd { s += " · \(pd.plan.name)" + (pd.index >= 0 ? ", day \(pd.index + 1) of \(pd.plan.days.count)" : "") }
        if let ses = day.session { s += ses.end != nil ? " · Finished in \(Fmt.mins(ses.end! - ses.start))" : " · In progress" }
        return s
    }

    func addExercise(_ exId: String, to k: String) {
        ensureDay(k)
        guard !data.days[k]!.items.contains(where: { $0.exId == exId }) else { return }
        data.days[k]!.items.append(WorkoutItem(exId: exId, sets: data.settings.defaultSets))
        Haptics.impact()
    }
    func addWorkout(_ wId: String, to k: String) {
        guard let w = woById(wId) else { return }
        ensureDay(k)
        for it in w.items where !data.days[k]!.items.contains(where: { $0.exId == it.exId }) { data.days[k]!.items.append(it) }
        if !data.days[k]!.workouts.contains(where: { $0.id == w.id }) { data.days[k]!.workouts.append(WorkoutRef(id: w.id, name: w.name)) }
        Haptics.impact()
    }
    func removeExercise(_ exId: String, from k: String) {
        // Already gone (a quick second tap on a row that's still fading out): do nothing. Going on would "empty"
        // the day a second time, which dropped the moved rest day and brought the planned exercises back.
        guard dayOf(k).items.contains(where: { $0.exId == exId }) else { return }
        ensureDay(k)
        Haptics.impact()
        if pad?.exId == exId && pad?.day == k { pad = nil }
        data.days[k]!.items.removeAll { $0.exId == exId }
        data.sets = data.sets.filter { !($0.exId == exId && $0.date == k) }
        drafts[exId + "|" + k] = nil
        if let r = rest, r.date == k, r.exId == exId { rest = nil }
        if data.days[k]!.items.isEmpty { clearEmptyDay(k, byUser: true) }
    }
    func moveExercise(in k: String, from: IndexSet, to: Int) {
        ensureDay(k)
        data.days[k]!.items.move(fromOffsets: from, toOffset: to)
    }
    /// Put a day's exercises in this order (after dragging one)
    func reorderExercises(in k: String, _ ids: [String]) {
        ensureDay(k)
        let items = data.days[k]!.items
        let sorted = ids.compactMap { id in items.first { $0.exId == id } } + items.filter { !ids.contains($0.exId) }
        if sorted.map(\.exId) != items.map(\.exId) { data.days[k]!.items = sorted }
    }
    /// A day whose exercises were all removed starts over: no workout name, no timer/finished state.
    /// If YOU emptied a planned day, it becomes a moved rest day so the plan moves along, like "Move back a day"
    /// with "Just this workout". Otherwise (e.g. an exercise was deleted) the stored copy goes and the plan shows the day again.
    func clearEmptyDay(_ k: String, byUser: Bool = false) {
        guard var d = data.days[k] else { return }
        d.workouts = []
        if !hasSets(k) { d.session = nil; pausedAt[k] = nil }
        if d.session != nil { data.days[k] = d; return }
        if byUser && d.plan != nil && d.pinned != true && k >= today && activePlan != nil {
            var r = Day(); r.rest = true; r.absorb = "next"; data.days[k] = r
        } else { data.days.removeValue(forKey: k) }
    }

    // MARK: Ticking sets

    func toggle(_ k: String, _ idx: Int, _ i: Int) {
        guard let m = logModel(k, idx) else { return }
        let done = m.bySlot[i]
        if var p = pad, p.day == k, p.exId == m.ex.id {
            padCommit()
            if p.i == i {
                p.fresh = true
                if done == nil { let nx = i + 1; pad = nx < m.n ? PadState(day: k, exId: m.ex.id, i: nx, field: .w, fresh: true) : nil }
                else { pad = p }
            }
        }
        if let done {
            Haptics.select()
            drafts[m.dkey, default: [:]][i] = Draft(w: units.w(done.weight), r: String(done.reps))
            data.sets = data.sets.filter { $0.id != done.id }
            justUnticked = m.dkey + "|\(i)"
            return
        }
        let v = suggest(m, i)
        let w = parseW(v.w), r = parseR(v.r)
        if w == nil { bad.insert(m.dkey + "|\(i)|w") }
        if r == nil { bad.insert(m.dkey + "|\(i)|r") }
        guard let w, let r else { Haptics.error(); return }
        Haptics.impact()
        let prBefore = prFor(m.ex.id, k)?.set.id
        let newSet = LoggedSet(id: newId(), exId: m.ex.id, date: k, slot: i, weight: units.fromU(w), reps: r, ts: nowMs())
        var d = data
        d.sets.append(newSet)
        d.days[k] = d.days[k] ?? virtualDay(k) ?? Day()
        if let it = d.days[k]!.items.firstIndex(where: { $0.exId == m.ex.id }), i + 1 > (d.days[k]!.items[it].sets ?? 0) {
            d.days[k]!.items[it].sets = i + 1
        }
        if d.days[k]!.session == nil && k == today { d.days[k]!.session = Session(start: nowMs()) }   // first set today starts the timer
        data = d
        justTicked = newSet.id
        drafts[m.dkey]?[i] = nil
        let prNow = prFor(m.ex.id, k)
        let newPR = prNow != nil && prNow!.set.id == newSet.id && prBefore != newSet.id
        if newPR, let prNow {
            Haptics.success(after: 0.14)
            let u = units
            showToast(.init(kind: .pr, title: "New personal record", sub: "\(m.ex.name) · est. 1RM \(String(format: "%.1f", (u.toU(prNow.now) * 10).rounded() / 10)) \(u.u)"))
        }
        if k == today && !isFinished(k) {
            let total = max(dayOf(k).items.first { $0.exId == m.ex.id }?.sets ?? 0, m.n)
            let doneNow = setsOf(m.ex.id, k).count
            if total >= 2 && doneNow < total { rest = RestState(start: nowMs(), exId: m.ex.id, date: today) } else { rest = nil }
            if setsLeft(k) == 0 && !newPR {
                Haptics.success(after: 0.14)
                showToast(.init(kind: .done, title: "All planned sets done", sub: "Finish the workout when you're ready"))
            }
        }
    }

    func addRow(_ k: String, _ idx: Int) {
        ensureDay(k)
        guard let m = logModel(k, idx), let it = data.days[k]?.items.firstIndex(where: { $0.exId == m.ex.id }) else { return }
        Haptics.select()
        newRow = m.dkey + "|\(m.n)"
        data.days[k]!.items[it].sets = m.n + 1
    }
    func removeRow(_ k: String, _ idx: Int) {
        ensureDay(k)
        guard let m = logModel(k, idx), m.n > 0, m.bySlot[m.n - 1] == nil,
              let it = data.days[k]?.items.firstIndex(where: { $0.exId == m.ex.id }) else { return }
        Haptics.select()
        if pad?.exId == m.ex.id && pad?.i == m.n - 1 { pad = nil }
        data.days[k]!.items[it].sets = m.n - 1
        drafts[m.dkey]?[m.n - 1] = nil
    }

    func setNote(_ exId: String, _ text: String) {
        guard let i = data.exercises.firstIndex(where: { $0.id == exId }) else { return }
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        data.exercises[i].note = t.isEmpty ? nil : t
    }

    // MARK: Number pad

    func padOpen(_ k: String, _ exId: String, _ i: Int, _ field: PadField) {
        let was = pad
        if let was, was.i != i || was.field != field || was.exId != exId { padCommit() }
        pad = PadState(day: k, exId: exId, i: i, field: field, fresh: true)
        if was == nil { Haptics.select() }
    }
    func padClose() {
        guard pad != nil else { return }
        padCommit()
        pad = nil
    }
    private func padModel() -> (LogModel, Int)? {
        guard let p = pad, let idx = dayOf(p.day).items.firstIndex(where: { $0.exId == p.exId }), let m = logModel(p.day, idx), p.i < m.n else { return nil }
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
        data.sets[at].weight = units.fromU(w)
        data.sets[at].reps = r
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
        case "w", "r": padOpen(p.day, p.exId, p.i, PadField(rawValue: k)!); return
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
        if p.field == .w { padOpen(p.day, p.exId, p.i, .r); return }
        if p.i + 1 < padRows { padOpen(p.day, p.exId, p.i + 1, .w); return }
        padClose()
    }

    // MARK: Timer and Finish

    func startTimer(_ k: String) {
        ensureDay(k)
        Haptics.impact()
        pausedAt[k] = nil
        data.days[k]!.session = Session(start: nowMs())
    }
    /// Resume a finished workout (Duration sheet)
    func resume(_ k: String) { pausedAt[k] = nil; data.days[k]?.session?.end = nil }

    func isPaused(_ k: String) -> Bool { pausedAt[k] != nil && isRunning(k) }
    /// The timer's time: up to now, or up to when it was paused
    func elapsed(_ k: String) -> Double {
        guard let s = dayOf(k).session else { return 0 }
        return (s.end ?? pausedAt[k] ?? nowMs()) - s.start
    }
    /// "Now" for a workout: when its timer was paused, or now
    func clock(_ k: String) -> Double { isPaused(k) ? pausedAt[k]! : nowMs() }
    /// Tapping the timer: start it, pause it, carry on. (Ending is only Finish workout.)
    func tapTimer(_ k: String) {
        guard let s = dayOf(k).session else { startTimer(k); return }
        guard s.end == nil else { return }
        if let p = pausedAt[k] {
            Haptics.impact()
            let start = s.start + (nowMs() - p)        // the paused time doesn't count
            pausedAt[k] = nil
            ensureDay(k)
            data.days[k]!.session = Session(start: start)
        } else {
            Haptics.select()
            pausedAt[k] = nowMs()
        }
    }

    struct Unticked { var exId: String; var slot: Int; var w: Double?; var r: Int? }
    func untickedSets(_ k: String) -> [Unticked] {
        var out: [Unticked] = []
        for idx in dayOf(k).items.indices {
            guard let m = logModel(k, idx) else { continue }
            for i in 0..<m.n where m.bySlot[i] == nil {
                let v = suggest(m, i)
                out.append(Unticked(exId: m.ex.id, slot: i, w: parseW(v.w), r: parseR(v.r)))
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
        for (k, d) in data.days where k < tk {
            guard let s = d.session, s.end == nil else { continue }
            let last = setsOn(k).map(\.ts).max()
            if max(last ?? 0, s.start) > now - 3 * 3600_000 { continue }
            data.days[k]!.session = Session(start: s.start, end: max(last ?? s.start, s.start))
            pausedAt[k] = nil
        }
    }
    /// The phone often resumes the app instead of reopening it: follow the date to the new today.
    func checkNewDay() {
        let tk = Day0.today
        guard tk != today else { return }
        let old = today
        // A workout still active (training past midnight) keeps you on that day until it's finished or idle
        if isRunning(old), max(setsOn(old).map(\.ts).max() ?? 0, dayOf(old).session!.start) > nowMs() - 3 * 3600_000 { return }
        today = tk
        if selected == old { selected = tk }
        closeStaleSessions()
        if let r = rest, r.date != tk { rest = nil }
        pausedAt = pausedAt.filter { $0.key >= tk || isRunning($0.key) }
    }
}

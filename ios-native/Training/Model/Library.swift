import Foundation

// The exercise database and your own exercises (app.js → "Exercise database", sheetExForm, progress + history).
// The 130 built-in entries are the web app's LIB_RAW, word for word. Shared entries (Firestore library/) come with sign-in.

nonisolated struct LibEntry: Identifiable, Equatable {
    var id: String          // "b:<normalized name>" for built-in, "s:<docId>" for shared
    var name: String
    var muscle: String
    var equip: String
    var builtin = true
}

nonisolated enum Library {
    static let muscles: [(key: String, name: String)] = [("chest", "Chest"), ("back", "Back"), ("shoulders", "Shoulders"), ("arms", "Arms"),
                                                        ("legs", "Legs"), ("glutes", "Glutes"), ("core", "Core"), ("full", "Full body")]
    static let equipment: [(key: String, name: String)] = [("barbell", "Barbell"), ("dumbbell", "Dumbbell"), ("machine", "Machine"), ("cable", "Cable"),
                                                          ("bodyweight", "Bodyweight"), ("kettlebell", "Kettlebell"), ("other", "Other")]
    static func muscleName(_ k: String?) -> String { muscles.first { $0.key == k }?.name ?? "" }
    static func equipName(_ k: String?) -> String { equipment.first { $0.key == k }?.name ?? "" }
    /// "Bench press" → "benchpress" (how names are compared and how built-in ids are made)
    static func norm(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }.map(Character.init)) }
    static func sub(_ x: LibEntry) -> String { [muscleName(x.muscle), equipName(x.equip)].filter { !$0.isEmpty }.joined(separator: " · ") }

    static let raw = """
Bench press|chest|barbell
Incline bench press|chest|barbell
Decline bench press|chest|barbell
Close-grip bench press|arms|barbell
Dumbbell bench press|chest|dumbbell
Incline dumbbell press|chest|dumbbell
Dumbbell fly|chest|dumbbell
Incline dumbbell fly|chest|dumbbell
Machine chest press|chest|machine
Incline machine press|chest|machine
Pec deck|chest|machine
Cable fly|chest|cable
Low-to-high cable fly|chest|cable
Smith machine bench press|chest|machine
Push-up|chest|bodyweight
Dip|chest|bodyweight
Deadlift|back|barbell
Sumo deadlift|back|barbell
Barbell row|back|barbell
Pendlay row|back|barbell
T-bar row|back|barbell
Rack pull|back|barbell
Dumbbell row|back|dumbbell
Chest-supported dumbbell row|back|dumbbell
Dumbbell pullover|back|dumbbell
Pull-up|back|bodyweight
Chin-up|back|bodyweight
Inverted row|back|bodyweight
Lat pulldown|back|cable
Close-grip lat pulldown|back|cable
Straight-arm pulldown|back|cable
Seated cable row|back|cable
Single-arm cable row|back|cable
Machine row|back|machine
Assisted pull-up|back|machine
Back extension|back|bodyweight
Shrug|back|barbell
Dumbbell shrug|back|dumbbell
Overhead press|shoulders|barbell
Push press|shoulders|barbell
Seated dumbbell shoulder press|shoulders|dumbbell
Arnold press|shoulders|dumbbell
Lateral raise|shoulders|dumbbell
Front raise|shoulders|dumbbell
Rear delt fly|shoulders|dumbbell
Upright row|shoulders|barbell
Machine shoulder press|shoulders|machine
Machine lateral raise|shoulders|machine
Reverse pec deck|shoulders|machine
Cable lateral raise|shoulders|cable
Face pull|shoulders|cable
Cable rear delt fly|shoulders|cable
Barbell curl|arms|barbell
EZ-bar curl|arms|barbell
Preacher curl|arms|barbell
Dumbbell curl|arms|dumbbell
Hammer curl|arms|dumbbell
Incline dumbbell curl|arms|dumbbell
Concentration curl|arms|dumbbell
Cable curl|arms|cable
Machine preacher curl|arms|machine
Skull crusher|arms|barbell
Overhead dumbbell triceps extension|arms|dumbbell
Dumbbell kickback|arms|dumbbell
Triceps pushdown|arms|cable
Rope pushdown|arms|cable
Overhead cable triceps extension|arms|cable
Machine triceps extension|arms|machine
Bench dip|arms|bodyweight
Wrist curl|arms|dumbbell
Reverse curl|arms|barbell
Back squat|legs|barbell
Front squat|legs|barbell
Box squat|legs|barbell
Romanian deadlift|legs|barbell
Good morning|legs|barbell
Barbell lunge|legs|barbell
Goblet squat|legs|dumbbell
Bulgarian split squat|legs|dumbbell
Dumbbell lunge|legs|dumbbell
Walking lunge|legs|dumbbell
Dumbbell Romanian deadlift|legs|dumbbell
Step-up|legs|dumbbell
Leg press|legs|machine
Hack squat|legs|machine
Smith machine squat|legs|machine
Leg extension|legs|machine
Lying leg curl|legs|machine
Seated leg curl|legs|machine
Standing calf raise|legs|machine
Seated calf raise|legs|machine
Leg press calf raise|legs|machine
Pendulum squat|legs|machine
Belt squat|legs|machine
Nordic curl|legs|bodyweight
Bodyweight squat|legs|bodyweight
Hip thrust|glutes|barbell
Glute bridge|glutes|barbell
Dumbbell hip thrust|glutes|dumbbell
Single-leg hip thrust|glutes|bodyweight
Machine hip thrust|glutes|machine
Hip abduction|glutes|machine
Hip adduction|legs|machine
Glute kickback machine|glutes|machine
Cable kickback|glutes|cable
Cable pull-through|glutes|cable
Frog pump|glutes|bodyweight
Kettlebell swing|glutes|kettlebell
Plank|core|bodyweight
Crunch|core|bodyweight
Hanging leg raise|core|bodyweight
Hanging knee raise|core|bodyweight
Lying leg raise|core|bodyweight
Ab wheel rollout|core|other
Russian twist|core|bodyweight
Dead bug|core|bodyweight
Cable crunch|core|cable
Pallof press|core|cable
Cable woodchopper|core|cable
Machine crunch|core|machine
Decline sit-up|core|bodyweight
Side plank|core|bodyweight
Kettlebell goblet squat|legs|kettlebell
Kettlebell deadlift|legs|kettlebell
Turkish get-up|full|kettlebell
Farmer's carry|full|dumbbell
Power clean|full|barbell
Clean and jerk|full|barbell
Snatch|full|barbell
Thruster|full|barbell
"""

    static let builtin: [LibEntry] = raw.split(separator: "\n").map { l in
        let p = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return LibEntry(id: "b:" + norm(p[0]), name: p[0], muscle: p[1], equip: p[2])
    }
    /// Built-in plus shared (shared ones whose name is already built in are left out), by name
    static var all: [LibEntry] { builtin.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }
    static func byId(_ id: String) -> LibEntry? { builtin.first { $0.id == id } }
    static func byName(_ n: String) -> LibEntry? { let k = norm(n); return builtin.first { norm($0.name) == k } }
}

/// The four ways to chart an exercise
nonisolated enum StatKind: String, CaseIterable, Identifiable {
    case e1rm, heaviest, volume, reps
    var id: String { rawValue }
    var label: String { switch self { case .e1rm: "Est. 1RM"; case .heaviest: "Heaviest"; case .volume: "Volume"; case .reps: "Reps" } }
}
/// How far back the chart reaches
nonisolated enum ChartRange: String, CaseIterable, Identifiable {
    case m3, m6, y1, all
    var id: String { rawValue }
    var short: String { switch self { case .m3: "3M"; case .m6: "6M"; case .y1: "1Y"; case .all: "All" } }
    var long: String { switch self { case .m3: "3 months"; case .m6: "6 months"; case .y1: "1 year"; case .all: "All time" } }
    /// The first day shown (nil = everything)
    func start(_ today: String) -> String? {
        let months: Int
        switch self { case .m3: months = 3; case .m6: months = 6; case .y1: months = 12; case .all: return nil }
        return Day0.key(Day0.cal.date(byAdding: .month, value: -months, to: Day0.date(today))!)
    }
}
nonisolated struct StatPoint: Identifiable, Equatable { var k: String; var date: Date; var v: Double; var note: String; var id: String { k } }

extension Store {
    func mineFor(_ x: LibEntry) -> Exercise? {
        let k = Library.norm(x.name)
        return data.exercises.first { $0.lib == x.id || Library.norm($0.name) == k }
    }
    /// Copy a database exercise into your own list (or find the one you already have)
    @discardableResult
    func addFromLib(_ x: LibEntry) -> String {
        if let have = mineFor(x), let i = data.exercises.firstIndex(where: { $0.id == have.id }) {
            if have.lib == nil {
                data.exercises[i].lib = x.id
                if (have.muscle ?? "").isEmpty { data.exercises[i].muscle = x.muscle }
                if (have.equip ?? "").isEmpty { data.exercises[i].equip = x.equip }
            }
            return have.id
        }
        var e = Exercise(id: newId(), name: x.name, muscle: x.muscle, equip: x.equip)
        e.lib = x.id
        data.exercises.append(e)
        Haptics.impact()
        return e.id
    }
    /// Existing exercises with a common name get linked to the database once (adds muscle group + equipment)
    func linkExistingToLib() {
        var d = data, changed = false
        for i in d.exercises.indices where d.exercises[i].lib == nil {
            guard let b = Library.byName(d.exercises[i].name) else { continue }
            d.exercises[i].lib = b.id
            if (d.exercises[i].muscle ?? "").isEmpty { d.exercises[i].muscle = b.muscle }
            if (d.exercises[i].equip ?? "").isEmpty { d.exercises[i].equip = b.equip }
            changed = true
        }
        if changed { data = d }
    }

    struct ExerciseFields { var name = "", muscle = "", equip = "", instructions = "", note = "", video = "" }

    /// New / Edit Exercise. Returns (error, id).
    func saveExercise(id: String?, _ f: ExerciseFields) -> (error: String?, id: String?) {
        let name = String(f.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if name.isEmpty { return ("Give the exercise a name.", nil) }
        if data.exercises.contains(where: { $0.name.lowercased() == name.lowercased() && $0.id != id }) { return ("An exercise with that name already exists.", nil) }
        let video = f.video.trimmingCharacters(in: .whitespacesAndNewlines)
        if !video.isEmpty && ytId(video) == nil { return ("That doesn't look like a YouTube link.", nil) }
        var d = data
        let i: Int
        if let id, let j = d.exercises.firstIndex(where: { $0.id == id }) { i = j }
        else { d.exercises.append(Exercise(id: newId(), name: name)); i = d.exercises.count - 1 }
        let linked = d.exercises[i].lib.flatMap(Library.byId)            // copied from the database
        d.exercises[i].name = name
        d.exercises[i].instructions = String(f.instructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        d.exercises[i].video = video
        d.exercises[i].muscle = f.muscle
        d.exercises[i].equip = f.equip
        let note = String(f.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Clean.noteMax))
        d.exercises[i].note = note.isEmpty ? nil : note
        if let linked, Library.norm(name) != Library.norm(linked.name) { d.exercises[i].lib = nil }   // renamed into your own variation
        else if linked == nil, d.exercises[i].lib != nil, !d.exercises[i].lib!.hasPrefix("s:") { d.exercises[i].lib = nil }
        data = d
        return (nil, d.exercises[i].id)
    }

    /// Deletes the exercise, its logged sets, and takes it out of workouts and days
    func deleteExercise(_ id: String) {
        var d = data
        d.exercises.removeAll { $0.id == id }
        d.sets = d.sets.filter { $0.exId != id }
        for i in d.workouts.indices { d.workouts[i].items.removeAll { $0.exId == id } }
        let touched = d.days.filter { $0.value.items.contains { $0.exId == id } }.map(\.key)
        for k in touched { d.days[k]!.items.removeAll { $0.exId == id } }
        if pad?.exId == id { pad = nil }
        if rest?.exId == id { rest = nil }
        data = d
        for k in touched where data.days[k]?.items.isEmpty == true { clearEmptyDay(k) }
    }

    // MARK: Progress and history

    /// One point per day the exercise was done
    func series(_ exId: String, _ stat: StatKind) -> [StatPoint] {
        let u = units
        return exDates(exId).map { k in
            let ss = setsOf(exId, k)
            let v: Double, note: String
            switch stat {
            case .e1rm:
                let best = ss.dropFirst().reduce(ss[0]) { e1rm($1) > e1rm($0) ? $1 : $0 }
                v = u.toU(e1rm(best)); note = "from \(u.w(best.weight)) × \(best.reps)"
            case .heaviest: v = u.toU(ss.map(\.weight).max() ?? 0); note = Fmt.plural(ss.count, "set")
            case .volume: v = u.toU(ss.reduce(0) { $0 + $1.weight * Double($1.reps) }); note = Fmt.plural(ss.count, "set")
            case .reps: v = Double(ss.reduce(0) { $0 + $1.reps }); note = Fmt.plural(ss.count, "set")
            }
            return StatPoint(k: k, date: Day0.date(k), v: v, note: note)
        }
    }
    /// The chart's points for a range (the latest few months, or everything)
    func series(_ exId: String, _ stat: StatKind, _ range: ChartRange) -> [StatPoint] {
        let all = series(exId, stat)
        guard let from = range.start(today) else { return all }
        return all.filter { $0.k >= from }
    }
    func statUnit(_ s: StatKind) -> String { s == .reps ? "reps" : units.u }
    /// Each day's PR set (best estimated 1RM beating every earlier day), oldest → newest in one pass
    func prSets(_ exId: String) -> [String: String] {
        var out: [String: String] = [:], run: Double?
        for k in exDates(exId) {
            let ss = setsOf(exId, k)
            let top = ss.dropFirst().reduce(ss[0]) { e1rm($1) > e1rm($0) ? $1 : $0 }
            if let r = run, e1rm(top) > r + 1e-6 { out[k] = top.id }
            run = max(run ?? 0, e1rm(top))
        }
        return out
    }
    /// "Today", "Yesterday", "Wed 4 Nov", or with the year when it isn't this year
    func relDay(_ k: String) -> String {
        let n = Day0.between(k, today)
        if n == 0 { return "Today" }
        if n == 1 { return "Yesterday" }
        return Fmt.year(k) == Fmt.year(today) ? Fmt.short(k) : Fmt.dayYear(k)
    }
}

/// The web app's fmtStat: volume and reps as whole numbers with thousands separators, the rest to one decimal
nonisolated func fmtStat(_ v: Double, _ s: StatKind) -> String {
    if s == .volume || s == .reps {
        let f = NumberFormatter(); f.locale = Locale(identifier: "en_GB"); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded()))
    }
    return String(format: "%.1f", (v * 10).rounded() / 10)
}

// MARK: Workout summary (app.js → renderSummary)

struct WorkoutSummary {
    enum Delta: Equatable { case first, up(Int), down(Int), same }
    struct ExRow: Identifiable { var id: String; var name: String; var sets: Int; var best: LoggedSet; var delta: Delta }
    struct PR: Identifiable { var id: String; var name: String; var now: Double; var prev: Double; var set: LoggedSet }
    var title: String
    var durationMs: Double?
    var sets: Int
    var volumeKg: Double
    var exercises: [ExRow]
    var prs: [PR]
}

extension Store {
    func summary(_ k: String) -> WorkoutSummary {
        let d = dayOf(k)
        let ss = setsOn(k).sorted { $0.ts < $1.ts }
        // the day's order first, then anything else logged that day
        var exIds: [String] = []
        for id in d.items.map(\.exId) + ss.map(\.exId) where !exIds.contains(id) && ss.contains(where: { $0.exId == id }) && exById(id) != nil { exIds.append(id) }
        let rows = exIds.map { id -> WorkoutSummary.ExRow in
            let mine = setsOf(id, k)
            let best = mine.dropFirst().reduce(mine[0]) { e1rm($1) > e1rm($0) ? $1 : $0 }
            var delta = WorkoutSummary.Delta.first
            if let pk = prevDateOf(id, k) {
                let pb = setsOf(id, pk).map(e1rm).max() ?? 0
                let pct = Int(floor(((e1rm(best) - pb) / pb) * 100 + 0.5))   // JS Math.round
                delta = pct > 0 ? .up(pct) : pct < 0 ? .down(-pct) : .same
            }
            return .init(id: id, name: exById(id)!.name, sets: mine.count, best: best, delta: delta)
        }
        let prs = exIds.compactMap { id -> WorkoutSummary.PR? in
            guard let p = prFor(id, k) else { return nil }
            return .init(id: id, name: exById(id)!.name, now: p.now, prev: p.prev, set: p.set)
        }
        let dur = d.session.flatMap { s in s.end.map { $0 - s.start } }
        return WorkoutSummary(title: d.workouts.isEmpty ? "Custom workout" : d.workouts.map(\.name).joined(separator: " + "),
                              durationMs: dur, sets: ss.count, volumeKg: ss.reduce(0) { $0 + $1.weight * Double($1.reps) },
                              exercises: rows, prs: prs)
    }
}

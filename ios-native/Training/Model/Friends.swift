import Foundation

// Friends, profiles and sending workouts/plans (app.js → "Friends", "Sending workouts and plans to friends", "Profiles").
// Same Firestore documents as the web app, so a Training β user and a web-app user can be friends:
//   codes/{CODE} = {uid, name}
//   links/{uidA_uidB} = {members, from, status: 'pending'|'accepted', share: {uid: bool}, names: {uid: name}, u}
//   gifts/{id} = {from, to, fromName, toName, kind: 'workout'|'plan', name, payload, status, u}
// This file is the Firebase-free part (tested in FriendsTests); the Firebase side is `Friends` in FriendsCloud.swift.

nonisolated enum FriendsCore {
    /// links/{id}: the two user ids, sorted, joined by _
    static func pairId(_ a: String, _ b: String) -> String { a < b ? a + "_" + b : b + "_" + a }
    /// "ABC123" → "ABC-123"
    static func fmtCode(_ c: String?) -> String {
        guard let c, !c.isEmpty else { return "" }
        return String(c.prefix(3)) + "-" + String(c.dropFirst(3))
    }
    /// What someone typed → at most 6 capital letters and digits
    static func cleanCode(_ s: String) -> String {
        String(s.uppercased().filter { $0.isASCII && ($0.isUppercase || $0.isNumber) }.prefix(6))
    }
    static func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
    static func initial(_ n: String) -> String { String(n.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "?").uppercased() }
    /// The web app's `str`: text, trimmed, at most n characters (UTF-16 units, like JS)
    static func str(_ v: Any?, _ n: Int) -> String {
        Clean.text(Clean.jsString(v).trimmingCharacters(in: .whitespacesAndNewlines), n)
    }
    /// JS parseInt(v, 10) for what JSON can hold (nil when it would be NaN)
    static func parseInt(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            return d.isFinite && abs(d) < 1e15 ? Int(d) : nil
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            var out = "", rest = Substring(t)
            if let f = rest.first, f == "-" || f == "+" { out.append(f); rest = rest.dropFirst() }
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty else { return nil }
            return Int(out + digits.prefix(15))
        default: return nil
        }
    }
}

/// A friendship (or a request), as stored in links/{id}. Names come from the other person, so they're cut to size.
nonisolated struct FriendLink: Identifiable, Equatable {
    var id: String
    var members: [String]
    var from: String
    var status: String
    var share: [String: Bool]
    var names: [String: String]
    var u: Double

    init(id: String, members: [String], from: String, status: String, share: [String: Bool], names: [String: String], u: Double = 0) {
        self.id = id; self.members = members; self.from = from; self.status = status; self.share = share; self.names = names; self.u = u
    }
    init?(id: String, data d: [String: Any]) {
        guard let m = d["members"] as? [String], m.count == 2 else { return nil }
        self.id = id
        members = m
        from = (d["from"] as? String) ?? ""
        status = (d["status"] as? String) == "accepted" ? "accepted" : "pending"
        share = ((d["share"] as? [String: Any]) ?? [:]).mapValues { ($0 as? Bool) == true }
        names = ((d["names"] as? [String: Any]) ?? [:]).mapValues { FriendsCore.str($0, 60) }
        u = Clean.num(d["u"], 0, 9e15)
    }
    var accepted: Bool { status == "accepted" }
    func other(_ me: String) -> String { members.first { $0 != me } ?? "" }
    func name(_ me: String) -> String { let n = names[other(me)] ?? ""; return n.isEmpty ? "Friend" : n }
    func theyShare(_ me: String) -> Bool { share[other(me)] == true }
    func iShare(_ me: String) -> Bool { share[me] == true }
    func incoming(_ me: String) -> Bool { !accepted && from != me }
    func outgoing(_ me: String) -> Bool { !accepted && from == me }
}

// MARK: Gifts (sent workouts and plans)

/// Safety limits on what's accepted from someone else (the web app's GIFT_MAX)
nonisolated enum GiftMax { static let name = 60, instr = 2000, items = 60, days = 120 }

/// An exercise inside a sent item, already cleaned (lengths, known values)
nonisolated struct GiftEx: Equatable {
    var name: String, lib: String, track: [String], instructions: String, video: String, muscle: String, equip: String
    init(_ v: Any?) {
        let x = (v as? [String: Any]) ?? [:]
        let n = FriendsCore.str(x["name"], GiftMax.name)
        name = n.isEmpty ? "Exercise" : n
        lib = FriendsCore.str(x["lib"], 80)
        if let t = x["track"] as? [Any], t.count == 2, (t[0] as? String) == "weight", (t[1] as? String) == "reps" { track = ["weight", "reps"] } else { track = ["weight", "reps"] }
        instructions = FriendsCore.str(x["instructions"], GiftMax.instr)
        let vid = Clean.jsString(x["video"])
        video = ytId(vid) != nil ? FriendsCore.str(x["video"], 200) : ""
        muscle = Clean.oneOf(x["muscle"], Clean.muscles)
        equip = Clean.oneOf(x["equip"], Clean.equipment)
    }
}
nonisolated struct GiftItem: Equatable { var ex: GiftEx; var sets: Int }
nonisolated struct GiftWorkout: Equatable {
    var name: String
    var items: [GiftItem]
    init(_ v: Any?) {
        let w = (v as? [String: Any]) ?? [:]
        let n = FriendsCore.str(w["name"], GiftMax.name)
        name = n.isEmpty ? "Workout" : n
        items = ((w["items"] as? [Any]) ?? []).prefix(GiftMax.items).compactMap { x in
            guard let i = x as? [String: Any], Clean.truthy(i["ex"]) else { return nil }
            let ex = i["ex"]
            let s = FriendsCore.parseInt(i["sets"]).flatMap { $0 == 0 ? nil : $0 } ?? 3      // parseInt(...) || 3
            return GiftItem(ex: GiftEx(ex), sets: max(1, min(10, s)))
        }
    }
}
nonisolated struct GiftPlan: Equatable {
    var name: String
    var weeks: Int
    var workouts: [GiftWorkout]
    var days: [Int?]                 // index into workouts, nil = rest
    init(_ v: Any?) {
        let p = (v as? [String: Any]) ?? [:]
        let n = FriendsCore.str(p["name"], GiftMax.name)
        name = n.isEmpty ? "Plan" : n
        weeks = max(0, min(52, FriendsCore.parseInt(p["weeks"]) ?? 0))
        workouts = ((p["workouts"] as? [Any]) ?? []).prefix(GiftMax.days).map(GiftWorkout.init)
        let nw = workouts.count
        days = ((p["days"] as? [Any]) ?? []).prefix(GiftMax.days).map { x in
            // JS wids[d.w]: a whole number, or text that is one ("1")
            guard let d = x as? [String: Any] else { return nil }
            var i: Int?
            if let w = d["w"] as? NSNumber, CFGetTypeID(w) != CFBooleanGetTypeID(), w.doubleValue == w.doubleValue.rounded(), abs(w.doubleValue) < 1e9 { i = w.intValue }
            if let s = d["w"] as? String, let n = Int(s), String(n) == s { i = n }
            guard let i, i >= 0, i < nw else { return nil }
            return i
        }
    }
}

nonisolated struct Gift: Identifiable, Equatable {
    var id: String
    var from: String, to: String
    var fromName: String, toName: String
    var kind: String                 // "workout" | "plan"
    var name: String
    var status: String               // "pending" | "added" | "declined"
    var u: Double
    var workout: GiftWorkout?
    var plan: GiftPlan?

    init(id: String, data d: [String: Any]) {
        self.id = id
        from = (d["from"] as? String) ?? ""
        to = (d["to"] as? String) ?? ""
        fromName = FriendsCore.str(d["fromName"], 60)
        toName = FriendsCore.str(d["toName"], 60)
        kind = (d["kind"] as? String) == "plan" ? "plan" : "workout"
        let n = FriendsCore.str(d["name"], GiftMax.name)
        name = n.isEmpty ? (kind == "plan" ? "Plan" : "Workout") : n
        status = Clean.oneOf(d["status"], ["pending", "added", "declined"], "pending")
        u = Clean.num(d["u"], 0, 9e15)
        if kind == "plan" { plan = GiftPlan(d["payload"]) } else { workout = GiftWorkout(d["payload"]) }
    }
    var pending: Bool { status == "pending" }
    /// Every exercise in it
    var allItems: [GiftItem] { plan.map { $0.workouts.flatMap(\.items) } ?? workout?.items ?? [] }
    /// "Plan · 7-day rotation · 2 workouts" or "Workout · 5 exercises"
    var summary: String {
        if let p = plan {
            return "Plan · \(p.days.count)-day rotation · \(FriendsCore.plural(p.workouts.count, "workout"))" + (p.weeks > 0 ? " · \(FriendsCore.plural(p.weeks, "week"))" : "")
        }
        return "Workout · \(FriendsCore.plural(workout?.items.count ?? 0, "exercise"))"
    }
}

// What gets sent (self-contained: exercises by name with their details, so it doesn't depend on the sender's ids)
extension AppData {
    func exPayload(_ id: String) -> [String: Any]? {
        guard let e = exercises.first(where: { $0.id == id }) else { return nil }
        return ["name": e.name, "track": e.track, "muscle": e.muscle ?? "", "equip": e.equip ?? "", "lib": e.lib ?? "",
                "instructions": e.instructions, "video": e.video]
    }
    func workoutPayload(_ w: Workout) -> [String: Any] {
        ["name": w.name, "items": w.items.compactMap { i -> [String: Any]? in
            guard let ex = exPayload(i.exId) else { return nil }
            return ["ex": ex, "sets": i.sets ?? 3]
        }]
    }
    func planPayload(_ p: Plan) -> [String: Any] {
        var ids: [String] = []
        for d in p.days { if let id = d.workoutId, workouts.contains(where: { $0.id == id }), !ids.contains(id) { ids.append(id) } }
        return ["name": p.name, "weeks": p.weeks,
                "workouts": ids.map { id in workoutPayload(workouts.first { $0.id == id }!) },
                "days": p.days.map { d -> [String: Any] in ["w": d.workoutId.flatMap { ids.firstIndex(of: $0) } ?? -1] }]
    }

    // Bringing a received item in (importExercise / importWorkout / importPlan). The gift is already cleaned.
    func haveExercise(_ x: GiftEx) -> Exercise? {
        (x.lib.isEmpty ? nil : exercises.first { $0.lib == x.lib }) ?? exercises.first { Library.norm($0.name) == Library.norm(x.name) }
    }
    mutating func importExercise(_ x: GiftEx) -> String {
        if let have = haveExercise(x) { return have.id }
        var e = Exercise(id: newId(), name: x.name, instructions: x.instructions, video: x.video, muscle: x.muscle, equip: x.equip)
        e.track = x.track
        if !x.lib.isEmpty, Library.byId(x.lib) != nil { e.lib = x.lib }
        exercises.append(e)
        return e.id
    }
    private static func uniqueName(_ name: String, _ taken: [String], _ from: String) -> String {
        taken.contains { $0.lowercased() == name.lowercased() } ? "\(name) (\(from))" : name
    }
    mutating func importWorkout(_ w: GiftWorkout, from: String) -> String {
        var items: [WorkoutItem] = []
        for i in w.items { items.append(WorkoutItem(exId: importExercise(i.ex), sets: i.sets)) }
        let id = newId()
        workouts.append(Workout(id: id, name: AppData.uniqueName(w.name, workouts.map(\.name), from), items: items))
        return id
    }
    mutating func importPlan(_ p: GiftPlan, from: String) -> String {
        var wids: [String] = []
        for w in p.workouts { wids.append(importWorkout(w, from: from)) }
        let days = p.days.map { PlanDay(workoutId: $0.map { wids[$0] }) }
        let id = newId()
        plans.append(Plan(id: id, name: AppData.uniqueName(p.name, plans.map(\.name), from), weeks: p.weeks, days: days.isEmpty ? [PlanDay(workoutId: nil)] : days))
        return id
    }
}

// MARK: Profiles (yours from this phone, a friend's from their shared training)

/// The training a profile shows: your own, or a friend's (exercises + the last 120 days, cleaned)
struct ProfileSource {
    var exercises: [Exercise]
    var ix: SetIndex
    var days: [String: Day]
    var mine: Bool
    var at: Double = 0                // when a friend's copy was loaded (ms)

    func exName(_ id: String) -> String { exercises.first { $0.id == id }?.name ?? "Exercise" }

    /// Days that count as a workout, newest first: sets logged, or a finished (or today's running) timer
    func dates(today tk: String) -> [String] {
        var s = Set(ix.byDate.keys.filter { $0 <= tk })
        for (k, d) in days where k <= tk { if let ss = d.session, ss.end != nil || k == tk { s.insert(k) } }
        return s.sorted(by: >)
    }
    func title(_ k: String) -> String {
        let w = days[k]?.workouts ?? []
        return w.isEmpty ? "Custom workout" : w.map(\.name).joined(separator: " + ")
    }
    /// "Yesterday · 5 exercises · 18 sets · 52 min"; the last part is nil while it's running ("in progress")
    func rowSub(_ k: String, relDay: String) -> (text: String, running: Bool) {
        let ss = ix.byDate[k] ?? []
        var bits = [relDay]
        let nEx = Set(ss.map(\.exId)).count
        if nEx > 0 { bits += [Fmt.plural(nEx, "exercise"), Fmt.plural(ss.count, "set")] } else { bits.append("No sets logged") }
        var running = false
        if let s = days[k]?.session { if let e = s.end { bits.append(Fmt.mins(e - s.start)) } else { running = true } }
        return (bits.joined(separator: " · "), running)
    }
    /// The exercises of a day, in the order they were first ticked
    func exercisesOn(_ k: String) -> [String] {
        var out: [String] = []
        for s in (ix.byDate[k] ?? []).sorted(by: { $0.ts < $1.ts }) where !out.contains(s.exId) { out.append(s.exId) }
        return out
    }
}

enum Profile {
    /// "Today", "Yesterday", "3 days", "4 Nov", or "–"
    static func lastTrained(_ k: String?, today: String) -> String {
        guard let k else { return "–" }
        let n = Day0.between(k, today)
        return n == 0 ? "Today" : n == 1 ? "Yesterday" : n < 7 ? "\(n) days" : Fmt.tiny(k)
    }
}

/// A friend's training as it comes from Firestore (documents' data with their ids), cleaned like the web app's `loadFriend`
enum FriendLoad {
    static func source(exercises: [[String: Any]], sets: [[String: Any]], days: [(String, [String: Any])], at: Double) -> ProfileSource {
        let live: ([String: Any]) -> Bool = { ($0["deleted"] as? Bool) != true }
        let ex = exercises.filter(live).compactMap(Clean.exercise)
        let ss = sets.filter(live).compactMap(Clean.set)
        var dd: [String: Any] = [:]
        for (k, d) in days where live(d) { dd[k] = d }
        return ProfileSource(exercises: ex, ix: SetIndex(ss), days: Clean.days(dd), mine: false, at: at)
    }
}

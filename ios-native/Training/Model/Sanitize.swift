import Foundation

// Cleaning data that comes from outside this phone (app.js → "Cleaning data that comes from outside this phone").
// Friends' training, shared database entries, received plans and imported backups are written by other people
// (or come from a file), so every value is checked: text is cut to a sane length, numbers must be real numbers
// in a sensible range, dates must look like dates, ids are plain, unknown fields are dropped.
// Works on parsed JSON (`Any`), exactly like the web app works on whatever JSON.parse gave it.

nonisolated enum Clean {
    static let muscles = ["chest", "back", "shoulders", "arms", "legs", "glutes", "core", "full"]
    static let equipment = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "kettlebell", "other"]
    static let noteMax = 200

    /// JS `String(v)` for the values JSON can hold
    static func jsString(_ v: Any?) -> String {
        switch v {
        case nil, is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return Training.num(n.doubleValue)
        case is [Any]: return ""          // (rare; the web app would join the array)
        default: return "[object Object]"
        }
    }
    /// cl.text: a string (or the value as text), at most n UTF-16 units like JS slice
    static func text(_ v: Any?, _ n: Int = 80) -> String {
        let s = (v is String) ? v as! String : (v == nil || v is NSNull) ? "" : jsString(v)
        let u = Array(s.utf16)
        return u.count <= n ? s : (String(utf16CodeUnits: u, count: n))
    }
    /// cl.id: plain characters only ([\w:.-]), at most 64
    static func id(_ v: Any?) -> String {
        text(v, 64).filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_:.-".contains($0)) }
    }
    /// JS Number(v)
    private static func jsNumber(_ v: Any?) -> Double {
        switch v {
        case nil: return .nan
        case is NSNull: return 0
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            return Double(t) ?? .nan
        default: return .nan
        }
    }
    static func num(_ v: Any?, _ lo: Double, _ hi: Double, _ dflt: Double = 0) -> Double {
        let n = jsNumber(v)
        return n.isFinite ? min(hi, max(lo, n)) : dflt
    }
    /// cl.int (Math.round rounds .5 up)
    static func int(_ v: Any?, _ lo: Double, _ hi: Double, _ dflt: Double = 0) -> Int {
        Int((num(v, lo, hi, dflt) + 0.5).rounded(.down))
    }
    static func date(_ v: Any?) -> String? {
        guard let s = v as? String, s.utf8.count == 10, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }
    static func oneOf(_ v: Any?, _ list: [String], _ dflt: String = "") -> String {
        if let s = v as? String, list.contains(s) { return s }
        return dflt
    }
    static func truthy(_ v: Any?) -> Bool {
        switch v {
        case nil, is NSNull: return false
        case let n as NSNumber: return n.doubleValue != 0 && !n.doubleValue.isNaN
        case let s as String: return !s.isEmpty
        default: return true
        }
    }
    private static func track(_ t: Any?) -> [String] {
        if let a = t as? [Any], a.count == 2, (a[0] as? String) == "weight", (a[1] as? String) == "reps" { return ["weight", "reps"] }
        return ["weight", "reps"]
    }

    static func set(_ v: Any?) -> LoggedSet? {
        guard let s = v as? [String: Any], let date = date(s["date"]), truthy(s["id"]), truthy(s["exId"]) else { return nil }
        return LoggedSet(id: id(s["id"]), exId: id(s["exId"]), date: date, slot: int(s["slot"], 0, 50),
                         weight: num(s["weight"], 0, 2000), reps: int(s["reps"], 0, 1000), ts: num(s["ts"], 0, 9e15))
    }
    static func exercise(_ v: Any?) -> Exercise? {
        guard let e = v as? [String: Any], truthy(e["id"]) else { return nil }
        let name = text(e["name"], 60).trimmingCharacters(in: .whitespacesAndNewlines)
        var out = Exercise(id: id(e["id"]), name: name.isEmpty ? "Exercise" : name,
                           instructions: text(e["instructions"], 2000),
                           video: ytId(jsString(e["video"])) != nil ? text(e["video"], 200) : "",
                           muscle: oneOf(e["muscle"], muscles), equip: oneOf(e["equip"], equipment))
        out.track = track(e["track"])
        if truthy(e["lib"]) { out.lib = text(e["lib"], 80) }
        if truthy(e["note"]) { out.note = text(e["note"], noteMax) }
        return out
    }
    static func day(_ v: Any?) -> Day? {
        guard let d = v as? [String: Any] else { return nil }
        var out = Day()
        out.items = ((d["items"] as? [Any]) ?? []).prefix(60).compactMap { x -> WorkoutItem? in
            guard let i = x as? [String: Any], truthy(i["exId"]) else { return nil }
            let sets: Int? = (i["sets"] == nil || i["sets"] is NSNull) ? nil : int(i["sets"], 0, 50)
            return WorkoutItem(exId: id(i["exId"]), sets: sets)
        }
        out.workouts = ((d["workouts"] as? [Any]) ?? []).prefix(10).compactMap { x -> WorkoutRef? in
            guard let w = x as? [String: Any], truthy(w["id"]) else { return nil }
            return WorkoutRef(id: id(w["id"]), name: text(w["name"], 60))
        }
        if let s = d["session"] as? [String: Any] {
            out.session = Session(start: num(s["start"], 0, 9e15))
            if s["end"] != nil && !(s["end"] is NSNull) { out.session!.end = num(s["end"], 0, 9e15) }
        }
        if let p = d["plan"] as? [String: Any] { out.plan = PlanRef(id: id(p["id"]), index: int(p["index"], 0, 500)) }
        if truthy(d["pinned"]) { out.pinned = true }
        if truthy(d["rest"]) { out.rest = true }
        if let a = d["absorb"] as? String, a == "next" || a == "round" { out.absorb = a }
        return out
    }
    static func days(_ v: Any?) -> [String: Day] {
        var out: [String: Day] = [:]
        for (k, d) in (v as? [String: Any]) ?? [:] { if date(k) != nil, let c = day(d) { out[k] = c } }
        return out
    }
    static func workout(_ v: Any?) -> Workout? {
        guard let w = v as? [String: Any], truthy(w["id"]) else { return nil }
        let name = text(w["name"], 60).trimmingCharacters(in: .whitespacesAndNewlines)
        let items = ((w["items"] as? [Any]) ?? []).prefix(60).compactMap { x -> WorkoutItem? in
            guard let i = x as? [String: Any], truthy(i["exId"]) else { return nil }
            return WorkoutItem(exId: id(i["exId"]), sets: int(i["sets"], 1, 10, 3))
        }
        return Workout(id: id(w["id"]), name: name.isEmpty ? "Workout" : name, items: items)
    }
    static func plan(_ v: Any?) -> Plan? {
        guard let p = v as? [String: Any], truthy(p["id"]) else { return nil }
        let name = text(p["name"], 60).trimmingCharacters(in: .whitespacesAndNewlines)
        let days = ((p["days"] as? [Any]) ?? []).prefix(120).map { x -> PlanDay in
            let d = x as? [String: Any]
            return PlanDay(workoutId: truthy(d?["workoutId"]) ? id(d?["workoutId"]) : nil)
        }
        return Plan(id: id(p["id"]), name: name.isEmpty ? "Plan" : name, weeks: int(p["weeks"], 0, 52), days: Array(days))
    }

    /// A whole backup file (Settings → Import). nil when it isn't a Training backup.
    static func backup(_ json: Data) -> AppData? {
        guard let d = (try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed])) as? [String: Any],
              let exercises = d["exercises"] as? [Any], let sets = d["sets"] as? [Any] else { return nil }
        let st = (d["settings"] as? [String: Any]) ?? [:]
        var out = AppData()
        out.exercises = exercises.compactMap(exercise)
        out.sets = sets.compactMap(set)
        out.days = days(d["days"])
        out.workouts = ((d["workouts"] as? [Any]) ?? []).compactMap(workout)
        out.plans = ((d["plans"] as? [Any]) ?? []).compactMap(plan)
        if let ap = d["activePlan"] as? [String: Any], let begin = date(ap["begin"]), let start = date(ap["start"]) {
            out.activePlan = ActivePlan(planId: id(ap["planId"]), begin: begin, start: start)
        }
        var s = Settings()
        s.units = oneOf(st["units"], ["metric", "imperial"], "metric")
        s.theme = oneOf(st["theme"], ["system", "light", "dark"], "system")
        if let w = st["weekStart"] as? NSNumber, CFGetTypeID(w) != CFBooleanGetTypeID(), w.doubleValue == 0 { s.weekStart = 0 } else { s.weekStart = 1 }
        s.defaultSets = int(st["defaultSets"], 1, 10, 3)
        s.name = text(st["name"], 40)
        if truthy(st["code"]) { s.code = text(st["code"], 8).filter { $0.isASCII && ($0.isUppercase || $0.isNumber) } }
        out.settings = s
        return out
    }
}

/// The YouTube video id in a link, or nil (app.js `ytId`).
nonisolated func ytId(_ url: String) -> String? {
    let pattern = #"(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/))([\w-]{11})"#
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
          let r = Range(m.range(at: 1), in: url) else { return nil }
    return String(url[r])
}

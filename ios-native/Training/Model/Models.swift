import Foundation

// The records, in exactly the shape the web app stores them (docs/NATIVE-REBUILD.md §5).
// Weights are kg, dates are local-day keys "YYYY-MM-DD", times are ms since 1970.
// Decoding is lenient (missing fields get the web app's defaults, numbers may arrive as Int or Double),
// and unknown optional fields are kept so nothing written by the web app is lost.

nonisolated struct Exercise: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var track: [String] = ["weight", "reps"]
    var instructions: String = ""
    var video: String = ""
    var lib: String?
    var muscle: String?
    var equip: String?
    var note: String?

    init(id: String, name: String, instructions: String = "", video: String = "", muscle: String? = nil, equip: String? = nil, note: String? = nil) {
        self.id = id; self.name = name; self.instructions = instructions; self.video = video
        self.muscle = muscle; self.equip = equip; self.note = note
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        track = (try? c.decode([String].self, forKey: .track)) ?? ["weight", "reps"]
        instructions = (try? c.decode(String.self, forKey: .instructions)) ?? ""
        video = (try? c.decode(String.self, forKey: .video)) ?? ""
        lib = try? c.decodeIfPresent(String.self, forKey: .lib)
        muscle = try? c.decodeIfPresent(String.self, forKey: .muscle)
        equip = try? c.decodeIfPresent(String.self, forKey: .equip)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}

nonisolated struct WorkoutItem: Codable, Equatable {
    var exId: String
    var sets: Int?
    init(exId: String, sets: Int?) { self.exId = exId; self.sets = sets }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        exId = try c.decode(String.self, forKey: .exId)
        sets = c.lenientInt(.sets)
    }
}

nonisolated struct Workout: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var items: [WorkoutItem]
}

nonisolated struct WorkoutRef: Codable, Equatable { var id: String; var name: String }
nonisolated struct PlanRef: Codable, Equatable {
    var id: String; var index: Int
    init(id: String, index: Int) { self.id = id; self.index = index }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        index = c.lenientInt(.index) ?? 0
    }
}
nonisolated struct Session: Codable, Equatable {
    var start: Double
    var end: Double?
    init(start: Double, end: Double? = nil) { self.start = start; self.end = end }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        start = c.lenientDouble(.start) ?? 0
        end = c.lenientDouble(.end)
    }
}

nonisolated struct Day: Codable, Equatable {
    var items: [WorkoutItem] = []
    var workouts: [WorkoutRef] = []
    var plan: PlanRef?
    var pinned: Bool?
    var rest: Bool?
    var absorb: String?
    var session: Session?

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([WorkoutItem].self, forKey: .items)) ?? []
        workouts = (try? c.decode([WorkoutRef].self, forKey: .workouts)) ?? []
        plan = try? c.decodeIfPresent(PlanRef.self, forKey: .plan)
        pinned = try? c.decodeIfPresent(Bool.self, forKey: .pinned)
        rest = try? c.decodeIfPresent(Bool.self, forKey: .rest)
        absorb = try? c.decodeIfPresent(String.self, forKey: .absorb)
        session = try? c.decodeIfPresent(Session.self, forKey: .session)
    }
}

/// A logged (ticked) set. Only ticked sets are stored; `slot` is the row number within that exercise + day.
nonisolated struct LoggedSet: Codable, Identifiable, Equatable {
    var id: String
    var exId: String
    var date: String
    var slot: Int
    var weight: Double
    var reps: Int
    var ts: Double

    init(id: String, exId: String, date: String, slot: Int, weight: Double, reps: Int, ts: Double) {
        self.id = id; self.exId = exId; self.date = date; self.slot = slot; self.weight = weight; self.reps = reps; self.ts = ts
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        exId = try c.decode(String.self, forKey: .exId)
        date = try c.decode(String.self, forKey: .date)
        slot = c.lenientInt(.slot) ?? 0
        weight = c.lenientDouble(.weight) ?? 0
        reps = c.lenientInt(.reps) ?? 0
        ts = c.lenientDouble(.ts) ?? 0
    }
}

nonisolated struct PlanDay: Codable, Equatable { var workoutId: String? }
nonisolated struct Plan: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var weeks: Int
    var days: [PlanDay]
}
nonisolated struct ActivePlan: Codable, Equatable { var planId: String; var begin: String; var start: String? }

nonisolated struct Settings: Codable, Equatable {
    var units: String = "metric"
    var theme: String = "system"
    var weekStart: Int = 1
    var defaultSets: Int = 3
    var name: String = ""
    var code: String?

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        units = (try? c.decode(String.self, forKey: .units)) ?? "metric"
        theme = (try? c.decode(String.self, forKey: .theme)) ?? "system"
        weekStart = c.lenientInt(.weekStart) ?? 1
        defaultSets = c.lenientInt(.defaultSets) ?? 3
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        code = try? c.decodeIfPresent(String.self, forKey: .code)
    }
}

/// Everything on the phone. Same shape as the web app's backup file (`sets` as one array).
nonisolated struct AppData: Codable, Equatable {
    var exercises: [Exercise] = []
    var workouts: [Workout] = []
    var days: [String: Day] = [:]
    var sets: [LoggedSet] = []
    var plans: [Plan] = []
    var activePlan: ActivePlan?
    var settings = Settings()
    var version: Int = 3

    enum CodingKeys: String, CodingKey { case exercises, workouts, days, sets, plans, activePlan, settings, version }

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        exercises = (try? c.decode([Exercise].self, forKey: .exercises)) ?? []
        workouts = (try? c.decode([Workout].self, forKey: .workouts)) ?? []
        days = (try? c.decode([String: Day].self, forKey: .days)) ?? [:]
        sets = (try? c.decode([LoggedSet].self, forKey: .sets)) ?? []
        plans = (try? c.decode([Plan].self, forKey: .plans)) ?? []
        activePlan = try? c.decodeIfPresent(ActivePlan.self, forKey: .activePlan)
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        version = 3
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(exercises, forKey: .exercises)
        try c.encode(workouts, forKey: .workouts)
        try c.encode(days, forKey: .days)
        try c.encode(sets, forKey: .sets)
        try c.encode(plans, forKey: .plans)
        try c.encode(activePlan, forKey: .activePlan)   // null when there's none, like the web app
        try c.encode(settings, forKey: .settings)
        try c.encode(version, forKey: .version)
    }
}

nonisolated extension KeyedDecodingContainer {
    func lenientInt(_ k: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: k), v.isFinite { return Int(v) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Int(s) }
        return nil
    }
    func lenientDouble(_ k: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: k), v.isFinite { return v }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }
}

nonisolated func newId() -> String { UUID().uuidString.lowercased() }
nonisolated func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

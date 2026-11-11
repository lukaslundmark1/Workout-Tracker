import Foundation

// Plans (rotation), ported line by line from app.js → "Plans (rotation)".
// A plan is an ORDER of days (Day 1, Day 2, …; rest days count) that repeats, laid out on the calendar from its start.
// The schedule is worked out by walking day by day from the start:
//  • Rest days pass with time. A planned workout you don't do waits for you (everything after it moves along).
//  • Training the workout that's due moves the plan on. Training a different plan workout (e.g. on a rest day) does that
//    one early: its next turn is skipped, so the rest of the week stays the same.
//  • "Move back a day" stores an extra rest day ({ rest: true, absorb }) where absorb says how far the change reaches:
//    'next' = the next rest day is used up, 'round' = the round's (week's) last rest day is used up, none = from now on.
//  • "Do it today" on a rest day stores today's copy of the next workout ({ pinned: true }).
// Planned days are read from the schedule until you touch them; then the day keeps its own copy.

struct SchedEntry: Equatable {
    var index: Int?          // which day of the plan
    var own = false          // a stored day that is (or does) a plan day
    var extra = false        // a moved rest day
    var absorb: String?
    var other = false        // you're doing something else that day
}

struct Schedule {
    var tk: String
    var map: [String: SchedEntry] = [:]
    var plan: Plan?
    var ap: ActivePlan?
}

struct PlanDayInfo {
    var plan: Plan
    var ap: ActivePlan
    var index: Int           // -1 for a moved rest day
    var workout: Workout?
    var extra = false
}

extension Store {
    func planById(_ id: String) -> Plan? { data.plans.first { $0.id == id } }
    var activePlan: ActivePlan? { if let ap = data.activePlan, planById(ap.planId) != nil { return ap } else { return nil } }
    func planEnd(_ ap: ActivePlan, _ plan: Plan) -> String? { plan.weeks > 0 ? Day0.add(ap.begin, plan.weeks * 7) : nil }
    func isPlanWorkout(_ plan: Plan, _ i: Int) -> Bool {
        guard i >= 0, i < plan.days.count, let w = plan.days[i].workoutId else { return false }
        return woById(w) != nil
    }
    /// Which day of the plan a (stored) day was
    func planIndexOf(_ d: Day?, _ plan: Plan) -> Int? {
        guard let d else { return nil }
        if let p = d.plan, p.id == plan.id, p.index >= 0, p.index < plan.days.count { return p.index }
        let ids = d.workouts.map(\.id)
        return plan.days.firstIndex { x in x.workoutId != nil && ids.contains(x.workoutId!) }
    }

    /// The schedule (cached until the data or the date changes).
    var schedule: Schedule {
        if let s = schedCache, s.tk == today { return s }
        let s = computeSchedule(days: data.days)
        schedCache = s
        return s
    }

    /// The walk itself. `days` is passed in so the move-back sheet can preview a change without making it.
    func computeSchedule(days: [String: Day]) -> Schedule {
        let tk = today
        var out = Schedule(tk: tk)
        guard let ap = activePlan, let plan = planById(ap.planId) else { return out }
        let len = plan.days.count
        let isW = plan.days.indices.map { isPlanWorkout(plan, $0) }   // looked up once, not on every day
        out.plan = plan; out.ap = ap
        if len == 0 || !isW.contains(true) { return out }
        let end = planEnd(ap, plan)
        let restIdx = plan.days.indices.filter { !isW[$0] }
        var pos = ((Day0.between(ap.start ?? ap.begin, ap.begin) % len) + len) % len
        var skips: [Int] = [], absorbs: [Int?] = []

        // The entry that's due now (after skipping workouts done early and rest days used up by a move)
        func due() -> Int {
            for _ in 0..<(len * 4) {
                let i = pos % len
                if let si = skips.firstIndex(of: i) { skips.remove(at: si); pos += 1; continue }
                if !isW[i], let ai = absorbs.firstIndex(where: { $0 == nil || $0 == i }) { absorbs.remove(at: ai); pos += 1; continue }
                return i
            }
            return pos % len
        }
        func addAbsorb(_ mode: String?) {
            if mode == "next" { absorbs.append(nil) }
            else if mode == "round" { let i = pos % len; let r = restIdx.filter { $0 > i }; absorbs.append(r.last) }
        }
        // A plan workout done (or put) on a day: in turn moves the plan on; out of turn skips its next turn
        func place(_ j: Int) { let i = due(); if i == j { pos += 1 } else { skips.append(j) } }

        let horizon = Day0.add(tk, 400)
        var k = ap.begin
        var date = Day0.date(ap.begin)
        while true {
            if k > horizon || (end != nil && k >= end!) { break }
            defer { date = Day0.cal.date(byAdding: .day, value: 1, to: date)!; k = Day0.key(date) }
            let st = days[k], tr = hasSets(k)
            if let st, st.rest == true, st.items.isEmpty, !tr {
                addAbsorb(st.absorb)
                if k >= tk { out.map[k] = SchedEntry(extra: true, absorb: st.absorb) }
                continue
            }
            if k < tk {
                if tr, let j = planIndexOf(st, plan) { place(j); continue }
                if !isW[due()] { pos += 1 }          // a rest day passes; a missed workout keeps waiting
                continue
            }
            // today and later
            let own = st != nil && (tr || st!.pinned == true || (st!.plan == nil && !st!.items.isEmpty))
            if own, let j = planIndexOf(st, plan) { place(j); out.map[k] = SchedEntry(index: j, own: true); continue }
            if own { out.map[k] = SchedEntry(other: true); if !isW[due()] { pos += 1 }; continue }   // something else that day
            out.map[k] = SchedEntry(index: due()); pos += 1
        }
        return out
    }

    func planDayFor(_ k: String, in sc: Schedule? = nil) -> PlanDayInfo? {
        let sc = sc ?? schedule
        guard let e = sc.map[k], !e.other, let plan = sc.plan, let ap = sc.ap else { return nil }
        if e.extra { return PlanDayInfo(plan: plan, ap: ap, index: -1, workout: nil, extra: true) }
        let i = e.index ?? 0
        return PlanDayInfo(plan: plan, ap: ap, index: i, workout: plan.days[i].workoutId.flatMap(woById))
    }
    /// The next planned workout from today on
    func upNext() -> (k: String, index: Int, workout: Workout)? {
        let sc = schedule
        for k in sc.map.keys.sorted() { if let pd = planDayFor(k, in: sc), let w = pd.workout { return (k, pd.index, w) } }
        return nil
    }
    /// Stored copies of planned days that no longer match the schedule (the workout moved) are dropped,
    /// unless you've trained, started a timer, or pinned them.
    func purgeStalePlanDays() {
        let sc = schedule
        guard sc.plan != nil else { return }
        let stale = data.days.filter { k, d in
            guard k >= today, d.plan != nil, d.pinned != true, d.rest != true, d.session == nil, !hasSets(k) else { return false }
            let e = sc.map[k]
            return e == nil || e!.index != d.plan!.index
        }.map(\.key)
        if !stale.isEmpty { var d = data; for k in stale { d.days.removeValue(forKey: k) }; data = d }
    }
    func virtualDay(_ k: String, in sc: Schedule? = nil) -> Day? {
        guard let pd = planDayFor(k, in: sc), let w = pd.workout else { return nil }
        var d = Day()
        d.items = w.items.filter { exById($0.exId) != nil }.map { WorkoutItem(exId: $0.exId, sets: $0.sets) }
        d.workouts = [WorkoutRef(id: w.id, name: w.name)]
        d.plan = PlanRef(id: pd.plan.id, index: pd.index)
        return d
    }
    /// Where a plan workout lands from a date on
    func whereIs(_ index: Int, from: String) -> String? {
        let sc = schedule
        return sc.map.keys.sorted().first { $0 >= from && sc.map[$0]!.index == index && !sc.map[$0]!.extra && !sc.map[$0]!.other }
    }

    // MARK: Moving things

    /// Move a planned workout back a day: an extra rest day there, and how far the change reaches
    func moveBack(_ k: String, absorb: String?) {
        let pd = planDayFor(k)
        var d = Day(); d.rest = true; d.absorb = absorb
        data.days[k] = d
        if let pd, let w = pd.workout, let to = whereIs(pd.index, from: k) {
            let when = to == Day0.add(k, 1) && k == today ? "tomorrow" : Fmt.short(to)
            showToast(.init(kind: .info, title: "\(w.name) moves to \(when)", sub: absorb != nil ? "Then your plan is back on track" : "Everything after it moves a day too"))
        }
    }
    func unrest(_ k: String) {
        if let d = data.days[k], d.rest == true, d.items.isEmpty, !hasSets(k) { data.days.removeValue(forKey: k) }
    }
    /// On a rest day: do the next workout today (the rest days it jumped over come after it)
    func pinToday() {
        guard let nx = upNext(), nx.k != today, let plan = schedule.plan else { return }
        var d = Day()
        d.items = nx.workout.items.filter { exById($0.exId) != nil }.map { WorkoutItem(exId: $0.exId, sets: $0.sets) }
        d.workouts = [WorkoutRef(id: nx.workout.id, name: nx.workout.name)]
        d.plan = PlanRef(id: plan.id, index: nx.index)
        d.pinned = true
        data.days[today] = d
        selected = today
        Haptics.impact()
        showToast(.init(kind: .info, title: "\(nx.workout.name) is on today", sub: "The rest of your plan stays the same"))
    }
    func unpin(_ k: String) {
        if let d = data.days[k], d.pinned == true, !hasSets(k), d.session == nil { data.days.removeValue(forKey: k) }
    }

    // "Do it today" from another day:
    //  • the next workout of your plan, while today is a rest day → it's brought to today (nothing is skipped)
    //  • a one-off workout you put on a day yourself → moved to today (copied if it's in the past)
    var todayIsFree: Bool { !hasSets(today) && dayOf(today).session == nil && dayOf(today).items.isEmpty }
    func canDoToday(_ k: String) -> Bool {
        let d = dayOf(k)
        if k == today || d.items.isEmpty || hasSets(k) || d.session != nil { return false }
        if let pd = planDayFor(k), pd.workout != nil, !(data.days[k] != nil && data.days[k]!.plan == nil) {
            guard let nx = upNext() else { return false }
            return k > today && todayIsFree && nx.k == k
        }
        return true
    }
    func doToday(_ k: String) {
        if let pd = planDayFor(k), pd.workout != nil, !(data.days[k] != nil && data.days[k]!.plan == nil) { pinToday(); return }
        let tk = today, src = dayOf(k)
        let name = src.workouts.isEmpty ? "Workout" : src.workouts.map(\.name).joined(separator: " + ")
        var d = data
        var t = d.days[tk] ?? virtualDay(tk) ?? Day()
        for it in src.items where !t.items.contains(where: { $0.exId == it.exId }) { t.items.append(WorkoutItem(exId: it.exId, sets: it.sets)) }
        for w in src.workouts where !t.workouts.contains(where: { $0.id == w.id }) { t.workouts.append(w) }
        t.rest = nil
        if t.session?.end != nil { t.session!.end = nil }   // today was already finished: carry on
        d.days[tk] = t
        if k > tk { d.days.removeValue(forKey: k) }         // moved, not copied
        data = d
        selected = tk
        Haptics.impact()
        showToast(.init(kind: .info, title: "\(name) is on today", sub: nil))
    }

    // MARK: The move-back sheet

    func dayLabelFor(_ k: String, in sc: Schedule, days: [String: Day]) -> String {
        if let st = days[k], !st.items.isEmpty, st.rest != true, st.plan == nil {
            return st.workouts.isEmpty ? "Custom" : st.workouts.map(\.name).joined(separator: " + ")
        }
        if let pd = planDayFor(k, in: sc), let w = pd.workout { return w.name }
        return "Rest"
    }
    /// The next n days if day `from` were moved back with `absorb`
    func previewDays(_ from: String, absorb: String?, n: Int = 7) -> [(k: String, name: String)] {
        var days = data.days
        var d = Day(); d.rest = true; d.absorb = absorb
        days[from] = d
        let sc = computeSchedule(days: days)
        return (0..<n).map { i in let k = Day0.add(from, i); return (k, dayLabelFor(k, in: sc, days: days)) }
    }
}

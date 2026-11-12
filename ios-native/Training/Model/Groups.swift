import Foundation

// Days hold workouts (2026-11-11, Lukas): a day's exercises are grouped by the workout they belong to, each group can be
// collapsed and moved to another day on its own. Exercises added by themselves go in "Other exercises" (key "").
// The same exercise can be in two workouts on one day, each with its own sets.
//
// Stored in the shared format with two small extras the web app keeps but ignores: `w` on a day's items and on sets
// (the group: a workout id, or "" for Other exercises), `moved` on a day's workout and `away` on a day (moving plan
// workouts, below). Older days have no `w`: `normalized` works the groups out (one workout → all its exercises; several →
// the workout whose exercises match; otherwise Other exercises). History, charts and PRs still count a day's sets
// per exercise, whatever group they were logged in.
//
// Moving a plan workout moves only that workout; every other planned day stays on its date:
//  • its own day keeps the plan's place, marked done (`pinned`), without the workout (`away` = where it went);
//  • the day it goes to gets it as `moved`, which doesn't count as doing the plan early; a planned day it lands on is
//    pinned so it stays put.

nonisolated let otherGroup = ""

struct DayGroup: Identifiable, Equatable {
    var id: String            // workout id, or "" for Other exercises
    var name: String
    var rows: [Int]           // indexes into the day's items, in order
    var moved = false
}

extension Store {
    /// A day with every exercise in a group (`w` filled in) and the exercises in group order (workouts, then Other).
    func normalized(_ day: Day) -> Day {
        var d = day
        let refs = d.workouts.map(\.id)
        var taken = Set<String>()
        for i in d.items.indices {
            let ex = d.items[i].exId
            var g = d.items[i].w
            if let x = g, x != otherGroup, !refs.contains(x) { g = otherGroup }   // its workout is no longer on the day
            if g == nil {
                if refs.count == 1 { g = refs[0] }
                else {
                    g = refs.first { id in !taken.contains(ex + "|" + id) && (woById(id)?.items.contains { $0.exId == ex } ?? false) } ?? otherGroup
                }
            }
            taken.insert(ex + "|" + g!)
            d.items[i].w = g
        }
        let order = refs + [otherGroup]
        let rank = { (it: WorkoutItem) in order.firstIndex(of: it.w ?? otherGroup) ?? order.count }
        let sorted = d.items.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        d.items = sorted
        return d
    }

    /// The day's groups as shown (workouts in order, then Other exercises), only those with exercises.
    func groups(_ k: String) -> [DayGroup] {
        let d = dayOf(k)
        var out = d.workouts.map { DayGroup(id: $0.id, name: $0.name, rows: [], moved: $0.moved == true) }
        out.append(DayGroup(id: otherGroup, name: "Other exercises", rows: []))
        for (i, it) in d.items.enumerated() {
            if let gi = out.firstIndex(where: { $0.id == (it.w ?? otherGroup) }) { out[gi].rows.append(i) }
        }
        out = out.filter { !$0.rows.isEmpty }
        if out.count == 1 && out[0].id == otherGroup { out[0].name = "Exercises" }
        return out
    }

    /// Which group a logged set belongs to: the one it was logged in, or (older sets) the first with that exercise.
    func groupOf(_ s: LoggedSet, in d: Day) -> String? {
        if let w = s.w, d.items.contains(where: { $0.exId == s.exId && $0.w == w }) { return w }
        return d.items.first { $0.exId == s.exId }?.w
    }
    /// An exercise's sets on a day, in one group
    /// The exercise screen's page for an exercise on a day (the workout it was logged in first; nil = not on that day)
    func logStart(_ exId: String, _ k: String) -> Int? {
        let items = dayOf(k).items
        return items.indices.first { items[$0].exId == exId && !setsOf(exId, k, items[$0].w ?? otherGroup).isEmpty }
            ?? items.firstIndex { $0.exId == exId }
    }

    func setsOf(_ exId: String, _ k: String, _ g: String) -> [LoggedSet] {
        let all = setsOf(exId, k)
        if all.isEmpty { return all }
        let d = dayOf(k)
        return all.filter { groupOf($0, in: d) == g }
    }
    /// All sets logged in a group on a day
    func groupSets(_ k: String, _ g: String) -> [LoggedSet] {
        let d = dayOf(k)
        return setsOn(k).filter { groupOf($0, in: d) == g }
    }

    // MARK: Adding and removing

    /// A single exercise goes in Other exercises
    func addExercise(_ exId: String, to k: String) {
        ensureDay(k)
        guard !data.days[k]!.items.contains(where: { $0.exId == exId && $0.w == otherGroup }) else { return }
        var d = data.days[k]!
        d.items.append(WorkoutItem(exId: exId, sets: data.settings.defaultSets, w: otherGroup))
        data.days[k] = normalized(d)
        Haptics.impact()
    }
    /// A workout becomes its own group (once per day)
    func addWorkout(_ wId: String, to k: String) {
        guard let w = woById(wId) else { return }
        ensureDay(k)
        var d = data.days[k]!
        guard !d.workouts.contains(where: { $0.id == w.id }) else { return }
        d.workouts.append(WorkoutRef(id: w.id, name: w.name))
        for it in w.items where exById(it.exId) != nil && !d.items.contains(where: { $0.exId == it.exId && $0.w == w.id }) {
            d.items.append(WorkoutItem(exId: it.exId, sets: it.sets, w: w.id))
        }
        data.days[k] = normalized(d)
        Haptics.impact()
    }

    func removeExercise(_ exId: String, group g: String, from k: String) {
        // Already gone (a quick second tap on a row that's still fading out): do nothing.
        guard dayOf(k).items.contains(where: { $0.exId == exId && $0.w == g }) else { return }
        ensureDay(k)
        Haptics.impact()
        if let p = pad, p.exId == exId, p.g == g, p.day == k { pad = nil }
        let gone = Set(setsOf(exId, k, g).map(\.id))
        var d = data
        var day = d.days[k]!
        day.items.removeAll { $0.exId == exId && $0.w == g }
        if !day.items.contains(where: { $0.w == g }) {
            if g != otherGroup { day.workouts.removeAll { $0.id == g } }
            if var ss = day.sessions, ss[g] != nil {
                ss[g] = nil; day.sessions = ss.isEmpty ? nil : ss; day.session = Store.span(ss); clearPause(k, g)
            }
        }
        d.days[k] = day
        if !gone.isEmpty { d.sets = d.sets.filter { !gone.contains($0.id) } }
        data = d
        drafts[exId + "|" + k + "|" + g] = nil
        if let r = rest, r.date == k, r.exId == exId, setsOf(exId, k).isEmpty { rest = nil }
        if data.days[k]!.items.isEmpty { clearEmptyDay(k, byUser: true) }
    }

    /// Put a group's exercises in this order (after dragging one)
    func reorderExercises(in k: String, group g: String, _ ids: [String]) {
        ensureDay(k)
        var d = data.days[k]!
        let mine = d.items.filter { $0.w == g }
        let sorted = ids.compactMap { id in mine.first { $0.exId == id } } + mine.filter { !ids.contains($0.exId) }
        guard sorted.map(\.exId) != mine.map(\.exId) else { return }
        var it = sorted.makeIterator()
        for i in d.items.indices where d.items[i].w == g { d.items[i] = it.next()! }
        data.days[k] = d
    }

    /// A day whose exercises were all removed starts over: no workout names, no timer/finished state.
    /// If YOU emptied a planned day, the plan's place that day is used up (it's skipped, nothing else moves).
    /// Otherwise (e.g. an exercise was deleted) the stored copy goes and the plan shows the day again.
    func clearEmptyDay(_ k: String, byUser: Bool = false) {
        guard var d = data.days[k] else { return }
        d.workouts = []
        if !hasSets(k) { d.session = nil; d.sessions = nil }
        if d.session != nil { data.days[k] = d; return }
        if byUser && d.plan != nil && k >= today && activePlan != nil {
            var r = Day(); r.plan = d.plan; r.pinned = true; r.away = d.away ?? ""
            data.days[k] = r
        } else { data.days.removeValue(forKey: k) }
    }

    // MARK: Moving a workout to another day

    /// A group can move while nothing in it is logged
    func canMove(_ k: String, _ g: String) -> Bool { groupSets(k, g).isEmpty && dayOf(k).items.contains { $0.w == g } }

    func moveGroup(_ g: String, from a: String, to b: String) {
        guard a != b, canMove(a, g) else { return }
        ensureDay(a)
        var src = data.days[a]!
        let items = src.items.filter { $0.w == g }
        let ref = src.workouts.first { $0.id == g }
        let name = ref?.name ?? (g == otherGroup ? "Exercises" : "Workout")
        let plan = activePlan.flatMap { planById($0.planId) }
        func isPlanWorkout(_ d: Day) -> Bool {
            guard let p = d.plan, let plan, p.id == plan.id, p.index >= 0, p.index < plan.days.count else { return false }
            return plan.days[p.index].workoutId == g
        }
        var d = data

        // Take it off its day
        src.items.removeAll { $0.w == g }
        src.workouts.removeAll { $0.id == g }
        if var ss = src.sessions ?? (src.session != nil ? sessions(a) : nil) {   // a timer started but nothing logged: it goes
            ss[g] = nil; src.sessions = ss.isEmpty ? nil : ss; src.session = Store.span(ss); clearPause(a, g)
        }
        if isPlanWorkout(src) && ref?.moved != true { src.pinned = true; src.away = b }   // the plan's place stays here
        if src.items.isEmpty && !hasSets(a) { src.session = nil; src.sessions = nil }
        if src.items.isEmpty && src.plan == nil && src.session == nil { d.days.removeValue(forKey: a) } else { d.days[a] = src }

        // Put it on the new day, next to what's there
        var dst = normalized(d.days[b] ?? virtualDay(b) ?? Day())
        dst.rest = nil
        if dst.plan != nil { dst.pinned = true }                // a planned day it lands on stays as it is
        if let ref, !dst.workouts.contains(where: { $0.id == g }) {
            var r = ref
            r.moved = isPlanWorkout(dst) ? nil : (r.moved == true || (plan?.days.contains { $0.workoutId == g } ?? false)) ? true : nil
            dst.workouts.append(r)
            if isPlanWorkout(dst) { dst.away = nil }            // back on its own day
        }
        for it in items where !dst.items.contains(where: { $0.exId == it.exId && $0.w == g }) { dst.items.append(it) }
        d.days[b] = normalized(dst)

        if let r = rest, r.date == a, !(d.days[a]?.items.contains { $0.exId == r.exId } ?? false) { rest = nil }
        if pad?.day == a { pad = nil }
        data = d
        Haptics.success()
        showToast(.init(kind: .info, title: "\(name) moved to \(b == today ? "today" : b == Day0.add(today, 1) ? "tomorrow" : Fmt.short(b))", sub: nil))
    }
}

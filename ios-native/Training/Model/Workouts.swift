import Foundation

// Workouts and plans: saving, deleting, starting and ending (app.js → renderWorkoutEdit, renderPlanEdit,
// sheetPlanStart, renderPlanView's End plan).

extension Store {
    func workoutSummary(_ w: Workout) -> String {
        "\(Fmt.plural(w.items.count, "exercise")) · \(Fmt.plural(w.items.reduce(0) { $0 + ($1.sets ?? 0) }, "set"))"
    }
    func planSummary(_ p: Plan) -> String {
        "\(p.days.count)-day rotation · \(Fmt.plural(p.days.filter { $0.workoutId.flatMap(woById) != nil }.count, "workout")) · \(p.weeks > 0 ? Fmt.plural(p.weeks, "week") : "ongoing")"
    }
    func planDayLabel(_ p: Plan, _ i: Int) -> String { p.days[i].workoutId.flatMap(woById)?.name ?? "Rest" }
    /// Plans in the list: the active one first, then by name
    var plansSorted: [Plan] {
        let ap = activePlan?.planId
        return data.plans.sorted { a, b in
            if a.id == ap { return true }
            if b.id == ap { return false }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }
    var workoutsSorted: [Workout] { data.workouts.sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }

    /// Returns an error to show, or nil when saved.
    @discardableResult
    func saveWorkout(id: String?, name: String, items: [WorkoutItem]) -> String? {
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nm.isEmpty { return "Give the workout a name." }
        if let id, let i = data.workouts.firstIndex(where: { $0.id == id }) {
            data.workouts[i].name = nm; data.workouts[i].items = items
        } else {
            data.workouts.append(Workout(id: newId(), name: nm, items: items))
        }
        return nil
    }
    /// Plan days that used it become rest days (they no longer point at a workout that exists)
    func deleteWorkout(_ id: String) { data.workouts.removeAll { $0.id == id } }
    func plansUsing(_ workoutId: String) -> [Plan] { data.plans.filter { $0.days.contains { $0.workoutId == workoutId } } }

    /// Returns (error, saved id)
    func savePlan(id: String?, name: String, weeks: Int, days: [PlanDay]) -> (error: String?, id: String?) {
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if nm.isEmpty { return ("Give the plan a name.", nil) }
        if !days.contains(where: { $0.workoutId.flatMap(woById) != nil }) { return ("Add at least one workout day.", nil) }
        if let id, let i = data.plans.firstIndex(where: { $0.id == id }) {
            data.plans[i].name = nm; data.plans[i].weeks = weeks; data.plans[i].days = days
            return (nil, id)
        }
        let nid = newId()
        data.plans.append(Plan(id: nid, name: nm, weeks: weeks, days: days))
        return (nil, nid)
    }
    func deletePlan(_ id: String) {
        var d = data
        if d.activePlan?.planId == id { d.activePlan = nil }
        d.plans.removeAll { $0.id == id }
        data = d
    }

    /// Future planned days that nobody has touched go (days already filled in are kept)
    private func dropFuturePlanDays(_ d: inout AppData) {
        for (k, day) in d.days where k >= today && (day.plan != nil || day.rest == true) && !hasSets(k) && day.session == nil {
            d.days.removeValue(forKey: k)
        }
    }
    /// Start a plan on `first`, beginning with day `startIdx` of its rotation
    func startPlan(_ planId: String, first: String, startIdx: Int) {
        var d = data
        dropFuturePlanDays(&d)
        d.activePlan = ActivePlan(planId: planId, begin: first, start: Day0.add(first, -startIdx))
        data = d
        Haptics.success()
    }
    func endPlan() {
        var d = data
        dropFuturePlanDays(&d)
        d.activePlan = nil
        data = d
    }
}

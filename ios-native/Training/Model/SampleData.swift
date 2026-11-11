import Foundation

/// Made-up training for the prototype (no account or backup yet): eight weeks of Push / Pull / Legs,
/// with Push planned for today so there's something to log.
enum SampleData {
    static func make(today: String = Day0.today) -> AppData {
        var d = AppData()
        func ex(_ name: String, _ muscle: String, _ equip: String, _ instr: String = "", note: String? = nil) -> Exercise {
            Exercise(id: "b:" + name.lowercased().filter { $0.isLetter || $0.isNumber }, name: name, instructions: instr, muscle: muscle, equip: equip, note: note)
        }
        let list: [(Exercise, Double, Int)] = [   // exercise, starting kg, reps
            (ex("Bench press", "chest", "barbell", "Lie on the bench with your eyes under the bar. Grip a little wider than shoulder width, lower the bar to your mid-chest and press it back up.", note: "Seat on 4"), 70, 8),
            (ex("Overhead press", "shoulders", "barbell"), 42.5, 8),
            (ex("Incline dumbbell press", "chest", "dumbbell"), 24, 10),
            (ex("Triceps pushdown", "arms", "cable"), 25, 12),
            (ex("Barbell row", "back", "barbell"), 60, 8),
            (ex("Lat pulldown", "back", "cable"), 55, 10),
            (ex("Seated cable row", "back", "cable"), 50, 10),
            (ex("Biceps curl", "arms", "dumbbell"), 12, 12),
            (ex("Squat", "legs", "barbell"), 85, 6),
            (ex("Romanian deadlift", "legs", "barbell"), 80, 8),
            (ex("Leg press", "legs", "machine"), 140, 10),
            (ex("Calf raise", "legs", "machine"), 60, 12),
        ]
        d.exercises = list.map(\.0)
        let start = Dictionary(uniqueKeysWithValues: list.map { ($0.0.id, ($0.1, $0.2)) })
        let ids = list.map(\.0.id)
        func wo(_ id: String, _ name: String, _ ex: ArraySlice<String>) -> Workout {
            Workout(id: id, name: name, items: ex.map { WorkoutItem(exId: $0, sets: 3) })
        }
        let push = wo("sample-push", "Push", ids[0..<4]), pull = wo("sample-pull", "Pull", ids[4..<8]), legs = wo("sample-legs", "Legs", ids[8..<12])
        d.workouts = [push, pull, legs]

        // The plan: Push, rest, Pull, rest, Legs, rest, round and round. Started 8 weeks ago and trained every time,
        // so today and the days ahead come from the plan (nothing stored for them until you touch them).
        let plan = Plan(id: "sample-ppl", name: "Push Pull Legs", weeks: 0,
                        days: [PlanDay(workoutId: push.id), PlanDay(workoutId: nil), PlanDay(workoutId: pull.id),
                               PlanDay(workoutId: nil), PlanDay(workoutId: legs.id), PlanDay(workoutId: nil)])
        d.plans = [plan]
        let begin = Day0.add(today, -56)
        d.activePlan = ActivePlan(planId: plan.id, begin: begin, start: begin)

        let rotation = [push, pull, legs]
        var session = 0
        var offset = -56
        while offset < 0 {
            let k = Day0.add(today, offset)
            let w = rotation[session % 3]
            let round = session / 3
            let startMs = (Day0.date(k).timeIntervalSince1970 + 18 * 3600) * 1000
            var ts = startMs + 60_000
            var day = Day()
            day.workouts = [WorkoutRef(id: w.id, name: w.name)]
            day.plan = PlanRef(id: plan.id, index: (session * 2) % 6)
            for it in w.items {
                day.items.append(it)
                let (base, reps) = start[it.exId]!
                let kg = base + Double(round / 2) * (base >= 40 ? 2.5 : 1)
                for slot in 0..<3 {
                    let r = max(1, reps - (slot == 2 ? 1 : 0) + (round % 2 == 1 ? 1 : 0))
                    d.sets.append(LoggedSet(id: newId(), exId: it.exId, date: k, slot: slot, weight: kg, reps: r, ts: ts))
                    ts += 150_000
                }
                ts += 120_000
            }
            day.session = Session(start: startMs, end: ts)
            d.days[k] = day
            session += 1
            offset += 2
        }
        return d
    }
}

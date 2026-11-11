import XCTest
@testable import Training

/// Days with several workouts (grouped, an exercise in two workouts with separate sets) and moving one workout.
final class DayGroupsTests: XCTestCase {
    let k = "2026-11-11"

    private func store(plan: Bool = false) -> Store {
        var d = AppData()
        d.exercises = ["bench", "squat", "row", "curl"].map { Exercise(id: $0, name: $0.capitalized) }
        d.workouts = [Workout(id: "push", name: "Push", items: [WorkoutItem(exId: "bench", sets: 3), WorkoutItem(exId: "squat", sets: 2)]),
                      Workout(id: "legs", name: "Legs", items: [WorkoutItem(exId: "squat", sets: 4)]),
                      Workout(id: "pull", name: "Pull", items: [WorkoutItem(exId: "row", sets: 3)])]
        if plan {
            d.plans = [Plan(id: "p", name: "PL", weeks: 0, days: [PlanDay(workoutId: "push"), PlanDay(workoutId: nil), PlanDay(workoutId: "pull"), PlanDay(workoutId: nil)])]
            d.activePlan = ActivePlan(planId: "p", begin: k, start: k)
        }
        let s = Store(data: d, persist: false)
        s.today = k; s.selected = k
        return s
    }

    func testOlderDaysAreGroupedSensibly() {
        let s = store()
        var one = Day(); one.items = [WorkoutItem(exId: "bench", sets: 3), WorkoutItem(exId: "curl", sets: 2)]
        one.workouts = [WorkoutRef(id: "push", name: "Push")]
        XCTAssertEqual(s.normalized(one).items.map(\.w), ["push", "push"], "one workout: everything is in it")

        var two = Day()
        two.items = [WorkoutItem(exId: "curl", sets: 2), WorkoutItem(exId: "row", sets: 3), WorkoutItem(exId: "bench", sets: 3)]
        two.workouts = [WorkoutRef(id: "push", name: "Push"), WorkoutRef(id: "pull", name: "Pull")]
        let n = s.normalized(two)
        XCTAssertEqual(n.items.map(\.exId), ["bench", "row", "curl"], "in workout order, then Other")
        XCTAssertEqual(n.items.map(\.w), ["push", "pull", ""])
        XCTAssertEqual(s.normalized(n), n, "stable")
    }

    func testSameExerciseInTwoWorkoutsHasSeparateSets() {
        let s = store()
        s.addWorkout("push", to: k)
        s.addWorkout("legs", to: k)
        s.addWorkout("legs", to: k)                                   // once per day
        XCTAssertEqual(s.groups(k).map(\.name), ["Push", "Legs"])
        XCTAssertEqual(s.dayOf(k).items.map(\.exId), ["bench", "squat", "squat"])
        let legsSquat = s.dayOf(k).items.firstIndex { $0.w == "legs" }!
        s.drafts["squat|\(k)|legs"] = [0: Draft(w: "100", r: "5")]
        s.toggle(k, legsSquat, 0)
        XCTAssertEqual(s.setsOf("squat", k, "legs").count, 1)
        XCTAssertEqual(s.setsOf("squat", k, "push").count, 0)
        XCTAssertEqual(s.setsOf("squat", k).count, 1, "history counts the day's sets together")
        XCTAssertEqual(s.data.sets.first?.w, "legs")
        XCTAssertEqual(s.logModel(k, legsSquat)?.n, 4, "Legs' own planned sets")
        XCTAssertEqual(s.setsLeft(k), 3 + 2 + 3)
    }

    func testOlderSetsBelongToTheFirstGroupWithTheExercise() {
        let s = store()
        s.addWorkout("push", to: k); s.addWorkout("legs", to: k)
        s.data.sets.append(LoggedSet(id: "old", exId: "squat", date: k, slot: 0, weight: 90, reps: 5, ts: 1))
        XCTAssertEqual(s.setsOf("squat", k, "push").map(\.id), ["old"])
        XCTAssertTrue(s.setsOf("squat", k, "legs").isEmpty)
    }

    func testSingleExercisesGoInOtherAtTheBottom() {
        let s = store()
        s.addExercise("curl", to: k)
        s.addExercise("curl", to: k)
        s.addWorkout("pull", to: k)
        XCTAssertEqual(s.groups(k).map(\.name), ["Pull", "Other exercises"])
        XCTAssertEqual(s.dayOf(k).items.map(\.exId), ["row", "curl"])
        let alone = store(); alone.addExercise("curl", to: k)
        XCTAssertEqual(alone.groups(k).map(\.name), ["Exercises"])
    }

    func testRemovingTheLastExerciseOfAWorkoutRemovesTheWorkout() {
        let s = store()
        s.addWorkout("legs", to: k); s.addWorkout("pull", to: k)
        s.removeExercise("squat", group: "legs", from: k)
        XCTAssertEqual(s.dayOf(k).workouts.map(\.id), ["pull"])
        XCTAssertEqual(s.dayLabel(k), "Pull")
    }

    func testMovingAWorkoutTakesItsExercisesAlong() {
        let s = store()
        s.addWorkout("push", to: k); s.addWorkout("pull", to: k)
        let fri = "2026-11-13"
        s.moveGroup("pull", from: k, to: fri)
        XCTAssertEqual(s.groups(k).map(\.id), ["push"])
        XCTAssertEqual(s.groups(fri).map(\.name), ["Pull"])
        XCTAssertEqual(s.dayOf(fri).items.map(\.exId), ["row"])
        s.moveGroup("push", from: k, to: fri)                         // next to what's there
        XCTAssertEqual(s.groups(fri).map(\.name), ["Pull", "Push"])
        XCTAssertNil(s.data.days[k], "an emptied unplanned day goes")
        XCTAssertEqual(s.toast?.title, "Push moved to Fri 13 Nov")
    }

    func testOnlyAWorkoutWithNothingLoggedMoves() {
        let s = store()
        s.addWorkout("pull", to: k)
        s.drafts["row|\(k)|pull"] = [0: Draft(w: "60", r: "8")]
        s.toggle(k, 0, 0)
        XCTAssertFalse(s.canMove(k, "pull"))
        s.moveGroup("pull", from: k, to: "2026-11-12")
        XCTAssertEqual(s.groups(k).map(\.id), ["pull"])
    }

    func testMovingAPlanWorkoutMovesOnlyThatWorkout() {
        let s = store(plan: true)
        // Push today, rest, Pull, rest, Push, …
        let before = (0..<12).map { s.planDayFor(Day0.add(k, $0))?.workout?.id }
        XCTAssertEqual(before[0], "push"); XCTAssertEqual(before[2], "pull"); XCTAssertEqual(before[4], "push")
        s.moveGroup("push", from: k, to: "2026-11-12")               // to tomorrow, a rest day
        XCTAssertTrue(s.dayOf(k).items.isEmpty)
        XCTAssertEqual(s.dayLabel(k), "Push moved to Thu 12 Nov · PL, day 1 of 4")
        XCTAssertEqual(s.groups("2026-11-12").map(\.name), ["Push"])
        XCTAssertEqual(s.dayOf("2026-11-12").workouts.first?.moved, true)
        for i in 2..<12 { XCTAssertEqual(s.planDayFor(Day0.add(k, i))?.workout?.id, before[i], "day +\(i) stays as it was") }
        s.purgeStalePlanDays()
        XCTAssertEqual(s.groups("2026-11-12").map(\.name), ["Push"], "kept")

        // Onto a planned day: it joins that day's workout, which stays on its date
        s.moveGroup("push", from: "2026-11-12", to: "2026-11-13")
        XCTAssertEqual(s.groups("2026-11-13").map(\.name), ["Pull", "Push"])
        XCTAssertNil(s.data.days["2026-11-12"])
        for i in 4..<12 { XCTAssertEqual(s.planDayFor(Day0.add(k, i))?.workout?.id, before[i], "day +\(i) stays as it was") }

        // And back to its own day
        s.moveGroup("push", from: "2026-11-13", to: k)
        XCTAssertEqual(s.groups(k).map(\.name), ["Push"])
        XCTAssertNil(s.dayOf(k).workouts.first?.moved)
        XCTAssertNil(s.data.days[k]?.away)
        XCTAssertEqual(s.dayLabel(k), "Push · PL, day 1 of 4")
        for i in 1..<12 where i != 3 { XCTAssertEqual(s.planDayFor(Day0.add(k, i))?.workout?.id, before[i]) }
    }

    func testEmptyingAPlannedDaySkipsItWithoutMovingTheRest() {
        let s = store(plan: true)
        s.removeExercise("bench", group: "push", from: k)
        s.removeExercise("squat", group: "push", from: k)
        XCTAssertEqual(s.dayLabel(k), "Rest day · PL, day 1 of 4")
        XCTAssertEqual(s.planDayFor("2026-11-13")?.workout?.id, "pull")
        XCTAssertEqual(s.planDayFor("2026-11-15")?.workout?.id, "push")
    }
}

import XCTest
@testable import Training

/// Saving, deleting, starting and ending, as the web app's Workouts tab does it.
final class WorkoutsTests: XCTestCase {
    private func store() -> Store {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench"), Exercise(id: "b", name: "Squat")]
        d.workouts = [Workout(id: "w1", name: "Upper", items: [WorkoutItem(exId: "a", sets: 3)]),
                      Workout(id: "w2", name: "Lower", items: [WorkoutItem(exId: "b", sets: 4)])]
        let s = Store(data: d, persist: false)
        s.today = "2026-11-11"
        return s
    }

    func testSaveWorkout() {
        let s = store()
        XCTAssertEqual(s.saveWorkout(id: nil, name: "   ", items: []), "Give the workout a name.")
        XCTAssertNil(s.saveWorkout(id: nil, name: " Arms ", items: [WorkoutItem(exId: "a", sets: 2)]))
        XCTAssertEqual(s.data.workouts.last?.name, "Arms")
        XCTAssertNil(s.saveWorkout(id: "w1", name: "Upper body", items: []))
        XCTAssertEqual(s.woById("w1")?.name, "Upper body")
        XCTAssertEqual(s.woById("w1")?.items.count, 0)
        XCTAssertEqual(s.workoutSummary(s.woById("w2")!), "1 exercise · 4 sets")
    }

    func testSavePlanNeedsANameAndAWorkoutDay() {
        let s = store()
        XCTAssertEqual(s.savePlan(id: nil, name: "", weeks: 8, days: [PlanDay(workoutId: "w1")]).error, "Give the plan a name.")
        XCTAssertEqual(s.savePlan(id: nil, name: "UL", weeks: 8, days: [PlanDay(workoutId: nil)]).error, "Add at least one workout day.")
        let r = s.savePlan(id: nil, name: "UL", weeks: 8, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: "w2"), PlanDay(workoutId: nil)])
        XCTAssertNil(r.error)
        XCTAssertEqual(s.planSummary(s.planById(r.id!)!), "3-day rotation · 2 workouts · 8 weeks")
    }

    func testStartPlanOnADayOfTheRotation() {
        let s = store()
        let id = s.savePlan(id: nil, name: "UL", weeks: 0, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: "w2"), PlanDay(workoutId: nil)]).id!
        // Start today with day 2 (Lower): like the web app, start = first − index
        s.startPlan(id, first: "2026-11-11", startIdx: 1)
        XCTAssertEqual(s.data.activePlan, ActivePlan(planId: id, begin: "2026-11-11", start: "2026-11-10"))
        XCTAssertEqual(s.planDayFor("2026-11-11")?.workout?.name, "Lower")
        XCTAssertEqual(s.planDayFor("2026-11-12")?.workout, nil)                 // rest
        XCTAssertEqual(s.planDayFor("2026-11-13")?.workout?.name, "Upper")
        XCTAssertEqual(s.upNext()?.k, "2026-11-11")
    }

    func testEndPlanKeepsTrainedDaysAndDropsPlannedOnes() {
        let s = store()
        let id = s.savePlan(id: nil, name: "UL", weeks: 0, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: "w2")]).id!
        s.startPlan(id, first: "2026-11-11", startIdx: 0)
        s.ensureDay("2026-11-11")                                                  // touched today (stored copy)
        s.data.sets.append(LoggedSet(id: "x", exId: "a", date: "2026-11-11", slot: 0, weight: 50, reps: 5, ts: 1))
        s.ensureDay("2026-11-12")                                                  // a stored, untouched future day
        s.moveBack("2026-11-13", absorb: "next")                                   // a moved rest day
        s.endPlan()
        XCTAssertNil(s.data.activePlan)
        XCTAssertNotNil(s.data.days["2026-11-11"], "trained today: kept")
        XCTAssertNil(s.data.days["2026-11-12"], "planned and untouched: gone")
        XCTAssertNil(s.data.days["2026-11-13"], "moved rest day: gone")
    }

    func testDeletingThings() {
        let s = store()
        let id = s.savePlan(id: nil, name: "UL", weeks: 0, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: "w2")]).id!
        s.startPlan(id, first: "2026-11-11", startIdx: 0)
        XCTAssertEqual(s.plansUsing("w2").map(\.name), ["UL"])
        s.deleteWorkout("w2")                     // its plan day becomes a rest day
        XCTAssertNil(s.planDayFor("2026-11-12")?.workout)
        s.deletePlan(id)                          // the active plan goes too
        XCTAssertNil(s.data.activePlan)
        XCTAssertTrue(s.data.plans.isEmpty)
    }
}

/// Dragging exercises into a new order on Today.
final class ReorderTests: XCTestCase {
    let h: [String: CGFloat] = ["a": 66, "b": 66, "c": 66, "d": 66]

    func testDraggingDownPastTwoRows() {
        var r = Reorder(id: "a", order: ["a", "b", "c", "d"])
        XCTAssertEqual(r.move(to: 5, heights: h), 0)
        XCTAssertEqual(r.move(to: 55, heights: h), 1)          // past the middle of b
        XCTAssertEqual(r.order, ["b", "a", "c", "d"])
        XCTAssertEqual(r.move(to: 105, heights: h), 1)         // past the middle of c
        XCTAssertEqual(r.order, ["b", "c", "a", "d"])
        XCTAssertEqual(r.offset, 105 - 132, accuracy: 0.01)    // still under the finger
        XCTAssertEqual(r.move(to: 147, heights: h), 0)
    }
    func testOneBigJumpAndBackUp() {
        var r = Reorder(id: "a", order: ["a", "b", "c", "d"])
        XCTAssertEqual(r.move(to: 250, heights: h), 3)
        XCTAssertEqual(r.order, ["b", "c", "d", "a"])
        XCTAssertEqual(r.move(to: 0, heights: h), 3)
        XCTAssertEqual(r.order, ["a", "b", "c", "d"])
        XCTAssertEqual(r.offset, 0, accuracy: 0.01)
    }
    func testStoreKeepsTheNewOrder() {
        var d = AppData(); var day = Day()
        day.items = ["a", "b", "c"].map { WorkoutItem(exId: $0, sets: 3) }
        d.days["2026-11-11"] = day
        let s = Store(data: d, persist: false)
        s.reorderExercises(in: "2026-11-11", ["c", "a", "b"])
        XCTAssertEqual(s.data.days["2026-11-11"]?.items.map(\.exId), ["c", "a", "b"])
    }

    func testRemovingTheSameExerciseTwiceDoesNothing() {
        // Quick taps: emptying a planned day makes it a moved rest day; a second "remove" mustn't bring the plan back
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "A"), Exercise(id: "b", name: "B")]
        d.workouts = [Workout(id: "w", name: "W", items: [WorkoutItem(exId: "a", sets: 3), WorkoutItem(exId: "b", sets: 3)])]
        d.plans = [Plan(id: "p", name: "P", weeks: 0, days: [PlanDay(workoutId: "w"), PlanDay(workoutId: nil)])]
        d.activePlan = ActivePlan(planId: "p", begin: "2026-11-11", start: "2026-11-11")
        let s = Store(data: d, persist: false)
        s.today = "2026-11-11"
        XCTAssertEqual(s.dayOf("2026-11-11").items.count, 2)
        s.removeExercise("a", from: "2026-11-11")
        s.removeExercise("b", from: "2026-11-11")
        XCTAssertTrue(s.dayOf("2026-11-11").items.isEmpty)
        XCTAssertEqual(s.data.days["2026-11-11"]?.rest, true)
        s.removeExercise("b", from: "2026-11-11")          // the late second tap
        s.removeExercise("a", from: "2026-11-11")
        XCTAssertTrue(s.dayOf("2026-11-11").items.isEmpty, "the exercises must not come back")
        XCTAssertEqual(s.data.days["2026-11-11"]?.rest, true)
    }
}

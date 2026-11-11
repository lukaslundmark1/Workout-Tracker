import XCTest
@testable import Training

/// The timer (tap to start, tap to pause, tap to carry on) and the workout summary.
final class SessionTests: XCTestCase {
    private func store() -> Store {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press"), Exercise(id: "b", name: "Row")]
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 2), WorkoutItem(exId: "b", sets: 2)]
        d.days[Day0.today] = day
        let s = Store(data: d, persist: false)
        return s
    }

    func testPauseDoesNotCount() {
        let s = store(), k = s.today, g = otherGroup
        s.tapTimer(k, g)                                       // start
        XCTAssertTrue(s.isRunning(k, g)); XCTAssertFalse(s.isPaused(k, g))
        // pretend it started 10 minutes ago and was paused 4 minutes ago
        let now = nowMs()
        s.setSession(k, g, Session(start: now - 600_000))
        s.pausedAt[k + "|" + g] = now - 240_000
        XCTAssertTrue(s.isPaused(k, g))
        XCTAssertEqual(s.elapsed(k, g), 360_000, accuracy: 1)   // 6 minutes, frozen while paused
        XCTAssertEqual(s.clock(k, g), now - 240_000, accuracy: 1) // Finish counts up to the pause
        s.tapTimer(k, g)                                       // carry on
        XCTAssertFalse(s.isPaused(k, g))
        XCTAssertNil(s.sessionOf(k, g)!.end)
        XCTAssertEqual(s.elapsed(k, g), 360_000, accuracy: 50)  // still 6 minutes: the start moved later by the pause
        s.tapTimer(k, g)                                       // pause again
        XCTAssertTrue(s.isPaused(k, g))
    }

    func testTimerNeverEndsTheWorkout() {
        let s = store(), k = s.today
        for _ in 0..<5 { s.tapTimer(k, otherGroup) }
        XCTAssertNil(s.dayOf(k).session?.end)
    }

    /// Each workout has its own timer and Finish; the day's shared session spans them (for the web app)
    func testEachWorkoutFinishesOnItsOwn() {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "A"), Exercise(id: "b", name: "B")]
        d.workouts = [Workout(id: "up", name: "Upper", items: [WorkoutItem(exId: "a", sets: 1)]),
                      Workout(id: "lo", name: "Lower", items: [WorkoutItem(exId: "b", sets: 1)])]
        let s = Store(data: d, persist: false), k = s.today
        s.addWorkout("up", to: k); s.addWorkout("lo", to: k)
        s.drafts["a|\(k)|up"] = [0: Draft(w: "50", r: "5")]
        s.toggle(k, 0, 0)                                      // first set of Upper starts Upper's timer only
        XCTAssertTrue(s.isRunning(k, "up")); XCTAssertNil(s.sessionOf(k, "lo"))
        XCTAssertTrue(s.canFinish(k, "up")); XCTAssertFalse(s.canFinish(k, "lo"))
        XCTAssertEqual(s.untickedSets(k, "up").count, 0); XCTAssertEqual(s.untickedSets(k, "lo").count, 1)
        let start = s.sessionOf(k, "up")!.start
        s.setSession(k, "up", Session(start: start, end: start + 1_800_000))   // Finish Upper
        XCTAssertTrue(s.isFinished(k, "up"))
        XCTAssertEqual(s.dayOf(k).session, Session(start: start, end: start + 1_800_000))
        // Later the same day: Lower
        s.drafts["b|\(k)|lo"] = [0: Draft(w: "100", r: "5")]
        s.toggle(k, 1, 0)
        XCTAssertTrue(s.isRunning(k, "lo")); XCTAssertTrue(s.isFinished(k, "up"))
        XCTAssertNil(s.dayOf(k).session?.end, "the day shows as in progress while any workout runs")
        XCTAssertEqual(s.dayOf(k).session?.start, start)
        XCTAssertTrue(s.isRunning(k)); XCTAssertFalse(s.isFinished(k))
        XCTAssertEqual(s.summary(k, "up").sets, 1)
        XCTAssertEqual(s.summary(k, "up").title, "Upper")
        XCTAssertEqual(s.summary(k, "up").durationMs, 1_800_000)
    }

    /// An older day has one timer: it belongs to the workouts that have sets, and a workout added later starts fresh
    func testOlderDaysTimerAndANewWorkout() {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "A"), Exercise(id: "b", name: "B")]
        d.workouts = [Workout(id: "lo", name: "Lower", items: [WorkoutItem(exId: "b", sets: 1)])]
        let k = Day0.today
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 1)]; day.workouts = [WorkoutRef(id: "up", name: "Upper")]
        day.session = Session(start: 1000, end: 5000)
        d.days[k] = day
        d.sets = [LoggedSet(id: "s", exId: "a", date: k, slot: 0, weight: 50, reps: 5, ts: 2000)]
        let s = Store(data: d, persist: false)
        XCTAssertTrue(s.isFinished(k, "up"))
        s.addWorkout("lo", to: k)
        XCTAssertNil(s.sessionOf(k, "lo"))
        XCTAssertTrue(s.isFinished(k, "up"))
        s.startTimer(k, "lo")
        XCTAssertTrue(s.isRunning(k, "lo")); XCTAssertTrue(s.isFinished(k, "up"))
        XCTAssertEqual(s.data.days[k]?.sessions?["up"], Session(start: 1000, end: 5000))
    }

    func testSummary() {
        let s = store(), k = s.today
        func set(_ ex: String, _ date: String, _ slot: Int, _ w: Double, _ r: Int, _ ts: Double) -> LoggedSet {
            LoggedSet(id: "\(ex)\(date)\(slot)", exId: ex, date: date, slot: slot, weight: w, reps: r, ts: ts)
        }
        let past = Day0.add(k, -3)
        s.data.sets = [set("a", past, 0, 80, 8, 1), set("b", past, 0, 60, 10, 2),
                       set("a", k, 0, 85, 8, 10), set("a", k, 1, 80, 8, 11), set("b", k, 0, 57.5, 10, 12)]
        s.data.days[k]!.session = Session(start: 0, end: 52 * 60000)
        s.data.days[k]!.workouts = [WorkoutRef(id: "w", name: "Upper")]
        s.data.days[k]!.items = s.data.days[k]!.items.map { WorkoutItem(exId: $0.exId, sets: $0.sets, w: "w") }
        let sum = s.summary(k)
        XCTAssertEqual(sum.title, "Upper")
        XCTAssertEqual(sum.sets, 3)
        XCTAssertEqual(sum.volumeKg, 85 * 8 + 80 * 8 + 57.5 * 10)
        XCTAssertEqual(sum.durationMs, 52 * 60000)
        XCTAssertEqual(sum.exercises.map(\.id), ["a", "b"])
        XCTAssertEqual(sum.exercises[0].best.weight, 85)
        XCTAssertEqual(sum.exercises[0].delta, .up(6))           // 85 vs 80 × 8: +6.25 % → 6
        XCTAssertEqual(sum.exercises[1].delta, .down(4))         // 57.5 vs 60 × 10: −4.17 % → 4
        XCTAssertEqual(sum.prs.map(\.id), ["a"])
    }
}

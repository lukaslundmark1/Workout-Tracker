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
        let s = store(), k = s.today
        s.tapTimer(k)                                          // start
        XCTAssertTrue(s.isRunning(k)); XCTAssertFalse(s.isPaused(k))
        // pretend it started 10 minutes ago and was paused 4 minutes ago
        let now = nowMs()
        s.data.days[k]!.session = Session(start: now - 600_000)
        s.pausedAt[k] = now - 240_000
        XCTAssertTrue(s.isPaused(k))
        XCTAssertEqual(s.elapsed(k), 360_000, accuracy: 1)      // 6 minutes, frozen while paused
        XCTAssertEqual(s.clock(k), now - 240_000, accuracy: 1)  // Finish counts up to the pause
        s.tapTimer(k)                                          // carry on
        XCTAssertFalse(s.isPaused(k))
        XCTAssertNil(s.data.days[k]!.session!.end)
        XCTAssertEqual(s.elapsed(k), 360_000, accuracy: 50)     // still 6 minutes: the start moved later by the pause
        s.tapTimer(k)                                          // pause again
        XCTAssertTrue(s.isPaused(k))
    }

    func testTimerNeverEndsTheWorkout() {
        let s = store(), k = s.today
        for _ in 0..<5 { s.tapTimer(k) }
        XCTAssertNil(s.dayOf(k).session?.end)
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

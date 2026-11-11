import XCTest
@testable import Training

/// The Exercises tab's rules. Expected numbers come from app.js's own formulas (node).
final class ExercisesTests: XCTestCase {
    private func store() -> Store {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press"), Exercise(id: "b", name: "My curl")]
        func set(_ k: String, _ slot: Int, _ w: Double, _ r: Int) -> LoggedSet { LoggedSet(id: "\(k)-\(slot)", exId: "a", date: k, slot: slot, weight: w, reps: r, ts: 0) }
        d.sets = [set("2026-11-01", 0, 80, 8), set("2026-11-01", 1, 80, 7),
                  set("2026-11-04", 0, 82.5, 6), set("2026-11-04", 1, 85, 3),
                  set("2026-11-07", 0, 80, 10), set("2026-11-07", 1, 0, 12)]
        d.workouts = [Workout(id: "w", name: "Upper", items: [WorkoutItem(exId: "a", sets: 3), WorkoutItem(exId: "b", sets: 3)])]
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 2)]
        d.days["2026-11-07"] = day
        let s = Store(data: d, persist: false)
        s.today = "2026-11-11"
        return s
    }

    func testBuiltInDatabase() {
        XCTAssertEqual(Library.builtin.count, 130)
        XCTAssertEqual(Library.builtin.first?.id, "b:benchpress")
        XCTAssertEqual(Library.byName("farmer's carry")?.id, "b:farmerscarry")
        XCTAssertEqual(Library.sub(Library.byName("Cable fly")!), "Chest · Cable")
        XCTAssertEqual(Set(Library.builtin.map(\.id)).count, 130, "ids are unique")
    }

    func testLinkingAndAddingFromTheDatabase() {
        let s = store()
        // "Bench press" got linked at start (muscle group and equipment filled in)
        XCTAssertEqual(s.exById("a")?.lib, "b:benchpress")
        XCTAssertEqual(s.exById("a")?.muscle, "chest")
        XCTAssertNil(s.exById("b")?.lib)
        // adding one you already have returns yours; a new one is copied in
        XCTAssertEqual(s.addFromLib(Library.byName("Bench press")!), "a")
        let id = s.addFromLib(Library.byName("Hammer curl")!)
        XCTAssertEqual(s.exById(id)?.name, "Hammer curl")
        XCTAssertEqual(s.exById(id)?.equip, "dumbbell")
        XCTAssertEqual(s.data.exercises.count, 3)
    }

    func testSaveExerciseRules() {
        let s = store()
        XCTAssertEqual(s.saveExercise(id: nil, .init(name: " ")).error, "Give the exercise a name.")
        XCTAssertEqual(s.saveExercise(id: nil, .init(name: "bench PRESS")).error, "An exercise with that name already exists.")
        XCTAssertEqual(s.saveExercise(id: nil, .init(name: "Pause bench", video: "https://vimeo.com/1")).error, "That doesn't look like a YouTube link.")
        let r = s.saveExercise(id: nil, .init(name: "Pause bench", muscle: "chest", note: "  2 s pause  ", video: "https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertNil(r.error)
        XCTAssertEqual(s.exById(r.id!)?.note, "2 s pause")
        // renaming a database exercise makes it your own variation (no longer linked)
        XCTAssertNil(s.saveExercise(id: "a", .init(name: "Bench press, wide", muscle: "chest", equip: "barbell")).error)
        XCTAssertNil(s.exById("a")?.lib)
    }

    func testDeleteExerciseTakesItOutEverywhere() {
        let s = store()
        s.deleteExercise("a")
        XCTAssertNil(s.exById("a"))
        XCTAssertTrue(s.data.sets.isEmpty)
        XCTAssertEqual(s.woById("w")?.items.map(\.exId), ["b"])
        // the day had only this exercise and its sets are gone, so the day starts over
        XCTAssertNil(s.data.days["2026-11-07"])
    }

    func testSeriesMatchTheWebApp() {
        let s = store()
        let e = s.series("a", .e1rm)
        XCTAssertEqual(e.map(\.k), ["2026-11-01", "2026-11-04", "2026-11-07"])
        XCTAssertEqual(e[0].v, 102.1371, accuracy: 0.0001)
        XCTAssertEqual(e[1].v, 99.2727, accuracy: 0.0001)
        XCTAssertEqual(e[2].v, 107.7974, accuracy: 0.0001)
        XCTAssertEqual(e[1].note, "from 82.5 × 6")
        XCTAssertEqual(s.series("a", .heaviest).map(\.v), [80, 85, 80])
        XCTAssertEqual(s.series("a", .volume).map(\.v), [1200, 750, 800])
        XCTAssertEqual(s.series("a", .reps).map(\.v), [15, 9, 22])
        XCTAssertEqual(s.series("a", .reps)[0].note, "2 sets")
        s.data.settings.units = "imperial"
        XCTAssertEqual(s.series("a", .e1rm)[0].v, 225.1738, accuracy: 0.0001)
        XCTAssertEqual(s.statUnit(.e1rm), "lb")
        XCTAssertEqual(s.statUnit(.reps), "reps")
    }

    func testPRsInHistoryAndNumberText() {
        let s = store()
        // the first day never counts; Nov 4 doesn't beat Nov 1; Nov 7 does
        XCTAssertEqual(s.prSets("a"), ["2026-11-07": "2026-11-07-0"])
        XCTAssertEqual(fmtStat(12340.4, .volume), "12,340")
        XCTAssertEqual(fmtStat(116.5825, .e1rm), "116.6")
        XCTAssertEqual(fmtStat(80, .heaviest), "80.0")
        XCTAssertEqual(s.relDay("2026-11-11"), "Today")
        XCTAssertEqual(s.relDay("2026-11-10"), "Yesterday")
        XCTAssertEqual(s.relDay("2026-11-04"), "Wed 4 Nov")
        XCTAssertEqual(s.relDay("2025-11-04"), "Tue 4 Nov 2025")
        XCTAssertEqual(niceTicks(99.27, 107.8, 4), [97.5, 100, 102.5, 105, 107.5, 110])   // app.js gives the same
    }

    func testChartRanges() {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press")]
        d.sets = ["2025-10-01", "2026-01-01", "2026-08-01", "2026-10-01", "2026-11-11"].enumerated().map { i, k in
            LoggedSet(id: "s\(i)", exId: "a", date: k, slot: 0, weight: 80 + Double(i), reps: 5, ts: 0)
        }
        let s = Store(data: d, persist: false)
        s.today = "2026-11-11"
        XCTAssertEqual(ChartRange.m3.start("2026-11-11"), "2026-08-11")
        XCTAssertEqual(ChartRange.y1.start("2026-11-11"), "2025-11-11")
        XCTAssertNil(ChartRange.all.start("2026-11-11"))
        XCTAssertEqual(ChartRange.m3.start("2026-05-31"), "2026-02-28")         // month ends are handled
        XCTAssertEqual(s.series("a", .heaviest, .m3).map(\.k), ["2026-10-01", "2026-11-11"])
        XCTAssertEqual(s.series("a", .heaviest, .m6).map(\.k), ["2026-08-01", "2026-10-01", "2026-11-11"])
        XCTAssertEqual(s.series("a", .heaviest, .y1).map(\.k), ["2026-01-01", "2026-08-01", "2026-10-01", "2026-11-11"])
        XCTAssertEqual(s.series("a", .heaviest, .all).count, 5)
    }
}

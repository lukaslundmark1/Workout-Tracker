import XCTest
@testable import Training

/// The ported rules, checked against what app.js does with the same input.
final class LogicTests: XCTestCase {
    private func set(_ ex: String, _ date: String, _ slot: Int, _ w: Double, _ r: Int, ts: Double = 0) -> LoggedSet {
        LoggedSet(id: "\(ex)-\(date)-\(slot)", exId: ex, date: date, slot: slot, weight: w, reps: r, ts: ts)
    }
    private func store(_ sets: [LoggedSet], days: [String: Day] = [:]) -> Store {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press"), Exercise(id: "b", name: "Squat")]
        d.sets = sets
        d.days = days
        return Store(data: d, persist: false)
    }

    func testE1rm() {
        // app.js: e1rm({weight: 100, reps: 5}) = 100*100 / (48.8 + 53.8*exp(-0.375)) = 116.5825 (node)
        XCTAssertEqual(e1rm(set("a", "2026-01-01", 0, 100, 5)), 116.5825, accuracy: 0.0001)
        XCTAssertEqual(e1rm(set("a", "2026-01-01", 0, 100, 1)), 100)
    }

    func testParsing() {
        XCTAssertEqual(parseW("77,5"), 77.5)
        XCTAssertEqual(parseW("80"), 80)
        XCTAssertEqual(parseW("0"), 0)
        XCTAssertNil(parseW(""))
        XCTAssertNil(parseW("abc"))
        XCTAssertEqual(parseR("8"), 8)
        XCTAssertNil(parseR("0"))
        XCTAssertNil(parseR(""))
    }

    func testUnitsAndCompactText() {
        let kg = Units(imperial: false), lb = Units(imperial: true)
        XCTAssertEqual(kg.w(77.5), "77.5")
        XCTAssertEqual(kg.w(80), "80")
        XCTAssertEqual(lb.w(100), "220.5")           // Math.round(100 * 2.20462262 * 10) / 10
        let ss = [set("a", "d", 0, 82.5, 8), set("a", "d", 1, 82.5, 7), set("a", "d", 2, 85, 5)]
        XCTAssertEqual(kg.compact(ss), "82.5 kg × 8, 7 · 85 kg × 5")
        XCTAssertEqual(kg.compact([set("a", "d", 0, 0, 12)]), "12 reps")
    }

    func testDates() {
        XCTAssertEqual(Day0.add("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(Day0.add("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(Day0.weekStart("2026-11-11", firstDay: 1), "2026-11-09")   // Wednesday → Monday
        XCTAssertEqual(Day0.weekStart("2026-11-11", firstDay: 0), "2026-11-08")   // → Sunday
        XCTAssertEqual(Fmt.long("2026-11-11"), "Wednesday 11 November")
        XCTAssertEqual(Fmt.short("2026-11-11"), "Wed 11 Nov")
        XCTAssertEqual(Fmt.dur(65_000), "1:05")
        XCTAssertEqual(Fmt.dur(3_725_000), "1:02:05")
        XCTAssertEqual(Fmt.mins(65 * 60000), "1 h 5 min")
    }

    func testPersonalRecords() {
        let s = store([
            set("a", "2026-11-01", 0, 80, 8), set("a", "2026-11-01", 1, 80, 8),
            set("a", "2026-11-04", 0, 82.5, 8), set("a", "2026-11-04", 1, 80, 6),
            set("a", "2026-11-07", 0, 80, 8),
        ])
        XCTAssertNil(s.prFor("a", "2026-11-01"), "the first session doesn't count")
        XCTAssertEqual(s.prFor("a", "2026-11-04")?.set.id, "a-2026-11-04-0")
        XCTAssertNil(s.prFor("a", "2026-11-07"), "doesn't beat 82.5 × 8")
    }

    func testSuggestions() {
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 4)]
        let s = store([
            set("a", "2026-11-01", 0, 80, 8), set("a", "2026-11-01", 1, 80, 7), set("a", "2026-11-01", 2, 77.5, 6),
            set("a", "2026-11-04", 0, 82.5, 6),
        ], days: ["2026-11-04": day])
        let m = s.logModel("2026-11-04", 0)!
        XCTAssertEqual(m.n, 4)
        XCTAssertEqual(m.prevK, "2026-11-01")
        // closest finished set above it today
        XCTAssertEqual(s.suggest(m, 1), Draft(w: "82.5", r: "6"))
        // nothing ticked above → same set last time; past the end → last set last time
        s.data.sets = s.data.sets.filter { $0.date != "2026-11-04" }
        let m2 = s.logModel("2026-11-04", 0)!
        XCTAssertEqual(s.suggest(m2, 1), Draft(w: "80", r: "7"))
        XCTAssertEqual(s.suggest(m2, 3), Draft(w: "77.5", r: "6"))
        // what you typed wins
        s.drafts[m2.dkey] = [2: Draft(w: "90", r: "3")]
        XCTAssertEqual(s.suggest(m2, 2), Draft(w: "90", r: "3"))
    }

    func testBackupRoundTrip() throws {
        // A backup in the web app's shape (numbers as JS writes them, optional fields missing) loads and saves back the same way
        let json = """
        {"exercises":[{"id":"b:benchpress","name":"Bench press","track":["weight","reps"],"instructions":"","video":"","lib":"b:benchpress"}],
         "workouts":[{"id":"w1","name":"Push","items":[{"exId":"b:benchpress","sets":3}]}],
         "days":{"2026-11-11":{"items":[{"exId":"b:benchpress","sets":null}],"workouts":[{"id":"w1","name":"Push"}],"session":{"start":1762880000000}}},
         "sets":[{"id":"s1","exId":"b:benchpress","date":"2026-11-11","slot":0,"weight":82.5,"reps":8,"ts":1762880100000}],
         "plans":[],"activePlan":null,"settings":{"units":"metric","theme":"system","weekStart":1,"defaultSets":3,"name":""},"version":3}
        """
        let d = try JSONDecoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(d.sets.first?.weight, 82.5)
        XCTAssertNil(d.days["2026-11-11"]?.items.first?.sets)
        XCTAssertEqual(d.days["2026-11-11"]?.session?.start, 1762880000000)
        let again = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(again, d)
    }

    func testNumberPadTyping() {
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 2)]
        let s = store([], days: ["2026-11-11": day])
        s.padOpen("2026-11-11", "a", 0, .w)
        s.padKey("7"); s.padKey("7"); s.padKey("."); s.padKey("5")
        XCTAssertEqual(s.padValue, "77.5")
        s.padKey("5")                                  // two decimals at most → ignored after "77.5"? (one more allowed)
        XCTAssertEqual(s.padValue, "77.55")
        s.padKey("1")
        XCTAssertEqual(s.padValue, "77.55")
        s.padKey("back"); s.padKey("back")
        XCTAssertEqual(s.padValue, "77.")
        s.padKey("plus")
        XCTAssertEqual(s.padValue, "79.5")
        s.padKey("next")
        XCTAssertEqual(s.pad?.field, .r)
        s.padKey("1"); s.padKey("0")
        XCTAssertEqual(s.padValue, "10")
        s.padKey("next")
        XCTAssertEqual(s.pad?.i, 1)
        XCTAssertEqual(s.pad?.field, .w)
        XCTAssertEqual(s.padValue, "")                 // nothing above it ticked and no history
    }
}

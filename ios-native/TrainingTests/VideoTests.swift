import XCTest
@testable import Training

/// Videos linked to sets: the `v` field on a set (sync format) and linking / unlinking / untick + re-tick.
final class VideoTests: XCTestCase {
    private func store() -> Store {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press")]
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 3)]
        d.days[Day0.today] = day
        let s = Store(data: d, persist: false)
        s.drafts["a|" + s.today + "|" + otherGroup] = [0: Draft(w: "80", r: "5"), 1: Draft(w: "80", r: "5")]
        return s
    }

    func testSetWithoutVideosEncodesAsBefore() throws {
        // no `v` key at all, so existing sets keep their sync hash (nothing re-uploads)
        let s = LoggedSet(id: "x", exId: "a", date: "2026-11-12", slot: 0, weight: 80, reps: 5, ts: 1)
        let json = String(data: try SyncCore.encoder().encode(s), encoding: .utf8)!
        XCTAssertFalse(json.contains("\"v\""))
    }

    func testDecodeKeepsAndCleansVideos() throws {
        let raw = #"{"id":"x","exId":"a","date":"2026-11-12","slot":0,"weight":80,"reps":5,"ts":1,"v":["AAA/L0/001","",42]}"#
        // a non-string inside drops the field rather than the set
        let bad = try JSONDecoder().decode(LoggedSet.self, from: Data(raw.utf8))
        XCTAssertEqual(bad.id, "x")
        let ok = #"{"id":"x","exId":"a","date":"2026-11-12","slot":0,"weight":80,"reps":5,"ts":1,"v":["AAA/L0/001",""]}"#
        let s = try JSONDecoder().decode(LoggedSet.self, from: Data(ok.utf8))
        XCTAssertEqual(s.v, ["AAA/L0/001"])
        let none = #"{"id":"x","exId":"a","date":"2026-11-12","slot":0,"weight":80,"reps":5,"ts":1,"v":[]}"#
        XCTAssertNil(try JSONDecoder().decode(LoggedSet.self, from: Data(none.utf8)).v)
    }

    func testLinkUnlinkAndRetick() {
        let s = store(), k = s.today
        s.toggle(k, 0, 0); s.toggle(k, 0, 1)
        let sets = s.setsOf("a", k).sorted { $0.slot < $1.slot }
        guard sets.count == 2 else { return XCTFail("expected 2 sets, got \(sets.count)") }
        s.linkVideos(["v1", "v2"], to: [sets[0].id, sets[1].id])
        s.linkVideos(["v1"], to: [sets[0].id])                       // not doubled
        XCTAssertEqual(s.setsOf("a", k).first { $0.slot == 0 }?.v, ["v1", "v2"])
        s.unlinkVideo("v1", from: sets[1].id)
        XCTAssertEqual(s.setsOf("a", k).first { $0.slot == 1 }?.v, ["v2"])
        s.unlinkVideo("v2", from: sets[1].id)
        XCTAssertNil(s.setsOf("a", k).first { $0.slot == 1 }?.v)      // empty → no field
        // untick and tick again: the set keeps its videos
        s.toggle(k, 0, 0)
        XCTAssertNil(s.setsOf("a", k).first { $0.slot == 0 })
        s.toggle(k, 0, 0)
        XCTAssertEqual(s.setsOf("a", k).first { $0.slot == 0 }?.v, ["v1", "v2"])
    }

    /// History → a day opens the exercise screen on that exercise (the workout it was logged in when it's in two)
    func testLogStartFromHistory() {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench press"), Exercise(id: "b", name: "Row")]
        var day = Day()
        day.workouts = [WorkoutRef(id: "w1", name: "Push")]
        day.items = [WorkoutItem(exId: "b", sets: 2, w: otherGroup), WorkoutItem(exId: "a", sets: 2, w: "w1"), WorkoutItem(exId: "a", sets: 2, w: otherGroup)]
        d.days["2026-11-01"] = day
        d.sets = [LoggedSet(id: "s1", exId: "a", date: "2026-11-01", slot: 0, weight: 80, reps: 5, ts: 1, w: otherGroup)]
        let s = Store(data: d, persist: false)
        let items = s.dayOf("2026-11-01").items
        let ia = s.logStart("a", "2026-11-01"), ib = s.logStart("b", "2026-11-01")
        XCTAssertEqual(ia.map { items[$0].exId }, "a")
        XCTAssertEqual(ia.map { items[$0].w ?? otherGroup }, otherGroup)   // where it was logged, not the w1 workout
        XCTAssertEqual(ib.map { items[$0].exId }, "b")
        XCTAssertNil(s.logStart("a", "2026-11-02"))           // not on that day
    }
}

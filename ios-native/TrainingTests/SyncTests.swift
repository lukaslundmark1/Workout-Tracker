import XCTest
@testable import Training

/// Cloud sync without Firebase: what gets sent, how incoming documents merge, and that the web app's documents
/// come in without being sent straight back. Expected hashes and friend codes come from app.js's own functions (node).
final class SyncTests: XCTestCase {
    private func sample() -> AppData {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench"), Exercise(id: "b", name: "Squat", muscle: "legs", equip: "barbell")]
        d.workouts = [Workout(id: "w1", name: "Upper", items: [WorkoutItem(exId: "a", sets: 3), WorkoutItem(exId: "b", sets: nil)])]
        var day = Day(); day.items = [WorkoutItem(exId: "a", sets: 3)]; day.session = Session(start: 1_700_000_000_000, end: nil)
        d.days = ["2026-11-10": day]
        d.sets = [LoggedSet(id: "s1", exId: "a", date: "2026-11-10", slot: 0, weight: 72.5, reps: 8, ts: 1_700_000_100_000),
                  LoggedSet(id: "s2", exId: "a", date: "2026-11-10", slot: 1, weight: 80, reps: 5, ts: 1_700_000_200_000)]
        d.plans = [Plan(id: "p1", name: "UL", weeks: 0, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: nil)])]
        d.activePlan = ActivePlan(planId: "p1", begin: "2026-11-01", start: "2026-11-01")
        d.settings.name = "Lukas"; d.settings.code = "ABCDEF"
        return d
    }
    private func doc(_ id: String, _ json: String) -> IncomingDoc {
        IncomingDoc(id: id, data: try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any])
    }
    private func asIncoming(_ ops: [SyncOp], _ col: SyncCol) -> [IncomingDoc] {
        ops.filter { $0.col == col }.map { IncomingDoc(id: $0.id, data: $0.body) }
    }

    func testHashAndFriendCodeMatchTheWebApp() {
        XCTAssertEqual(SyncCore.hash(""), "ztntfp")
        XCTAssertEqual(SyncCore.hash("a"), "1r9wi7g")
        XCTAssertEqual(SyncCore.hash(#"{"id":"x","weight":72.5}"#), "1qbzee4")
        XCTAssertEqual(SyncCore.hash("Bänkpress ✓ 💪"), "1spsimd")
        XCTAssertEqual([0, 1, 5].map { FriendCode.code(for: "kQ3vX9aBcD1eF2gH3iJ4kL5mN6o2", variant: $0) }, ["USSCCN", "F7SRJR", "3LRVZB"])
        XCTAssertEqual([0, 1, 5].map { FriendCode.code(for: "u1", variant: $0) }, ["BUATZH", "QFASRV", "4ZBN3G"])
        XCTAssertEqual([0, 1, 5].map { FriendCode.code(for: "ÅÄÖ", variant: $0) }, ["EKJWUP", "ZXJ5JR", "MDH9C5"])
    }

    func testOpsSendChangesOnceAndTombstonesForDeletes() {
        var d = sample(), st = SyncState()
        let cache = HashCache()
        let first = SyncCore.ops(d, &st, now: 5, cache: cache)
        // 2 exercises, 1 workout, 1 day, 2 sets, 1 plan, settings + active
        XCTAssertEqual(first.count, 9)
        XCTAssertTrue(first.allSatisfy { ($0.body["u"] as? Double) == 5 })
        let set = first.first { $0.col == .sets && $0.id == "s1" }!.body
        XCTAssertEqual(set["weight"] as? Double, 72.5)
        XCTAssertEqual(set["reps"] as? Int, 8)
        XCTAssertEqual(set["date"] as? String, "2026-11-10")
        let dayBody = first.first { $0.col == .days }!.body
        XCTAssertNil(dayBody["id"], "days are keyed by date, with no id inside")

        // Mark as sent: nothing more to send
        for o in first { st.maps[o.col.rawValue, default: [:]][o.id] = o.h }
        XCTAssertTrue(SyncCore.ops(d, &st, now: 6, cache: cache).isEmpty)

        // Edit a set in place, delete an exercise, end the plan
        d.sets[1].weight = 82.5
        d.exercises.removeAll { $0.id == "b" }
        d.activePlan = nil
        let next = SyncCore.ops(d, &st, now: 7, cache: cache)
        XCTAssertEqual(Set(next.map { "\($0.col.rawValue)/\($0.id)" }), ["sets/s2", "exercises/b", "meta/active"])
        let tomb = next.first { $0.id == "b" }!
        XCTAssertNil(tomb.h)
        XCTAssertEqual(tomb.body["deleted"] as? Bool, true)
        XCTAssertEqual(tomb.body.count, 2)
        let active = next.first { $0.id == "active" }!.body
        XCTAssertTrue(active["planId"] is NSNull, "no plan is written as {planId: null}, like the web app")
    }

    func testRoundTripThroughDocumentsKeepsEverything() {
        let d = sample()
        var st = SyncState()
        let ops = SyncCore.ops(d, &st, now: 1_800_000_000_000, cache: HashCache())
        var other = AppData(), st2 = SyncState()
        for c in SyncCol.allCases { SyncCore.merge(asIncoming(ops, c), into: &other, col: c, state: &st2, firstSync: true) }
        XCTAssertEqual(other, d)
        XCTAssertEqual(st2.since, 1_800_000_000_000)
        // What arrived is remembered as synced: nothing to send back
        XCTAssertTrue(SyncCore.ops(other, &st2, now: 1, cache: HashCache()).isEmpty)
    }

    func testFirstSyncAccountWinsAndTombstonesRemove() {
        var d = sample(), st = SyncState()
        let docs = [
            doc("s1", #"{"id":"s1","exId":"a","date":"2026-11-10","slot":0,"weight":75,"reps":8,"ts":1700000100000,"u":100}"#),
            doc("s2", #"{"deleted":true,"u":300}"#),
            doc("s9", #"{"id":"s9","exId":"b","date":"2026-11-11","slot":0,"weight":100,"reps":3,"ts":1,"u":200}"#),
        ]
        XCTAssertTrue(SyncCore.merge(docs, into: &d, col: .sets, state: &st, firstSync: true))
        XCTAssertEqual(d.sets.map(\.id), ["s1", "s9"])
        XCTAssertEqual(d.sets[0].weight, 75)
        XCTAssertEqual(st.since, 300)
        XCTAssertEqual(Set(st.maps["sets"]!.keys), ["s1", "s9"])
    }

    func testWebDocumentsComeInWithoutEchoing() {
        // Shaped exactly like the web app writes them (null sets, null workoutId, integer weights, unknown order)
        var d = AppData(), st = SyncState()
        SyncCore.merge([doc("w1", #"{"name":"Upper","id":"w1","items":[{"exId":"a","sets":null},{"exId":"b","sets":4}],"u":10}"#)],
                       into: &d, col: .workouts, state: &st)
        SyncCore.merge([doc("p1", #"{"id":"p1","name":"UL","weeks":8,"days":[{"workoutId":"w1"},{"workoutId":null}],"u":11}"#)],
                       into: &d, col: .plans, state: &st)
        SyncCore.merge([doc("2026-11-11", #"{"items":[{"exId":"a","sets":3}],"workouts":[{"id":"w1","name":"Upper"}],"plan":{"id":"p1","index":0},"session":{"start":1700000000000},"u":12}"#)],
                       into: &d, col: .days, state: &st)
        SyncCore.merge([doc("e1", #"{"id":"e1","name":"Bench press","track":["weight","reps"],"instructions":"","video":"","lib":"b:benchpress","muscle":"chest","equip":"barbell","u":13}"#)],
                       into: &d, col: .exercises, state: &st)
        SyncCore.merge([doc("settings", #"{"units":"imperial","theme":"dark","weekStart":0,"defaultSets":4,"name":"Lukas","code":"QWERTY","u":14}"#),
                        doc("active", #"{"planId":"p1","begin":"2026-11-01","start":"2026-10-31","u":15}"#)],
                       into: &d, col: .meta, state: &st)
        XCTAssertEqual(d.workouts.first?.items.first?.sets, nil)
        XCTAssertEqual(d.plans.first?.days.last?.workoutId, nil)
        XCTAssertEqual(d.days["2026-11-11"]?.plan?.index, 0)
        XCTAssertEqual(d.exercises.first?.lib, "b:benchpress")
        XCTAssertEqual(d.settings.units, "imperial"); XCTAssertEqual(d.settings.code, "QWERTY"); XCTAssertEqual(d.settings.weekStart, 0)
        XCTAssertEqual(d.activePlan?.start, "2026-10-31")
        XCTAssertEqual(st.since, 15)
        XCTAssertTrue(SyncCore.ops(d, &st, now: 99, cache: HashCache()).isEmpty, "records that just arrived must not be sent back")

        // The web app ends the plan
        XCTAssertTrue(SyncCore.merge([doc("active", #"{"planId":null,"u":20}"#)], into: &d, col: .meta, state: &st))
        XCTAssertNil(d.activePlan)
        XCTAssertTrue(SyncCore.ops(d, &st, now: 99, cache: HashCache()).isEmpty)
    }

    func testListenerSkipsUnchangedAndKeepsOrder() {
        var d = sample(), st = SyncState()
        var tmp = SyncState()
        let ops = SyncCore.ops(d, &tmp, now: 50, cache: HashCache())
        for c in SyncCol.allCases { SyncCore.merge(asIncoming(ops, c), into: &d, col: c, state: &st, firstSync: true) }
        // The same documents again: nothing changes
        XCTAssertFalse(SyncCore.merge(asIncoming(ops, .exercises), into: &d, col: .exercises, state: &st))
        // A renamed exercise keeps its place; a new one goes at the end
        let changed = SyncCore.merge([doc("a", #"{"id":"a","name":"Bench press","track":["weight","reps"],"instructions":"","video":"","u":60}"#),
                                      doc("c", #"{"id":"c","name":"Curl","u":61}"#)], into: &d, col: .exercises, state: &st)
        XCTAssertTrue(changed)
        XCTAssertEqual(d.exercises.map(\.name), ["Bench press", "Squat", "Curl"])
        XCTAssertEqual(st.since, 61)
        // A tombstone for something this phone never had
        XCTAssertFalse(SyncCore.merge([doc("zz", #"{"deleted":true,"u":70}"#)], into: &d, col: .exercises, state: &st))
        XCTAssertEqual(st.since, 70)
    }

    func testBrokenDocumentsAreSkipped() {
        var d = sample(), st = SyncState()
        let before = d.sets
        SyncCore.merge([doc("x", #"{"exId":"a","u":5}"#), doc("y", #"{"weight":"lots","u":6}"#)], into: &d, col: .sets, state: &st)
        XCTAssertEqual(d.sets, before)
    }

    func testListenerStartMovesOnlyMonthly() {
        var st = SyncState(); st.since = 10 * 864e5
        XCTAssertEqual(SyncCore.listenFrom(&st), 10 * 864e5 - 300_000)
        st.since = 39 * 864e5
        XCTAssertEqual(SyncCore.listenFrom(&st), 10 * 864e5 - 300_000, "a stable query: still the old start")
        st.since = 41 * 864e5
        XCTAssertEqual(SyncCore.listenFrom(&st), 41 * 864e5 - 300_000)
    }

    func testHashCacheFollowsEdits() {
        var d = sample(), st = SyncState()
        let cache = HashCache()
        for o in SyncCore.ops(d, &st, now: 1, cache: cache) { st.maps[o.col.rawValue, default: [:]][o.id] = o.h }
        d.sets[0].reps = 9
        XCTAssertEqual(SyncCore.ops(d, &st, now: 2, cache: cache).map(\.id), ["s1"])
        d.sets[0].reps = 8                                   // back to what was synced
        XCTAssertTrue(SyncCore.ops(d, &st, now: 3, cache: cache).isEmpty)
    }
}

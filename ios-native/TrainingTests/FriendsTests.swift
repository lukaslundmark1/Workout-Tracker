import XCTest
@testable import Training

/// Friends without Firebase: codes, links, what's sent, and bringing a received workout/plan in.
/// Fixtures/gift-expected.json is made by `node ios-native/dev/gift-fixtures.js` (app.js's own import code on gift-payload.json).
final class FriendsTests: XCTestCase {
    private func json(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: FriendsTests.self).url(forResource: name, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testCodesAndPairIdMatchTheWebApp() throws {
        let p = try json("gift-payload"), e = try json("gift-expected")
        let codes = p["codes"] as! [String], want = e["codes"] as! [[String]]
        for (c, w) in zip(codes, want) {
            XCTAssertEqual(FriendsCore.cleanCode(c), w[0])
            XCTAssertEqual(FriendsCore.fmtCode(FriendsCore.cleanCode(c)), w[1])
        }
        XCTAssertEqual(FriendsCore.pairId("zed", "amy"), e["pair"] as? String)
        XCTAssertEqual(FriendsCore.pairId("amy", "zed"), "amy_zed")
    }

    func testImportingAGiftMatchesTheWebApp() throws {
        let p = try json("gift-payload"), e = try json("gift-expected")["data"] as! [String: Any]
        var d = AppData()
        d.exercises = [Exercise(id: "e1", name: "Bench Press"), { var x = Exercise(id: "e2", name: "Squat"); x.lib = "b:backsquat"; return x }()]
        d.workouts = [Workout(id: "w0", name: "Push", items: [])]
        d.plans = [Plan(id: "p0", name: "PPL", weeks: 0, days: [])]
        // through the same parsing as a received gift document
        let gw = Gift(id: "g1", data: ["kind": "workout", "payload": p["workout"]!, "name": "Push"]).workout!
        let gp = Gift(id: "g2", data: ["kind": "plan", "payload": p["plan"]!, "name": "ppl"]).plan!
        _ = d.importWorkout(gw, from: "Anna")
        _ = d.importPlan(gp, from: "Anna")

        // exercises: same records (ids aside)
        let wantEx = e["exercises"] as! [[String: Any]]
        XCTAssertEqual(d.exercises.count, wantEx.count)
        var nameOf: [String: String] = [:]                        // id → name, both sides
        for (have, want) in zip(d.exercises, wantEx) {
            nameOf[have.id] = have.name; nameOf[want["id"] as! String] = want["name"] as? String
            XCTAssertEqual(have.name, want["name"] as? String)
            if want["track"] != nil {                              // a new one
                XCTAssertEqual(have.track, want["track"] as? [String])
                XCTAssertEqual(have.instructions, want["instructions"] as? String)
                XCTAssertEqual(have.video, want["video"] as? String)
                XCTAssertEqual(have.muscle ?? "", want["muscle"] as? String)
                XCTAssertEqual(have.equip ?? "", want["equip"] as? String)
                XCTAssertEqual(have.lib, want["lib"] as? String)
            }
        }
        // workouts: names, and each item's exercise and sets
        let wantW = e["workouts"] as! [[String: Any]]
        XCTAssertEqual(d.workouts.map(\.name), wantW.map { $0["name"] as! String })
        var wName: [String: String] = [:]
        for (have, want) in zip(d.workouts, wantW) {
            wName[have.id] = have.name + "#" + have.id; wName[want["id"] as! String] = have.name + "#" + have.id
            let items = (want["items"] as? [[String: Any]]) ?? []
            XCTAssertEqual(have.items.map { nameOf[$0.exId]! }, items.map { nameOf[$0["exId"] as! String]! }, have.name)
            XCTAssertEqual(have.items.map { $0.sets ?? -1 }, items.map { $0["sets"] as! Int }, have.name)
        }
        // plan: name, weeks, and which workout each day is
        let wantP = (e["plans"] as! [[String: Any]])[1], haveP = d.plans[1]
        XCTAssertEqual(haveP.name, wantP["name"] as? String)
        XCTAssertEqual(haveP.weeks, wantP["weeks"] as? Int)
        let wantDays = (wantP["days"] as! [[String: Any]]).map { ($0["workoutId"] as? String).map { wName[$0]! } }
        XCTAssertEqual(haveP.days.map { $0.workoutId.map { wName[$0]! } }, wantDays)
    }

    func testWhatIsSentRoundTrips() {
        var d = AppData()
        var bench = Exercise(id: "a", name: "Bench press", instructions: "Arch.", muscle: "chest", equip: "barbell"); bench.lib = "b:benchpress"
        d.exercises = [bench, Exercise(id: "b", name: "Row")]
        d.workouts = [Workout(id: "w1", name: "Upper", items: [WorkoutItem(exId: "a", sets: 4), WorkoutItem(exId: "gone", sets: 3), WorkoutItem(exId: "b", sets: 2)]),
                      Workout(id: "w2", name: "Lower", items: [])]
        let plan = Plan(id: "p", name: "UL", weeks: 6, days: [PlanDay(workoutId: "w1"), PlanDay(workoutId: nil), PlanDay(workoutId: "w2"), PlanDay(workoutId: "w1"), PlanDay(workoutId: "missing")])
        let g = Gift(id: "x", data: ["kind": "plan", "name": "UL", "payload": d.planPayload(plan)])
        XCTAssertEqual(g.summary, "Plan · 5-day rotation · 2 workouts · 6 weeks")
        XCTAssertEqual(g.plan?.workouts.map(\.name), ["Upper", "Lower"])
        XCTAssertEqual(g.plan?.workouts[0].items.map(\.ex.name), ["Bench press", "Row"])   // a deleted exercise isn't sent
        XCTAssertEqual(g.plan?.days, [0, nil, 1, 0, nil])
        XCTAssertEqual(g.plan?.workouts[0].items[0].ex.lib, "b:benchpress")
        let w = Gift(id: "y", data: ["kind": "workout", "name": "Upper", "payload": d.workoutPayload(d.workouts[0])])
        XCTAssertEqual(w.summary, "Workout · 2 exercises")

        // received by someone who already has a bench press: it's reused; Row is new
        var other = AppData()
        other.exercises = [{ var x = Exercise(id: "mine", name: "Barbell bench"); x.lib = "b:benchpress"; return x }()]
        let pid = other.importPlan(g.plan!, from: "Lukas")
        XCTAssertEqual(other.exercises.map(\.name), ["Barbell bench", "Row"])
        XCTAssertEqual(other.plans.first { $0.id == pid }?.days.count, 5)
        XCTAssertEqual(other.workouts.first?.items.first?.exId, "mine")
    }

    func testLinksFromDocuments() {
        let l = FriendLink(id: "a_b", data: ["members": ["a", "b"], "from": "b", "status": "pending", "share": ["b": true, "a": "yes"],
                                            "names": ["b": String(repeating: "N", count: 90), "a": 5], "u": 3])!
        XCTAssertTrue(l.incoming("a")); XCTAssertFalse(l.incoming("b")); XCTAssertTrue(l.outgoing("b"))
        XCTAssertTrue(l.theyShare("a")); XCTAssertFalse(l.iShare("a"))     // only a real true counts
        XCTAssertEqual(l.name("a").count, 60)
        XCTAssertEqual(l.name("b"), "5")
        XCTAssertNil(FriendLink(id: "x", data: ["members": ["a"]]))
        let empty = FriendLink(id: "a_c", data: ["members": ["a", "c"], "status": "accepted"])!
        XCTAssertEqual(empty.name("a"), "Friend"); XCTAssertTrue(empty.accepted)
    }

    func testProfileFromAFriendsDocuments() {
        let src = FriendLoad.source(
            exercises: [["id": "e1", "name": "Squat"], ["id": "e2", "name": "Gone", "deleted": true]],
            sets: [["id": "s1", "exId": "e1", "date": "2026-11-10", "slot": 0, "weight": 100, "reps": 5, "ts": 2],
                   ["id": "s2", "exId": "e1", "date": "2026-11-10", "slot": 1, "weight": "x", "reps": 5, "ts": 1],
                   ["id": "s3", "exId": "e1", "date": "bad", "weight": 1, "reps": 1],
                   ["id": "s4", "exId": "e1", "date": "2026-11-11", "deleted": true]],
            days: [("2026-11-09", ["session": ["start": 1000, "end": 61000], "workouts": [["id": "w", "name": "Legs"]], "sessions": ["w": ["start": 1]]]),
                   ("2026-11-12", ["session": ["start": 5]]), ("2026-11-13", ["session": ["start": 5]])],
            at: 0)
        XCTAssertEqual(src.exercises.map(\.name), ["Squat"])
        XCTAssertEqual(src.ix.byDate.keys.sorted(), ["2026-11-10"])
        XCTAssertEqual(src.dates(today: "2026-11-12"), ["2026-11-12", "2026-11-10", "2026-11-09"])   // running today counts; the future doesn't
        XCTAssertEqual(src.title("2026-11-09"), "Legs")
        XCTAssertEqual(src.title("2026-11-10"), "Custom workout")
        XCTAssertEqual(src.rowSub("2026-11-09", relDay: "Mon").text, "Mon · No sets logged · 1 min")
        XCTAssertEqual(src.rowSub("2026-11-10", relDay: "Tue").text, "Tue · 1 exercise · 2 sets")
        XCTAssertTrue(src.rowSub("2026-11-12", relDay: "Today").running)
        XCTAssertEqual(src.exercisesOn("2026-11-10"), ["e1"])
        XCTAssertEqual(Profile.lastTrained("2026-11-12", today: "2026-11-12"), "Today")
        XCTAssertEqual(Profile.lastTrained("2026-11-09", today: "2026-11-12"), "3 days")
        XCTAssertEqual(Profile.lastTrained("2026-10-01", today: "2026-11-12"), "1 Oct")
        XCTAssertEqual(Profile.lastTrained(nil, today: "2026-11-12"), "–")
    }
}

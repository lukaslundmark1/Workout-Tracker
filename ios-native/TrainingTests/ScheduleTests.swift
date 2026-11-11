import XCTest
@testable import Training

/// The plan schedule must agree with the web app's exactly.
/// Fixtures/schedule-fuzz.json is made by `node ios-native/dev/schedule-fixtures.js`, which runs app.js's own plan code
/// through 1,500 random steps (three plans) and records the schedule, Up next, the days and the stored data after each one.
/// Here the same steps are replayed on the Swift port and every result is compared.
final class ScheduleTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ any: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]))
    }
    private func norm(_ e: SchedEntry) -> String {
        if e.extra { return "x" + (e.absorb ?? "") }
        if e.other { return "z" }
        return "i\(e.index ?? -1)" + (e.own ? "o" : "")
    }
    private func norm(_ e: [String: Any]) -> String {
        if e["extra"] as? Bool == true { return "x" + ((e["absorb"] as? String) ?? "") }
        if e["other"] as? Bool == true { return "z" }
        return "i\((e["index"] as? Int) ?? -1)" + (e["own"] as? Bool == true ? "o" : "")
    }

    func testReplayWebAppSchedule() throws {
        let url = try XCTUnwrap(Bundle(for: ScheduleTests.self).url(forResource: "schedule-fuzz", withExtension: "json"))
        let runs = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        var checked = 0, failures = 0
        for run in runs {
            let tk = run["today"] as! String
            let s = Store(data: try decode(AppData.self, run["start"]!), persist: false)
            s.today = tk
            let horizon = Day0.add(tk, 45)
            for (n, step) in (run["steps"] as! [[String: Any]]).enumerated() {
                let op = step["op"] as! Int, k = step["k"] as! String, done = step["done"] as! Bool
                if done {
                    switch op {
                    case 0: s.moveBack(k, absorb: step["absorb"] as? String)
                    case 1: s.unrest(k)
                    case 2, 7:
                        XCTAssertTrue(s.canDoToday(k), "run \(run["variant"]!) step \(n): canDoToday")
                        s.doToday(k)
                    case 3:
                        s.ensureDay(k)
                        s.data.sets.append(try decode(LoggedSet.self, step["set"]!))
                    case 4: s.data.sets = s.data.sets.filter { $0.date != k }
                    case 5: s.pinToday()
                    case 6: s.unpin(k)
                    case 8: s.addWorkout(step["workout"] as! String, to: k)
                    default: XCTFail("unknown op \(op)")
                    }
                }
                s.purgeStalePlanDays()
                let where_ = "run \(run["variant"]!) step \(n) (op \(op) on \(k))"

                // stored days
                let days = try decode([String: Day].self, step["days"]!)
                if s.data.days != days {
                    failures += 1
                    let diff = Set(days.keys).union(s.data.days.keys).filter { days[$0] != s.data.days[$0] }.sorted()
                    XCTFail("\(where_): stored days differ at \(diff.prefix(3)) web=\(diff.first.flatMap { days[$0] }.map { "\($0)" } ?? "nil") swift=\(diff.first.flatMap { s.data.days[$0] }.map { "\($0)" } ?? "nil")")
                }
                let ex = step["expect"] as! [String: Any]

                // the schedule
                let webMap = (ex["map"] as! [String: [String: Any]]).mapValues(norm)
                let myMap = s.schedule.map.filter { $0.key <= horizon }.mapValues(norm)
                if webMap != myMap {
                    failures += 1
                    let diff = Set(webMap.keys).union(myMap.keys).filter { webMap[$0] != myMap[$0] }.sorted()
                    XCTFail("\(where_): schedule differs from \(diff.first ?? "?"): web \(diff.prefix(4).map { webMap[$0] ?? "-" }) swift \(diff.prefix(4).map { myMap[$0] ?? "-" })")
                }
                XCTAssertEqual(s.upNext()?.k, ex["upNext"] as? String, "\(where_): up next")
                XCTAssertEqual(s.todayIsFree, ex["todayIsFree"] as! Bool, "\(where_): today is free")
                for row in ex["days30"] as! [[Any]] {
                    let d = row[0] as! String
                    XCTAssertEqual(s.planDayFor(d)?.index, row[1] as? Int, "\(where_): plan day of \(d)")
                    XCTAssertEqual(s.dayOf(d).items.count, row[2] as! Int, "\(where_): items on \(d)")
                    XCTAssertEqual(s.canDoToday(d), row[3] as! Bool, "\(where_): can do \(d) today")
                }
                // the move-back sheet's previews
                if let pv = step["preview"] as? [[String]] {
                    for (i, absorb) in ["next", "round", nil].enumerated() {
                        XCTAssertEqual(s.previewDays(k, absorb: absorb).map(\.name), pv[i], "\(where_): preview \(absorb ?? "all")")
                    }
                }
                checked += 1
                if failures > 5 { return }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testDayLabels() {
        var d = AppData()
        d.exercises = [Exercise(id: "a", name: "Bench")]
        d.workouts = [Workout(id: "w", name: "Upper", items: [WorkoutItem(exId: "a", sets: 3)])]
        d.plans = [Plan(id: "p", name: "My plan", weeks: 0, days: [PlanDay(workoutId: "w"), PlanDay(workoutId: nil)])]
        d.activePlan = ActivePlan(planId: "p", begin: "2026-11-09", start: "2026-11-09")
        let s = Store(data: d, persist: false)
        s.today = "2026-11-11"
        // 9th: Upper (missed, past) → waits; 11th (today): Upper is due
        XCTAssertEqual(s.dayLabel("2026-11-11"), "Upper · My plan, day 1 of 2")
        XCTAssertEqual(s.dayLabel("2026-11-12"), "Rest day · My plan, day 2 of 2")
        s.moveBack("2026-11-11", absorb: "next")
        XCTAssertEqual(s.dayLabel("2026-11-11"), "Rest day (moved) · My plan")
        XCTAssertEqual(s.dayLabel("2026-11-12"), "Upper · My plan, day 1 of 2")
        XCTAssertEqual(s.dayLabel("2026-11-01"), "Nothing logged")
    }
}

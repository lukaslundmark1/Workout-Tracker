import XCTest
import SwiftUI
@testable import Training

/// The performance work (2026-11-12): faster versions must give exactly the old answers, and caches must never go stale.
final class PerformanceTests: XCTestCase {

    // MARK: Day arithmetic without Calendar

    /// The Calendar version (what Day0 did before), as the reference
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()
    private func refKey(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private func refDate(_ k: String) -> Date {
        let p = k.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    func testDayMathMatchesCalendar() {
        // every day from 1995 to 2055 (leap years, centuries: 2000), in this machine's time zone (DST changes included)
        var k = "1995-01-01"
        var d = refDate(k)
        var n = Day0.num(k)!
        for _ in 0..<(60 * 366) {
            XCTAssertEqual(Day0.key(num: n), k)
            XCTAssertEqual(Day0.num(k), n)
            XCTAssertEqual(Day0.weekday(k), cal.component(.weekday, from: d) - 1, k)
            XCTAssertEqual(Day0.dayOfMonth(k), cal.component(.day, from: d), k)
            XCTAssertEqual(Fmt.month(k), Fmt.months[cal.component(.month, from: d) - 1], k)
            XCTAssertEqual(Fmt.year(k), cal.component(.year, from: d), k)
            let next = refKey(cal.date(byAdding: .day, value: 1, to: d)!)
            XCTAssertEqual(Day0.add(k, 1), next, k)
            d = cal.date(byAdding: .day, value: 1, to: d)!
            k = next; n += 1
        }
        // bigger jumps, both ways, and between
        for (a, off) in [("2024-02-28", 1), ("2024-02-29", 365), ("2026-03-29", -400), ("2000-02-28", 1), ("1999-12-31", 1),
                         ("2026-10-25", 7), ("2026-11-12", -800), ("2026-11-12", 400)] {
            let ref = refKey(cal.date(byAdding: .day, value: off, to: refDate(a))!)
            XCTAssertEqual(Day0.add(a, off), ref)
            XCTAssertEqual(Day0.between(a, ref), off)
            XCTAssertEqual(Day0.between(a, ref), cal.dateComponents([.day], from: refDate(a), to: refDate(ref)).day)
        }
        for fd in [0, 1] {
            for a in ["2026-11-08", "2026-11-09", "2026-11-12", "2026-11-15", "2027-01-01"] {
                let wd = cal.component(.weekday, from: refDate(a)) - 1
                XCTAssertEqual(Day0.weekStart(a, firstDay: fd), refKey(cal.date(byAdding: .day, value: -((wd - fd + 7) % 7), to: refDate(a))!))
            }
        }
    }

    // MARK: The set index, updated in place

    /// Ticking, unticking and editing sets in a random order, on several days and exercises (two workouts with the same
    /// exercise, sets on earlier days): the index kept up to date in place must always equal one rebuilt from scratch,
    /// and every remembered day must equal one worked out fresh.
    func testIndexAndDaysStayCorrect() {
        let today = "2026-11-12"
        var d = SampleData.make(today: today, weeks: 6)
        d.workouts.append(Workout(id: "w2", name: "Extra", items: [WorkoutItem(exId: d.workouts[0].items[0].exId, sets: 3)]))
        let s = Store(data: d, persist: false)
        s.today = today; s.selected = today
        var rng = SystemRandomNumberGenerator()
        for k in [today, Day0.add(today, -1), Day0.add(today, 3)] {
            s.addWorkout(d.workouts[1].id, to: k)
            s.addWorkout("w2", to: k)
        }
        func check(_ what: String) {
            XCTAssertEqual(s.index, SetIndex(s.data.sets), "index after \(what)")
            for k in [today, Day0.add(today, -1), Day0.add(today, 3), Day0.add(today, -7), Day0.add(today, 1)] {
                let fresh = s.normalized(s.data.days[k] ?? s.virtualDay(k) ?? Day())
                XCTAssertEqual(s.dayOf(k), fresh, "day \(k) after \(what)")
                for ex in s.data.exercises.prefix(4) {          // remembered personal-record baselines
                    let naive = s.data.sets.filter { $0.exId == ex.id && $0.date < k }.map(e1rm).max()
                    XCTAssertEqual(s.prevBest(ex.id, k), naive, "prevBest \(ex.id) \(k) after \(what)")
                }
            }
        }
        check("start")
        for step in 0..<300 {
            let k = [today, Day0.add(today, -1), Day0.add(today, 3)].randomElement(using: &rng)!
            let items = s.dayOf(k).items
            guard !items.isEmpty else { continue }
            let i = Int.random(in: 0..<items.count, using: &rng)
            guard let m = s.logModel(k, i) else { continue }
            let row = Int.random(in: 0..<max(1, m.n), using: &rng)
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<6:
                s.toggle(k, i, row)                               // tick or untick
            case 6, 7:
                if m.bySlot[row] != nil {                         // edit a ticked set's weight with the number pad
                    s.padOpen(k, m.ex.id, row, .w, group: m.g)
                    s.padKey(String(Int.random(in: 1...9, using: &rng))); s.padKey("0")
                    s.padClose()
                }
            case 8:
                s.addRow(k, i)
            default:
                s.setNote(m.ex.id, "note \(step)")                // a change that doesn't touch the sets
            }
            check("step \(step)")
        }
        // a change from elsewhere (sync) replaces everything: the index is rebuilt
        var remote = s.data
        remote.sets.removeLast(3)
        s.applyRemote(remote)
        check("remote")
    }

    // MARK: Saving in the background

    func testFileWriterNeverWritesOlderOverNewer() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID().uuidString).txt")
        let w = FileWriter()
        for i in 0..<50 {
            // a slow background save, then a newer one that waits: the newer one must be what's on disk
            w.write(url, wait: false) { Thread.sleep(forTimeInterval: 0.002); return Data("old \(i)".utf8) }
            w.write(url, wait: true) { Data("new \(i)".utf8) }
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new \(i)")
        }
        // a removal wins over saves still waiting in line
        w.write(url, wait: false) { Thread.sleep(forTimeInterval: 0.01); return Data("late".utf8) }
        w.remove(url)
        w.write(url, wait: false) { Data("skipped".utf8) }   // (a later write is fine; this checks the queue drains)
        w.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Charts with many sessions

    func testThinnedChartKeepsTheShape() {
        func pts(_ n: Int) -> [StatPoint] {
            (0..<n).map { i in
                let k = Day0.add("2024-01-01", i * 2)
                return StatPoint(k: k, date: Day0.date(k), v: 100 + 20 * sin(Double(i) / 9) + Double(i % 7), note: "")
            }
        }
        let few = pts(80)
        XCTAssertEqual(thinned(few, to: 100), few, "under the limit: every point, unchanged")
        for n in [101, 208, 730, 2000] {
            let all = pts(n), t = thinned(all, to: 100)
            XCTAssertLessThanOrEqual(t.count, 102)
            XCTAssertGreaterThan(t.count, 90)
            XCTAssertEqual(t.first, all.first); XCTAssertEqual(t.last, all.last)
            XCTAssertTrue(t.contains(all.max { $0.v < $1.v }!), "the best session stays")
            XCTAssertTrue(t.contains(all.min { $0.v < $1.v }!), "the lowest session stays")
            XCTAssertEqual(t.map(\.k), t.map(\.k).sorted(), "in date order")
            XCTAssertEqual(Set(t.map(\.k)).count, t.count, "no point twice")
        }
    }

    func testMonthStepsMatchCalendar() {
        var k = "2019-01-17"
        for _ in 0..<(30 * 12) {
            for n in [-25, -12, -1, 0, 1, 11, 12, 13] {
                let first = Day0.add(k, 1 - Day0.dayOfMonth(k))
                let ref = n == 0 ? first : refKey(cal.date(byAdding: .month, value: n, to: refDate(first))!)
                XCTAssertEqual(MonthGrid<EmptyView>.monthStart(k, plus: n), ref, "\(k) \(n)")
            }
            k = Day0.add(k, 30)
        }
    }

    func testDayMathOddKeys() {
        // not zero-padded: still a date (the old split-based parser accepted it); the result is padded, like before
        XCTAssertEqual(Day0.add("2026-1-5", 1), "2026-01-06")
        XCTAssertEqual(Day0.between("2026-1-5", "2026-01-15"), 10)
        // not real dates: no fast path (the Calendar decides, as before)
        for bad in ["", "2026-02-30", "2026-13-01", "abc", "2026-11", "2026-11-12-1", "2026--1"] {
            XCTAssertNil(Day0.num(bad), bad)
        }
    }
}

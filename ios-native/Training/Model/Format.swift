import Foundation

// Dates, units and number formatting, ported from app.js (Dates / Helpers / Units).

nonisolated enum Day0 {
    static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()

    /// "YYYY-MM-DD" for a date, in local time (the web app's `dk`).
    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    /// The web app's `parse`: local midnight of that day.
    static func date(_ k: String) -> Date {
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
    }
    static func add(_ k: String, _ n: Int) -> String { key(cal.date(byAdding: .day, value: n, to: date(k))!) }
    static var today: String { key(Date()) }
    static func between(_ a: String, _ b: String) -> Int {
        cal.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    /// Monday or Sunday of the week containing k (Settings → week starts on).
    static func weekStart(_ k: String, firstDay: Int) -> String {
        let wd = cal.component(.weekday, from: date(k)) - 1   // 0 = Sunday, like JS getDay()
        return add(k, -((wd - firstDay + 7) % 7))
    }
    static func dayOfMonth(_ k: String) -> Int { cal.component(.day, from: date(k)) }
}

enum Fmt {
    private static let longF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE d MMMM"; return f }()
    private static let shortF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM"; return f }()
    private static let timeF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f }()
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// "Wednesday 11 November"
    static func long(_ k: String) -> String { longF.string(from: Day0.date(k)) }
    private static let wdF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE"; return f }()
    static func weekdayShort(_ k: String) -> String { wdF.string(from: Day0.date(k)) }
    private static let tinyF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"; return f }()
    /// "9 Nov"
    static func tiny(_ k: String) -> String { tinyF.string(from: Day0.date(k)) }
    private static let dayYearF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM yyyy"; return f }()
    /// "Wed 11 Nov 2025"
    static func dayYear(_ k: String) -> String { dayYearF.string(from: Day0.date(k)) }
    /// "Wed 11 Nov"
    static func short(_ k: String) -> String { shortF.string(from: Day0.date(k)) }
    static func hm(_ ms: Double) -> String { timeF.string(from: Date(timeIntervalSince1970: ms / 1000)) }
    static func month(_ k: String) -> String { months[Day0.cal.component(.month, from: Day0.date(k)) - 1] }
    static func year(_ k: String) -> Int { Day0.cal.component(.year, from: Day0.date(k)) }

    /// Header title for a week: "November", "Nov – Dec", with the year when it isn't this year.
    static func weekLabel(_ ws: String) -> (text: String, year: String?) {
        let we = Day0.add(ws, 6)
        let thisYear = Day0.cal.component(.year, from: Date())
        let m1 = month(ws), m2 = month(we)
        if m1 == m2 { return (m1, year(ws) == thisYear ? nil : String(year(ws))) }
        return ("\(m1.prefix(3)) – \(m2.prefix(3))", year(we) == thisYear ? nil : String(year(we)))
    }

    /// Running stopwatch: "4:07", "1:02:09"
    static func dur(_ ms: Double) -> String {
        let t = max(0, Int(ms / 1000)), h = t / 3600, m = (t / 60) % 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    /// "52 min", "1 h 5 min"
    static func mins(_ ms: Double) -> String {
        let m = Int((ms / 60000).rounded()), h = m / 60
        return h > 0 ? "\(h) h \(m % 60) min" : "\(m) min"
    }
    static func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
}

/// Units: weights are always stored in kg, shown and typed in the unit chosen in Settings.
struct Units {
    static let LB = 2.20462262
    var imperial: Bool
    var u: String { imperial ? "lb" : "kg" }
    var step: Double { imperial ? 5 : 2.5 }
    func toU(_ kg: Double) -> Double { imperial ? kg * Units.LB : kg }
    func fromU(_ v: Double) -> Double { imperial ? v / Units.LB : v }
    /// The web app's `W`: a weight as typed/shown in the chosen unit.
    func w(_ kg: Double) -> String { imperial ? num((kg * Units.LB * 10).rounded() / 10) : num((kg * 100).rounded() / 100) }

    /// Sets written compactly: "82.5 kg × 8, 7 · 85 kg × 5"
    func compact(_ ss: [LoggedSet]) -> String {
        var out: [(w: Double, r: [Int])] = []
        for s in ss {
            if let last = out.last, last.w == s.weight { out[out.count - 1].r.append(s.reps) } else { out.append((s.weight, [s.reps])) }
        }
        return out.map { g in
            let reps = g.r.map(String.init).joined(separator: ", ")
            return g.w > 0 ? "\(w(g.w)) \(u) × \(reps)" : "\(reps) reps"
        }.joined(separator: " · ")
    }
    func setText(_ s: LoggedSet) -> String { s.weight > 0 ? "\(w(s.weight)) \(u) × \(s.reps)" : "\(s.reps) reps" }
}

/// JS `String(n)` for the numbers we show: no trailing ".0".
nonisolated func num(_ v: Double) -> String {
    if v == v.rounded() && abs(v) < 1e15 { return String(Int(v)) }
    var s = String(v)
    if s.contains("e") { s = String(format: "%.2f", v) }
    return s
}
/// The web app's parseW: a typed weight (comma or point), ≥ 0, or nil.
nonisolated func parseW(_ s: String) -> Double? {
    let t = s.replacingOccurrences(of: ",", with: ".")
    // parseFloat reads a leading number and ignores the rest
    var lead = ""
    for ch in t { if ch.isNumber || (ch == "." && !lead.contains(".")) { lead.append(ch) } else { break } }
    guard let n = Double(lead), n >= 0 else { return nil }
    return n
}
/// The web app's parseR: whole reps > 0, or nil.
nonisolated func parseR(_ s: String) -> Int? {
    var lead = ""
    for ch in s { if ch.isNumber { lead.append(ch) } else { break } }
    guard let n = Int(lead), n > 0 else { return nil }
    return n
}

/// Estimated 1RM, Wathan (1994).
nonisolated func e1rm(_ s: LoggedSet) -> Double {
    s.reps <= 1 ? s.weight : (100 * s.weight) / (48.8 + 53.8 * exp(-0.075 * Double(s.reps)))
}

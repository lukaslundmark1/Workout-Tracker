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
    static var today: String { key(Date()) }

    // Day arithmetic on the keys themselves (2026-11-12, performance): a key is a calendar day, so adding days and
    // counting the days between two keys is plain integer maths on a day number (days since 1970-01-01), no Calendar
    // or time zone involved. ~100x faster than the Calendar version, which these are called from in every redraw
    // (week strip, day pager, plan schedule). Keys that don't parse fall back to the Calendar (same results as before).
    static func add(_ k: String, _ n: Int) -> String {
        if let d = num(k) { return key(num: d + n) }
        return key(cal.date(byAdding: .day, value: n, to: date(k))!)
    }
    static func between(_ a: String, _ b: String) -> Int {
        if let x = num(a), let y = num(b) { return y - x }
        return cal.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    /// Monday or Sunday of the week containing k (Settings → week starts on).
    static func weekStart(_ k: String, firstDay: Int) -> String {
        return add(k, -((weekday(k) - firstDay + 7) % 7))
    }
    /// 0 = Sunday, like JS getDay()
    static func weekday(_ k: String) -> Int {
        if let d = num(k) { return ((d % 7) + 7 + 4) % 7 }    // 1970-01-01 was a Thursday
        return cal.component(.weekday, from: date(k)) - 1
    }
    static func dayOfMonth(_ k: String) -> Int {
        if let p = parts(k) { return p.d }
        return cal.component(.day, from: date(k))
    }

    /// "YYYY-M(M)-D(D)" → year, month, day, if it's a real date
    static func parts(_ k: String) -> (y: Int, m: Int, d: Int)? {
        var v = [0, 0, 0], i = 0, digits = 0
        for c in k.utf8 {
            if c == 45 /* - */ { if digits == 0 || i == 2 { return nil }; i += 1; digits = 0; continue }
            guard c >= 48 && c <= 57, digits < 9 else { return nil }
            v[i] = v[i] * 10 + Int(c - 48); digits += 1
        }
        guard i == 2, digits > 0, v[1] >= 1, v[1] <= 12, v[2] >= 1, v[2] <= daysIn(v[0], v[1]) else { return nil }
        return (v[0], v[1], v[2])
    }
    private static func daysIn(_ y: Int, _ m: Int) -> Int {
        if m == 2 { return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28 }
        return [4, 6, 9, 11].contains(m) ? 30 : 31
    }
    /// Day number of a key (days since 1970-01-01), or nil if it isn't a real date. (Howard Hinnant's days_from_civil.)
    static func num(_ k: String) -> Int? {
        guard let (y0, m, d) = parts(k) else { return nil }
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    /// The key of a day number (civil_from_days), zero-padded like `key(_ d: Date)`.
    static func key(num z0: Int) -> String {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        guard y >= 0 && y <= 9999 else { return String(format: "%04d-%02d-%02d", y, m, d) }
        let b: [UInt8] = [UInt8(48 + y / 1000), UInt8(48 + y / 100 % 10), UInt8(48 + y / 10 % 10), UInt8(48 + y % 10), 45,
                          UInt8(48 + m / 10), UInt8(48 + m % 10), 45, UInt8(48 + d / 10), UInt8(48 + d % 10)]
        return String(decoding: b, as: UTF8.self)
    }
}

enum Fmt {
    private static let longF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEEE d MMMM"; return f }()
    private static let shortF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM"; return f }()
    private static let timeF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f }()
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// Formatted dates are remembered (like the web app's memoised formatters): a DateFormatter call costs more than
    /// everything else a row does, and the same few dates are drawn over and over.
    private static var memo: [Int: [String: String]] = [:]
    private static func cached(_ f: DateFormatter, _ slot: Int, _ k: String) -> String {
        if let s = memo[slot]?[k] { return s }
        let s = f.string(from: Day0.date(k))
        if memo[slot, default: [:]].count > 2000 { memo[slot] = [:] }
        memo[slot, default: [:]][k] = s
        return s
    }

    /// "Wednesday 11 November"
    static func long(_ k: String) -> String { cached(longF, 0, k) }
    private static let wdF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE"; return f }()
    static func weekdayShort(_ k: String) -> String { cached(wdF, 1, k) }
    private static let tinyF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"; return f }()
    /// "9 Nov"
    static func tiny(_ k: String) -> String { cached(tinyF, 2, k) }
    private static let dayYearF: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "EEE d MMM yyyy"; return f }()
    /// "Wed 11 Nov 2025"
    static func dayYear(_ k: String) -> String { cached(dayYearF, 3, k) }
    /// "Wed 11 Nov"
    static func short(_ k: String) -> String { cached(shortF, 4, k) }
    static func hm(_ ms: Double) -> String { timeF.string(from: Date(timeIntervalSince1970: ms / 1000)) }
    static func month(_ k: String) -> String {
        if let p = Day0.parts(k) { return months[p.m - 1] }
        return months[Day0.cal.component(.month, from: Day0.date(k)) - 1]
    }
    static func year(_ k: String) -> Int {
        if let p = Day0.parts(k) { return p.y }
        return Day0.cal.component(.year, from: Day0.date(k))
    }

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

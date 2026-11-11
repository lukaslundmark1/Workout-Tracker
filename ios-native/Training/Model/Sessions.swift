import Foundation

// Each workout on a day has its own timer and its own Finish (2026-11-11, Lukas: "separate finish workouts for each
// of them. Even on a day where you have already worked out, you should still be able to work out").
// Stored as `sessions` on the day (group id → {start, end}). The day's own `session` (the shared format) is kept as the
// span of them all, so the web app still shows the day as in progress / finished. Older days have only `session`:
// it belongs to the workouts that have logged sets (or the first workout), until the day is next changed.

/// A workout on a day (for routes and sheets)
struct GroupKey: Identifiable, Hashable {
    var k: String
    var g: String
    var id: String { k + "|" + g }
}

extension Store {
    /// Every workout's timer on a day
    func sessions(_ k: String) -> [String: Session] {
        let d = dayOf(k)
        if let ss = d.sessions { return ss }
        guard let s = d.session else { return [:] }
        let gs = groups(k).map(\.id)
        let withSets = gs.filter { !groupSets(k, $0).isEmpty }
        return Dictionary(uniqueKeysWithValues: (withSets.isEmpty ? Array(gs.prefix(1)) : withSets).map { ($0, s) })
    }
    func sessionOf(_ k: String, _ g: String) -> Session? { sessions(k)[g] }

    /// The day's shared `session`: from the first start to the last end (open while any workout runs)
    static func span(_ ss: [String: Session]) -> Session? {
        guard let start = ss.values.map(\.start).min() else { return nil }
        let running = ss.values.contains { $0.end == nil }
        return Session(start: start, end: running ? nil : ss.values.compactMap(\.end).max())
    }

    /// Change one workout's timer (nil removes it), keeping the day's span in step
    func setSession(_ k: String, _ g: String, _ s: Session?, in d: inout AppData) {
        var ss = sessions(k)
        ss[g] = s
        var day = normalized(d.days[k] ?? virtualDay(k) ?? Day())
        day.sessions = ss.isEmpty ? nil : ss
        day.session = Store.span(ss)
        d.days[k] = day
    }
    func setSession(_ k: String, _ g: String, _ s: Session?) {
        var d = data
        setSession(k, g, s, in: &d)
        data = d
    }

    // MARK: Per workout

    func isFinished(_ k: String, _ g: String) -> Bool { sessionOf(k, g)?.end != nil }
    func isRunning(_ k: String, _ g: String) -> Bool { if let s = sessionOf(k, g) { return s.end == nil } else { return false } }
    /// Finish is offered for a workout that's running, or for today's workout once something in it is logged.
    func canFinish(_ k: String, _ g: String) -> Bool { !isFinished(k, g) && (isRunning(k, g) || (k == today && !groupSets(k, g).isEmpty)) }
    func setsLeft(_ k: String, _ g: String) -> Int {
        dayOf(k).items.filter { $0.w == g }.reduce(0) { $0 + max(0, ($1.sets ?? 0) - setsOf($1.exId, k, g).count) }
    }

    private func pauseKey(_ k: String, _ g: String) -> String { k + "|" + g }
    func isPaused(_ k: String, _ g: String) -> Bool { pausedAt[pauseKey(k, g)] != nil && isRunning(k, g) }
    /// The timer's time: up to now, or up to when it was paused
    func elapsed(_ k: String, _ g: String) -> Double {
        guard let s = sessionOf(k, g) else { return 0 }
        return (s.end ?? pausedAt[pauseKey(k, g)] ?? nowMs()) - s.start
    }
    /// "Now" for a workout: when its timer was paused, or now
    func clock(_ k: String, _ g: String) -> Double { isPaused(k, g) ? pausedAt[pauseKey(k, g)]! : nowMs() }

    func startTimer(_ k: String, _ g: String) {
        Haptics.impact()
        pausedAt[pauseKey(k, g)] = nil
        setSession(k, g, Session(start: nowMs()))
    }
    /// Resume a finished workout (Duration sheet)
    func resume(_ k: String, _ g: String) {
        guard let s = sessionOf(k, g) else { return }
        pausedAt[pauseKey(k, g)] = nil
        setSession(k, g, Session(start: s.start))
    }
    /// Tapping the timer: start it, pause it, carry on. (Ending is only Finish workout.)
    func tapTimer(_ k: String, _ g: String) {
        guard let s = sessionOf(k, g) else { startTimer(k, g); return }
        guard s.end == nil else { return }
        if let p = pausedAt[pauseKey(k, g)] {
            Haptics.impact()
            pausedAt[pauseKey(k, g)] = nil
            setSession(k, g, Session(start: s.start + (nowMs() - p)))   // the paused time doesn't count
        } else {
            Haptics.select()
            pausedAt[pauseKey(k, g)] = nowMs()
        }
    }
    func clearPause(_ k: String, _ g: String) { pausedAt[pauseKey(k, g)] = nil }

    // MARK: The whole day

    /// Any workout on the day running
    func isRunning(_ k: String) -> Bool { sessions(k).values.contains { $0.end == nil } }
    /// Every workout on the day finished (an older day with a finished timer and no workouts counts too)
    func isFinished(_ k: String) -> Bool {
        let ss = sessions(k), gs = groups(k)
        if gs.isEmpty { return dayOf(k).session?.end != nil }
        return gs.allSatisfy { ss[$0.id]?.end != nil }
    }
    /// Time spent: each workout's duration added up
    func dayDuration(_ k: String) -> Double { sessions(k).values.reduce(0) { $0 + (($1.end ?? $1.start) - $1.start) } }

    /// The last set logged in a workout that day
    func lastSetTs(_ k: String, _ g: String) -> Double? { groupSets(k, g).map(\.ts).max() }
}

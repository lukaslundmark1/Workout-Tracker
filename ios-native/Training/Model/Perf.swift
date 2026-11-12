import Foundation
import QuartzCore
import os

/// Performance tools (2026-11-12). Nothing here runs without a launch argument (only Xcode / `simctl launch` can pass
/// one), so they're compiled into every build: that way the optimised (Release) build can be measured too.
///  • `-perfData <weeks>`: starts with made-up training (dense: ~16 sets a day, 6 days a week, e.g. 104 weeks ≈ 10,000
///    sets), kept in its own file (`training-perf.json`), with accounts and sync switched off so it can never upload.
///  • `-perfLog 1`: logs slow work (`Perf.measure`) and dropped frames (`HitchMonitor`) to the unified log, subsystem
///    "perf". Read it with `xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "perf"'`.
nonisolated enum Perf {
    static let dataWeeks: Int = ProcessInfo.processInfo.arguments.contains("-perfData") ? UserDefaults.standard.integer(forKey: "perfData") : 0
    static let logging: Bool = ProcessInfo.processInfo.arguments.contains("-perfLog") && UserDefaults.standard.bool(forKey: "perfLog")
    static var fixture: Bool { dataWeeks > 0 }
    static let log = Logger(subsystem: "perf", category: "perf")

    /// Times a piece of work; logs it when it took longer than `over` ms (only with `-perfLog`).
    @inline(__always)
    static func measure<T>(_ name: StaticString, over: Double = 0.5, _ body: () throws -> T) rethrows -> T {
        guard logging else { return try body() }
        let t = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - t) * 1000
            if ms > over { log.log("\(name, privacy: .public) \(String(format: "%.2f", ms), privacy: .public) ms") }
        }
        return try body()
    }
}

/// Counts dropped frames: each display refresh that came more than half a frame late. Logs hitches over 40 ms
/// and, once a second, a summary of the second if anything was dropped.
@MainActor
final class HitchMonitor: NSObject {
    static let shared = HitchMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0
    private var hitchMs = 0.0, worst = 0.0
    private var burstStart: CFTimeInterval = 0

    func start() {
        guard Perf.logging, link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp, frame = l.targetTimestamp - l.timestamp
        defer { last = now }
        guard last > 0, frame > 0 else { return }
        let gap = now - last
        frames += 1
        if burstStart == 0 { burstStart = now }
        if gap > frame * 1.5 {
            let lost = (gap - frame) * 1000
            hitches += 1; hitchMs += lost; worst = max(worst, lost)
            if lost > 40 { Perf.log.log("hitch \(String(format: "%.0f", lost), privacy: .public) ms") }
        }
        // once a second: a summary, if anything was dropped
        if now - burstStart > 1 {
            if hitches > 0 {
                Perf.log.log("second: \(self.frames, privacy: .public) frames · \(self.hitches, privacy: .public) hitches · lost \(String(format: "%.0f", self.hitchMs), privacy: .public) ms · worst \(String(format: "%.0f", self.worst), privacy: .public) ms")
            }
            frames = 0; hitches = 0; hitchMs = 0; worst = 0; burstStart = now
        }
    }
}

/// Counts view redraws (`let _ = Perf.body("Name")` at the top of a body), logged as one line after each burst:
/// shows how much of the screen a change redraws. Only with `-perfLog`.
@MainActor
enum BodyCount {
    private static var counts: [String: Int] = [:]
    private static var flush: DispatchWorkItem?
    static func hit(_ name: String) {
        guard Perf.logging else { return }
        counts[name, default: 0] += 1
        flush?.cancel()
        let w = DispatchWorkItem {
            let line = counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            Perf.log.log("bodies: \(line, privacy: .public)")
            counts = [:]
        }
        flush = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }
}
extension Perf {
    @MainActor static func body(_ name: String) { BodyCount.hit(name) }
}

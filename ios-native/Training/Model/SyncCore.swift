import Foundation

// The parts of cloud sync that don't need Firebase (port of app.js "Cloud: accounts + sync"), so they can be tested.
// Each record is its own document under users/{uid}/{col}/{id}; every write carries `u` (ms); deletes are
// `{deleted: true, u}` tombstones. What was last synced is remembered as a hash per record (`maps[col][id]`).

nonisolated enum SyncCol: String, CaseIterable {
    case exercises, workouts, days, sets, plans, meta
}

/// What this phone last synced with one account (the web app's `tt.sync.<uid>`).
nonisolated struct SyncState: Codable, Equatable {
    var since: Double = 0                 // newest `u` seen
    var from: Double?                     // where the listener's query starts (moves on about once a month)
    var maps: [String: [String: String]] = [:]
}

/// One document to write: a record (with `u`) or a tombstone (`h == nil`).
nonisolated struct SyncOp {
    let col: SyncCol
    let id: String
    let body: [String: Any]
    let h: String?
}

/// A document that arrived from the account.
nonisolated struct IncomingDoc {
    let id: String
    let data: [String: Any]
}

nonisolated enum SyncCore {
    /// FNV-1a over UTF-16 code units, base 36 (the web app's `hash`). Only compared on this phone.
    static func hash(_ s: String) -> String {
        var h: UInt32 = 2166136261
        for c in s.utf16 { h ^= UInt32(c); h = h &* 16777619 }
        return String(h, radix: 36)
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// A record as JSON text (stable key order) and its hash.
    static func json<T: Encodable>(_ rec: T, _ enc: JSONEncoder) -> (text: Data, h: String)? {
        guard let d = try? enc.encode(rec) else { return nil }
        return (d, hash(String(decoding: d, as: UTF8.self)))
    }

    static func object(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }

    static let noPlan = Data(#"{"planId":null}"#.utf8)

    // MARK: Local records per collection

    /// Calls `f(id, record JSON, hash)` for every record this phone has in `col`. Hashes of unchanged records come
    /// from `cache` (a set only ever changes weight, reps or slot, like the web app's `recHash` cache, but here for all).
    static func eachLocal(_ d: AppData, _ col: SyncCol, _ cache: HashCache, _ enc: JSONEncoder, _ f: (String, () -> Data?, String) -> Void) {
        func run<T: Encodable & Equatable>(_ id: String, _ rec: T) {
            if let c = cache.get(col, id, rec) { f(id, { try? enc.encode(rec) }, c); return }
            guard let (text, h) = json(rec, enc) else { return }
            cache.put(col, id, rec, h)
            f(id, { text }, h)
        }
        switch col {
        case .exercises: for r in d.exercises { run(r.id, r) }
        case .workouts: for r in d.workouts { run(r.id, r) }
        case .days: for (k, r) in d.days { run(k, r) }
        case .sets: for r in d.sets { run(r.id, r) }
        case .plans: for r in d.plans { run(r.id, r) }
        case .meta:
            run("settings", d.settings)
            if let a = d.activePlan { run("active", a) }
            else { f("active", { noPlan }, hash(String(decoding: noPlan, as: UTF8.self))) }
        }
    }

    /// Records that differ from what was last synced, and tombstones for ones that are gone (the web app's `syncOps`).
    static func ops(_ d: AppData, _ state: inout SyncState, now: Double, cache: HashCache) -> [SyncOp] {
        let enc = encoder()
        var out: [SyncOp] = []
        for col in SyncCol.allCases {
            let map = state.maps[col.rawValue] ?? [:]
            var seen = Set<String>()
            eachLocal(d, col, cache, enc) { id, text, h in
                seen.insert(id)
                guard map[id] != h, let t = text(), var body = object(t) else { return }
                body["u"] = now
                out.append(SyncOp(col: col, id: id, body: body, h: h))
            }
            for id in map.keys where !seen.contains(id) {
                out.append(SyncOp(col: col, id: id, body: ["deleted": true, "u": now], h: nil))
            }
            state.maps[col.rawValue] = map
        }
        return out
    }

    // MARK: Incoming records

    /// A document's data without `u` and `deleted` (the web app's `stripRec`), as JSON for decoding.
    static func stripped(_ v: [String: Any]) -> Data? {
        var r = v; r["u"] = nil; r["deleted"] = nil
        guard JSONSerialization.isValidJSONObject(r) else { return nil }
        return try? JSONSerialization.data(withJSONObject: r)
    }

    /// Merges documents from the account into the phone's data. `firstSync`: the account's copy wins on a clash and
    /// unchanged hashes aren't skipped (the first download); otherwise records whose hash matches what was last
    /// synced are skipped (the listener). Returns whether anything on the phone changed.
    @discardableResult
    static func merge(_ docs: [IncomingDoc], into d: inout AppData, col: SyncCol, state: inout SyncState, firstSync: Bool = false) -> Bool {
        let enc = encoder(), dec = JSONDecoder()
        var map = state.maps[col.rawValue] ?? [:]
        var changed = false

        // Records keyed by id, keeping the phone's order (new ones go at the end, like Object.values in JS)
        func apply<T: Codable & Equatable>(_ list: inout [T], id: KeyPath<T, String>) {
            var pos: [String: Int] = [:]
            for (i, r) in list.enumerated() { pos[r[keyPath: id]] = i }
            var removed = Set<Int>()
            for doc in docs {
                let u = (doc.data["u"] as? NSNumber)?.doubleValue ?? 0
                state.since = max(state.since, u)
                if (doc.data["deleted"] as? Bool) == true {
                    if let i = pos[doc.id], !removed.contains(i) { removed.insert(i); changed = true }
                    map[doc.id] = nil
                    continue
                }
                guard let raw = stripped(doc.data), var rec = try? dec.decode(T.self, from: raw) else { continue }
                if rec[keyPath: id] != doc.id, let fixed = withId(rec, doc.id) { rec = fixed }
                guard let (_, h) = json(rec, enc) else { continue }
                let have = pos[doc.id].flatMap { removed.contains($0) ? nil : $0 }
                if !firstSync, map[doc.id] == h, have != nil { continue }
                map[doc.id] = h
                if let i = have { if list[i] != rec { list[i] = rec; changed = true } }
                else if let i = pos[doc.id] { removed.remove(i); list[i] = rec; changed = true }
                else { pos[doc.id] = list.count; list.append(rec); changed = true }
            }
            if !removed.isEmpty { list = list.enumerated().filter { !removed.contains($0.offset) }.map(\.element) }
        }

        switch col {
        case .exercises: apply(&d.exercises, id: \.id)
        case .workouts: apply(&d.workouts, id: \.id)
        case .sets: apply(&d.sets, id: \.id)
        case .plans: apply(&d.plans, id: \.id)
        case .days:
            for doc in docs {
                state.since = max(state.since, (doc.data["u"] as? NSNumber)?.doubleValue ?? 0)
                if (doc.data["deleted"] as? Bool) == true {
                    if d.days[doc.id] != nil { d.days[doc.id] = nil; changed = true }
                    map[doc.id] = nil
                    continue
                }
                guard let raw = stripped(doc.data), let rec = try? dec.decode(Day.self, from: raw), let (_, h) = json(rec, enc) else { continue }
                if !firstSync, map[doc.id] == h, d.days[doc.id] != nil { continue }
                map[doc.id] = h
                if d.days[doc.id] != rec { d.days[doc.id] = rec; changed = true }
            }
        case .meta:
            for doc in docs {
                state.since = max(state.since, (doc.data["u"] as? NSNumber)?.doubleValue ?? 0)
                if (doc.data["deleted"] as? Bool) == true { map[doc.id] = nil; continue }
                guard let raw = stripped(doc.data) else { continue }
                if doc.id == "settings" {
                    guard let s = try? dec.decode(Settings.self, from: raw), let (_, h) = json(s, enc) else { continue }
                    if !firstSync, map[doc.id] == h { continue }
                    map[doc.id] = h
                    if d.settings != s { d.settings = s; changed = true }
                } else if doc.id == "active" {
                    // `{planId: null}` means no plan is active
                    let a = (object(raw)?["planId"] as? String) != nil ? try? dec.decode(ActivePlan.self, from: raw) : nil
                    let h: String
                    if let a { guard let j = json(a, enc) else { continue }; h = j.h } else { h = hash(String(decoding: noPlan, as: UTF8.self)) }
                    if !firstSync, map[doc.id] == h { continue }
                    map[doc.id] = h
                    if d.activePlan != a { d.activePlan = a; changed = true }
                }
            }
        }
        state.maps[col.rawValue] = map
        return changed
    }

    private static func withId<T>(_ rec: T, _ id: String) -> T? {
        switch rec {
        case var r as Exercise: r.id = id; return r as? T
        case var r as Workout: r.id = id; return r as? T
        case var r as LoggedSet: r.id = id; return r as? T
        case var r as Plan: r.id = id; return r as? T
        default: return nil
        }
    }

    /// Moves the listener's start on only when it's a month behind (a stable query makes launches cheap).
    static func listenFrom(_ state: inout SyncState) -> Double {
        if state.from == nil || state.since - (state.from ?? 0) > 30 * 864e5 {
            state.from = max(0, state.since - 5 * 60 * 1000)   // small margin for clock differences
        }
        return state.from!
    }
}

/// Remembers each record's hash until the record changes, so a push doesn't re-encode thousands of sets.
nonisolated final class HashCache {
    private var m: [SyncCol: [String: (rec: Any, h: String)]] = [:]
    func get<T: Equatable>(_ col: SyncCol, _ id: String, _ rec: T) -> String? {
        guard let c = m[col]?[id], let r = c.rec as? T, r == rec else { return nil }
        return c.h
    }
    func put<T>(_ col: SyncCol, _ id: String, _ rec: T, _ h: String) { m[col, default: [:]][id] = (rec, h) }
    func clear() { m = [:] }
}

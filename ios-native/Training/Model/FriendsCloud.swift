import Foundation
import Observation
import FirebaseFirestore

/// The Firebase side of Friends (port of app.js startFriends / ensureCode / links / loadFriend / gifts).
/// Owned and started by `Cloud` when someone signs in; uses Cloud's Firestore.
@Observable
final class Friends {
    private(set) var links: [FriendLink] = []
    private(set) var giftsIn: [Gift] = []
    private(set) var giftsOut: [Gift] = []
    /// "rules" when Firebase refuses (rules not published), or an error code; "" when fine
    var error = ""
    var giftError = ""
    private(set) var running = false

    @ObservationIgnored weak var cloud: Cloud?
    @ObservationIgnored weak var store: Store?
    @ObservationIgnored private var uid = ""
    @ObservationIgnored private var regs: [ListenerRegistration] = []
    @ObservationIgnored private var seen: Set<String>?
    @ObservationIgnored private var cache: [String: ProfileSource] = [:]
    @ObservationIgnored private var exCache: [String: (ix: SetIndex, at: Double)] = [:]
    @ObservationIgnored private var lastName = ""
    @ObservationIgnored private var nameTask: Task<Void, Never>?
    @ObservationIgnored private var gen = 0

    var me: String { uid }
    var incoming: [FriendLink] { links.filter { $0.incoming(uid) } }
    var outgoing: [FriendLink] { links.filter { $0.outgoing(uid) } }
    var accepted: [FriendLink] { links.filter(\.accepted).sorted { $0.name(uid).localizedCompare($1.name(uid)) == .orderedAscending } }
    var pendingGifts: [Gift] { giftsIn.filter(\.pending).sorted { $0.u > $1.u } }
    /// The red number on the Friends tab: requests to answer + things sent to you
    var badge: Int { running ? incoming.count + pendingGifts.count : 0 }
    func link(_ id: String) -> FriendLink? { links.first { $0.id == id } }

    /// Your name as friends see it (settings, else the account's name, else the start of the email)
    var myName: String {
        let n = (store?.data.settings.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        if let u = cloud?.user {
            if let d = u.name, !d.isEmpty { return d }
            let e = u.email.split(separator: "@").first.map(String.init) ?? ""
            if !e.isEmpty { return e }
        }
        return "Someone"
    }

    private var db: Firestore? { cloud?.db }
    private static func isPerm(_ e: Error) -> Bool {
        let ns = e as NSError
        return ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }
    static func message(_ e: Error) -> String {
        if isPerm(e) { return "Firebase refused this. Check that the Firestore rules are published." }
        let ns = e as NSError
        if ns.domain == FirestoreErrorDomain && ns.code == FirestoreErrorCode.unavailable.rawValue { return "Couldn't reach the server. Check your connection." }
        return ns.localizedDescription
    }
    private static var u: Int64 { Int64(nowMs()) }

    // MARK: Starting and stopping

    func start(uid: String) {
        stop()
        guard let db else { return }
        self.uid = uid
        gen += 1
        let g = gen
        running = true
        error = ""; giftError = ""
        lastName = myName
        Task { await ensureCode(g) }
        regs.append(db.collection("links").whereField("members", arrayContains: uid).addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated { self?.linksChanged(snap, err, g) }
        })
        let gifts = db.collection("gifts")
        regs.append(gifts.whereField("to", isEqualTo: uid).addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated { self?.giftsInChanged(snap, err, g) }
        })
        regs.append(gifts.whereField("from", isEqualTo: uid).addSnapshotListener { [weak self] snap, err in
            MainActor.assumeIsolated {
                guard let self, g == self.gen else { return }
                if let err { self.giftError = Friends.isPerm(err) ? "rules" : Friends.message(err); return }
                self.giftsOut = (snap?.documents ?? []).map { Gift(id: $0.documentID, data: $0.data()) }
            }
        })
    }

    func stop() {
        gen += 1
        regs.forEach { $0.remove() }; regs = []
        nameTask?.cancel(); nameTask = nil
        links = []; giftsIn = []; giftsOut = []; seen = nil
        cache = [:]; exCache = [:]
        error = ""; giftError = ""
        running = false
        uid = ""
    }

    private func linksChanged(_ snap: QuerySnapshot?, _ err: Error?, _ g: Int) {
        guard g == gen else { return }
        if let err { error = Friends.isPerm(err) ? "rules" : Friends.message(err); return }
        guard let snap else { return }
        let list = snap.documents.compactMap { FriendLink(id: $0.documentID, data: $0.data()) }
        if list != links { links = list }
        if error != "rules" { error = "" }
        // Keep your name up to date on every link
        let n = myName
        for l in list where l.names[uid] != n {
            db?.collection("links").document(l.id).updateData(["names.\(uid)": n, "u": Friends.u]) { _ in }
        }
    }

    private func giftsInChanged(_ snap: QuerySnapshot?, _ err: Error?, _ g: Int) {
        guard g == gen else { return }
        if let err { giftError = Friends.isPerm(err) ? "rules" : Friends.message(err); return }
        guard let snap else { return }
        let list = snap.documents.map { Gift(id: $0.documentID, data: $0.data()) }
        // Something new arrived while the app is open: say so
        if let seen {
            for x in list where x.pending && !seen.contains(x.id) {
                store?.showToast(ToastMsg(kind: .gift, title: "\(x.fromName.isEmpty ? "A friend" : x.fromName) sent you \(x.name)", sub: "Open Friends to add it"))
                Haptics.success()
            }
        }
        seen = Set(list.map(\.id))
        giftsIn = list
        giftError = ""
    }

    // MARK: Your friend code (worked out from your account id, reserved in codes/{CODE})

    private func ensureCode(_ g: Int, wait: Double = 0) async {
        guard let db, let store else { return }
        let uid = self.uid
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)); guard g == gen else { return } }
        do {
            for v in 0..<6 {
                let code = FriendCode.code(for: uid, variant: v)
                let ref = db.collection("codes").document(code)
                let ex = try await ref.getDocument()
                guard g == gen else { return }
                if ex.exists, (ex.data()?["uid"] as? String) != uid { continue }       // taken by someone else
                try await ref.setData(["uid": uid, "name": myName])
                guard g == gen else { return }
                let old = store.data.settings.code
                if old != code {
                    // Release an older code if it's ours
                    if let old, !old.isEmpty {
                        let oref = db.collection("codes").document(old)
                        if let d = try? await oref.getDocument(), (d.data()?["uid"] as? String) == uid { try? await oref.delete() }
                    }
                    store.data.settings.code = code
                }
                return
            }
        } catch {
            guard g == gen else { return }
            if Friends.isPerm(error) { self.error = "rules"; return }
            // Offline or not connected yet: try again in a moment (5 s, doubling up to a minute)
            Task { await ensureCode(g, wait: min(60, max(5, wait * 2))) }
        }
    }

    /// Called after every data change: a new name goes to your code and to every link (1.5 s after typing stops)
    func nameMaybeChanged() {
        guard running else { return }
        let n = myName
        guard n != lastName else { return }
        lastName = n
        nameTask?.cancel()
        nameTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.running, let db = self.db else { return }
            let uid = self.uid, name = self.myName
            if let code = self.store?.data.settings.code, !code.isEmpty {
                try? await db.collection("codes").document(code).setData(["uid": uid, "name": name])
            }
            for l in self.links { try? await db.collection("links").document(l.id).updateData(["names.\(uid)": name, "u": Friends.u]) }
        }
    }

    // MARK: Requests and links

    func lookupCode(_ code: String) async throws -> (uid: String, name: String)? {
        guard let db else { return nil }
        let snap = try await db.collection("codes").document(code).getDocument(source: .server)
        guard snap.exists, let d = snap.data(), let id = d["uid"] as? String else { return nil }
        let n = FriendsCore.str(d["name"], 60)
        return (id, n.isEmpty ? "Friend" : n)
    }

    struct FriendError: LocalizedError { var errorDescription: String? }

    /// Sends a request (or accepts theirs, if they already asked you)
    func sendRequest(to other: String, name otherName: String, share: Bool) async throws {
        guard let db else { return }
        let id = FriendsCore.pairId(uid, other), ref = db.collection("links").document(id)
        let ex = try await ref.getDocument(source: .server)
        if ex.exists, let d = ex.data(), let l = FriendLink(id: id, data: d) {
            if !l.accepted && l.from == other { try await accept(l, share: share); return }
            throw FriendError(errorDescription: l.accepted ? "You're already friends." : "Request already sent.")
        }
        try await ref.setData(["members": [uid, other].sorted(), "from": uid, "status": "pending", "share": [uid: share],
                               "names": [uid: myName, other: otherName], "u": Friends.u])
    }
    func accept(_ l: FriendLink, share: Bool) async throws {
        try await db?.collection("links").document(l.id).updateData(["status": "accepted", "share.\(uid)": share, "names.\(uid)": myName, "u": Friends.u])
    }
    func setShare(_ l: FriendLink, _ on: Bool) async throws {
        try await db?.collection("links").document(l.id).updateData(["share.\(uid)": on, "u": Friends.u])
    }
    /// Decline, cancel a request, or remove a friend
    func remove(_ l: FriendLink) async throws {
        links.removeAll { $0.id == l.id }               // (the listener confirms)
        try await db?.collection("links").document(l.id).delete()
    }

    // MARK: A friend's training (read-only; readable only while they share it with you)

    func cached(_ friend: String) -> ProfileSource? {
        guard let c = cache[friend], nowMs() - c.at < 60_000 else { return nil }
        return c
    }
    /// Their exercises + the last 120 days of sets and days, cleaned. Cached for a minute.
    func loadFriend(_ friend: String, force: Bool = false) async throws -> ProfileSource {
        if !force, let c = cached(friend) { return c }
        guard let db, let store else { throw FriendError(errorDescription: "Not signed in.") }
        let col = { (n: String) in db.collection("users").document(friend).collection(n) }
        let cutoff = Day0.add(store.today, -120)
        async let ex = col("exercises").getDocuments()
        async let ss = col("sets").whereField("date", isGreaterThanOrEqualTo: cutoff).getDocuments()
        async let dd = col("days").whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: cutoff).getDocuments()
        let (e, s, d) = try await (ex, ss, dd)
        let withId = { (q: QuerySnapshot) in q.documents.map { doc -> [String: Any] in var x = doc.data(); x["id"] = doc.documentID; return x } }
        let src = FriendLoad.source(exercises: withId(e), sets: withId(s), days: d.documents.map { ($0.documentID, $0.data()) }, at: nowMs())
        cache[friend] = src
        return src
    }
    /// One exercise's whole history (for its graph)
    func loadFriendExercise(_ friend: String, _ exId: String) async throws -> SetIndex {
        let key = friend + "|" + exId
        if let c = exCache[key], nowMs() - c.at < 60_000 { return c.ix }
        guard let db else { throw FriendError(errorDescription: "Not signed in.") }
        let q = try await db.collection("users").document(friend).collection("sets").whereField("exId", isEqualTo: exId).getDocuments()
        let sets = q.documents.compactMap { doc -> LoggedSet? in
            var x = doc.data(); x["id"] = doc.documentID
            return (x["deleted"] as? Bool) == true ? nil : Clean.set(x)
        }
        let ix = SetIndex(sets)
        exCache[key] = (ix, nowMs())
        return ix
    }

    // MARK: Sending workouts and plans

    enum Item { case workout(Workout), plan(Plan) }

    func send(_ item: Item, to targets: [FriendLink]) async throws {
        guard let db, let store else { return }
        let kind: String, payload: [String: Any], name: String
        switch item {
        case .workout(let w): kind = "workout"; payload = store.data.workoutPayload(w); name = w.name
        case .plan(let p): kind = "plan"; payload = store.data.planPayload(p); name = p.name
        }
        let nm = FriendsCore.str(name, GiftMax.name)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for l in targets {
                let doc: [String: Any] = ["from": uid, "to": l.other(uid), "fromName": FriendsCore.str(myName, 60), "toName": FriendsCore.str(l.name(uid), 60),
                                          "kind": kind, "name": nm.isEmpty ? (kind == "plan" ? "Plan" : "Workout") : nm,
                                          "payload": payload, "status": "pending", "u": Friends.u]
                group.addTask { try await db.collection("gifts").document(newId()).setData(doc) }
            }
            try await group.waitForAll()
        }
    }

    /// Copies it into your workouts (or plans) and marks it added. Returns what was added.
    func add(_ g: Gift) -> Store.OpenRequest? {
        guard let store else { return nil }
        let from = FriendsCore.str(g.fromName, 40).isEmpty ? "friend" : FriendsCore.str(g.fromName, 40)
        var d = store.data
        let out: Store.OpenRequest
        if let p = g.plan { out = .plan(d.importPlan(p, from: from)) }
        else { out = .workout(d.importWorkout(g.workout ?? GiftWorkout(nil), from: from)) }
        store.data = d
        mark(g, "added")
        return out
    }
    func decline(_ g: Gift) { mark(g, "declined") }
    private func mark(_ g: Gift, _ status: String) {
        if let i = giftsIn.firstIndex(where: { $0.id == g.id }) { giftsIn[i].status = status }
        db?.collection("gifts").document(g.id).updateData(["status": status, "u": Friends.u]) { _ in }
    }
    func unsend(_ g: Gift) {
        giftsOut.removeAll { $0.id == g.id }
        db?.collection("gifts").document(g.id).delete { _ in }
    }
}

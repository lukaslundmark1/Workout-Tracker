import Foundation
import Network
import Observation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Accounts and sync with the same Firebase project as the web app (port of app.js "Cloud: accounts + sync").
/// Local-first: the app always reads and writes the phone's copy; when signed in, changes are sent to the account
/// and changes from other devices (the web app included) are merged in.
@Observable
final class Cloud {
    enum Status: Equatable { case off, connecting, syncing, synced, offline, error(String) }
    struct Account: Equatable { var uid: String; var email: String; var name: String? }

    /// False when Firebase isn't set up in this build (no GoogleService-Info.plist)
    let available: Bool
    private(set) var user: Account?
    private(set) var status: Status = .off
    private(set) var online = true
    /// Friends, requests and sent workouts/plans (started at sign-in)
    let friends = Friends()

    var statusText: String {
        switch status {
        case .off: "Not signed in"
        case .connecting: "Connecting…"
        case .syncing: "Syncing…"
        case .synced: "Backed up"
        case .offline: "Offline — will sync later"
        case .error(let e): "Sync problem: " + e
        }
    }

    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private(set) var sync: SyncState?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryWait: Double = 0
    @ObservationIgnored private var saveSyncTask: Task<Void, Never>?
    @ObservationIgnored private let cache = HashCache()
    @ObservationIgnored private var deleting = false
    @ObservationIgnored private var gen = 0            // moves on at every sign-in/out, so late answers are ignored
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var dbConfigured: ObjectIdentifier?
    @ObservationIgnored private static var emulatorHost: String?

    // MARK: Setup

    /// Configures Firebase from GoogleService-Info.plist. In debug builds, `-emulator <host>` (a launch argument)
    /// uses Firebase's local emulators instead (for testing with throwaway accounts).
    static func configure() -> Bool {
        #if DEBUG
        if let host = UserDefaults.standard.string(forKey: "emulator"), !host.isEmpty {
            emulatorHost = host
            let o = FirebaseOptions(googleAppID: "1:366945347041:ios:0000000000000000000000", gcmSenderID: "366945347041")
            o.apiKey = "emulator-key"; o.projectID = "workout-tracker-705ae"
            FirebaseApp.configure(options: o)
            Auth.auth().useEmulator(withHost: host, port: 9099)
            return true
        }
        #endif
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        FirebaseApp.configure()
        return true
    }

    init(store: Store, enabled: Bool = true) {
        self.store = store
        available = enabled && Cloud.configure()
        guard available else { return }
        friends.cloud = self; friends.store = store
        store.onChange = { [weak self] in self?.scheduleSync(); self?.friends.nameMaybeChanged() }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            MainActor.assumeIsolated { self?.authChanged(u) }
        }
        monitor.pathUpdateHandler = { [weak self] path in
            let on = path.status == .satisfied
            Task { @MainActor in self?.setOnline(on) }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    var db: Firestore {
        let f = Firestore.firestore()
        if dbConfigured != ObjectIdentifier(f) {
            dbConfigured = ObjectIdentifier(f)
            if let host = Cloud.emulatorHost {
                let s = f.settings
                s.host = host + ":8080"; s.isSSLEnabled = false; s.cacheSettings = MemoryCacheSettings()
                f.settings = s
            }
        }
        return f
    }
    private func col(_ uid: String, _ c: SyncCol) -> CollectionReference { db.collection("users").document(uid).collection(c.rawValue) }

    private func setOnline(_ on: Bool) {
        guard on != online else { return }
        online = on
        guard user != nil else { return }
        if on { if sync == nil { startSync() } else { push() } }
        else if status == .synced || status == .syncing { status = .offline }
    }

    /// Coming back to the app: send anything that's waiting
    func foreground() { if user != nil { if sync == nil { startSync() } else { push() } } }
    func background() { saveSyncNow() }

    // MARK: Signing in

    private func authChanged(_ u: User?) {
        stopListening()
        friends.stop()
        gen += 1
        guard let u else {
            if user != nil { saveSyncNow() }
            user = nil; sync = nil; status = .off
            return
        }
        user = Account(uid: u.uid, email: u.email ?? "", name: u.displayName)
        startSync()
        friends.start(uid: u.uid)
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
    }
    func createAccount(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
    }
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespaces))
    }

    /// The web app's `friendlyAuthError`
    static func friendly(_ e: Error) -> String {
        let ns = e as NSError
        guard ns.domain == AuthErrorDomain, let c = AuthErrorCode(rawValue: ns.code) else {
            return "Sign-in failed (\(ns.localizedDescription))."
        }
        switch c {
        case .invalidCredential, .wrongPassword, .userNotFound: return "Wrong email or password."
        case .emailAlreadyInUse: return "There is already an account with that email. Sign in instead."
        case .weakPassword: return "Use at least 6 characters for the password."
        case .invalidEmail, .missingEmail: return "That email address doesn't look right."
        case .networkError: return "Couldn't reach the server. Check your connection."
        case .operationNotAllowed: return "This sign-in method is turned off in Firebase."
        case .tooManyRequests: return "Too many attempts. Wait a moment and try again."
        default: return "Sign-in failed (\(ns.code))."
        }
    }

    // MARK: Sync

    private func startSync() {
        guard let user, let store else { return }
        let g = gen, uid = user.uid
        let same = store.claimLocalData(uid)
        if store.data.settings.name.isEmpty, let n = user.name, !n.isEmpty { store.data.settings.name = n }
        // What was last synced only describes the phone's data if it already belonged to this account. Otherwise
        // (another account was here in between) start over with a full merge: using the old record would make
        // everything missing on the phone look deleted and wipe it from the account.
        sync = same ? Cloud.loadSync(uid) : nil
        cache.clear()
        status = .connecting
        Task {
            do {
                if sync == nil {
                    // First time this phone signs in to this account: download everything once and merge it in.
                    // (From the server only: an empty answer from an empty offline cache would look like an empty account.)
                    var st = SyncState()
                    for c in SyncCol.allCases {
                        let snap = try await col(uid, c).getDocuments(source: .server)
                        guard g == gen else { return }
                        var d = store.data
                        let docs = snap.documents.map { IncomingDoc(id: $0.documentID, data: $0.data()) }
                        if SyncCore.merge(docs, into: &d, col: c, state: &st, firstSync: true) { store.applyRemote(d) }
                    }
                    sync = st
                    saveSyncSoon()
                    store.saveNow()
                }
                guard g == gen else { return }
                listen(uid, g)
                await push()
            } catch {
                guard g == gen else { return }
                status = online ? .error(Cloud.code(error)) : .offline
            }
        }
    }

    /// Live updates from your other devices
    private func listen(_ uid: String, _ g: Int) {
        guard var st = sync else { return }
        let from = SyncCore.listenFrom(&st)
        sync = st; saveSyncSoon()
        for c in SyncCol.allCases {
            let reg = col(uid, c).whereField("u", isGreaterThan: from).addSnapshotListener { [weak self] snap, err in
                MainActor.assumeIsolated { self?.received(c, snap, err, g) }
            }
            listeners.append(reg)
        }
    }

    private func received(_ c: SyncCol, _ snap: QuerySnapshot?, _ err: Error?, _ g: Int) {
        guard g == gen, let store else { return }
        if let err { status = .error(Cloud.code(err)); return }
        guard let snap, var st = sync else { return }
        let docs = snap.documentChanges
            .filter { !$0.document.metadata.hasPendingWrites && $0.type != .removed }   // our own writes echoing back
            .map { IncomingDoc(id: $0.document.documentID, data: $0.document.data()) }
        var d = store.data
        let changed = SyncCore.merge(docs, into: &d, col: c, state: &st)
        sync = st
        saveSyncSoon()
        if changed { store.applyRemote(d) }
        if !snap.metadata.isFromCache && status != .syncing { status = .synced }
    }

    private func stopListening() { listeners.forEach { $0.remove() }; listeners = [] }

    /// Send local changes a moment after they happen (600 ms, like the web app)
    func scheduleSync() {
        guard user != nil, sync != nil else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { await push() }
        }
    }
    func push() { Task { await push() } }

    /// Sends records that differ from what was last synced (the web app's `pushChanges`)
    private func push() async {
        pushTask?.cancel(); pushTask = nil
        retryTask?.cancel(); retryTask = nil
        guard let user, var st = sync, let store, !deleting else { return }
        let g = gen, uid = user.uid
        let ops = SyncCore.ops(store.data, &st, now: nowMs(), cache: cache)
        sync = st
        if ops.isEmpty {
            if case .error = status {} else { status = online ? .synced : .offline }
            return
        }
        status = .syncing
        for i in stride(from: 0, to: ops.count, by: 400) {
            let part = Array(ops[i..<min(i + 400, ops.count)])
            let batch = db.batch()
            for o in part {
                var body = o.body
                if let u = body["u"] as? Double { body["u"] = Int64(u) }
                batch.setData(body, forDocument: col(uid, o.col).document(o.id))
            }
            // Marked as synced right away (Firestore keeps queued writes and sends them when back online). If the cloud
            // turns the save down, the marks are taken back so the records are sent again later.
            let before = part.map { sync?.maps[$0.col.rawValue]?[$0.id] }
            for o in part { sync?.maps[o.col.rawValue, default: [:]][o.id] = o.h }
            saveSyncSoon()
            let undo = { [weak self] in
                guard let self, g == self.gen else { return }
                for (j, o) in part.enumerated() {
                    let now = self.sync?.maps[o.col.rawValue]?[o.id]
                    if now != o.h { continue }                         // sent again since: that send counts
                    self.sync?.maps[o.col.rawValue]?[o.id] = before[j]
                }
                self.saveSyncSoon()
                self.retryPush()
            }
            if online {
                do { try await batch.commit() } catch {
                    undo()
                    if g == gen { status = online ? .error(Cloud.code(error)) : .offline }
                    return
                }
            } else {
                batch.commit { [weak self] err in
                    guard let err else { return }
                    MainActor.assumeIsolated { undo(); if g == self?.gen { self?.status = .error(Cloud.code(err)) } }
                }
            }
        }
        guard g == gen else { return }
        retryWait = 0
        status = online ? .synced : .offline
    }

    /// A save the cloud turned down is tried again later: sooner at first, then every few minutes
    private func retryPush() {
        retryTask?.cancel()
        retryWait = min(300, (retryWait == 0 ? 7.5 : retryWait) * 2)
        let wait = retryWait
        retryTask = Task {
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { retryTask = nil; await push() }
        }
    }

    private static func code(_ e: Error) -> String {
        let ns = e as NSError
        if ns.domain == FirestoreErrorDomain, let c = FirestoreErrorCode.Code(rawValue: ns.code) {
            switch c {
            case .permissionDenied: return "permission-denied"
            case .unavailable: return "unavailable"
            case .unauthenticated: return "unauthenticated"
            default: return "error \(ns.code)"
            }
        }
        return ns.localizedDescription
    }

    // MARK: What was last synced (a file per account, written a moment after changes and when the app is put away)

    private static func syncURL(_ uid: String) -> URL {
        Store.fileURL.deletingLastPathComponent().appendingPathComponent("sync.\(uid.filter { $0.isLetter || $0.isNumber }).json")
    }
    private static func loadSync(_ uid: String) -> SyncState? {
        guard let d = try? Data(contentsOf: syncURL(uid)) else { return nil }
        return try? JSONDecoder().decode(SyncState.self, from: d)
    }
    private func saveSyncSoon() {
        guard saveSyncTask == nil else { return }
        saveSyncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            saveSyncNow()
        }
    }
    func saveSyncNow() {
        saveSyncTask?.cancel(); saveSyncTask = nil
        guard let user, let sync, let d = try? JSONEncoder().encode(sync) else { return }
        try? d.write(to: Cloud.syncURL(user.uid), options: .atomic)
    }

    // MARK: Leaving: sign out, delete account

    func signOut(removeHere: Bool) async {
        guard let u = user else { return }
        await push()
        stopListening()
        saveSyncNow()
        try? Auth.auth().signOut()
        if removeHere { await wipeDevice(u.uid) }
    }

    /// Removes your training from this phone (your account's copy is untouched unless you deleted the account)
    private func wipeDevice(_ uid: String) async {
        saveSyncTask?.cancel(); saveSyncTask = nil
        sync = nil; cache.clear()
        try? FileManager.default.removeItem(at: Cloud.syncURL(uid))
        store?.wipeDevice(uid)
        // Firestore keeps its own offline copy on the phone too
        let f = db
        try? await f.terminate()
        try? await f.clearPersistence()
        dbConfigured = nil                                 // the next one is a new instance
    }

    var usesPassword: Bool { Auth.auth().currentUser?.providerData.contains { $0.providerID == "password" } ?? false }

    /// Deletes everything about you in the cloud, then the account itself, then this phone's copy (the web app's `deleteAccount`)
    func deleteAccount(password: String, progress: @escaping (String) -> Void) async throws {
        guard let u = Auth.auth().currentUser, let email = u.email else { return }
        let uid = u.uid, db = db
        progress("Confirming it's you…")
        try await u.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
        deleting = true
        defer { deleting = false }
        stopListening()
        friends.stop()
        do { try await deleteEverything(uid, u, db, progress) } catch {
            // Carry on syncing what's left (trying again finishes the job)
            deleting = false; gen += 1; startSync(); friends.start(uid: uid)
            throw error
        }
        await wipeDevice(uid)
    }

    private func deleteEverything(_ uid: String, _ u: User, _ db: Firestore, _ progress: (String) -> Void) async throws {
        func delDocs(_ snap: QuerySnapshot) async throws {
            let refs = snap.documents.map(\.reference)
            for i in stride(from: 0, to: refs.count, by: 50) {
                try await withThrowingTaskGroup(of: Void.self) { g in
                    for r in refs[i..<min(i + 50, refs.count)] { g.addTask { try await r.delete() } }
                    try await g.waitForAll()
                }
            }
        }
        progress("Deleting your training…")
        for c in SyncCol.allCases { try await delDocs(try await col(uid, c).getDocuments(source: .server)) }
        progress("Deleting friends and shared items…")
        try await delDocs(try await db.collection("links").whereField("members", arrayContains: uid).getDocuments(source: .server))
        try await delDocs(try await db.collection("gifts").whereField("to", isEqualTo: uid).getDocuments(source: .server))
        try await delDocs(try await db.collection("gifts").whereField("from", isEqualTo: uid).getDocuments(source: .server))
        try await delDocs(try await db.collection("library").whereField("by", isEqualTo: uid).getDocuments(source: .server))
        for v in 0..<6 { try? await db.collection("codes").document(FriendCode.code(for: uid, variant: v)).delete() }   // only yours can be deleted
        progress("Deleting your account…")
        try await u.delete()
    }
}

/// Friend codes, computed exactly like the web app's `codeFor` (same account → same code on every device).
nonisolated enum FriendCode {
    static let abc = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static func code(for uid: String, variant: Int) -> String {
        func h(_ s: String, _ seed: UInt32) -> UInt32 {
            var x = seed
            for c in s.utf16 { x ^= UInt32(c); x = x &* 16777619 }
            return x
        }
        let a = h(uid + ":" + String(variant), 2166136261), b = h(String(variant) + ":" + uid, 374761393)
        var out = ""
        for i in 0..<6 { out.append(abc[Int((i < 3 ? a >> UInt32(i * 5) : b >> UInt32((i - 3) * 5)) & 31)]) }
        return out
    }
}

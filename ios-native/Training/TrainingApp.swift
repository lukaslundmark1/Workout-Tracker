import SwiftUI

@main
struct TrainingApp: App {
    @State private var store: Store
    @State private var cloud: Cloud
    @Environment(\.scenePhase) private var phase

    init() {
        let s = Store()
        _store = State(initialValue: s)
        _cloud = State(initialValue: Cloud(store: s, enabled: !Perf.fixture))   // made-up test data never syncs
        HitchMonitor.shared.start()   // only with the -perfLog launch argument
        if Perf.fixture && Perf.logging {   // what a sync push costs with this much data (sync itself is off with -perfData)
            var st = SyncState(); let c = HashCache()
            let first = Perf.measure("sync ops, first", over: 0) { SyncCore.ops(s.data, &st, now: 1, cache: c) }
            for o in first { st.maps[o.col.rawValue, default: [:]][o.id] = o.h }
            var st2 = st
            _ = Perf.measure("sync ops, steady", over: 0) { SyncCore.ops(s.data, &st2, now: 2, cache: c) }
            _ = Perf.measure("sync state encode", over: 0) { try? JSONEncoder().encode(st2) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(cloud)
                .onChange(of: phase) { _, p in
                    if p == .active { store.checkNewDay(); cloud.foreground() }
                    if p == .background { store.saveNow(); cloud.background() }
                }
                .task {
                    // A new day can start while the app is open
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        store.checkNewDay()
                    }
                }
        }
    }
}

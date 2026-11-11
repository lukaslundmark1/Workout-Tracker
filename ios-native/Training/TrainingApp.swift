import SwiftUI

@main
struct TrainingApp: App {
    @State private var store: Store
    @State private var cloud: Cloud
    @Environment(\.scenePhase) private var phase

    init() {
        let s = Store()
        _store = State(initialValue: s)
        _cloud = State(initialValue: Cloud(store: s))
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

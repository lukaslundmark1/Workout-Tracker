import SwiftUI

@main
struct TrainingApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onChange(of: phase) { _, p in
                    if p == .active { store.checkNewDay() }
                    if p == .background { store.saveNow() }
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

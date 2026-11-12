import SwiftUI

enum AppTab: Hashable { case friends, workouts, today, exercises, settings }

/// Tab bar: Friends | Workouts | Today (centre) | Exercises | Settings.
/// The rest stopwatch, toasts and the number pad float above everything.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud

    var body: some View {
        let _ = Perf.body("RootView")
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Friends", systemImage: "person.2.fill", value: AppTab.friends) {
                FriendsView()
            }
            .badge(cloud.friends.badge)
            Tab("Workouts", systemImage: "dumbbell.fill", value: AppTab.workouts) {
                WorkoutsView()
            }
            Tab(value: AppTab.today) {
                TodayView().modifier(RestRoom())
            } label: {
                Label { Text("Today") } icon: { Image(uiImage: TodayIcon.image(day: Day0.dayOfMonth(store.today))) }
            }
            Tab("Exercises", systemImage: "list.bullet", value: AppTab.exercises) {
                ExercisesView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .onChange(of: store.tab) { _, _ in Haptics.select(); store.padClose() }
        .overlay(alignment: .bottom) { BottomLayer() }
        .overlay(alignment: .top) { if !store.logOpen { ToastView() } }
        .background {
            GeometryReader { g in
                Color.clear.onAppear { measure(g) }.onChange(of: g.size) { measure(g) }
            }
        }
        .preferredColorScheme(store.data.settings.theme == "light" ? .light : store.data.settings.theme == "dark" ? .dark : nil)
    }

    private func measure(_ g: GeometryProxy) {
        let m = ScreenMetrics(height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom, safeBottom: g.safeAreaInsets.bottom)
        if store.screen != m { store.screen = m }
    }
}

/// Rest stopwatch above the tab bar.
private struct BottomLayer: View {
    @Environment(Store.self) private var store
    var body: some View {
        let _ = Perf.body("BottomLayer")
        ZStack(alignment: .bottom) {
            // (the exercise screen shows its own, over the tab bar's spot)
            if let r = store.rest, r.date == store.today, !store.logOpen {
                RestPill(rest: r)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.reduced ? .easeInOut(duration: 0.2) : Motion.sheet, value: store.rest)
    }
}

/// The Today tab's icon: a page showing today's date, like the Calendar app icon.
enum TodayIcon {
    private static var cache: [Int: UIImage] = [:]
    static func image(day: Int) -> UIImage {
        if let i = cache[day] { return i }
        let r = ImageRenderer(content: Glyph(day: day))
        r.scale = 3
        let img = (r.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
        cache[day] = img
        return img
    }
    private struct Glyph: View {
        let day: Int
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(lineWidth: 1.8)
                VStack(spacing: 0) {
                    Rectangle().frame(height: 1.8).padding(.top, 5.5)
                    Spacer(minLength: 0)
                }
                Text("\(day)").font(.system(size: 11.5, weight: .bold, design: .rounded)).offset(y: 3)
            }
            .frame(width: 23, height: 23)
            .padding(1.5)
            .foregroundStyle(.black)
        }
    }
}

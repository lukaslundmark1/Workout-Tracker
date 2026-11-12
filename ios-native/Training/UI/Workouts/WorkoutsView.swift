import SwiftUI

/// Workouts tab: a Plans | Workouts switch. The plan screen and both editors slide up from the bottom.
struct WorkoutsView: View {
    @Environment(Store.self) private var store
    @AppStorage("tt.wSeg") private var seg = "plans"
    @State private var openPlan: Ident?
    @State private var editWorkout: WorkoutDraft?
    @State private var editPlan: PlanDraft?

    var body: some View {
        let _ = Perf.body("WorkoutsView")
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: Binding(get: { seg }, set: { v in Haptics.select(); Motion.run { seg = v } })) {
                        Text("Plans").tag("plans"); Text("Workouts").tag("workouts")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                if seg == "plans" { plans } else { workouts }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .modifier(RestRoom())
            .navigationTitle("Workouts")
        }
        .sheet(item: $openPlan) { p in PlanView(planId: p.id).presentationDragIndicator(.visible) }
        .sheet(item: $editWorkout) { d in WorkoutEditor(draft: d) }
        .sheet(item: $editPlan) { d in PlanEditor(draft: d) { id in if let id { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openPlan = Ident(id: id) } } } }
        .onChange(of: store.openRequest, initial: true) { _, r in openRequested(r) }
    }

    /// A workout or plan a friend sent, just added: show it
    private func openRequested(_ r: Store.OpenRequest?) {
        guard let r else { return }
        store.openRequest = nil
        switch r {
        case .plan(let id): Motion.run { seg = "plans" }; openPlan = Ident(id: id)
        case .workout: Motion.run { seg = "workouts" }          // (it's in the list, like the web app)
        }
    }

    @ViewBuilder private var plans: some View {
        let list = store.plansSorted, active = store.activePlan?.planId
        if !list.isEmpty {
            Section {
                ForEach(list) { p in
                    Button { openPlan = Ident(id: p.id) } label: {
                        // "Active" sits by the name, so the line under it gets the full width
                        Row(title: p.name, sub: store.planSummary(p), tag: p.id == active ? "Active" : nil) { EmptyView() }
                    }
                }
            }
            .transition(.opacity)
        }
        Section {
            Button { editPlan = PlanDraft(planId: nil, name: "", weeks: 8, days: []) } label: { Label("Create a new plan", systemImage: "plus") }
                .buttonStyle(TintedButton())
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        } footer: {
            if list.isEmpty {
                Text("A plan is a rotation of your workouts and rest days that fills in your calendar.")
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 6)
            }
        }
    }

    @ViewBuilder private var workouts: some View {
        let list = store.workoutsSorted
        if !list.isEmpty {
            Section {
                ForEach(list) { w in
                    Button { editWorkout = WorkoutDraft(workoutId: w.id, name: w.name, items: w.items) } label: {
                        Row(title: w.name, sub: store.workoutSummary(w)) { EmptyView() }
                    }
                }
            }
            .transition(.opacity)
        }
        Section {
            Button { editWorkout = WorkoutDraft(workoutId: nil, name: "", items: []) } label: { Label("Create a new workout", systemImage: "plus") }
                .buttonStyle(TintedButton())
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
    }
}

struct Ident: Identifiable, Hashable { var id: String }

/// A list row: title, a grey line under it, something on the right, and a chevron.
struct Row<Trailing: View>: View {
    var title: String
    var sub: String? = nil
    var tag: String? = nil
    var chevron = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(Color.primary)
                    if let tag {
                        Text(tag).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.green)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .fixedSize()
                    }
                }
                if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(Color.label2) }
            }
            Spacer(minLength: 6)
            trailing
            if chevron { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.label3) }
        }
        .contentShape(Rectangle())
    }
}

/// A day number in a little rounded square (blue when it's up next).
struct DayNumber: View {
    let n: Int
    var now = false
    var body: some View {
        Text("\(n)").font(.rounded(13, .bold)).monospacedDigit()
            .foregroundStyle(now ? Color.white : Color.label2)
            .frame(width: 26, height: 26)
            .background(now ? Color.tint : Color.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// How many sets, on a wheel (1–10).
struct SetCountPicker: View {
    @Binding var sets: Int
    var body: some View {
        Picker("Number of sets", selection: $sets) {
            ForEach(1...10, id: \.self) { Text(Fmt.plural($0, "set")).tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: 220, maxHeight: 180)
        .frame(maxWidth: .infinity)
        .onChange(of: sets) { Haptics.select() }
    }
}

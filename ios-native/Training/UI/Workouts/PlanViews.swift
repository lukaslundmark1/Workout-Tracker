import SwiftUI

struct PlanDraft: Identifiable {
    let id = UUID()
    var planId: String?
    var name: String
    var weeks: Int
    var days: [PlanDay]
}

/// A plan: its rotation (with Up next), and when it's active, the next 10 days and End plan; otherwise Start plan.
struct PlanView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planId: String
    @State private var editing: PlanDraft?
    @State private var starting = false
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack {
            if let p = store.planById(planId) { content(p) } else { Color.clear.onAppear { dismiss() } }
        }
        .sheet(item: $editing) { d in PlanEditor(draft: d) { id in if id == nil { dismiss() } } }
        .sheet(isPresented: $starting) { PlanStartSheet(planId: planId) }
    }

    private func content(_ p: Plan) -> some View {
        let ap = store.activePlan, isActive = ap?.planId == p.id
        let nx = isActive ? store.upNext() : nil
        let end = isActive ? store.planEnd(ap!, p) : nil
        let tk = store.today
        return List {
            Section {
                ForEach(Array(p.days.enumerated()), id: \.offset) { i, d in
                    let w = d.workoutId.flatMap(store.woById), now = nx?.index == i
                    HStack(spacing: 12) {
                        DayNumber(n: i + 1, now: now)
                        Text(w?.name ?? "Rest").foregroundStyle(w == nil ? Color.label2 : Color.primary)
                        Spacer()
                        Text(now ? "Up next" : w.map { Fmt.plural($0.items.count, "exercise") } ?? "")
                            .foregroundStyle(now ? Color.tint : Color.label2).fontWeight(now ? .semibold : .regular)
                    }
                }
                if p.days.isEmpty { Text("No days yet. Tap Edit to build the rotation.").foregroundStyle(Color.label2) }
            } header: { Text("Rotation") } footer: {
                Text("After the last day it starts again from day 1." + (p.weeks > 0 ? " Runs for \(Fmt.plural(p.weeks, "week"))." : " Runs until you end it."))
            }
            if isActive {
                Section {
                    ForEach(0..<10, id: \.self) { i in
                        let k = Day0.add(tk, i)
                        if end == nil || k < end! { comingRow(k) }
                    }
                } header: { Text("Coming up") } footer: {
                    Text("Missed a workout? It waits for you and the rest moves along. Can't make a day? Open it in Today and tap “Move back a day” to choose how far the change reaches. On a rest day you can do your next workout early.")
                }
                Section {
                    Button("End plan", role: .destructive) { Haptics.warn(); confirmEnd = true }
                }
            } else {
                Section {
                    Button { Haptics.select(); starting = true } label: { Text("Start plan") }
                        .buttonStyle(PrimaryButton())
                        .disabled(p.days.isEmpty)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle(p.name)
        .navigationSubtitle(isActive ? "Active since \(Fmt.tiny(ap!.begin))" + (end.map { " · ends \(Fmt.tiny($0))" } ?? "") : store.planSummary(p))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = PlanDraft(planId: p.id, name: p.name, weeks: p.weeks, days: p.days) }
            }
        }
        .confirmationDialog("End \(p.name)?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End plan", role: .destructive) { Haptics.impact(); Motion.run { store.endPlan() } }
        } message: { Text("Days you've already trained are kept; the planned days ahead disappear.") }
    }

    private func comingRow(_ k: String) -> some View {
        let tk = store.today, d = store.dayOf(k), pd = store.planDayFor(k), done = store.hasSets(k)
        let label = !d.items.isEmpty ? (d.workouts.isEmpty ? "Custom workout" : d.workouts.map(\.name).joined(separator: " + "))
            : pd?.extra == true ? "Rest (moved)" : "Rest"
        return Button {
            // open that day in Today
            Haptics.select()
            store.selected = k
            store.tab = .today
            dismiss()
        } label: {
            Row(title: k == tk ? "Today" : k == Day0.add(tk, 1) ? "Tomorrow" : Fmt.short(k)) {
                Text(label + (done ? " ✓" : "")).foregroundStyle(d.items.isEmpty ? Color.label2 : Color.primary)
            }
        }
    }
}

/// New / Edit Plan: name, the rotation (tap a day to change it, ⊖ to remove, ≡ to reorder), length, Delete.
struct PlanEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: PlanDraft
    var done: (String?) -> Void            // the saved plan's id; nil when it was deleted
    @State private var error = ""
    @State private var dayPick: DayPick?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    struct DayPick: Identifiable { var index: Int; var isNew: Bool; var id: Int { isNew ? -1 : index } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Plan name, e.g. Push pull legs", text: $draft.name)
                        .font(.system(size: 20, weight: .semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onChange(of: draft.name) { error = "" }
                }
                Section {
                    ForEach(Array(draft.days.enumerated()), id: \.offset) { i, d in
                        let w = d.workoutId.flatMap(store.woById)
                        Button { dayPick = DayPick(index: i, isNew: false) } label: {
                            HStack(spacing: 12) {
                                DayNumber(n: i + 1)
                                Text(w?.name ?? "Rest").foregroundStyle(w == nil ? Color.label2 : Color.primary)
                                Spacer()
                                if let w { Text(Fmt.plural(w.items.count, "exercise")).foregroundStyle(Color.label2) }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .onDelete { idx in Haptics.impact(); Motion.run { draft.days.remove(atOffsets: idx) } }
                    .onMove { from, to in Haptics.select(); draft.days.move(fromOffsets: from, toOffset: to) }
                    Button { dayPick = DayPick(index: draft.days.count, isNew: true) } label: { Label("Add workout day", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Color.tint).deleteDisabled(true).moveDisabled(true)
                    Button { Haptics.select(); Motion.run { draft.days.append(PlanDay(workoutId: nil)); error = "" } } label: { Label("Add rest day", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Color.tint).deleteDisabled(true).moveDisabled(true)
                } header: { Text("Rotation") } footer: {
                    Text("The days repeat in this order. Tap a day to change it, drag ≡ to reorder.")
                }
                Section("Length") {
                    Stepper(value: Binding(get: { draft.weeks }, set: { Haptics.select(); draft.weeks = $0 }), in: 0...52) {
                        HStack {
                            Text("Run for")
                            Spacer()
                            Text(draft.weeks > 0 ? Fmt.plural(draft.weeks, "week") : "Ongoing").foregroundStyle(Color.label2)
                                .monospacedDigit().contentTransition(.numericText())
                        }
                    }
                    .deleteDisabled(true)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Color.red) }.listRowBackground(Color.clear)
                }
                if draft.planId != nil {
                    Section { Button("Delete Plan", role: .destructive) { Haptics.warn(); confirmDelete = true } }
                }
            }
            .environment(\.editMode, .constant(.active))
            .animation(Motion.soft, value: draft.weeks)
            .navigationTitle(draft.planId == nil ? "New Plan" : "Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Save")
                }
            }
            .confirmationDialog("Delete this plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive) {
                    if let id = draft.planId { Motion.run { store.deletePlan(id) } }
                    Haptics.impact(); dismiss(); done(nil)
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(item: $dayPick) { pick in
            PlanDayPicker(index: pick.index, current: pick.isNew ? nil : draft.days[pick.index]) { v in
                Motion.run {
                    if pick.isNew { draft.days.append(v) } else { draft.days[pick.index] = v }
                    error = ""
                }
            }
        }
        .onAppear { if draft.planId == nil { nameFocused = true } }
    }

    private func save() {
        let r = store.savePlan(id: draft.planId, name: draft.name, weeks: draft.weeks, days: draft.days)
        if let e = r.error { Haptics.error(); Motion.run { error = e }; if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { nameFocused = true }; return }
        Haptics.success()
        let isNew = draft.planId == nil
        dismiss()
        if isNew { done(r.id) }
    }
}

/// What a rotation day is: Rest, or one of your workouts.
struct PlanDayPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let index: Int
    let current: PlanDay?
    var pick: (PlanDay) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    choice(nil) { Text("Rest").foregroundStyle(Color.label2) }
                }
                Section("Workouts") {
                    let list = store.workoutsSorted
                    if list.isEmpty {
                        Text("No workouts yet. Switch to Workouts at the top of this tab and create some first.").foregroundStyle(Color.label2)
                    }
                    ForEach(list) { w in
                        choice(w.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).foregroundStyle(Color.primary)
                                Text(Fmt.plural(w.items.count, "exercise")).font(.system(size: 15)).foregroundStyle(Color.label2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Day \(index + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choice<L: View>(_ workoutId: String?, @ViewBuilder label: () -> L) -> some View {
        Button { Haptics.select(); pick(PlanDay(workoutId: workoutId)); dismiss() } label: {
            HStack {
                label()
                Spacer()
                if let current, current.workoutId == workoutId { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.tint) }
            }
            .contentShape(Rectangle())
        }
    }
}

/// Start a plan: which date, and which day of the rotation to start with.
struct PlanStartSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planId: String
    @State private var date = Date()
    @State private var startIdx = 0

    var body: some View {
        if let p = store.planById(planId) {
            let replacing = store.activePlan.flatMap { $0.planId != p.id ? store.planById($0.planId) : nil }
            NavigationStack {
                List {
                    Section {
                        DatePicker("First day", selection: $date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                    }
                    Section("Start with") {
                        Picker("Start with", selection: $startIdx) {
                            ForEach(p.days.indices, id: \.self) { i in Text("Day \(i + 1) · \(store.planDayLabel(p, i))").tag(i) }
                        }
                        .pickerStyle(.wheel)
                        .onChange(of: startIdx) { Haptics.select() }
                    }
                    Section {
                        Button(replacing != nil ? "Replace and start" : "Start plan") {
                            store.startPlan(p.id, first: Day0.key(date), startIdx: startIdx)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButton())
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    } footer: {
                        if let r = replacing {
                            Text("This ends \(r.name). Days you've already trained are kept.").foregroundStyle(Color.red)
                        }
                    }
                }
                .navigationTitle("Start \(p.name)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                    }
                }
            }
        }
    }
}

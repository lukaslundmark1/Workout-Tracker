import SwiftUI

struct WorkoutDraft: Identifiable {
    let id = UUID()
    var workoutId: String?
    var name: String
    var items: [WorkoutItem]
}

/// New / Edit Workout: name, exercises with their sets (tap to change, ⊖ to remove, ≡ to reorder), Delete.
struct WorkoutEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: WorkoutDraft
    @State private var error = ""
    @State private var adding = false
    @State private var setsFor: Int?
    @State private var confirmDelete = false
    @State private var sending = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name, e.g. Push day", text: $draft.name)
                        .font(.system(size: 20, weight: .semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onChange(of: draft.name) { error = "" }
                }
                Section("Exercises") {
                    ForEach(Array(draft.items.enumerated()), id: \.element.exId) { i, it in
                        Button { setsFor = i } label: {
                            Row(title: store.exById(it.exId)?.name ?? "Deleted exercise", chevron: false) {
                                Text(Fmt.plural(it.sets ?? 3, "set")).foregroundStyle(Color.label2).monospacedDigit()
                            }
                        }
                    }
                    .onDelete { idx in Haptics.impact(); Motion.run { draft.items.remove(atOffsets: idx) } }
                    .onMove { from, to in Haptics.select(); draft.items.move(fromOffsets: from, toOffset: to) }
                    Button { adding = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Color.tint)
                        .deleteDisabled(true).moveDisabled(true)
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Color.red) }.listRowBackground(Color.clear)
                }
                if !draft.items.isEmpty {
                    Section {
                        Button { Haptics.select(); sending = true } label: { Label("Send to a friend", systemImage: "paperplane") }
                    }
                }
                if draft.workoutId != nil {
                    Section {
                        Button("Delete Workout", role: .destructive) { Haptics.warn(); confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(draft.workoutId == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Save")
                }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive) {
                    if let id = draft.workoutId { Motion.run { store.deleteWorkout(id) } }
                    Haptics.impact(); dismiss()
                }
            }
        }
        .interactiveDismissDisabled()   // editors close with ✕ or ✓, not by pulling down
        .sheet(isPresented: $adding) {
            AddToWorkoutSheet(have: Set(draft.items.map(\.exId))) { exId, sets in
                Motion.run { draft.items.append(WorkoutItem(exId: exId, sets: sets)) }
            }
        }
        .sheet(item: Binding(get: { setsFor.map { Ident(id: String($0)) } }, set: { setsFor = $0.flatMap { Int($0.id) } })) { s in
            let i = Int(s.id)!
            SetCountSheet(title: store.exById(draft.items[i].exId)?.name ?? "Exercise", button: "Save", start: draft.items[i].sets ?? 3) { n in
                draft.items[i].sets = n
            }
        }
        .sheet(isPresented: $sending) {
            // what's in the editor now (like the web app)
            let nm = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            SendToSheet(item: .workout(Workout(id: draft.workoutId ?? "", name: nm.isEmpty ? "Workout" : nm, items: draft.items)))
        }
        .onAppear { if draft.workoutId == nil { nameFocused = true } }
    }

    private var deleteTitle: String {
        guard let id = draft.workoutId else { return "" }
        let used = store.plansUsing(id)
        return used.isEmpty ? "Delete this workout?" : "Used in \(used.map(\.name).joined(separator: ", ")). Those days will become rest days."
    }

    private func save() {
        if let e = store.saveWorkout(id: draft.workoutId, name: draft.name, items: draft.items) {
            Haptics.error(); Motion.run { error = e }; nameFocused = true; return
        }
        Haptics.success(); dismiss()
    }
}

/// Number of sets for one exercise (also the second step of adding one to a workout).
struct SetCountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let button: String
    @State var start: Int
    var done: (Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                Text("Number of sets").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2).textCase(.uppercase)
                SetCountPicker(sets: $start)
                Button(button) { Haptics.select(); done(start); dismiss() }
                    .buttonStyle(PrimaryButton())
                    .padding(.horizontal, 16).padding(.top, 8)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDetents([.height(380)])
    }
}

/// Add Exercise to a workout: search, pick (or make a new one), then choose the number of sets.
struct AddToWorkoutSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let have: Set<String>
    var add: (String, Int) -> Void
    @State private var query = ""
    @State private var picked: Ident?
    @State private var sets = 3
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                Section {
                    Button { creating = true } label: { Label(q.isEmpty ? "New exercise" : "New exercise “\(q)”", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Color.tint)
                }
                let list = store.data.exercises.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                if !list.isEmpty {
                    Section {
                        ForEach(list) { e in
                            if have.contains(e.id) {
                                HStack { Text(e.name).foregroundStyle(Color.label2); Spacer(); Text("Added").foregroundStyle(Color.label3) }
                            } else {
                                Button { sets = store.data.settings.defaultSets; picked = Ident(id: e.id) } label: { Row(title: e.name) { EmptyView() } }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseForm(exId: nil, preset: .init(name: query.trimmingCharacters(in: .whitespacesAndNewlines))) { id in
                    sets = store.data.settings.defaultSets
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { picked = Ident(id: id) }
                }
            }
            .navigationDestination(item: $picked) { p in
                VStack(spacing: 6) {
                    Text("Number of sets").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2).textCase(.uppercase)
                    SetCountPicker(sets: $sets)
                    Button("Add to Workout") {
                        Haptics.impact()
                        add(p.id, sets); dismiss()
                    }
                        .buttonStyle(PrimaryButton())
                        .padding(.horizontal, 16).padding(.top, 8)
                    Spacer()
                }
                .padding(.top, 20)
                .background(Color(uiColor: .secondarySystemBackground))
                .navigationTitle(store.exById(p.id)?.name ?? "Exercise")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

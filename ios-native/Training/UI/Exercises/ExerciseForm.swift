import SwiftUI

/// New / Edit Exercise: name, muscle group, equipment, instructions, note, video, Delete.
struct ExerciseForm: View {
    struct Preset { var name = "", muscle = "", equip = "" }
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exId: String?
    var preset = Preset()
    var saved: (String) -> Void = { _ in }
    var deleted: () -> Void = {}
    @State private var f = Store.ExerciseFields()
    @State private var loaded = false
    @State private var error = ""
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let ex = exId.flatMap(store.exById)
        let fromDb = ex?.lib.flatMap { Library.byId($0) } != nil
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $f.name)
                        .font(.system(size: 20, weight: .semibold))
                        .focused($nameFocused)
                        .onChange(of: f.name) { error = "" }
                }
                Section("Muscle group") { chips(Library.muscles, $f.muscle) }
                Section("Equipment") { chips(Library.equipment, $f.equip) }
                Section { TextField("Setup, cues, things to remember…", text: $f.instructions, axis: .vertical).lineLimit(3...8) }
                    header: { optional("Instructions", "optional") }
                Section {
                    TextField("E.g. seat on 4", text: $f.note, axis: .vertical).lineLimit(2...4)
                        .onChange(of: f.note) { if f.note.count > Clean.noteMax { f.note = String(f.note.prefix(Clean.noteMax)) } }
                } header: { optional("Note", "shows when you log it") }
                Section {
                    TextField("YouTube link", text: $f.video).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { optional("Video", "optional") }
                Section("Exercise database") {
                    Text(fromDb ? "From the exercise database. Your notes, video and changes stay private to you."
                                : "Sign in to share exercises with the database. This one stays private.")
                        .font(.system(size: 15)).foregroundStyle(Color.label2)
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(Color.red) }.listRowBackground(Color.clear) }
                if ex != nil {
                    Section { Button("Delete Exercise", role: .destructive) { Haptics.warn(); confirmDelete = true } }
                }
            }
            .navigationTitle(ex == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Save")
                }
            }
            .confirmationDialog(deleteTitle(ex), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Exercise", role: .destructive) {
                    if let id = exId { Haptics.impact(); Motion.run { store.deleteExercise(id) } }
                    dismiss(); deleted()
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let ex {
                f = .init(name: ex.name, muscle: ex.muscle ?? "", equip: ex.equip ?? "", instructions: ex.instructions, note: ex.note ?? "", video: ex.video)
            } else {
                f = .init(name: preset.name, muscle: preset.muscle, equip: preset.equip)
                if preset.name.isEmpty { nameFocused = true }
            }
        }
    }

    private func deleteTitle(_ ex: Exercise?) -> String {
        guard let ex else { return "" }
        let n = store.exSets(ex.id).count
        return "Delete \(ex.name)\(n > 0 ? " and \(Fmt.plural(n, "logged set"))" : "")?"
    }
    private func optional(_ title: String, _ hint: String) -> some View {
        Text("\(title)\(Text(" · \(hint)").foregroundStyle(Color.label3))")
    }
    private func chips(_ options: [(key: String, name: String)], _ sel: Binding<String>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.key) { o in
                ChipButton(title: o.name, on: sel.wrappedValue == o.key) { sel.wrappedValue = sel.wrappedValue == o.key ? "" : o.key }
            }
        }
        .padding(.vertical, 4)
    }
    private func save() {
        let r = store.saveExercise(id: exId, f)
        if let e = r.error { Haptics.error(); Motion.run { error = e }; return }
        Haptics.success()
        dismiss()
        if let id = r.id { saved(id) }
    }
}

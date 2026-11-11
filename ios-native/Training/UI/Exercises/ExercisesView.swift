import SwiftUI

/// Exercises tab: search, Add exercise, then your exercises (while searching, matches from the database too).
struct ExercisesView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var openEx: Ident?
    @State private var browsing = false

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let mine = store.data.exercises.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let fromLib = q.isEmpty ? [] : Array(Library.all.filter { Library.norm($0.name).contains(Library.norm(q)) && store.mineFor($0) == nil }.prefix(5))
        NavigationStack {
            List {
                // right under the search field, so a long list doesn't mean scrolling to make a new one
                Section {
                    Button { browsing = true } label: { Label("Add exercise", systemImage: "plus") }
                        .buttonStyle(TintedButton())
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if !mine.isEmpty || fromLib.isEmpty {
                    Section {
                        if mine.isEmpty {
                            Text(store.data.exercises.isEmpty ? "No exercises yet. Tap Add exercise to pick from the database." : "None of your exercises match.")
                                .foregroundStyle(Color.label2)
                        }
                        ForEach(mine) { e in
                            Button { openEx = Ident(id: e.id) } label: {
                                Row(title: e.name, sub: store.exDates(e.id).last.map { "Last logged \(Fmt.short($0))" } ?? "Never logged") { EmptyView() }
                            }
                        }
                    }
                }
                if !fromLib.isEmpty {
                    Section("From the database") {
                        ForEach(fromLib) { x in LibRow(x: x, state: .add) { Motion.run { store.addFromLib(x) } } }
                    }
                }
            }
            .listSectionSpacing(14)
            .animation(Motion.soft, value: mine.map(\.id))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .navigationTitle("Exercises")
        }
        .sheet(item: $openEx) { e in ExerciseDetail(exId: e.id, mode: .detail).presentationDragIndicator(.visible) }
        .sheet(isPresented: $browsing) {
            LibraryView(mode: .list, query: query) { id in
                // a new exercise of your own opens right away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { openEx = Ident(id: id) }
            }
        }
    }
}

/// A database row: name, "Chest · Barbell", and + (or "In your list" / "Added").
struct LibRow: View {
    enum State { case add, inList, added }
    let x: LibEntry
    let state: State
    var tap: () -> Void
    var body: some View {
        Button { if state == .add { tap() } } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.name).foregroundStyle(Color.primary)
                    Text(Library.sub(x)).font(.system(size: 15)).foregroundStyle(Color.label2)
                }
                Spacer()
                switch state {
                case .add:
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.tint)
                        .frame(width: 28, height: 28).background(Color.tint.opacity(0.14), in: Circle())
                case .inList: Text("In your list").foregroundStyle(Color.label2)
                case .added: Text("Added").foregroundStyle(Color.label2)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(state != .add)
    }
}

/// The exercise database: search, muscle group and equipment filters, Create your own.
/// mode .list adds to your exercises; .day adds it to the day and hands it back.
struct LibraryView: View {
    enum Mode { case list, day(String) }
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State var query: String
    var picked: (String) -> Void
    @State private var muscle = ""
    @State private var equip = ""
    @State private var creating = false

    var body: some View {
        let term = Library.norm(query)
        let list = Library.all.filter { (term.isEmpty || Library.norm($0.name).contains(term)) && (muscle.isEmpty || $0.muscle == muscle) && (equip.isEmpty || $0.equip == equip) }
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Chips(options: Library.muscles, selected: $muscle)
                        Chips(options: Library.equipment, selected: $equip)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section {
                    Button { creating = true } label: { Label("Create your own exercise", systemImage: "plus.circle.fill") }
                        .foregroundStyle(Color.tint)
                }
                Section {
                    if list.isEmpty {
                        Text("Nothing matches\(query.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " “\(query.trimmingCharacters(in: .whitespaces))”"). Create your own above.")
                            .foregroundStyle(Color.label2)
                    }
                    ForEach(list) { x in
                        LibRow(x: x, state: rowState(x)) {
                            let id = store.addFromLib(x)
                            if case .day(let k) = mode { store.addExercise(id, to: k); dismiss(); picked(id) }
                        }
                    }
                } footer: {
                    if !list.isEmpty { Text("\(Fmt.plural(list.count, "exercise")). Tap one to add it to your exercises.") }
                }
            }
            .listSectionSpacing(12)
            .animation(Motion.soft, value: list.map(\.id))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Exercise database")
            .navigationSubtitle({ if case .day(let k) = mode { return "Adding to \(Fmt.long(k))" } else { return "" } }())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .sheet(isPresented: $creating) {
            ExerciseForm(exId: nil, preset: .init(name: query.trimmingCharacters(in: .whitespaces), muscle: muscle, equip: equip)) { id in
                if case .day(let k) = mode { store.addExercise(id, to: k) }
                dismiss(); picked(id)
            }
        }
    }

    private func rowState(_ x: LibEntry) -> LibRow.State {
        guard let mine = store.mineFor(x) else { return .add }
        if case .day(let k) = mode { return store.dayOf(k).items.contains { $0.exId == mine.id } ? .added : .add }
        return .inList
    }
}

/// A row of filter chips (tap again to clear).
struct Chips: View {
    let options: [(key: String, name: String)]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.key) { o in ChipButton(title: o.name, on: selected == o.key) { selected = selected == o.key ? "" : o.key } }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()        // chips run to the screen edges while you scroll them
    }
}

struct ChipButton: View {
    let title: String
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button { Haptics.select(); Motion.run(Motion.soft) { action() } } label: {
            Text(title).font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? Color.white : Color.primary)
                .padding(.horizontal, 14).frame(height: 34)
                .background(on ? Color.tint : Color.fill, in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Chips that wrap onto more lines (the exercise form).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

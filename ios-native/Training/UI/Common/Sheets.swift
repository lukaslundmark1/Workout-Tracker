import SwiftUI

/// Finish workout (or, once finished, Duration): log the unticked sets as shown, and confirm the duration to the minute.
/// If the last ticked set was more than 15 minutes ago, the workout ends at that set.
struct FinishSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    var done: (Bool) -> Void
    @State private var logRest: Bool?
    @State private var h = 0
    @State private var m = 0
    @State private var ready = false

    private struct Calc {
        var editing: Bool, logged: [LoggedSet], unticked: [Store.Unticked], ok: [Store.Unticked]
        var ranLong: Bool, lastTs: Double?, endAt: Double, mins: Int, session: Session?
    }
    private func calc() -> Calc {
        let s = store.dayOf(day).session
        let editing = s?.end != nil
        let logged = store.setsOn(day)
        let unticked = editing ? [] : store.untickedSets(day)
        let ok = unticked.filter { $0.w != nil && $0.r != nil }
        let firstTs = logged.map(\.ts).min(), lastTs = logged.map(\.ts).max()
        let now = store.clock(day)          // a paused timer counts up to when it was paused
        let ranLong = !editing && lastTs != nil && now - lastTs! > 15 * 60000 && (s == nil || lastTs! > s!.start)
        let endAt = editing ? s!.end! : ranLong ? lastTs! : now
        let ms: Double = s != nil ? endAt - s!.start : (firstTs != nil && (day == store.today || ranLong)) ? endAt - firstTs! : 0
        return Calc(editing: editing, logged: logged, unticked: unticked, ok: ok, ranLong: ranLong, lastTs: lastTs, endAt: endAt,
                    mins: max(0, Int((ms / 60000).rounded())), session: s)
    }

    var body: some View {
        let c = calc()
        let logIt = logRest ?? !c.ok.isEmpty
        let nothing = c.logged.isEmpty && !(logIt && !c.ok.isEmpty)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !c.editing {
                        Text("\(Fmt.plural(c.logged.count, "set")) logged\(c.unticked.isEmpty ? "" : " · \(Fmt.plural(c.unticked.count, "set")) not ticked")")
                            .font(.system(size: 15)).foregroundStyle(Color.label2)
                            .frame(maxWidth: .infinity).padding(.bottom, 12)
                        if !c.ok.isEmpty {
                            Toggle("Log the \(Fmt.plural(c.ok.count, "unticked set")) as shown", isOn: Binding(get: { logIt }, set: { Haptics.select(); logRest = $0 }))
                                .tint(.green)
                                .padding(.horizontal, 16).frame(minHeight: 52)
                                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            footnote("Uses the weight and reps shown in each row." + (c.unticked.count > c.ok.count ? " \(Fmt.plural(c.unticked.count - c.ok.count, "set")) without numbers will be skipped." : ""))
                        }
                        if nothing {
                            footnote("No sets are logged, so this workout will show as empty. " + (c.ok.isEmpty ? "Tick the sets you did first." : "Tick the sets you did, or log them above."))
                                .foregroundStyle(Color.red)
                        }
                        Text("Duration").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2)
                            .textCase(.uppercase).padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 6)
                    }
                    Text(c.ranLong
                         ? "\(c.session.map { "Started \(Fmt.hm($0.start)) · " } ?? "")ends at your last set, \(Fmt.hm(c.lastTs!))"
                         : "\(c.session.map { "Started \(Fmt.hm($0.start))" } ?? "The timer wasn't running") · adjust if needed")
                        .font(.system(size: 15)).foregroundStyle(Color.label2)
                        .padding(.horizontal, 6).padding(.bottom, 4)
                    HStack(spacing: 0) {
                        Picker("Hours", selection: $h) { ForEach(0..<10) { Text("\($0)").tag($0) } }
                            .pickerStyle(.wheel).frame(width: 90)
                        Text("h").fontWeight(.semibold)
                        Picker("Minutes", selection: $m) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }
                            .pickerStyle(.wheel).frame(width: 90)
                        Text("min").fontWeight(.semibold)
                    }
                    .font(.rounded(20))
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onChange(of: h) { if ready { Haptics.select() } }
                    .onChange(of: m) { if ready { Haptics.select() } }

                    if c.editing && day == store.today {
                        Button { store.resume(day); Haptics.select(); dismiss() } label: { Label("Resume workout", systemImage: "play.fill") }
                            .buttonStyle(TintedButton()).padding(.top, 14)
                        footnote("Pressed Finish too early, or training again later today? The timer carries on from where it was.")
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 30)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle(c.editing ? "Duration" : "Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save(c, logIt) } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(c.editing ? "Save duration" : "Finish workout")
                }
            }
        }
        .onAppear {
            let c = calc()
            h = min(9, c.mins / 60); m = c.mins % 60
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ready = true }
        }
    }

    private func footnote(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundStyle(Color.label2).padding(.horizontal, 16).padding(.top, 8)
    }

    private func save(_ c: Calc, _ logIt: Bool) {
        let total = Double(h * 60 + m) * 60000
        var d = store.data
        if d.days[day] == nil { d.days[day] = store.virtualDay(day) ?? Day() }
        if !c.editing && logIt {
            var ts = c.ranLong ? c.lastTs! + 1 : nowMs()
            for u in c.ok {
                d.sets.append(LoggedSet(id: newId(), exId: u.exId, date: day, slot: u.slot, weight: store.units.fromU(u.w!), reps: u.r!, ts: ts))
                ts += 1
                store.drafts[u.exId + "|" + day]?[u.slot] = nil
            }
        }
        // A running timer keeps its start and the duration sets the end; otherwise the duration counts back from the end
        if let s = c.session, !c.editing { d.days[day]!.session = Session(start: s.start, end: s.start + total) }
        else { let end = c.editing ? c.session!.end! : c.endAt; d.days[day]!.session = Session(start: end - total, end: end) }
        store.padClose()
        store.pausedAt[day] = nil
        Motion.run { store.data = d }
        if c.editing { Haptics.select(); dismiss(); done(false); return }
        Haptics.success()
        store.rest = nil
        dismiss()
        done(true)
        // then the workout summary slides up (once this sheet, and the exercise screen if it was open, have gone)
        if store.hasSets(day) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { store.summaryFor = day } }
    }
}

/// Add an exercise or a whole workout to the day.
struct AddSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    var exercisesOnly = false
    var onAdded: (String?) -> Void = { _ in }    // the exercise added (nil for a workout)
    @State private var mode = 0
    @State private var query = ""
    @State private var browsing = false
    @State private var creating = false

    private func add(_ exId: String) {
        Motion.run { store.addExercise(exId, to: day) }
        dismiss(); onAdded(exId)
    }

    var body: some View {
        NavigationStack {
            List {
                if mode == 0 && !exercisesOnly && !store.data.workouts.isEmpty {
                    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    let list = store.workoutsSorted.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
                    if list.isEmpty { Text("No workouts match “\(q)”.").foregroundStyle(Color.label2) }
                    ForEach(list) { w in
                        Button {
                            Motion.run { store.addWorkout(w.id, to: day) }
                            dismiss(); onAdded(nil)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.name).foregroundStyle(Color.primary)
                                Text(w.items.compactMap { store.exById($0.exId)?.name }.joined(separator: ", "))
                                    .font(.subheadline).foregroundStyle(Color.label2).lineLimit(1)
                            }
                        }
                    }
                } else {
                    let have = Set(store.dayOf(day).items.map(\.exId))
                    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    Section {
                        Button { browsing = true } label: { Label("Browse exercise database", systemImage: "plus.circle.fill") }
                        Button { creating = true } label: { Label(q.isEmpty ? "New exercise" : "New exercise “\(q)”", systemImage: "plus.circle.fill") }
                    }
                    .foregroundStyle(Color.tint)
                    let mine = store.data.exercises.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
                        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                    if !mine.isEmpty {
                        Section {
                            ForEach(mine) { ex in
                                Button { add(ex.id) } label: {
                                    HStack {
                                        Text(ex.name).foregroundStyle(have.contains(ex.id) ? Color.label2 : Color.primary)
                                        Spacer()
                                        if have.contains(ex.id) { Text("Added").foregroundStyle(Color.label3) }
                                    }
                                }
                                .disabled(have.contains(ex.id))
                            }
                        }
                    }
                    let fromLib = q.isEmpty ? [] : Array(Library.all.filter { Library.norm($0.name).contains(Library.norm(q)) && store.mineFor($0) == nil }.prefix(5))
                    if !fromLib.isEmpty {
                        Section("From the database") {
                            ForEach(fromLib) { x in LibRow(x: x, state: .add) { add(store.addFromLib(x)) } }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: mode == 0 && !exercisesOnly && !store.data.workouts.isEmpty ? "Search workouts" : "Search exercises")
            .navigationTitle(exercisesOnly ? "Add exercise" : "Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
                if !exercisesOnly {
                    ToolbarItem(placement: .principal) {
                        Picker("Show", selection: $mode) { Text("Workouts").tag(0); Text("Exercises").tag(1) }
                            .pickerStyle(.segmented).frame(width: 220)
                            .onChange(of: mode) { Haptics.select() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $browsing) {
            LibraryView(mode: .day(day), query: query) { id in dismiss(); onAdded(id) }
        }
        .sheet(isPresented: $creating) {
            ExerciseForm(exId: nil, preset: .init(name: query.trimmingCharacters(in: .whitespacesAndNewlines))) { id in add(id) }
        }
        .onAppear { if exercisesOnly || store.data.workouts.isEmpty { mode = 1 } }
    }
}

/// An exercise's private note, e.g. "seat on 4" (up to 200 characters).
struct NoteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exId: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. seat on 4", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focused)
                    .padding(14)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: text) { if text.count > 200 { text = String(text.prefix(200)) } }
                Text("Only you can see this. It isn't sent with workouts or plans.")
                    .font(.footnote).foregroundStyle(Color.label2).padding(.horizontal, 6)
                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .navigationTitle(store.exById(exId)?.name ?? "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { store.setNote(exId, text); Haptics.select(); dismiss() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Save")
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { text = store.exById(exId)?.note ?? ""; focused = true }
    }
}

/// Settings for the prototype: units, week start, appearance, backups, and starting over with the sample data.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var confirmReset = false
    @State private var picking = false
    @State private var pending: AppData?
    @State private var importError = ""
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var s = store
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $s.data.settings.units) { Text("kg").tag("metric"); Text("lb").tag("imperial") }
                    Picker("Week starts on", selection: $s.data.settings.weekStart) { Text("Monday").tag(1); Text("Sunday").tag(0) }
                    Picker("Appearance", selection: $s.data.settings.theme) { Text("Auto").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                }
                Section {
                    if let url = exportURL {
                        ShareLink(item: url) { Text("Export backup") }
                    }
                    Button("Import backup") { importError = ""; picking = true }
                } footer: {
                    Text(importError.isEmpty
                         ? "A backup exported from the Training web app (Settings → Export backup) loads here, so you can try this app with your own training. Importing replaces what's in this prototype; your account isn't touched."
                         : importError)
                        .foregroundStyle(importError.isEmpty ? Color.label2 : Color.red)
                }
                Section {
                    Button("Start over with the sample data", role: .destructive) { Haptics.warn(); confirmReset = true }
                } footer: {
                    Text("This is a prototype to compare how a fully native app feels. Everything is stored only on this phone. Sign-in, sync and the other tabs come in later steps.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Replace everything in this prototype with the sample data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.resetSampleData(); exportURL = store.exportBackupFile() }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let raw = try? Data(contentsOf: url), let d = Clean.backup(raw) {
                    Haptics.warn(); pending = d
                } else {
                    Haptics.error(); importError = "That file isn't a Training backup."
                }
            }
            .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Replace everything", role: .destructive) {
                    if let d = pending { store.importBackup(d); Haptics.success(); exportURL = store.exportBackupFile() }
                    pending = nil
                }
            } message: {
                if let d = pending { Text("\(Fmt.plural(d.exercises.count, "exercise")), \(Fmt.plural(d.sets.count, "set")) and \(Fmt.plural(d.workouts.count, "workout")).") }
            }
            .onChange(of: store.data.settings) { Haptics.select() }
            .onAppear { exportURL = store.exportBackupFile() }
        }
    }
}

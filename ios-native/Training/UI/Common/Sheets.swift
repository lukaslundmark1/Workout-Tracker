import SwiftUI

/// Finish workout (or, once finished, Duration): log the unticked sets as shown, and confirm the duration to the minute.
/// If the last ticked set was more than 15 minutes ago, the workout ends at that set.
struct FinishSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: String
    let g: String                      // which workout on the day
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
        let s = store.sessionOf(day, g)
        let editing = s?.end != nil
        let logged = store.groupSets(day, g)
        let unticked = editing ? [] : store.untickedSets(day, g)
        let ok = unticked.filter { $0.w != nil && $0.r != nil }
        let firstTs = logged.map(\.ts).min(), lastTs = logged.map(\.ts).max()
        let now = store.clock(day, g)       // a paused timer counts up to when it was paused
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
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onChange(of: h) { if ready { Haptics.select() } }
                    .onChange(of: m) { if ready { Haptics.select() } }

                    if c.editing && day == store.today {
                        Button { store.resume(day, g); Haptics.select(); dismiss() } label: { Label("Resume workout", systemImage: "play.fill") }
                            .buttonStyle(TintedButton()).padding(.top, 14)
                        footnote("Pressed Finish too early, or training again later today? The timer carries on from where it was.")
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 30)
            }
            .background(Color.bg)
            .navigationTitle(c.editing ? "Duration" : "Finish \(store.groups(day).first { $0.id == g }.map { $0.id == otherGroup ? "workout" : $0.name } ?? "workout")")
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
        d.days[day] = store.normalized(d.days[day] ?? store.virtualDay(day) ?? Day())
        if !c.editing && logIt {
            var ts = c.ranLong ? c.lastTs! + 1 : nowMs()
            for u in c.ok {
                d.sets.append(LoggedSet(id: newId(), exId: u.exId, date: day, slot: u.slot, weight: store.units.fromU(u.w!), reps: u.r!, ts: ts, w: u.g))
                ts += 1
                store.drafts[u.exId + "|" + day + "|" + u.g]?[u.slot] = nil
            }
        }
        // A running timer keeps its start and the duration sets the end; otherwise the duration counts back from the end
        if let s = c.session, !c.editing { store.setSession(day, g, Session(start: s.start, end: s.start + total), in: &d) }
        else { let end = c.editing ? c.session!.end! : c.endAt; store.setSession(day, g, Session(start: end - total, end: end), in: &d) }
        store.padClose()
        store.clearPause(day, g)
        Motion.run { store.data = d }
        if c.editing { Haptics.select(); dismiss(); done(false); return }
        Haptics.success()
        store.rest = nil
        dismiss()
        done(true)
        // then the workout summary slides up (once this sheet, and the exercise screen if it was open, have gone)
        if !store.groupSets(day, g).isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { store.summaryFor = GroupKey(k: day, g: g) } }
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
                    let onDay = Set(store.dayOf(day).workouts.map(\.id))
                    if list.isEmpty { Text("No workouts match “\(q)”.").foregroundStyle(Color.label2) }
                    ForEach(list) { w in
                        Button {
                            Motion.run { store.addWorkout(w.id, to: day) }
                            dismiss(); onAdded(nil)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.name).foregroundStyle(Color.primary)
                                    Text(w.items.compactMap { store.exById($0.exId)?.name }.joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(Color.label2).lineLimit(1)
                                }
                                if onDay.contains(w.id) {
                                    Spacer()
                                    Image(systemName: "checkmark").foregroundStyle(Color.tint).accessibilityLabel("On this day")
                                }
                            }
                        }
                        .disabled(onDay.contains(w.id))
                    }
                } else {
                    let have = Set(store.dayOf(day).items.filter { $0.w == otherGroup }.map(\.exId))
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
        .sheetColors()   // half height: the pop-up shade keeps its edge visible over the dimmed page
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
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onChange(of: text) { if text.count > 200 { text = String(text.prefix(200)) } }
                Text("Only you can see this. It isn't sent with workouts or plans.")
                    .font(.footnote).foregroundStyle(Color.label2).padding(.horizontal, 6)
                Spacer()
            }
            .padding(16)
            .background(Color.bg)
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
        .sheetColors()
        .onAppear { text = store.exById(exId)?.note ?? ""; focused = true }
    }
}

/// Settings: account and sync, preferences, backups (the web app's Settings tab).
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @State private var confirmReset = false
    @State private var picking = false
    @State private var pending: AppData?
    @State private var importError = ""
    @State private var exportURL: URL?
    @State private var sheet: AccountSheet?

    enum AccountSheet: String, Identifiable { case signIn, signOut, delete; var id: String { rawValue } }

    var body: some View {
        let _ = Perf.body("SettingsView")
        @Bindable var s = store
        let signedIn = cloud.user != nil
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(String(store.data.settings.name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
                            .font(.rounded(22)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(LinearGradient(colors: [Color.tint.mix(with: .white, by: 0.15), Color.tint], startPoint: .top, endPoint: .bottom), in: Circle())
                        TextField("Your name", text: $s.data.settings.name)
                            .font(.system(size: 20, weight: .semibold))
                            .textContentType(.name)
                            .onChange(of: store.data.settings.name) { _, n in if n.count > 40 { s.data.settings.name = String(n.prefix(40)) } }
                    }
                    .padding(.vertical, 4)
                    if let u = cloud.user {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Account")
                                Text(u.email.isEmpty ? (u.name ?? "Signed in") : u.email)
                                    .font(.subheadline).foregroundStyle(Color.label2).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            SyncBadge(status: cloud.status, text: cloud.statusText)
                        }
                        Button("Sign out", role: .destructive) { Haptics.select(); sheet = .signOut }
                    } else {
                        Button { Haptics.select(); sheet = .signIn } label: {
                            Label("Sign in to back up and sync", systemImage: "person.crop.circle.badge.plus")
                        }
                        .disabled(!cloud.available)
                    }
                } footer: {
                    if case .error = cloud.status, signedIn { Text(cloud.statusText).foregroundStyle(Color.red) }
                    else if !cloud.available { Text("Sign-in needs one more setup step in this build (the Firebase file GoogleService-Info.plist).") }
                }
                Section {
                    Picker("Units", selection: $s.data.settings.units) { Text("kg").tag("metric"); Text("lb").tag("imperial") }
                    Picker("Appearance", selection: $s.data.settings.theme) { Text("Auto").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    Picker("Week starts on", selection: $s.data.settings.weekStart) { Text("Monday").tag(1); Text("Sunday").tag(0) }
                    Stepper(value: $s.data.settings.defaultSets, in: 1...10) {
                        HStack { Text("Default sets"); Spacer(); Text("\(store.data.settings.defaultSets)").foregroundStyle(Color.label2).monospacedDigit() }
                    }
                } header: { Text("Preferences") } footer: {
                    Text("Default sets is used when you add a single exercise to a day or to a workout.")
                }
                Section {
                    if let url = exportURL {
                        ShareLink(item: url) { Text("Export backup") }
                    }
                    Button("Import backup") { importError = ""; picking = true }
                } header: { Text("Data") } footer: {
                    Text(!importError.isEmpty ? importError
                         : signedIn ? "Your workouts are backed up to your account and synced between your devices. Importing a backup replaces everything, in your account too."
                         : "You're not signed in, so your workouts are stored only on this phone. A backup exported from the Training web app (Settings → Export backup) loads here.")
                        .foregroundStyle(importError.isEmpty ? Color.label2 : Color.red)
                }
                if !signedIn && UserDefaults.standard.string(forKey: Store.ownerKey) == nil {
                    Section {
                        Button("Start over with the sample data", role: .destructive) { Haptics.warn(); confirmReset = true }
                    } footer: {
                        Text("Puts the made-up sample training back, to try things out. It stays on this phone: signing in starts from your account's own training.")
                    }
                }
                if signedIn {
                    Section {
                        Button("Delete account", role: .destructive) { Haptics.select(); sheet = .delete }
                    } footer: {
                        Text("Permanently deletes your account and everything stored about you in the cloud.")
                    }
                }
            }
            .modifier(RestRoom())
            .navigationTitle("Settings")
            .confirmationDialog("Replace everything on this phone with the sample data?", isPresented: $confirmReset, titleVisibility: .visible) {
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
                if let d = pending { Text("\(Fmt.plural(d.exercises.count, "exercise")), \(Fmt.plural(d.sets.count, "set")) and \(Fmt.plural(d.workouts.count, "workout"))." + (signedIn ? " This also replaces what's in your account." : "")) }
            }
            .onChange(of: store.data.settings.units) { Haptics.select() }
            .onChange(of: store.data.settings.theme) { Haptics.select() }
            .onChange(of: store.data.settings.weekStart) { Haptics.select() }
            .onChange(of: store.data.settings.defaultSets) { Haptics.select() }
            .onAppear { exportURL = store.exportBackupFile() }
            .sheet(item: $sheet) { which in
                switch which {
                case .signIn: SignInSheet()
                case .signOut: SignOutSheet()
                case .delete: DeleteAccountSheet()
                }
            }
        }
    }
}

/// "Backed up" (green), "Syncing…", "Offline — will sync later" next to the account
private struct SyncBadge: View {
    let status: Cloud.Status
    let text: String
    var body: some View {
        let color: Color = switch status {
        case .synced: .green
        case .error: .red
        case .offline: .orange
        default: Color.label2
        }
        HStack(spacing: 5) {
            if status == .syncing || status == .connecting { ProgressView().controlSize(.mini) }
            else { Image(systemName: status == .synced ? "checkmark.icloud.fill" : status == .offline ? "icloud.slash" : "exclamationmark.icloud") }
            Text(text.hasPrefix("Sync problem") ? "Sync problem" : text).lineLimit(1)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .contentTransition(.opacity)
        .animation(Motion.soft, value: status)
    }
}

import SwiftUI

/// Your profile, or a friend's page (app.js renderMe / renderFriend). Slides up; inside it, All workouts → a workout →
/// an exercise's graph slide in from the side.
struct ProfileView: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    /// nil = you
    let linkId: String?
    @State private var src: ProfileSource?
    @State private var loading = false
    @State private var loadError = ""
    @State private var confirmRemove = false
    @State private var sending = false

    enum Route: Hashable { case workouts, workout(String), exercise(String) }

    private var f: Friends { cloud.friends }
    private var link: FriendLink? { linkId.flatMap { f.link($0) }.flatMap { $0.accepted ? $0 : nil } }
    private var mine: ProfileSource { ProfileSource(exercises: store.data.exercises, ix: store.index, days: store.data.days, mine: true) }
    private var name: String { link.map { $0.name(f.me) } ?? f.myNameOrYou(store) }
    /// What the pages show: your own training, or the friend's loaded copy
    private var shown: ProfileSource? { linkId == nil ? mine : src }

    var body: some View {
        NavigationStack {
            Group {
                if linkId != nil && link == nil {
                    Color.clear.onAppear { dismiss() }               // no longer friends
                } else {
                    List { content }
                        .listStyle(.insetGrouped)
                        .listSectionSpacing(14)
                        .refreshable { if link?.theyShare(f.me) == true { await load(force: true) } }
                }
            }
            .navigationTitle(name)
            .navigationDestination(for: Route.self) { r in
                if let s = shown {
                    switch r {
                    case .workouts: ProfileWorkouts(src: s, who: name)
                    case .workout(let k): ProfileWorkout(src: s, k: k, who: name)
                    case .exercise(let id): ProfileExercise(src: s, exId: id, who: name, friend: link?.other(f.me))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close")
                }
                if let l = link, l.theyShare(f.me) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Haptics.select(); Task { await load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Refresh")
                            .disabled(loading)
                    }
                }
            }
        }
        .pageColors()
        .task(id: link?.theyShare(f.me)) { if link?.theyShare(f.me) == true { await load(force: false) } }
        .sheet(isPresented: $sending) { if let l = link { SendPickSheet(linkId: l.id) } }
    }

    @ViewBuilder private var content: some View {
        Section {
            HStack { Spacer(); Avatar(name: name, size: 72); Spacer() }
                .listRowBackground(Color.clear)
        }
        if let l = link {
            let me = f.me
            if !l.theyShare(me) {
                Section { Text("\(name) isn't sharing their training with you.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 8) }
            } else if !loadError.isEmpty && src == nil {
                Section { Text(loadError).foregroundStyle(Color.red) }
            } else if let s = src {
                ProfileBody(src: s)
            } else {
                Section { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 24) }
            }
            GiftHistory(link: l) { sending = true }
            Section {
                Toggle("Share my training with \(name)", isOn: Binding(get: { l.iShare(me) }, set: { on in
                    Haptics.select()
                    Task { do { try await f.setShare(l, on) } catch { f.error = Friends.message(error) } }
                }))
            } header: { Text("Your sharing") } footer: {
                Text("\(name) can see your workouts, sets and progress, but can't change anything.")
            }
            Section {
                Button("Remove friend", role: .destructive) { Haptics.warn(); confirmRemove = true }
                    .frame(maxWidth: .infinity)
                    .confirmationDialog("Remove \(name) as a friend?", isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Remove friend", role: .destructive) {
                            Haptics.impact()
                            Task { try? await f.remove(l) }
                        }
                    } message: { Text("You'll stop seeing each other's training. You can add each other again with your codes.") }
            }
        } else {
            ProfileBody(src: mine)
            Section {} footer: {
                Text((cloud.user != nil ? "This is what friends you share with see. " : "") + "Change your name in Settings.")
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
    }

    private func load(force: Bool) async {
        guard let l = link else { return }
        if !force, let c = f.cached(l.other(f.me)) { src = c; return }
        loading = true; loadError = ""
        do {
            let s = try await f.loadFriend(l.other(f.me), force: force)
            Motion.run { src = s }
        } catch {
            loadError = "Couldn't load. " + Friends.message(error)
        }
        loading = false
    }
}

/// Stats and the latest three workouts (app.js profileBodyHTML)
struct ProfileBody: View {
    @Environment(Store.self) private var store
    let src: ProfileSource

    var body: some View {
        let tk = store.today, dates = src.dates(today: tk)
        let since30 = Day0.add(tk, -30), wk = Day0.weekStart(tk, firstDay: store.data.settings.weekStart)
        Section {
            HStack(spacing: 10) {
                StatTile(value: "\(dates.filter { $0 >= since30 }.count)", label: "in 30 days")
                StatTile(value: "\(dates.filter { $0 >= wk }.count)", label: "this week")
                StatTile(value: Profile.lastTrained(dates.first, today: tk), label: "last workout")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            if dates.isEmpty {
                Text(src.mine ? "No workouts logged yet." : "No workouts in the last 4 months.")
                    .foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            ForEach(dates.prefix(3), id: \.self) { k in WorkoutLink(src: src, k: k) }
        } header: {
            HStack {
                Text("Recent workouts")
                Spacer()
                if dates.count > 3 {
                    NavigationLink(value: ProfileView.Route.workouts) { Text("See all").textCase(nil) }
                }
            }
        }
    }
}

private struct StatTile: View {
    let value: String, label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.rounded(22, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 13)).foregroundStyle(Color.label2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .card(18)
    }
}

/// A workout row: what it was, when, how much
private struct WorkoutLink: View {
    @Environment(Store.self) private var store
    let src: ProfileSource
    let k: String
    var body: some View {
        let sub = src.rowSub(k, relDay: store.relDay(k))
        NavigationLink(value: ProfileView.Route.workout(k)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(src.title(k))
                Text("\(Text(sub.text))\(Text(sub.running ? " · in progress" : "").foregroundStyle(Color.green))")
                    .font(.system(size: 15)).foregroundStyle(Color.label2)
            }
        }
    }
}

/// Every workout, by month (app.js renderProfWorkouts)
struct ProfileWorkouts: View {
    let src: ProfileSource
    let who: String
    @Environment(Store.self) private var store
    var body: some View {
        let dates = src.dates(today: store.today)
        let months = Dictionary(grouping: dates) { String($0.prefix(7)) }.sorted { $0.key > $1.key }
        List {
            ForEach(months, id: \.key) { m, ks in
                Section("\(Fmt.month(m + "-01")) \(String(Fmt.year(m + "-01")))") {
                    ForEach(ks, id: \.self) { k in WorkoutLink(src: src, k: k) }
                }
            }
            if !src.mine { Section {} footer: { Text("The last 4 months.") } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Workouts")
        .navigationSubtitle(who)
    }
}

/// One workout: each exercise with its sets (app.js renderProfWorkout)
struct ProfileWorkout: View {
    let src: ProfileSource
    let k: String
    let who: String
    @Environment(Store.self) private var store
    var body: some View {
        let ids = src.exercisesOn(k), ss = src.ix.byDate[k] ?? [], u = store.units
        let d = src.days[k]
        let dur = d?.session.map { s in s.end.map { " · " + Fmt.mins($0 - s.start) } ?? " · in progress" } ?? ""
        List {
            Section {
                if ids.isEmpty { Text("No sets logged.").foregroundStyle(Color.label2) }
                ForEach(ids, id: \.self) { id in
                    NavigationLink(value: ProfileView.Route.exercise(id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(src.exName(id))
                            Text((src.ix.byExDate[id + "|" + k] ?? []).map { s in s.weight > 0 ? "\(u.w(s.weight)) \(u.u) × \(s.reps)" : "\(s.reps) reps" }.joined(separator: " · "))
                                .font(.system(size: 15)).foregroundStyle(Color.label2).monospacedDigit()
                        }
                    }
                }
            } header: { Text("\(Fmt.long(k))\(dur)").textCase(nil) } footer: {
                if !ids.isEmpty { Text("\(Fmt.plural(ss.count, "set")) logged. Tap an exercise to see its progress.") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(src.title(k))
        .navigationSubtitle(who)
    }
}

/// An exercise's graph and history: yours, or a friend's (their whole history is loaded for it)
struct ProfileExercise: View {
    let src: ProfileSource
    let exId: String
    let who: String
    let friend: String?
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @AppStorage("tt.stat") private var statRaw = StatKind.e1rm.rawValue
    @State private var ix: SetIndex?
    @State private var failed = false

    private var stat: StatKind { StatKind(rawValue: statRaw) ?? .e1rm }

    var body: some View {
        let x = friend == nil ? store.index : ix
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let x {
                    Picker("Show", selection: Binding(get: { stat }, set: { v in Haptics.select(); Motion.run { statRaw = v.rawValue } })) {
                        ForEach(StatKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 12)
                    ProgressCard(exId: exId, stat: stat, ix: x)
                    HistoryList(exId: exId, ix: x)
                } else if failed {
                    Text("Couldn't load this exercise.").foregroundStyle(Color.label2).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Color.bg)
        .navigationTitle(src.exName(exId))
        .navigationSubtitle(who)
        .task {
            guard let friend, ix == nil else { return }
            do { let r = try await cloud.friends.loadFriendExercise(friend, exId); Motion.run { ix = r } } catch { failed = true }
        }
    }
}

/// On a friend's page: send them something, and what you've sent / they've sent (app.js giftHistoryHTML)
private struct GiftHistory: View {
    @Environment(Cloud.self) private var cloud
    let link: FriendLink
    let send: () -> Void
    var body: some View {
        let f = cloud.friends, o = link.other(f.me), name = link.name(f.me)
        let sent = f.giftsOut.filter { $0.to == o }.sorted { $0.u > $1.u }.prefix(8)
        let got = f.giftsIn.filter { $0.from == o && !$0.pending }.sorted { $0.u > $1.u }.prefix(5)
        Section {
            Button { Haptics.select(); send() } label: { Label("Send a workout or plan", systemImage: "paperplane.fill") }
            ForEach(Array(sent)) { g in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name)
                        Text("\(g.kind == "plan" ? "Plan" : "Workout") · sent \(whenSent(g.u))").font(.system(size: 15)).foregroundStyle(Color.label2)
                    }
                    Spacer()
                    let (t, c): (String, Color) = g.status == "added" ? ("Added", .green) : g.status == "declined" ? ("Declined", Color.label2) : ("Waiting", Color.label2)
                    Text(t).font(.system(size: 13, weight: .semibold)).foregroundStyle(c)
                        .padding(.horizontal, 9).padding(.vertical, 3).background((g.status == "added" ? Color.green.opacity(0.15) : Color.fill), in: Capsule())
                    if g.pending { CircleX(label: "Unsend \(g.name)") { Haptics.impact(); Motion.run { f.unsend(g) } } }
                }
            }
        } header: { Text("Send to \(name)") } footer: {
            if !got.isEmpty {
                Text("From \(name): " + got.map { "\($0.name) (\($0.status == "added" ? "added" : "declined"))" }.joined(separator: ", ") + ".")
            }
        }
    }
}

/// "today", "yesterday", "on Wed 4 Nov"
@MainActor func whenSent(_ u: Double) -> String {
    let k = Day0.key(Date(timeIntervalSince1970: (u > 0 ? u : nowMs()) / 1000))
    let n = Day0.between(k, Day0.today)
    if n == 0 { return "today" }
    if n == 1 { return "yesterday" }
    return "on " + (Fmt.year(k) == Fmt.year(Day0.today) ? Fmt.short(k) : Fmt.dayYear(k))
}

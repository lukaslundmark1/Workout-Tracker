import SwiftUI

/// Add a friend by their code (app.js sheetAddFriend): type it, Find shows who it is, then Send friend request.
struct AddFriendSheet: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var found: (uid: String, name: String)?
    @State private var share = true
    @State private var error = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var code: String { FriendsCore.cleanCode(text) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("ABC-123", text: $text)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await go() } }
                        .onChange(of: text) { old, new in
                            let c = FriendsCore.cleanCode(new)
                            let f = c.count > 3 ? FriendsCore.fmtCode(c) : c
                            if f != new { text = f }
                            if c != FriendsCore.cleanCode(old) { Motion.run { found = nil }; error = "" }
                        }
                } footer: { Text("Ask your friend for their code. It's on their Friends tab.") }
                if let fd = found {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(name: fd.name, size: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fd.name).font(.system(size: 18, weight: .semibold))
                                Text(FriendsCore.fmtCode(code)).font(.system(size: 14)).foregroundStyle(Color.label2)
                            }
                        }
                        Toggle("Share my training with them", isOn: $share).onChange(of: share) { Haptics.select() }
                    } footer: { Text("You can change this any time on their page.") }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(Color.red) } }
                Section {
                    Button(found == nil ? "Find" : "Send friend request") { Task { await go() } }
                        .buttonStyle(PrimaryButton())
                        .disabled(busy || code.count != 6)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .onAppear { focused = true }
        }
    }

    private func go() async {
        let f = cloud.friends
        guard !busy else { return }
        if let fd = found {
            busy = true
            do {
                try await f.sendRequest(to: fd.uid, name: fd.name, share: share)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                self.error = (error as? Friends.FriendError)?.errorDescription ?? Friends.message(error)
            }
            busy = false
            return
        }
        if code.count != 6 { error = "Codes have 6 characters."; return }
        if code == store.data.settings.code { error = "That's your own code."; Haptics.error(); return }
        busy = true
        do {
            if let r = try await f.lookupCode(code) {
                if r.uid == f.me { error = "That's your own code."; Haptics.error() }
                else { Haptics.select(); Motion.run { found = r }; focused = false }
            } else { error = "No one has that code. Check it and try again."; Haptics.error() }
        } catch {
            self.error = "Couldn't look that up. " + Friends.message(error)
        }
        busy = false
    }
}

/// Accept a request, choosing whether to share back (app.js sheetAcceptFriend)
struct AcceptFriendSheet: View {
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let linkId: String
    @State private var share = true
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        let f = cloud.friends
        NavigationStack {
            if let l = f.link(linkId) {
                let name = l.name(f.me)
                List {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(name: name, size: 46)
                            Text(name).font(.system(size: 18, weight: .semibold))
                        }
                        Toggle("Share my training with \(name)", isOn: $share).onChange(of: share) { Haptics.select() }
                    } footer: {
                        Text(l.theyShare(f.me) ? "\(name) is sharing their training with you." : "\(name) isn't sharing their training yet.")
                    }
                    if !error.isEmpty { Section { Text(error).foregroundStyle(Color.red) } }
                    Section {
                        Button("Accept") {
                            busy = true
                            Task {
                                do { try await f.accept(l, share: share); Haptics.success(); dismiss() }
                                catch { self.error = Friends.message(error); Haptics.error() }
                                busy = false
                            }
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(busy)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Friend request")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                    }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Something a friend sent: see what's in it, then Add or Decline (app.js sheetGift)
struct GiftSheet: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let giftId: String

    var body: some View {
        let f = cloud.friends
        NavigationStack {
            if let g = f.giftsIn.first(where: { $0.id == giftId }) {
                List { content(g) }
                    .listStyle(.insetGrouped)
                    .navigationTitle("From \(g.fromName.isEmpty ? "a friend" : g.fromName)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                        }
                    }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    @ViewBuilder private func content(_ g: Gift) -> some View {
        let d = store.data
        let isNew: (GiftEx) -> Bool = { d.haveExercise($0) == nil }
        Section {
            VStack(spacing: 8) {
                Image(systemName: "gift.fill").font(.system(size: 30)).foregroundStyle(Color.tint)
                    .frame(width: 64, height: 64).background(Color.tint.opacity(0.14), in: Circle())
                Text(g.name).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                Text("\(g.summary)\nSent \(whenSent(g.u))").font(.system(size: 15)).foregroundStyle(Color.label2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
        if let p = g.plan {
            Section("Rotation") {
                ForEach(Array(p.days.enumerated()), id: \.offset) { i, w in
                    HStack(spacing: 12) {
                        DayNumber(n: i + 1)
                        if let w { Text(p.workouts[w].name) } else { Text("Rest").foregroundStyle(Color.label2) }
                    }
                }
            }
            ForEach(Array(p.workouts.enumerated()), id: \.offset) { _, w in
                Section(w.name) { items(w.items, isNew) }
            }
        } else if let w = g.workout {
            Section("Exercises") { items(w.items, isNew) }
        }
        let newCount = Set(g.allItems.map(\.ex).filter(isNew).map { Library.norm($0.name) }).count
        Section {
            Button(g.kind == "plan" ? "Add plan" : "Add to my workouts") { add(g) }
                .buttonStyle(PrimaryButton())
            Button("Decline") { Haptics.impact(); cloud.friends.decline(g); dismiss() }
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.red)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.red.opacity(0.12), in: Capsule())
                .buttonStyle(PressStyle(scale: 0.96))
        } header: {
            Text((newCount > 0 ? "\(Fmt.plural(newCount, "exercise")) you don't have yet will be added to your exercises. " : "") + "Exercises you already have are reused.")
                .textCase(nil).font(.footnote).padding(.bottom, 8)
        }
        .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private func items(_ list: [GiftItem], _ isNew: @escaping (GiftEx) -> Bool) -> some View {
        if list.isEmpty { Text("No exercises").foregroundStyle(Color.label2) }
        ForEach(Array(list.enumerated()), id: \.offset) { _, i in
            HStack {
                Text(i.ex.name)
                if isNew(i.ex) {
                    Text("New").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.tint)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Color.tint.opacity(0.14), in: Capsule())
                }
                Spacer()
                Text(Fmt.plural(i.sets, "set")).foregroundStyle(Color.label2).monospacedDigit()
            }
        }
    }

    private func add(_ g: Gift) {
        guard let what = cloud.friends.add(g) else { return }
        Haptics.success()
        dismiss()
        store.showToast(ToastMsg(kind: .done, title: "\(g.name) added", sub: g.kind == "plan" ? "Start it whenever you like" : "It's in your workouts"))
        // Open what was added in the Workouts tab, once this sheet has gone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            store.tab = .workouts
            store.openRequest = what
        }
    }
}

/// From a friend's page: pick a plan or workout to send them (app.js sheetSendPick)
struct SendPickSheet: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let linkId: String
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        let f = cloud.friends
        NavigationStack {
            if let l = f.link(linkId) {
                List {
                    if !store.data.plans.isEmpty {
                        Section("Plans") {
                            ForEach(store.plansSorted) { p in row(p.name, store.planSummary(p)) { send(.plan(p), l) } }
                        }
                    }
                    if !store.data.workouts.isEmpty {
                        Section("Workouts") {
                            ForEach(store.workoutsSorted) { w in row(w.name, Fmt.plural(w.items.count, "exercise")) { send(.workout(w), l) } }
                        }
                    }
                    if store.data.plans.isEmpty && store.data.workouts.isEmpty {
                        Text("You have no workouts or plans yet. Make some in the Workouts tab.").foregroundStyle(Color.label2)
                    }
                    if !error.isEmpty { Section { Text(error).foregroundStyle(Color.red) } }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Send to \(l.name(f.me))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                    }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(sub).font(.system(size: 15)).foregroundStyle(Color.label2)
            }
            Spacer()
            Button("Send", action: action).buttonStyle(CapsuleButton(filled: true)).disabled(busy)
        }
    }

    private func send(_ item: Friends.Item, _ l: FriendLink) {
        busy = true; error = ""
        let f = cloud.friends
        Task {
            do {
                try await f.send(item, to: [l])
                sentToast(store, item, [l.name(f.me)])
                dismiss()
            } catch { self.error = "Couldn't send. " + Friends.message(error); Haptics.error() }
            busy = false
        }
    }
}

/// From a workout or plan: pick friends to send it to (app.js sheetSendTo)
struct SendToSheet: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    let item: Friends.Item
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var error = ""
    @State private var signingIn = false

    private var kindName: String { if case .plan = item { "plan" } else { "workout" } }
    private var name: String { switch item { case .plan(let p): p.name; case .workout(let w): w.name } }
    private var summary: String {
        switch item {
        case .plan(let p): Gift(id: "", data: ["kind": "plan", "payload": store.data.planPayload(p)]).summary
        case .workout(let w): Gift(id: "", data: ["kind": "workout", "payload": store.data.workoutPayload(w)]).summary
        }
    }

    var body: some View {
        let f = cloud.friends, accepted = f.accepted
        NavigationStack {
            List {
                Section {} footer: { Text(summary).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
                if cloud.user == nil {
                    Section {
                        Text("Sign in and add a friend to send them \(kindName)s.").foregroundStyle(Color.label2)
                        Button("Sign in") { signingIn = true }.disabled(!cloud.available)
                    }
                } else if accepted.isEmpty {
                    Section { Text("No friends yet. Add someone in the Friends tab first.").foregroundStyle(Color.label2) }
                } else {
                    Section {
                        ForEach(accepted) { l in
                            let on = picked.contains(l.id)
                            Button {
                                Haptics.select()
                                Motion.run(Motion.pop) { if on { picked.remove(l.id) } else { picked.insert(l.id) } }
                                error = ""
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(name: l.name(f.me), size: 34)
                                    Text(l.name(f.me)).foregroundStyle(Color.primary)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22)).foregroundStyle(on ? Color.tint : Color.label3)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                            }
                        }
                    } footer: {
                        Text("They get their own copy\(kindName == "plan" ? ", with its workouts and exercises" : " with its exercises"). Changes you make later won't affect it.")
                    }
                    if !error.isEmpty { Section { Text(error).foregroundStyle(Color.red) } }
                    Section {
                        Button(busy ? "Sending…" : picked.count > 1 ? "Send to \(picked.count) friends" : "Send") { send() }
                            .buttonStyle(PrimaryButton())
                            .disabled(picked.isEmpty || busy)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Send \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .sheet(isPresented: $signingIn) { SignInSheet() }
    }

    private func send() {
        let f = cloud.friends
        let targets = f.accepted.filter { picked.contains($0.id) }
        busy = true; error = ""
        Task {
            do {
                try await f.send(item, to: targets)
                sentToast(store, item, targets.map { $0.name(f.me) })
                dismiss()
            } catch { self.error = "Couldn't send. " + Friends.message(error); Haptics.error() }
            busy = false
        }
    }
}

@MainActor private func sentToast(_ store: Store, _ item: Friends.Item, _ names: [String]) {
    let n: String = switch item { case .plan(let p): p.name; case .workout(let w): w.name }
    Haptics.success()
    store.showToast(ToastMsg(kind: .done, title: "Sent \(n)", sub: "To " + names.joined(separator: ", ")))
}

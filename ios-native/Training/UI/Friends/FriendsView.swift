import SwiftUI

/// Friends tab (app.js renderFriends): your profile, the inbox of things friends sent you, your friend code,
/// requests to answer, your friends, and requests you've sent. + adds a friend by their code.
struct FriendsView: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @State private var sheet: FriendsSheet?
    @State private var copied = false

    enum FriendsSheet: Identifiable {
        case me, friend(String), add, accept(String), gift(String), signIn
        var id: String {
            switch self {
            case .me: "me"; case .friend(let i): "f" + i; case .add: "add"; case .accept(let i): "a" + i
            case .gift(let i): "g" + i; case .signIn: "signin"
            }
        }
    }

    private var f: Friends { cloud.friends }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { Haptics.select(); sheet = .me } label: {
                        HStack(spacing: 14) {
                            Avatar(name: f.myNameOrYou(store), size: 46)
                            Row(title: f.myNameOrYou(store), sub: "Your profile") { EmptyView() }
                        }
                    }
                }
                if cloud.user == nil { signedOut } else if f.error == "rules" { rulesHelp } else { signedIn }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .navigationTitle("Friends")
            .toolbar {
                if cloud.user != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Haptics.select(); sheet = .add } label: { Image(systemName: "plus") }.accessibilityLabel("Add friend")
                    }
                }
            }
            .animation(Motion.soft, value: f.links)
            .animation(Motion.soft, value: f.giftsIn)
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .me: ProfileView(linkId: nil).presentationDragIndicator(.visible)
            case .friend(let id): ProfileView(linkId: id).presentationDragIndicator(.visible)
            case .add: AddFriendSheet()
            case .accept(let id): AcceptFriendSheet(linkId: id)
            case .gift(let id): GiftSheet(giftId: id)
            case .signIn: SignInSheet()
            }
        }
    }

    @ViewBuilder private var signedOut: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(Color.tint)
                Text("Train together").font(.title2.bold())
                Text("Add friends, share your training, and follow each other's progress. Sign in to get started.")
                    .multilineTextAlignment(.center).foregroundStyle(Color.label2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
        Section {
            Button("Sign in") { Haptics.select(); sheet = .signIn }
                .buttonStyle(PrimaryButton())
                .disabled(!cloud.available)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
    }

    private var rulesHelp: some View {
        Section {
            VStack(spacing: 8) {
                Text("One more Firebase step").font(.headline)
                Text("Friends needs the Firestore security rules. In the Firebase console, open Firestore → Rules, paste the rules from Claude and click Publish. Then reopen the app.")
                    .foregroundStyle(Color.label2)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var signedIn: some View {
        let me = f.me, inbox = f.pendingGifts, incoming = f.incoming, outgoing = f.outgoing, accepted = f.accepted
        if !inbox.isEmpty {
            Section("Inbox") {
                ForEach(inbox) { g in
                    Button { Haptics.select(); sheet = .gift(g.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gift.fill").foregroundStyle(Color.tint)
                                .frame(width: 34, height: 34).background(Color.tint.opacity(0.14), in: Circle())
                            Row(title: g.name, sub: "From \(g.fromName.isEmpty ? "a friend" : g.fromName) · \(g.summary)") { EmptyView() }
                        }
                    }
                }
            }
        }
        if f.giftError == "rules" {
            Section { Text("Sending workouts and plans needs the Firestore rules published.").foregroundStyle(Color.red) }
        }
        Section { codeCard }
        if !f.error.isEmpty {
            Section { Text(f.error).foregroundStyle(Color.red) }
        }
        if !incoming.isEmpty {
            Section("Requests") {
                ForEach(incoming) { l in
                    HStack(spacing: 12) {
                        Avatar(name: l.name(me), size: 34)
                        Text(l.name(me))
                        Spacer()
                        Button("Accept") { Haptics.select(); sheet = .accept(l.id) }
                            .buttonStyle(CapsuleButton(filled: true))
                        CircleX(label: "Decline") { decline(l) }
                    }
                }
            }
        }
        Section("Friends") {
            if accepted.isEmpty {
                Text("No friends yet. Share your code, or tap + to add someone by their code.")
                    .foregroundStyle(Color.label2).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 8)
            }
            ForEach(accepted) { l in
                Button { Haptics.select(); sheet = .friend(l.id) } label: {
                    HStack(spacing: 12) {
                        Avatar(name: l.name(me), size: 34)
                        Row(title: l.name(me), sub: (l.theyShare(me) ? "Shares their training" : "Not sharing") + (l.iShare(me) ? " · you share yours" : "")) { EmptyView() }
                    }
                }
            }
        }
        if !outgoing.isEmpty {
            Section("Sent") {
                ForEach(outgoing) { l in
                    HStack(spacing: 12) {
                        Avatar(name: l.name(me), size: 34)
                        Text(l.name(me))
                        Spacer()
                        Text("Waiting").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2)
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Color.fill, in: Capsule())
                        CircleX(label: "Cancel request") { decline(l) }
                    }
                }
            }
        }
    }

    private var codeCard: some View {
        let code = store.data.settings.code ?? ""
        let shown = FriendsCore.fmtCode(code)
        return VStack(spacing: 12) {
            Text("Your friend code").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.label2).textCase(.uppercase)
            Text(shown.isEmpty ? "······" : shown)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .foregroundStyle(shown.isEmpty ? Color.label3 : Color.primary)
                .textSelection(.enabled)
                .contentTransition(.opacity)
            HStack(spacing: 10) {
                ShareLink(item: inviteText(code)) {
                    Label("Share invite", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(CapsuleButton(filled: false, wide: true))
                Button {
                    UIPasteboard.general.string = shown
                    Haptics.success()
                    Motion.run { copied = true }
                    Task { try? await Task.sleep(for: .seconds(1.5)); Motion.run { copied = false } }
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(CapsuleButton(filled: false, wide: true))
            }
            .disabled(code.isEmpty)
            .opacity(code.isEmpty ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func inviteText(_ code: String) -> String {
        "Add me on Training tracker — my friend code is \(FriendsCore.fmtCode(code))\nhttps://lukaslundmark1.github.io/Workout-Tracker/#add-\(code)"
    }

    private func decline(_ l: FriendLink) {
        Haptics.impact()
        Task { do { try await f.remove(l) } catch { f.error = Friends.message(error) } }
    }
}

extension Friends {
    /// Your profile row's name: your name, else "You"
    func myNameOrYou(_ store: Store) -> String {
        let n = store.data.settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        if running { return myName }
        return "You"
    }
}

/// A round avatar with someone's initial
struct Avatar: View {
    let name: String
    var size: CGFloat = 34
    var body: some View {
        Text(FriendsCore.initial(name))
            .font(.rounded(size * 0.45)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color.tint.mix(with: .white, by: 0.15), Color.tint], startPoint: .top, endPoint: .bottom), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A small capsule button (Accept, Send, Share invite)
struct CapsuleButton: ButtonStyle {
    var filled = true
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? Color.white : Color.tint)
            .padding(.horizontal, wide ? 12 : 14).frame(height: wide ? 40 : 32)
            .background(filled ? Color.tint : Color.tint.opacity(0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.08) : Motion.pop, value: configuration.isPressed)
    }
}

/// A grey ✕ in a circle (decline, cancel, unsend)
struct CircleX: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.label2)
                .frame(width: 30, height: 30).background(Color.fill, in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

import SwiftUI

/// Sign in or create an account with email and password (the web app's sign-in sheet).
struct SignInSheet: View {
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var create = false
    @State private var email = ""
    @State private var password = ""
    @State private var err = ""
    @State private var msg = ""
    @State private var busy = false
    @FocusState private var field: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($field, equals: 0)
                        .onSubmit { field = 1 }
                    SecureField(create ? "Choose a password (6+ characters)" : "Password", text: $password)
                        .textContentType(create ? .newPassword : .password)
                        .submitLabel(.go)
                        .focused($field, equals: 1)
                        .onSubmit { go() }
                } header: {
                    Text("Back up your workouts, use them on all your devices, and add friends.")
                        .font(.subheadline).foregroundStyle(Color.label2)
                        .textCase(nil).padding(.bottom, 8).padding(.horizontal, -4)
                } footer: {
                    if !err.isEmpty { Text(err).foregroundStyle(Color.red) }
                    else if !msg.isEmpty { Text(msg).foregroundStyle(Color.green) }
                }
                Section {
                    Button { go() } label: {
                        if busy { ProgressView().tint(.white) } else { Text(create ? "Create account" : "Sign in") }
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(busy)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } footer: {
                    Text("If you normally sign in with Google, tap “Forgot password?” with your Google email to give the same account a password.")
                        .padding(.top, 10)
                }
                Section {
                    Button(create ? "I already have an account" : "Create an account") {
                        Haptics.select()
                        withAnimation(Motion.soft) { create.toggle(); err = ""; msg = "" }
                    }
                    if !create {
                        Button("Forgot password?") { forgot() }
                    }
                }
            }
            .navigationTitle(create ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .onAppear { field = 0 }
    }

    private func go() {
        guard !busy else { return }
        err = ""; msg = ""; busy = true
        Task {
            do {
                if create { try await cloud.createAccount(email: email, password: password) }
                else { try await cloud.signIn(email: email, password: password) }
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                err = Cloud.friendly(error)
            }
            busy = false
        }
    }

    private func forgot() {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            Haptics.error(); err = "Type your email above first."; msg = ""; field = 0
            return
        }
        Task {
            do {
                try await cloud.resetPassword(email: email)
                err = ""; msg = "Password reset email sent. Check your inbox."
                Haptics.success()
            } catch { err = Cloud.friendly(error); msg = ""; Haptics.error() }
        }
    }
}

/// Sign out, optionally removing your training from this phone (the web app's sign-out sheet).
struct SignOutSheet: View {
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var remove = true
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Remove my training from this phone", isOn: $remove)
                        .tint(.green)
                        .onChange(of: remove) { Haptics.select() }
                } footer: {
                    Text((cloud.online ? "" : "You're offline, so your latest changes may not be backed up yet. Keep them on this phone until you're back online. ")
                         + "Your training stays safe in your account either way. Removing it is a good idea on a phone other people use.")
                }
                Section {
                    Button {
                        busy = true
                        Haptics.impact()
                        Task { await cloud.signOut(removeHere: remove); dismiss() }
                    } label: { Text(busy ? "Signing out…" : "Sign out") }
                    .buttonStyle(DestructiveButton())
                    .disabled(busy)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Sign out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.disabled(busy)
                }
            }
        }
        .presentationDetents([.medium])
        .sheetColors()
        .interactiveDismissDisabled(busy)
        .onAppear { remove = cloud.online }
    }
}

/// Delete the account and everything stored about you in the cloud (the web app's delete-account sheet).
struct DeleteAccountSheet: View {
    @Environment(Store.self) private var store
    @Environment(Cloud.self) private var cloud
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var err = ""
    @State private var busy = ""
    @State private var confirm = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Export a copy first", systemImage: "square.and.arrow.down") }
                    }
                } header: {
                    (Text("This permanently deletes your account and everything stored about you in the cloud: your training, plans, exercises, friend code, friendships, things you've sent or received, and exercises you shared to the database. It also removes your training from this phone. ")
                     + Text("This can't be undone.").bold())
                        .font(.subheadline).foregroundStyle(Color.label2)
                        .textCase(nil).padding(.bottom, 8).padding(.horizontal, -4)
                }
                Section {
                    SecureField("Password", text: $password).textContentType(.password)
                } header: {
                    Text("Confirm with your password")
                } footer: {
                    if !err.isEmpty { Text(err).foregroundStyle(Color.red) }
                    else if !busy.isEmpty { Text(busy) }
                }
                Section {
                    Button("Delete account") {
                        guard !password.isEmpty else { Haptics.error(); err = "Enter your password."; return }
                        err = ""; Haptics.warn(); confirm = true
                    }
                    .buttonStyle(DestructiveButton())
                    .disabled(!busy.isEmpty)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }.disabled(!busy.isEmpty)
                }
            }
            .confirmationDialog("Delete your account and everything in it?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { run() }
            } message: { Text("This can't be undone.") }
        }
        .interactiveDismissDisabled(!busy.isEmpty)
        .onAppear { exportURL = store.exportBackupFile() }
    }

    private func run() {
        busy = "Confirming it's you…"
        Task {
            do {
                try await cloud.deleteAccount(password: password) { busy = $0 }
                Haptics.success()
                dismiss()
            } catch {
                busy = ""
                Haptics.error()
                let ns = error as NSError
                let c = Cloud.friendly(error)
                err = c == "Wrong email or password." ? "That password isn't right."
                    : c.hasPrefix("Couldn't reach") || ns.code == 14 ? "You're offline. Connect to the internet and try again."
                    : "Something went wrong (\(ns.code)). If some of your data was already removed, try again to finish."
            }
        }
    }
}

struct DestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.red, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? .easeOut(duration: 0.12) : Motion.pop, value: configuration.isPressed)
    }
}

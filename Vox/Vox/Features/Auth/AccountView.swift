import SwiftUI

/// Sign in, create an account, or sign out. The app works the same without an account.
struct AccountView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch auth.state {
                case .signedIn(let email, _):
                    SignedInCard(email: email)
                case .signedOut:
                    if auth.isConfigured { SignInCard() } else { NotSetUpCard() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .overScenery()
        .navigationTitle("Account")
        .onChange(of: auth.state) { Haptics.success() }
        .onChange(of: auth.errorMessage) { _, message in if message != nil { Haptics.error() } }
        .onChange(of: auth.confirmationSentTo) { _, email in if email != nil { Haptics.success() } }
    }
}

private struct SignInCard: View {
    @Environment(AuthModel.self) private var auth
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Back up and sync")
                    .font(.title3.weight(.semibold))
                Text("Vox works without an account. Sign in to keep your notes safe and use them on the web later. Everything already on this phone moves into the account.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }

            Picker("Mode", selection: $creating) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .fieldStyle()
                SecureField(creating ? "Password, at least 6 characters" : "Password", text: $password)
                    .textContentType(creating ? .newPassword : .password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .fieldStyle()
            }

            if let error = auth.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(TaskStatus.doing.tint)
            }
            if let sentTo = auth.confirmationSentTo {
                Label("Check your email. We sent a link to \(sentTo). Tap it on this phone and Vox signs you in.", systemImage: "envelope.fill")
                    .font(.footnote)
                    .foregroundStyle(TaskStatus.done.tint)
            }
            if auth.errorMessage == AuthModel.notConfirmedMessage || auth.confirmationSentTo != nil {
                Button("Send the link again") {
                    Task { await auth.resendConfirmation(email: email) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.voxAmber)
                .disabled(auth.busy || !email.contains("@"))
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if auth.busy { ProgressView().tint(.black) }
                    Text(creating ? "Create account" : "Sign in")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.08))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.voxAmber.opacity(canSubmit ? 1 : 0.4), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .voxCard(radius: 28, padding: 20)
        .animation(.snappy, value: creating)
        .onChange(of: creating) { auth.errorMessage = nil }
    }

    private var canSubmit: Bool {
        !auth.busy && email.contains("@") && password.count >= (creating ? 6 : 1)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            if creating {
                await auth.signUp(email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

private struct SignedInCard: View {
    let email: String
    @Environment(AuthModel.self) private var auth

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.voxAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                    Text(email).font(.headline).lineLimit(1)
                }
            }
            Text("Your notes, reminders and history now belong to this account. Syncing them is the next step.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            if let error = auth.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(TaskStatus.doing.tint)
            }
            Button {
                Task { await auth.signOut() }
            } label: {
                Text("Sign out")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .voxGlass(in: .rect(cornerRadius: 16), interactive: true)
                    .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(auth.busy)
            Text("Signing out keeps everything on this phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .voxCard(radius: 28, padding: 20)
    }
}

/// Shown until the project URL and key are in `SupabaseConfig`.
private struct NotSetUpCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accounts aren't set up yet", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
            Text("Everything works on this phone without one.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
        }
        .voxCard(radius: 28, padding: 20)
    }
}

private extension View {
    /// A text field on a soft glass strip.
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1) }
    }
}

import Foundation
import Observation
import Supabase

/// Signing in is optional. Signed out, everything stays on the phone and works the same.
/// Signed in, what is on the phone belongs to that account, ready for sync.
@Observable
final class AuthModel {
    enum State: Equatable {
        case signedOut
        case signedIn(email: String, userID: UUID)
    }

    private(set) var state: State = .signedOut
    /// True while a sign in, sign up or sign out is running.
    private(set) var busy = false
    var errorMessage: String?
    /// Set after signing up when the project wants the email confirmed first.
    private(set) var confirmationSentTo: String?

    /// Where the confirmation email's link goes: back into Vox. Also listed in Supabase under URL Configuration.
    static let callback = URL(string: "vox://auth-callback")!
    static let notConfirmedMessage = "Confirm your email first. Check your inbox for the link."

    /// False until the project URL and key are filled in.
    var isConfigured: Bool { client != nil }

    private let client: SupabaseClient?
    /// Runs every time someone is signed in, including when the app opens with a saved session.
    private let onSignIn: (UUID) -> Void
    private let onSignOut: () -> Void

    init(
        client: SupabaseClient? = SupabaseConfig.client,
        onSignIn: @escaping (UUID) -> Void = { _ in },
        onSignOut: @escaping () -> Void = {}
    ) {
        self.client = client
        self.onSignIn = onSignIn
        self.onSignOut = onSignOut
        Task { await watchSession() }
    }

    func signIn(email: String, password: String) async {
        await run { client in
            _ = try await client.auth.signIn(email: Self.clean(email), password: password)
        }
    }

    func signUp(email: String, password: String) async {
        await run { client in
            let response = try await client.auth.signUp(email: Self.clean(email), password: password, redirectTo: Self.callback)
            // No session yet means the project sends a confirmation email first.
            if response.session == nil { self.confirmationSentTo = Self.clean(email) }
        }
    }

    /// Sends the confirmation email again, with a link that opens Vox.
    func resendConfirmation(email: String) async {
        await run { client in
            try await client.auth.resend(email: Self.clean(email), type: .signup, emailRedirectTo: Self.callback)
            self.confirmationSentTo = Self.clean(email)
        }
    }

    /// The email link opened Vox. Finishes signing in.
    func handle(_ url: URL) async {
        guard url.scheme == Self.callback.scheme else { return }
        await run { client in _ = try await client.auth.session(from: url) }
    }

    func signOut() async {
        await run { client in try await client.auth.signOut() }
    }

    // MARK: Helpers

    /// Follows the saved session and every sign in or out.
    private func watchSession() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            if let session, !session.isExpired {
                state = .signedIn(email: session.user.email ?? "", userID: session.user.id)
                confirmationSentTo = nil
                onSignIn(session.user.id)
            } else {
                state = .signedOut
                onSignOut()
            }
        }
    }

    private func run(_ work: (SupabaseClient) async throws -> Void) async {
        guard let client else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await work(client)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func clean(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Plain words for the errors people actually hit.
    private static func message(for error: Error) -> String {
        let text = error.localizedDescription
        let lower = text.lowercased()
        if lower.contains("invalid login credentials") { return "That email and password don't match." }
        if lower.contains("email not confirmed") { return notConfirmedMessage }
        if lower.contains("already registered") { return "That email already has an account. Sign in instead." }
        if lower.contains("offline") || lower.contains("internet") { return "No internet connection. Try again when you're online." }
        return text
    }
}

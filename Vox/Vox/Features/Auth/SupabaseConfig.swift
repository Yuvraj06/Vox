import Foundation
import Supabase

/// Where the Supabase project lives. Both values are public and safe to ship in the app.
/// Never put the secret key or the service_role key here.
enum SupabaseConfig {
    /// Project URL, like https://abcdefgh.supabase.co
    static let url = "https://suzmgshfjscxzngcqjdh.supabase.co"
    /// The publishable key (sb_publishable_...) or the legacy anon key.
    static let publishableKey = "sb_publishable_fyjXegNWaquUwHkbk_TvRw_f8mBKU3H"

    /// Nil until both values above are filled in. The app then works signed out only.
    /// The session is kept in the iOS Keychain by the Supabase library.
    static let client: SupabaseClient? = {
        guard let url = URL(string: url), url.host != nil, !publishableKey.isEmpty else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
    }()
}

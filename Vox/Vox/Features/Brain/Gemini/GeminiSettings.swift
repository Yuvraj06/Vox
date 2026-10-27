import Foundation
import Observation

/// The user's own Gemini key and model. The key lives in the Keychain, the rest in UserDefaults.
@Observable
final class GeminiSettings {
    static let defaultModel = "gemini-3.5-flash-lite"
    private static let enabledKey = "gemini.enabled"
    private static let modelKey = "gemini.model"
    private static let apiKeyAccount = "gemini.apiKey"

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }

    var apiKey: String {
        didSet {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            KeychainStore.write(key.isEmpty ? nil : key, for: Self.apiKeyAccount)
        }
    }

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
        apiKey = KeychainStore.read(Self.apiKeyAccount) ?? ""
    }

    /// A client to call, or nil when Gemini is off or has no key.
    var client: GeminiClient? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !key.isEmpty else { return nil }
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return GeminiClient(apiKey: key, model: name.isEmpty ? Self.defaultModel : name)
    }
}

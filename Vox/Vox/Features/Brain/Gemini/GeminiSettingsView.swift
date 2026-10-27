import SwiftUI

/// Settings, inside Thinking: the user's own Gemini key, the model, and a connection test.
struct GeminiSettingsView: View {
    @Environment(GeminiSettings.self) private var settings
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Use Gemini", isOn: $settings.enabled)
            } footer: {
                Text("Gemini gets 3 seconds to plan each command. If it is slower, the on-device plan is shown and Gemini checks it in Thinking.")
            }

            Section {
                SecureField("Paste your API key", text: $settings.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("Get a free key from Google AI Studio", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("API key")
            } footer: {
                Text("Stored in the iOS Keychain on this phone.")
            }

            Section {
                TextField(GeminiSettings.defaultModel, text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Model")
            } footer: {
                Text("Leave as \(GeminiSettings.defaultModel) unless you know you want another. Faster models beat the 3 second window more often.")
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing || settings.client == nil)
                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Your commands and the titles of your lists and items are sent to Google. Note text is not. On the free tier, Google may use what you send to improve its products.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Plans a sample command and reports how long it took, so you can see if it fits in 3 seconds.
    private func test() async {
        guard let client = settings.client else { return }
        testing = true
        testResult = nil
        let start = ContinuousClock.now
        do {
            let actions = try await client.plan(command: "Add Dune to movies I watched", outline: "n1 Movies Watched (list)")
            let elapsed = ContinuousClock.now - start
            let ms = Int(elapsed / .milliseconds(1))
            let fits = elapsed <= Brain.geminiWindow ? "fits in the 3 second window" : "slower than 3 seconds"
            let right = actions.first.map { $0.type == .addItem && $0.parent == "n1" } == true
            testResult = "Connected in \(ms) ms, \(fits)." + (right ? " The sample command came back right." : " The sample answer looked off.")
        } catch {
            testResult = error.localizedDescription
        }
        testing = false
    }
}

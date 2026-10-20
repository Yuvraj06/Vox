import SwiftUI

/// Slice 0 test screen, kept around for checking speech. Replaced by the real capture UI in Slice 3.
struct SpeechTestView: View {
    @State private var spike = SpeechSpike()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    Task {
                        if spike.isRunning { await spike.stop() } else { await spike.start() }
                    }
                } label: {
                    Text(spike.isRunning ? "Stop" : "Start listening")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(spike.isRunning ? .red : .blue)
                .controlSize(.large)

                Text("Status: \(spike.status)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(spike.finalText + spike.partialText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(.quaternary, in: .rect(cornerRadius: 8))

                Text("Log (newest first)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(spike.log, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                }
                .listStyle(.plain)
            }
            .padding()
            .navigationTitle("Speech test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            if spike.isRunning { await spike.stop() }
                            dismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            spike.appPhase = "\(newPhase)"
            spike.addLog("App is now \(newPhase)")
        }
    }
}

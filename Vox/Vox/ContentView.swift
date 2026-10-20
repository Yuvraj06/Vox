import SwiftUI

/// Slice 0 test screen. Replaced by the real root view in Slice 1.
struct ContentView: View {
    @State private var spike = SpeechSpike()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Slice 0: background speech test")
                .font(.headline)

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
        .onChange(of: scenePhase) { _, newPhase in
            spike.appPhase = "\(newPhase)"
            spike.addLog("App is now \(newPhase)")
        }
    }
}

#Preview {
    ContentView()
}

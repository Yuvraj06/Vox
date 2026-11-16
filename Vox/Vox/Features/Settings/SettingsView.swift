import SwiftUI

/// Everything behind the gear: Thinking, History, Account, and how the glass looks.
struct SettingsView: View {
    @Environment(ThinkingQueue.self) private var queue
    @Environment(GeminiSettings.self) private var gemini
    @Environment(AuthModel.self) private var auth
    @Environment(SyncEngine.self) private var sync

    @AppStorage(GlassLook.darknessKey) private var darkness = GlassLook.defaultDarkness
    @AppStorage(GlassLook.frostKey) private var frost = GlassLook.defaultFrost
    @State private var showingThinking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Brain") {
                    Button { showingThinking = true } label: {
                        SettingsRow(icon: "brain", title: "Thinking", subtitle: thinkingSubtitle) {
                            if busyCount > 0 {
                                Text("\(busyCount) running")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.voxAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.voxAccent.opacity(0.16), in: .capsule)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                section("Activity") {
                    NavigationLink(value: Route.history) {
                        SettingsRow(icon: "clock.arrow.circlepath", title: "History", subtitle: "Every command, undo any of them")
                    }
                    .buttonStyle(.plain)
                }
                section("Account") {
                    NavigationLink(value: Route.account) {
                        SettingsRow(icon: "person.crop.circle", title: "Account", subtitle: accountSubtitle)
                    }
                    .buttonStyle(.plain)
                }
                section("Appearance") { glassControls }
                Text("Vox \(Self.version)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .overScenery()
        .navigationTitle("Settings")
        .sheet(isPresented: $showingThinking) { ThinkingView() }
    }

    // MARK: Sections

    /// A small caps label over one glass card.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0, content: content)
                .voxCard(radius: 24, padding: 16)
        }
    }

    /// A preview over the scenery, then a slider for how dark and one for how frosted.
    private var glassControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Glass").font(.headline)
                Spacer()
                Button("Reset") {
                    withAnimation(.smooth) {
                        darkness = GlassLook.defaultDarkness
                        frost = GlassLook.defaultFrost
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.voxAccent)
                .disabled(darkness == GlassLook.defaultDarkness && frost == GlassLook.defaultFrost)
            }
            GlassPreview()
            GlassSlider(
                title: "Darkness",
                caption: "How much the glass darkens the scenery",
                low: "sun.max",
                high: "moon",
                value: $darkness
            )
            GlassSlider(
                title: "Frost",
                caption: "How blurry the scenery looks through it",
                low: "drop",
                high: "snowflake",
                value: $frost
            )
        }
    }

    // MARK: Text

    private var busyCount: Int { queue.activeCount + queue.waitingCount }

    private var thinkingSubtitle: String {
        gemini.enabled ? "Live checks, Gemini on" : "Live checks and Gemini key"
    }

    private var accountSubtitle: String {
        guard case .signedIn(let email, _) = auth.state else { return "Not signed in, sync is off" }
        guard let last = sync.lastSynced else { return email }
        return "Synced \(last.formatted(.relative(presentation: .named)))"
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Icon tile, title and subtitle, an optional accessory, and a chevron.
private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A strip of scenery with a glass chip on it, so the sliders show their effect right away.
private struct GlassPreview: View {
    var body: some View {
        Image("Scenery")
            .resizable()
            .scaledToFill()
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .leading) {
                Label("This is how cards look", systemImage: "drop")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .voxGlass(in: .rect(cornerRadius: 16))
                    .padding(.leading, 16)
            }
            .clipShape(.rect(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

/// Title and percent, then the slider between two icons, then what it does.
private struct GlassSlider: View {
    let title: String
    let caption: String
    let low: String
    let high: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 15, weight: .medium))
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: 0...1) {
                Text(title)
            } minimumValueLabel: {
                Image(systemName: low).foregroundStyle(.white.opacity(0.5))
            } maximumValueLabel: {
                Image(systemName: high).foregroundStyle(.white.opacity(0.5))
            }
            .tint(.voxAccent)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

import AudioToolbox
import CoreHaptics
import SwiftUI
import UIKit

/// Every haptic in the app, so they feel like one family.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    /// Any tap.
    static func tap() { light.impactOccurred(intensity: 0.7) }
    /// Something landed, like a card dropped in a column.
    static func thud() { medium.impactOccurred() }
    static func success() { notice.notificationOccurred(.success) }
    static func warning() { notice.notificationOccurred(.warning) }
    static func error() { notice.notificationOccurred(.error) }

    // MARK: Task done

    private static var engine: CHHapticEngine?
    private static var ting: SystemSoundID = {
        var id: SystemSoundID = 0
        if let url = Bundle.main.url(forResource: "ting", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
        }
        return id
    }()

    /// Ticking off a task: a quick rising ripple, then a big hit that rings out, with a bell.
    /// The bell follows the ringer switch, so it stays quiet on silent.
    static func taskDone() {
        let hit = 0.2
        DispatchQueue.main.asyncAfter(deadline: .now() + hit) {
            if ting != 0 { AudioServicesPlaySystemSound(ting) }
        }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = startedEngine() else {
            success()
            return
        }
        do {
            let player = try engine.makePlayer(with: try donePattern(hit: hit))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            success()
        }
    }

    private static func donePattern(hit: TimeInterval) throws -> CHHapticPattern {
        func event(_ type: CHHapticEvent.EventType, at time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval = 0) -> CHHapticEvent {
            CHHapticEvent(
                eventType: type,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time,
                duration: duration
            )
        }
        // Five clicks getting stronger and sharper, like a ratchet winding up.
        let ripple = (0..<5).map { step in
            event(.hapticTransient, at: Double(step) * 0.035, intensity: 0.35 + 0.12 * Float(step), sharpness: 0.4 + 0.12 * Float(step))
        }
        // The hit, then a bright buzz that fades like a bell.
        let ring = 0.4
        let events = ripple + [
            event(.hapticTransient, at: hit, intensity: 1, sharpness: 1),
            event(.hapticContinuous, at: hit, intensity: 0.7, sharpness: 0.85, duration: ring),
            event(.hapticTransient, at: hit + 0.09, intensity: 0.5, sharpness: 0.9),
        ]
        let fade = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: ring * 0.3, value: 0.45),
                .init(relativeTime: ring, value: 0),
            ],
            relativeTime: hit
        )
        return try CHHapticPattern(events: events, parameterCurves: [fade])
    }

    /// One engine for the whole app. It restarts itself if the system stops it.
    private static func startedEngine() -> CHHapticEngine? {
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { try? engine?.start() }
        }
        try? engine?.start()
        return engine
    }
}

// MARK: Every tap

/// Puts a light tap under every touch in the app, sheets and menus included.
/// It only listens: buttons, scrolling, dragging and the mic work exactly as before.
struct TapHaptics: UIViewRepresentable {
    func makeUIView(context: Context) -> Listener { Listener() }
    func updateUIView(_ uiView: Listener, context: Context) {}

    final class Listener: UIView, UIGestureRecognizerDelegate {
        private static let name = "vox.tapHaptics"

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0.name == Self.name }) else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.name = Self.name
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func tapped() { Haptics.tap() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    /// A light tap for every touch in the window this view is in.
    func tapHaptics() -> some View {
        background { TapHaptics().allowsHitTesting(false).frame(width: 0, height: 0) }
    }
}

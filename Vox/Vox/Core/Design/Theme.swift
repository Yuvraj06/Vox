import SwiftUI

/// Status colors taken from the scenery: sky, sunlit ridge, glacier.
extension TaskStatus {
    var tint: Color {
        switch self {
        case .todo: Color(red: 0.58, green: 0.68, blue: 0.82)   // misty slate blue
        case .doing: Color(red: 0.97, green: 0.68, blue: 0.32)  // sunrise amber
        case .done: Color(red: 0.55, green: 0.82, blue: 0.70)   // glacier sage
        }
    }
}

extension Color {
    /// The one accent: the mic, the countdown, buttons that move you forward. A glowing ice blue.
    static let voxAccent = Color(red: 0.55, green: 0.85, blue: 1.0)   // #8CD9FF
    /// Dark text on the accent.
    static let voxInk = Color(red: 0.04, green: 0.09, blue: 0.14)
    /// Errors. Soft, so it reads on dark glass without shouting.
    static let voxError = Color(red: 1.0, green: 0.55, blue: 0.52)
    /// Folders with no color picked yet.
    static let voxFolder = Color(red: 0.56, green: 0.66, blue: 0.85)  // #8FA8D8
}

/// How the glass looks. Set with the sliders in Settings.
enum GlassLook {
    static let darknessKey = "glassDarkness"
    static let frostKey = "glassFrost"
    static let defaultDarkness = 0.6
    static let defaultFrost = 0.3
}

/// Smoky glass: you see the scenery through it, darkened so text stays readable.
/// Frost blurs the scenery more. A faint sheen at the top left, and an edge that is
/// bright where the light hits and faint on the far side.
private struct VoxGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false

    @AppStorage(GlassLook.darknessKey) private var darkness = GlassLook.defaultDarkness
    @AppStorage(GlassLook.frostKey) private var frost = GlassLook.defaultFrost
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            // Sits on the glass, under the content.
            .background {
                ZStack {
                    if frost > 0.01 {
                        shape.fill(.ultraThinMaterial).opacity(frost)
                    }
                    shape.fill(Color.black.opacity(reduceTransparency ? 0.8 : darkness * 0.6))
                    shape.fill(LinearGradient(
                        colors: [.white.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    ))
                }
            }
            .glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.06), .white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// The app's clear glass in any shape.
    func voxGlass(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        modifier(VoxGlass(shape: shape, interactive: interactive))
    }

    /// A clear glass panel, like the home screen cards.
    func voxCard(radius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .voxGlass(in: .rect(cornerRadius: radius))
    }
}

/// A round 40 pt glass icon, for buttons in a screen's own header.
struct GlassCircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 40, height: 40)
            .voxGlass(in: .circle)
            .contentShape(.circle)
    }
}

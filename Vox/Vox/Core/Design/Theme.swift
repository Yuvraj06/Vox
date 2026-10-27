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
    /// The one accent: alarms, the countdown label, progress.
    static let voxAmber = Color(red: 0.95, green: 0.69, blue: 0.29)   // #F2B04A
    /// Icon tints on the home screen's notes card.
    static let voxFolder = Color(red: 0.56, green: 0.66, blue: 0.85)  // #8FA8D8
    static let voxList = Color(red: 0.91, green: 0.63, blue: 0.42)    // #E8A06A
    static let voxBoard = Color(red: 0.49, green: 0.77, blue: 0.60)   // #7CC59A
}

/// Clear glass: you see the scenery through it. A soft sheen at the top left,
/// and an edge that is bright where the light hits and faint on the far side.
private struct VoxGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false

    func body(content: Content) -> some View {
        content
            // Sits on the glass, under the content.
            .background {
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.14), location: 0),
                        .init(color: .white.opacity(0.03), location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
            .glassEffect(interactive ? .clear.interactive() : .clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1), .white.opacity(0.25)],
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

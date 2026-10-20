import SwiftUI
import UIKit

/// Full-screen scenic background. Uses the "Scenery" image from Assets if it exists,
/// otherwise a calm mountain scene drawn in code.
struct SceneryBackground: View {
    private static let hasPhoto = UIImage(named: "Scenery") != nil

    var body: some View {
        GeometryReader { geo in
            Group {
                if Self.hasPhoto {
                    Image("Scenery")
                        .resizable()
                        .scaledToFill()
                } else {
                    DrawnMountains()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Darken the top and bottom a little so text on glass stays readable.
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.45), .black.opacity(0.05), .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Fallback scene: moody sky, golden glow, layered snowy ridges, mist.
struct DrawnMountains: View {
    private struct Ridge {
        let points: [(x: Double, y: Double)]
        let top: Color
        let bottom: Color
    }

    private let ridges: [Ridge] = [
        Ridge(
            points: [(0, 0.52), (0.18, 0.44), (0.34, 0.5), (0.55, 0.38), (0.72, 0.47), (0.88, 0.42), (1, 0.48)],
            top: Color(white: 0.78), bottom: Color(white: 0.55)
        ),
        Ridge(
            points: [(0, 0.62), (0.22, 0.5), (0.4, 0.58), (0.62, 0.46), (0.8, 0.57), (1, 0.53)],
            top: Color(white: 0.92), bottom: Color(white: 0.42)
        ),
        Ridge(
            points: [(0, 0.74), (0.25, 0.64), (0.45, 0.7), (0.7, 0.6), (1, 0.72)],
            top: Color(red: 0.36, green: 0.38, blue: 0.42), bottom: Color(red: 0.12, green: 0.13, blue: 0.15)
        ),
    ]

    var body: some View {
        Canvas { context, size in
            let full = CGRect(origin: .zero, size: size)

            // Sky.
            let sky = Gradient(colors: [
                Color(red: 0.14, green: 0.15, blue: 0.18),
                Color(red: 0.42, green: 0.44, blue: 0.48),
                Color(red: 0.92, green: 0.74, blue: 0.44),
            ])
            context.fill(Path(full), with: .linearGradient(
                sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.55)
            ))

            // Sun glow behind the peaks.
            let sun = CGPoint(x: size.width * 0.7, y: size.height * 0.44)
            context.fill(Path(full), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.55).opacity(0.85), .clear]),
                center: sun, startRadius: 0, endRadius: size.width * 0.55
            ))

            // Ridges, back to front.
            for ridge in ridges {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for point in ridge.points {
                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                let minY = (ridge.points.map(\.y).min() ?? 0.5) * size.height
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [ridge.top, ridge.bottom]),
                    startPoint: CGPoint(x: 0, y: minY),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }

            // Mist in the valley.
            let mist = CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.15)
            context.fill(Path(mist), with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.18), .clear]),
                startPoint: CGPoint(x: 0, y: mist.minY),
                endPoint: CGPoint(x: 0, y: mist.maxY)
            ))
        }
    }
}

extension View {
    /// Puts the scenery behind a screen and hides the default list background.
    func sceneryBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { SceneryBackground() }
    }

    /// A list row drawn as a floating glass card. `indent` shifts it right for tree levels.
    func glassRow(indent: CGFloat = 0) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16 + indent, bottom: 5, trailing: 16))
    }
}

#Preview {
    SceneryBackground()
}

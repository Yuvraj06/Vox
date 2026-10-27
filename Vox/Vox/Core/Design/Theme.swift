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

extension View {
    /// A frosted glass panel with a faint white edge, like the home screen cards.
    func voxCard(radius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
    }
}

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

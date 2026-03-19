import SwiftUI

extension Color {
    static func appNamed(_ name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray", "grey": return .gray
        default: return .accentColor
        }
    }
}

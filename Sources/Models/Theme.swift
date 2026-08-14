import SwiftUI

/// Brand palette — matches the app icon (indigo-blue gradient, amber accent).
enum Theme {
    static let accent = Color(red: 0.23, green: 0.36, blue: 0.92)
    static let accentDeep = Color(red: 0.16, green: 0.24, blue: 0.75)
    static let warm = Color(red: 1.0, green: 0.72, blue: 0.25)

    /// The mic-button / hero gradient.
    static let heroGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

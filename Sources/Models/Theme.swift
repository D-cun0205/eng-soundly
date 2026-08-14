import SwiftUI
import UIKit

/// Brand palette — matches the app icon (indigo-blue gradient, amber accent).
enum Theme {
    /// Adaptive brand accent: deep indigo in light mode, lifted for
    /// contrast against dark backgrounds.
    static let accent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.58, blue: 1.0, alpha: 1)
            : UIColor(red: 0.23, green: 0.36, blue: 0.92, alpha: 1)
    })
    static let accentDeep = Color(red: 0.16, green: 0.24, blue: 0.75)
    static let warm = Color(red: 1.0, green: 0.72, blue: 0.25)

    /// The mic-button / hero gradient.
    static let heroGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

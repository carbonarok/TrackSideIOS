import SwiftUI
import UIKit

/// TrackSide's colours, taken from the app icon: a deep navy, and the
/// green of a signal showing clear. The accent colour (buttons, links, the
/// selected tab) is the navy, lightened in dark mode so it reads on black.
extension Color {
    /// The icon's navy, for large areas such as the welcome screen.
    static let brandNavy = Color(red: 17 / 255, green: 39 / 255, blue: 97 / 255)
    /// The icon's signal green.
    static let signalGreen = Color(red: 48 / 255, green: 159 / 255, blue: 91 / 255)
    /// "On time", and other good news, as text: the signal green, darkened
    /// in light mode to reach 4.5:1 on white.
    static let onTime = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.77, blue: 0.48, alpha: 1)
            : UIColor(red: 0.12, green: 0.47, blue: 0.27, alpha: 1)
    })
}

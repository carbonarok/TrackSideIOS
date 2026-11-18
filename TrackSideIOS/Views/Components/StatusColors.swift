import SwiftUI
import UIKit

/// Colours for train status. The system yellow, orange, red and blue are
/// too faint as text on white (yellow is about 1.5:1, orange 2.2:1), which
/// matters on a bright platform; in light mode these are darker shades
/// that reach at least 4.5:1, the WCAG minimum for small text. Dark mode
/// keeps the system colours, which are already clear on black.
extension Color {
    /// A delay of a few minutes.
    static let delayMinor = adaptive(light: UIColor(red: 0.60, green: 0.38, blue: 0.00, alpha: 1), dark: .systemYellow)
    /// A delay of 5–9 minutes, or a platform change.
    static let delayModerate = adaptive(light: UIColor(red: 0.72, green: 0.29, blue: 0.00, alpha: 1), dark: .systemOrange)
    /// A delay of 10 minutes or more, or a cancellation.
    static let delaySevere = adaptive(light: UIColor(red: 0.75, green: 0.15, blue: 0.11, alpha: 1), dark: .systemRed)
    /// A confirmed platform.
    static let platformConfirmed = adaptive(light: UIColor(red: 0.04, green: 0.36, blue: 0.77, alpha: 1), dark: .systemBlue)

    /// The colour for a delay of this many minutes.
    static func delay(minutes: Int) -> Color {
        if minutes >= 10 { return .delaySevere }
        if minutes >= 5 { return .delayModerate }
        return .delayMinor
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

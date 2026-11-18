import SwiftUI

/// How much a toolbar item matters when a bar runs out of room, as on the
/// iPhone Duo's vertical bars: low-priority items go to the overflow menu
/// first, high-priority ones last.
enum ToolbarItemImportance {
    case low, high
}

extension ToolbarContent {
    /// Sets the item's visibility priority where the system supports it
    /// (iOS 27), and does nothing before.
    @ToolbarContentBuilder
    func keepsVisible(_ importance: ToolbarItemImportance) -> some ToolbarContent {
        if #available(iOS 27.0, *) {
            visibilityPriority(importance == .high ? .high : .low)
        } else {
            self
        }
    }
}

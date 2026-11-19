import Foundation

/// What a tracked journey's Live Activity shows, and journey planning
/// preferences.
///
/// Kept in the App Group's defaults, which the widget extension shares:
/// the Live Activity reads the display switches each time it's drawn, so a
/// change shows on a journey already being tracked.
struct LiveActivitySettings: Codable, Equatable {
    // Live Activity display
    var showCountdown: Bool = true
    var showNextConnection: Bool = true
    var showProgressBar: Bool = true
    var showOperatorName: Bool = true
    var showPlatformBadge: Bool = true
    var showDelayBadge: Bool = true
    var showFinalArrival: Bool = true

    // Journey planning
    var minimumConnectionMinutes: Int = 5

    private static let storageKey = "liveActivitySettings"

    /// The App Group's defaults, shared with the widget extension.
    private static var defaults: UserDefaults {
        (Bundle.main.object(forInfoDictionaryKey: "TrackSideAppGroup") as? String)
            .flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func load() -> LiveActivitySettings {
        // Settings saved before they moved to the App Group are still
        // read from the app's own defaults.
        guard let data = defaults.data(forKey: storageKey) ?? UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(LiveActivitySettings.self, from: data) else {
            return LiveActivitySettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            Self.defaults.set(data, forKey: Self.storageKey)
        }
    }
}

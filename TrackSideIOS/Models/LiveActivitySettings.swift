import Foundation

/// User preferences stored in UserDefaults for persistence across app launches.
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

    static func load() -> LiveActivitySettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(LiveActivitySettings.self, from: data) else {
            return LiveActivitySettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

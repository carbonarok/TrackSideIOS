import Foundation

/// Which parts of a tracked journey's Live Activity to show, as chosen in
/// the app's Settings. The app saves them to the App Group's defaults; the
/// Live Activity reads them each time it's drawn, so a change shows on a
/// journey already being tracked once the app redraws it.
nonisolated struct LiveActivityDisplay: Decodable {
    var showCountdown = true
    var showNextConnection = true
    var showProgressBar = true
    var showOperatorName = true
    var showPlatformBadge = true
    var showDelayBadge = true
    var showFinalArrival = true

    init() {}

    /// Each switch on unless saved off, so settings saved by an older app
    /// (without one of them) still read.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showCountdown = try container.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? true
        showNextConnection = try container.decodeIfPresent(Bool.self, forKey: .showNextConnection) ?? true
        showProgressBar = try container.decodeIfPresent(Bool.self, forKey: .showProgressBar) ?? true
        showOperatorName = try container.decodeIfPresent(Bool.self, forKey: .showOperatorName) ?? true
        showPlatformBadge = try container.decodeIfPresent(Bool.self, forKey: .showPlatformBadge) ?? true
        showDelayBadge = try container.decodeIfPresent(Bool.self, forKey: .showDelayBadge) ?? true
        showFinalArrival = try container.decodeIfPresent(Bool.self, forKey: .showFinalArrival) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case showCountdown, showNextConnection, showProgressBar, showOperatorName
        case showPlatformBadge, showDelayBadge, showFinalArrival
    }

    static var current: LiveActivityDisplay {
        let group = Bundle.main.object(forInfoDictionaryKey: "TrackSideAppGroup") as? String
        guard let defaults = group.flatMap({ UserDefaults(suiteName: $0) }),
              let data = defaults.data(forKey: "liveActivitySettings"),
              let display = try? JSONDecoder().decode(LiveActivityDisplay.self, from: data)
        else { return LiveActivityDisplay() }
        return display
    }
}

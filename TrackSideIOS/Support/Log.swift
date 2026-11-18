import Foundation
import os

/// Where the app writes what it's doing. Unlike `print`, this is kept on
/// the phone: connect it to a Mac and open Console.app, filter by the
/// subsystem, to see what happened during a journey after the fact.
///
/// Values are public unless they identify the server or the device, such
/// as its address or push tokens.
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TrackSide"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let live = Logger(subsystem: subsystem, category: "live")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let boards = Logger(subsystem: subsystem, category: "boards")
    static let journeys = Logger(subsystem: subsystem, category: "journeys")
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
    static let push = Logger(subsystem: subsystem, category: "push")
}

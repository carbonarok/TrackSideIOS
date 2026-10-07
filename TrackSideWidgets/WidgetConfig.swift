import Foundation

/// Shared configuration for the widget extension
/// Must be kept in sync with the main app's AppConfig
enum AppConfig {
    static var baseURL: URL {
        URL(string: "https://trackside.example.com/")!
    }
}

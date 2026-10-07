import Foundation

enum AppConfig {
    static var baseURL: URL {
        URL(string: "https://trackside.example.com/")!
    }

    static var webSocketURL: URL {
        URL(string: "wss://trackside.example.com/v1/live")!
    }
}

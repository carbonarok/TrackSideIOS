import UIKit
import UserNotifications

/// The device's own APNs token, for normal notifications from the server.
/// (A Live Activity's push token is separate and can't show a notification.)
enum PushDeviceToken {
    private(set) static var hex: String?

    static func set(_ token: Data) {
        hex = token.map { String(format: "%02x", $0) }.joined()
        print("[Push] Device token: \(hex?.prefix(16) ?? "")...")
    }

    /// The token, waiting up to `timeout` for iOS to hand it over at launch.
    static func value(timeout: Duration = .seconds(5)) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while hex == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return hex
    }
}

/// Registers for remote notifications and shows them while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushDeviceToken.set(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] Remote notification registration failed: \(error.localizedDescription)")
    }

    /// Platform changes and delays should show even with the app on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

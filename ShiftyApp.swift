import SwiftUI
import UserNotifications
import Combine

class NotificationHandler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var lastNotificationId: String?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let shiftId = response.notification.request.identifier
        print("Notification tapped for shift: \(shiftId)")
        lastNotificationId = shiftId
        completionHandler()
    }
}

@main
struct ShiftyApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var notificationHandler = NotificationHandler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(settingsManager)
                .environmentObject(notificationHandler)
                .withAppColorScheme()
                .accentColor(settingsManager.accentColor)
                .onChange(of: settingsManager.colorScheme) { _ in
                    updateColorScheme()
                }
                .onChange(of: settingsManager.accentColor) { _ in
                    // This will ensure the app updates when the accent color changes
                }
                .onAppear {
                    setupNotifications()
                }
        }
    }

    private func updateColorScheme() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }

        switch settingsManager.colorScheme {
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        case .unspecified:
            window.overrideUserInterfaceStyle = .unspecified
        }
    }

    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = notificationHandler
    }
}

// Add this extension to your AppColor struct
extension AppColor {
    static func forScheme(_ scheme: AppColorScheme) -> AppColor {
        switch scheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .unspecified:
            return .light  // Default to light, or you could use a system-based default
        }
    }
}

// You might want to add this extension to handle custom notifications within your app
extension Notification.Name {
    static let openShiftDetail = Notification.Name("openShiftDetail")
}

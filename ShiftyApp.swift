import SwiftUI

@main
struct ShiftyApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var settingsManager = SettingsManager()
    
    // Define accent colors
    let accentColors: [Color] = [.blue, .red, .green, .orange, .purple, .pink]

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(settingsManager)
                .withAppColorScheme()  // Apply our custom color scheme
                .accentColor(accentColors[settingsManager.accentColorIndex])
                .onChange(of: settingsManager.colorScheme) { _ in
                    updateColorScheme()
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


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
                .preferredColorScheme(colorScheme)
                .accentColor(accentColors[settingsManager.accentColor])
                .onChange(of: settingsManager.colorScheme) { _ in
                    updateColorScheme()
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch settingsManager.colorScheme {
        case .light:
            return .light
        case .dark:
            return .dark
        case .unspecified:
            return nil
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

// Define AppColorScheme if it's not in a separate file
enum AppColorScheme: Int {
    case unspecified = 0
    case light = 1
    case dark = 2
}

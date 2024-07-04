import SwiftUI

@main
struct ShiftyApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(settingsManager)
        }
    }
}

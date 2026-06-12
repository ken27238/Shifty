//
//  ShiftyWatchApp.swift
//  ShiftyWatch
//

import SwiftUI
import SwiftData

@main
struct ShiftyWatchApp: App {
    var sharedModelContainer: ModelContainer = {
        AppSettings.registerDefaults()

        let schema = Schema.shifty
        // The watch keeps its own store; CloudKit syncs it with the phone.
        let syncEnabled = UserDefaults.shared.bool(forKey: SettingsKeys.iCloudSyncEnabled)
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: syncEnabled ? .automatic : .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            return container
        }

        let localConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

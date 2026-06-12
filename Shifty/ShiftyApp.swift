//
//  ShiftyApp.swift
//  Shifty
//

import SwiftUI
import SwiftData

@main
struct ShiftyApp: App {
    var sharedModelContainer: ModelContainer = {
        AppSettings.registerDefaults()

        let schema = Schema([
            Shift.self,
            Job.self,
        ])
        let syncEnabled = UserDefaults.shared.bool(forKey: SettingsKeys.iCloudSyncEnabled)

        // The app group container is shared with the widget extension;
        // CloudKit keeps it in sync across the user's devices.
        let groupConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: syncEnabled ? .automatic : .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [groupConfiguration]) {
            return container
        }

        // Fall back: app group without CloudKit, then the default local store.
        let localGroupConfiguration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [localGroupConfiguration]) {
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

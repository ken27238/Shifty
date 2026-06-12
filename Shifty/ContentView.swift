//
//  ContentView.swift
//  Shifty
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home
    case shifts
    case calendar
    case pay
    case settings
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    /// A week the Pay tab should jump to, set when navigating from Shifts.
    @State private var payRequestDate: Date?
    /// A job the Shifts tab should filter to, set when navigating from Pay.
    @State private var shiftsJobFilterRequest: String?
    /// Asks Home to open the new-shift form (⌘N from anywhere).
    @State private var addShiftRequest = false

    @Query(sort: \Shift.start) private var shifts: [Shift]
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderLeadMinutes") private var reminderLeadMinutes = 60
    @AppStorage(SettingsKeys.appearance, store: .shared) private var appearance = "system"
    @AppStorage(SettingsKeys.accentColorName, store: .shared) private var accentColorName = ""

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var upcomingShifts: [Shift] {
        shifts.filter { $0.start > .now }
    }

    /// Re-syncs reminders whenever shifts or reminder settings change.
    private var reminderSyncKey: Int {
        var hasher = Hasher()
        hasher.combine(remindersEnabled)
        hasher.combine(reminderLeadMinutes)
        for shift in upcomingShifts {
            hasher.combine(shift.start)
            hasher.combine(shift.job?.name)
        }
        return hasher.finalize()
    }

    /// Hidden buttons providing hardware-keyboard shortcuts on iPad.
    private var keyboardShortcuts: some View {
        Group {
            Button("New Shift") {
                selectedTab = .home
                addShiftRequest = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Home") { selectedTab = .home }
                .keyboardShortcut("1", modifiers: .command)
            Button("Shifts") { selectedTab = .shifts }
                .keyboardShortcut("2", modifiers: .command)
            Button("Calendar") { selectedTab = .calendar }
                .keyboardShortcut("3", modifiers: .command)
            Button("Pay") { selectedTab = .pay }
                .keyboardShortcut("4", modifiers: .command)
            Button("Settings") { selectedTab = .settings }
                .keyboardShortcut("5", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(selectedTab: $selectedTab, addShiftRequest: $addShiftRequest)
            }
            Tab("Shifts", systemImage: "clock", value: .shifts) {
                ShiftsView(
                    selectedTab: $selectedTab,
                    payRequestDate: $payRequestDate,
                    jobFilterRequest: $shiftsJobFilterRequest
                )
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }
            Tab("Pay", systemImage: "banknote", value: .pay) {
                PayView(
                    selectedTab: $selectedTab,
                    requestedDate: $payRequestDate,
                    jobFilterRequest: $shiftsJobFilterRequest
                )
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background { keyboardShortcuts }
        .onOpenURL { url in
            // Deep links from widgets: shifty://<destination>
            switch url.host() ?? url.lastPathComponent {
            case "home": selectedTab = .home
            case "shifts": selectedTab = .shifts
            case "calendar": selectedTab = .calendar
            case "pay": selectedTab = .pay
            case "settings": selectedTab = .settings
            case "newshift":
                selectedTab = .home
                addShiftRequest = true
            default: break
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(accentColorName.isEmpty ? nil : Job.palette[accentColorName])
        .task(id: reminderSyncKey) {
            await ReminderScheduler.sync(
                upcomingShifts: upcomingShifts,
                enabled: remindersEnabled,
                leadMinutes: reminderLeadMinutes
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

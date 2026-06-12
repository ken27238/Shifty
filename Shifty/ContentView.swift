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

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(selectedTab: $selectedTab)
            }
            Tab("Shifts", systemImage: "clock", value: .shifts) {
                ShiftsView(selectedTab: $selectedTab, payRequestDate: $payRequestDate)
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }
            Tab("Pay", systemImage: "banknote", value: .pay) {
                PayView(requestedDate: $payRequestDate)
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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

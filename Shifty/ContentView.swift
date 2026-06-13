//
//  ContentView.swift
//  Shifty
//

import SwiftUI
import SwiftData

enum AppTab: Hashable, CaseIterable, Identifiable {
    case home
    case shifts
    case calendar
    case pay
    case settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .shifts: "Shifts"
        case .calendar: "Calendar"
        case .pay: "Pay"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .shifts: "clock"
        case .calendar: "calendar"
        case .pay: "banknote"
        case .settings: "gear"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = {
        // `-startSection pay` etc. jumps straight to a section (screenshots).
        switch UserDefaults.standard.string(forKey: "startSection") {
        case "shifts": .shifts
        case "calendar": .calendar
        case "pay": .pay
        case "settings": .settings
        default: .home
        }
    }()
    /// A week the Pay tab should jump to, set when navigating from Shifts.
    @State private var payRequestDate: Date?
    /// A job the Shifts tab should filter to, set when navigating from Pay.
    @State private var shiftsJobFilterRequest: String?
    /// Asks Home to open the new-shift form (⌘N from anywhere).
    @State private var addShiftRequest = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start) private var shifts: [Shift]
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderLeadMinutes") private var reminderLeadMinutes = 60
    @AppStorage("tipRemindersEnabled") private var tipRemindersEnabled = false
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled = false
    // The weekly summary's totals depend on these, so reschedule on change.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false
    @AppStorage(SettingsKeys.overtimeThreshold, store: .shared) private var overtimeThreshold = 40.0
    @AppStorage(SettingsKeys.overtimeMultiplier, store: .shared) private var overtimeMultiplier = 1.5
    @AppStorage(SettingsKeys.overtimeWeekly, store: .shared) private var overtimeWeekly = true
    @AppStorage(SettingsKeys.appearance, store: .shared) private var appearance = "system"
    @AppStorage(SettingsKeys.accentColorName, store: .shared) private var accentColorName = ""

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// iPad and wide layouts get a persistent sidebar split view; compact
    /// widths keep the tab bar.
    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    /// Re-syncs reminders whenever shifts or reminder settings change.
    private var reminderSyncKey: Int {
        var hasher = Hasher()
        hasher.combine(remindersEnabled)
        hasher.combine(reminderLeadMinutes)
        hasher.combine(tipRemindersEnabled)
        hasher.combine(weeklySummaryEnabled)
        hasher.combine(weekStartDay)
        hasher.combine(overtimeEnabled)
        hasher.combine(overtimeThreshold)
        hasher.combine(overtimeMultiplier)
        hasher.combine(overtimeWeekly)
        for shift in shifts where shift.end > .now {
            hasher.combine(shift.start)
            hasher.combine(shift.end)
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

    /// The view for one section, reused by the tab bar and the split detail.
    @ViewBuilder
    private func section(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(selectedTab: $selectedTab, addShiftRequest: $addShiftRequest)
        case .shifts:
            ShiftsView(
                selectedTab: $selectedTab,
                payRequestDate: $payRequestDate,
                jobFilterRequest: $shiftsJobFilterRequest
            )
        case .calendar:
            CalendarView()
        case .pay:
            PayView(
                selectedTab: $selectedTab,
                requestedDate: $payRequestDate,
                jobFilterRequest: $shiftsJobFilterRequest
            )
        case .settings:
            SettingsView()
        }
    }

    /// Single-selection sidebar lists take an optional binding; keep a
    /// section always selected by ignoring deselection.
    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { if let new = $0 { selectedTab = new } }
        )
    }

    /// iPad: a persistent sidebar listing the sections beside the content.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppTab.allCases, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Shifty")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        } detail: {
            section(selectedTab)
                .id(selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// iPhone: the standard bottom tab bar.
    private var tabView: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    section(tab)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    var body: some View {
        Group {
            if isRegularWidth {
                splitView
            } else {
                tabView
            }
        }
        .background { keyboardShortcuts }
        .onAppear {
            if DemoData.isRequested {
                DemoData.seedIfNeeded(modelContext)
                hasCompletedOnboarding = true
            }
            // Returning users (e.g. data synced from iCloud) skip onboarding.
            if !hasCompletedOnboarding, !shifts.isEmpty {
                hasCompletedOnboarding = true
            }
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
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
                shifts: shifts,
                remindersEnabled: remindersEnabled,
                leadMinutes: reminderLeadMinutes,
                tipRemindersEnabled: tipRemindersEnabled,
                weeklySummaryEnabled: weeklySummaryEnabled
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ShiftyModels.all, inMemory: true)
}

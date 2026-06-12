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
    case jobs
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView(selectedTab: $selectedTab)
            }
            Tab("Shifts", systemImage: "clock", value: .shifts) {
                ShiftsView()
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarView()
            }
            Tab("Pay", systemImage: "banknote", value: .pay) {
                PayView()
            }
            Tab("Jobs", systemImage: "briefcase", value: .jobs) {
                JobsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

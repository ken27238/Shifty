import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        ZStack {
            settingsManager.isDarkMode ? Color.black.edgesIgnoringSafeArea(.all) : Color.white.edgesIgnoringSafeArea(.all)
            
            TabView {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                
                ShiftListView()
                    .tabItem {
                        Label("Shifts", systemImage: "list.bullet")
                    }
                
                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                
                EarningsView()
                    .tabItem {
                        Label("Earnings", systemImage: "dollarsign.circle")
                    }
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .accentColor(settingsManager.isDarkMode ? .white : .blue)
        }
        .preferredColorScheme(settingsManager.isDarkMode ? .dark : .light)
    }
}

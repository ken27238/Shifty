import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("userInterfaceStyle") private var userInterfaceStyle: UIUserInterfaceStyle = .unspecified

    var body: some View {
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
        .accentColor(Color.accent)
        .background(Color.background.edgesIgnoringSafeArea(.all))
        .preferredColorScheme(colorScheme)
        .onChange(of: userInterfaceStyle) { oldValue, newValue in
            updateColorScheme(newValue)
        }
    }
    
    private func updateColorScheme(_ style: UIUserInterfaceStyle) {
        switch style {
        case .light:
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { $0.windows.first?.overrideUserInterfaceStyle = .light }
        case .dark:
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { $0.windows.first?.overrideUserInterfaceStyle = .dark }
        case .unspecified:
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { $0.windows.first?.overrideUserInterfaceStyle = .unspecified }
        @unknown default:
            break
        }
    }
}

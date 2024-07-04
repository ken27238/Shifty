import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
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
        .accentColor(colors.accent)
        .background(colors.background.edgesIgnoringSafeArea(.all))
        .onChange(of: settingsManager.colorScheme) { _, newValue in
            updateColorScheme(newValue)
        }
        .onChange(of: userInterfaceStyle) { _, newValue in
            updateColorScheme(AppColorScheme(rawValue: newValue.rawValue) ?? .unspecified)
        }
    }
    
    private func updateColorScheme(_ scheme: AppColorScheme) {
        let style: UIUserInterfaceStyle
        switch scheme {
        case .light:
            style = .light
        case .dark:
            style = .dark
        case .unspecified:
            style = .unspecified
        }
        
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { $0.windows.first?.overrideUserInterfaceStyle = style }
        
        userInterfaceStyle = style
        settingsManager.colorScheme = scheme
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .previewDisplayName("Light Mode")
        
        ContentView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
    }
}

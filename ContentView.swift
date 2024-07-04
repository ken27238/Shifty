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
        .accentColor(settingsManager.accentColor)
        .background(colors.background.ignoresSafeArea())
        .onChange(of: settingsManager.colorScheme) { newValue in
            updateColorScheme(newValue)
        }
        .onChange(of: userInterfaceStyle) { newValue in
            updateColorScheme(AppColorScheme(uiStyle: newValue))
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

extension AppColorScheme {
    init(uiStyle: UIUserInterfaceStyle) {
        switch uiStyle {
        case .light:
            self = .light
        case .dark:
            self = .dark
        default:
            self = .unspecified
        }
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

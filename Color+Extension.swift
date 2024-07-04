import SwiftUI

struct AppColor {
    let background: Color
    let text: Color
    let accent: Color
    let secondaryBackground: Color
    let secondaryText: Color
    
    static let light = AppColor(
        background: .white,
        text: .black,
        accent: .purple,
        secondaryBackground: Color(UIColor.systemGray6),
        secondaryText: .gray
    )
    
    static let dark = AppColor(
        background: .black,
        text: .white,
        accent: .purple,
        secondaryBackground: Color(UIColor.systemGray5),
        secondaryText: .gray
    )
}

struct ColorScheme: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .environment(\.appColor, colorScheme == .dark ? .dark : .light)
    }
}

extension EnvironmentValues {
    var appColor: AppColor {
        get { self[AppColorKey.self] }
        set { self[AppColorKey.self] = newValue }
    }
}

private struct AppColorKey: EnvironmentKey {
    static let defaultValue: AppColor = .light
}

extension View {
    func withAppColorScheme() -> some View {
        self.modifier(ColorScheme())
    }
}

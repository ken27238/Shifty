//
//  AppSettings.swift
//  Shifty
//

import Foundation

nonisolated extension UserDefaults {
    /// App group defaults, shared with the widget extension.
    static let shared = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
}

/// Keys for settings stored in the shared defaults suite.
nonisolated enum SettingsKeys {
    // Shift defaults
    static let defaultStartMinutes = "defaultStartMinutes"   // minutes from midnight
    static let defaultDurationHours = "defaultDurationHours"
    static let defaultBreakMinutes = "defaultBreakMinutes"
    static let defaultJobName = "defaultJobName"
    static let tipsEnabled = "tipsEnabled"

    // Pay
    static let overtimeEnabled = "overtimeEnabled"
    static let overtimeWeekly = "overtimeWeekly"             // true: per week, false: per day
    static let overtimeThreshold = "overtimeThreshold"
    static let overtimeMultiplier = "overtimeMultiplier"
    static let takeHomePercent = "takeHomePercent"           // estimated deductions, 0 = off
    static let currencyOverride = "currencyOverride"         // "" = system locale
    static let weekStartDay = "weekStartDay"                 // 0 = system, 1 = Sunday, 2 = Monday

    // Sync & appearance
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
    static let appearance = "appearance"                     // system | light | dark
    static let accentColorName = "accentColorName"           // "" = default accent
}

nonisolated enum AppSettings {
    /// Call once per process before reading settings.
    static func registerDefaults() {
        UserDefaults.shared.register(defaults: [
            SettingsKeys.defaultStartMinutes: 9 * 60,
            SettingsKeys.defaultDurationHours: 8.0,
            SettingsKeys.defaultBreakMinutes: 0,
            SettingsKeys.tipsEnabled: true,
            SettingsKeys.overtimeWeekly: true,
            SettingsKeys.overtimeThreshold: 40.0,
            SettingsKeys.overtimeMultiplier: 1.5,
            SettingsKeys.iCloudSyncEnabled: true,
        ])
    }
}

nonisolated extension Calendar {
    /// The user's calendar, honoring the week-start setting.
    static var app: Calendar {
        var calendar = Calendar.current
        let preference = UserDefaults.shared.integer(forKey: SettingsKeys.weekStartDay)
        if preference > 0 {
            calendar.firstWeekday = preference
        }
        return calendar
    }
}

//
//  ReminderScheduler.swift
//  Shifty
//

import Foundation
import UserNotifications

/// Schedules local notifications: upcoming-shift reminders, tip-logging
/// nudges when shifts end, and a weekly summary.
enum ReminderScheduler {
    private static let shiftPrefix = "shift-reminder-"
    private static let tipPrefix = "tip-reminder-"
    private static let weeklyIdentifier = "weekly-summary"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    /// Replaces all pending Shifty notifications to match current data.
    static func sync(
        shifts: [Shift],
        remindersEnabled: Bool,
        leadMinutes: Int,
        tipRemindersEnabled: Bool,
        weeklySummaryEnabled: Bool
    ) async {
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0.hasPrefix(shiftPrefix) || $0.hasPrefix(tipPrefix) || $0 == weeklyIdentifier
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard remindersEnabled || tipRemindersEnabled || weeklySummaryEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let upcoming = shifts.filter { $0.start > .now }.sorted { $0.start < $1.start }

        if remindersEnabled {
            // The system caps pending notifications at 64; nearest shifts matter most.
            for shift in upcoming.prefix(20) {
                let fireDate = shift.start.addingTimeInterval(-TimeInterval(leadMinutes * 60))
                guard fireDate > .now else { continue }

                let content = UNMutableNotificationContent()
                if let job = shift.job {
                    content.title = String(localized: "Shift at \(job.name)")
                } else {
                    content.title = String(localized: "Upcoming Shift")
                }
                content.body = String(localized: "Starts at \(shift.start.formatted(date: .omitted, time: .shortened))")
                content.sound = .default
                await add(content, at: fireDate, identifier: shiftPrefix + UUID().uuidString, to: center)
            }
        }

        if tipRemindersEnabled, UserDefaults.shared.bool(forKey: SettingsKeys.tipsEnabled) {
            let ending = shifts.filter { $0.end > .now }.sorted { $0.end < $1.end }
            for shift in ending.prefix(20) {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Shift Ended")
                content.body = String(localized: "How were tips? Log them while they're fresh.")
                content.sound = .default
                await add(content, at: shift.end, identifier: tipPrefix + UUID().uuidString, to: center)
            }
        }

        if weeklySummaryEnabled {
            await scheduleWeeklySummary(shifts: shifts, center: center)
        }
    }

    /// Fires near the end of the current week with its totals as of now.
    private static func scheduleWeeklySummary(shifts: [Shift], center: UNUserNotificationCenter) async {
        let calendar = Calendar.app
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return }
        // Evening of the last day of the week.
        let fireDate = week.end.addingTimeInterval(-4 * 3600)
        guard fireDate > .now else { return }

        let weekShifts = shifts.filter { week.contains($0.start) }
        let hours = weekShifts.reduce(0) { $0 + $1.workedHours }
        let earnings = PayCalculator.totalEarnings(for: weekShifts, calendar: calendar)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your Week in Shifts")
        content.body = String(localized: "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) this week. See the full picture in Pay.")
        content.sound = .default
        await add(content, at: fireDate, identifier: weeklyIdentifier, to: center)
    }

    private static func add(
        _ content: UNMutableNotificationContent,
        at date: Date,
        identifier: String,
        to center: UNUserNotificationCenter
    ) async {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }
}

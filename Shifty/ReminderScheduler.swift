//
//  ReminderScheduler.swift
//  Shifty
//

import Foundation
import UserNotifications

/// Schedules local notifications before upcoming shifts.
enum ReminderScheduler {
    private static let identifierPrefix = "shift-reminder-"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorizationDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    /// Replaces all pending shift reminders to match the given upcoming shifts.
    static func sync(upcomingShifts: [Shift], enabled: Bool, leadMinutes: Int) async {
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        // The system caps pending notifications at 64; the nearest shifts matter most.
        for shift in upcomingShifts.sorted(by: { $0.start < $1.start }).prefix(20) {
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

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + UUID().uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

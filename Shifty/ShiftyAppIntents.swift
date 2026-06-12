//
//  ShiftyAppIntents.swift
//  Shifty
//

import AppIntents
import SwiftData
import Foundation

/// Opens the shared store the same way the app does (read-only is fine here;
/// these intents only summarize).
@MainActor
private func fetchShifts() throws -> [Shift] {
    AppSettings.registerDefaults()
    let schema = Schema.shifty
    let configuration = ModelConfiguration(
        schema: schema,
        groupContainer: .identifier(AppGroup.identifier),
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return try container.mainContext.fetch(FetchDescriptor<Shift>())
}

struct NextShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Shift"
    static let description = IntentDescription("Tells you when your next shift starts.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shifts = try fetchShifts()
        guard let next = shifts.filter({ $0.start > .now }).min(by: { $0.start < $1.start }) else {
            return .result(dialog: "You have no upcoming shifts.")
        }
        let day = next.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let time = next.start.formatted(date: .omitted, time: .shortened)
        if let job = next.job {
            return .result(dialog: "Your next shift is at \(job.name) on \(day) at \(time).")
        }
        return .result(dialog: "Your next shift is on \(day) at \(time).")
    }
}

struct HoursThisWeekIntent: AppIntent {
    static let title: LocalizedStringResource = "Hours This Week"
    static let description = IntentDescription("Summarizes your hours and earnings this week.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let shifts = try fetchShifts()
        let calendar = Calendar.app
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else {
            return .result(dialog: "I couldn't work out the current week.")
        }
        let weekShifts = shifts.filter { week.contains($0.start) && $0.end <= .now }
        let hours = weekShifts.reduce(0) { $0 + $1.workedHours }
        let earnings = PayCalculator.totalEarnings(for: weekShifts, calendar: calendar)
        return .result(dialog: "So far this week you've worked \(hours.formatted(.number.precision(.fractionLength(0...1)))) hours and earned \(earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))).")
    }
}

struct LogShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Shift"
    static let description = IntentDescription("Opens Shifty to log a new shift.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "shifty://newshift") else {
            return .result(opensIntent: OpenURLIntent())
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct ShiftyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextShiftIntent(),
            phrases: [
                "When's my next shift in \(.applicationName)?",
                "What's my next \(.applicationName) shift?",
            ],
            shortTitle: "Next Shift",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: HoursThisWeekIntent(),
            phrases: [
                "How many hours this week in \(.applicationName)?",
                "What did I earn this week in \(.applicationName)?",
            ],
            shortTitle: "Hours This Week",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: LogShiftIntent(),
            phrases: [
                "Log a shift in \(.applicationName)",
                "Add a shift to \(.applicationName)",
            ],
            shortTitle: "Log Shift",
            systemImageName: "plus.circle"
        )
    }
}

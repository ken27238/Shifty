//
//  ShiftyAppIntents.swift
//  Shifty
//

import AppIntents
import SwiftData
import Foundation
import WidgetKit

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

/// Logs a shift from spoken parameters — "log 8 hours at Cafe today" —
/// without opening the app.
struct LogHoursIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Hours"
    static let description = IntentDescription("Logs a shift of a given length, without opening the app.")

    @Parameter(title: "Hours", inclusiveRange: (0.5, 24))
    var hours: Double

    @Parameter(title: "Job")
    var jobName: String?

    @Parameter(title: "Day")
    var day: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$hours) hours at \(\.$jobName) on \(\.$day)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppSettings.registerDefaults()
        let container = try ModelContainer(
            for: .shifty,
            configurations: ModelConfiguration(
                schema: .shifty,
                groupContainer: .identifier(AppGroup.identifier),
                cloudKitDatabase: .none
            )
        )
        let context = container.mainContext
        let jobs = try context.fetch(FetchDescriptor<Job>()).filter { !$0.archived }

        // Resolve the job by spoken name, else the default job, else the
        // only one there is.
        let defaultName = UserDefaults.shared.string(forKey: SettingsKeys.defaultJobName) ?? ""
        let job: Job? = if let jobName, !jobName.isEmpty {
            jobs.first { $0.name.localizedCaseInsensitiveContains(jobName) }
        } else if !defaultName.isEmpty {
            jobs.first { $0.name == defaultName }
        } else {
            jobs.count == 1 ? jobs.first : nil
        }

        let calendar = Calendar.app
        let targetDay = calendar.startOfDay(for: day ?? .now)
        let startMinutes = UserDefaults.shared.integer(forKey: SettingsKeys.defaultStartMinutes)
        let start = calendar.date(
            bySettingHour: startMinutes / 60,
            minute: startMinutes % 60,
            second: 0,
            of: targetDay
        ) ?? targetDay

        let shift = Shift(
            start: start,
            end: start.addingTimeInterval(hours * 3600),
            job: job
        )
        context.insert(shift)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()

        let dayText = calendar.isDateInToday(start)
            ? String(localized: "today")
            : start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if let job {
            return .result(dialog: "Logged \(hours.formatted(.number.precision(.fractionLength(0...1)))) hours at \(job.name) \(dayText).")
        }
        return .result(dialog: "Logged \(hours.formatted(.number.precision(.fractionLength(0...1)))) hours \(dayText).")
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
        AppShortcut(
            intent: LogHoursIntent(),
            phrases: [
                "Log hours in \(.applicationName)",
                "Log my hours with \(.applicationName)",
            ],
            shortTitle: "Log Hours",
            systemImageName: "clock.badge.checkmark"
        )
    }
}

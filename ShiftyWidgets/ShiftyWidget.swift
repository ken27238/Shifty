//
//  ShiftyWidget.swift
//  ShiftyWidgets
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Shared snapshot

nonisolated struct UpcomingItem: Identifiable {
    let id: Int
    let start: Date
    let end: Date
    let jobName: String?
    let colorName: String?

    var color: Color {
        colorName.flatMap { Job.palette[$0] } ?? .secondary
    }
}

/// One entry type shared by every Shifty widget; each widget reads the
/// slice it needs.
nonisolated struct ShiftySnapshot: TimelineEntry {
    let date: Date

    // Up next
    let nextStart: Date?
    let nextEnd: Date?
    let nextJobName: String?
    let nextColorName: String?

    // This week
    let weekHoursWorked: Double
    let weekEarningsSoFar: Double
    let weekShiftCount: Int
    let weekProjectedHours: Double
    let weekProjectedEarnings: Double
    let weeklyGoal: Double

    // Payday
    let payday: Date?
    let expectedPay: Double
    let takeHomeApplied: Bool

    // Schedule
    let upcoming: [UpcomingItem]

    // Month
    let monthStart: Date
    let leadingBlanks: Int
    let dayHours: [Int: Double]

    var nextColor: Color {
        nextColorName.flatMap { Job.palette[$0] } ?? .accentColor
    }

    static let empty = ShiftySnapshot(
        date: .now,
        nextStart: nil, nextEnd: nil, nextJobName: nil, nextColorName: nil,
        weekHoursWorked: 0, weekEarningsSoFar: 0, weekShiftCount: 0,
        weekProjectedHours: 0, weekProjectedEarnings: 0, weeklyGoal: 0,
        payday: nil, expectedPay: 0, takeHomeApplied: false,
        upcoming: [],
        monthStart: .now, leadingBlanks: 0, dayHours: [:]
    )

    static var placeholder: ShiftySnapshot {
        ShiftySnapshot(
            date: .now,
            nextStart: Calendar.current.date(byAdding: .hour, value: 3, to: .now),
            nextEnd: Calendar.current.date(byAdding: .hour, value: 11, to: .now),
            nextJobName: "Cafe",
            nextColorName: "teal",
            weekHoursWorked: 12.5,
            weekEarningsSoFar: 264,
            weekShiftCount: 3,
            weekProjectedHours: 20,
            weekProjectedEarnings: 420,
            weeklyGoal: 400,
            payday: Calendar.current.date(byAdding: .day, value: 4, to: .now),
            expectedPay: 420,
            takeHomeApplied: false,
            upcoming: [
                UpcomingItem(id: 0, start: .now.addingTimeInterval(10_800), end: .now.addingTimeInterval(39_600), jobName: "Cafe", colorName: "teal"),
                UpcomingItem(id: 1, start: .now.addingTimeInterval(97_200), end: .now.addingTimeInterval(126_000), jobName: "Warehouse", colorName: "purple"),
            ],
            monthStart: Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now,
            leadingBlanks: 2,
            dayHours: [3: 8, 5: 6, 10: 7.5, 12: 8]
        )
    }
}

// MARK: - Snapshot maker

@MainActor
enum SnapshotMaker {
    static func make(jobFilter: String? = nil) -> ShiftySnapshot {
        AppSettings.registerDefaults()

        let schema = Schema([Shift.self, Job.self, ShiftPreset.self])
        // Read-only access to the app's store; the app owns CloudKit syncing.
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]),
              let allShifts = try? container.mainContext.fetch(FetchDescriptor<Shift>())
        else { return .empty }

        let shifts = jobFilter.map { name in allShifts.filter { $0.job?.name == name } } ?? allShifts
        let calendar = Calendar.app
        let defaults = UserDefaults.shared

        let next = shifts.filter { $0.start > .now }.min { $0.start < $1.start }

        let week = calendar.dateInterval(of: .weekOfYear, for: .now)
        let weekShifts = shifts.filter { week?.contains($0.start) ?? false }
        let completed = weekShifts.filter { $0.end <= .now }

        let cycle = PayCycle.load()
        let payPeriod = PayPeriods.interval(containing: .now, cycle: cycle, calendar: calendar)
        let takeHomePercent = defaults.double(forKey: SettingsKeys.takeHomePercent)
        let payPeriodEarnings = PayCalculator.totalEarnings(
            for: allShifts.filter { payPeriod.contains($0.start) }, calendar: calendar
        )

        let upcoming = shifts
            .filter { $0.start > .now }
            .sorted { $0.start < $1.start }
            .prefix(6)
            .enumerated()
            .map { index, shift in
                UpcomingItem(
                    id: index,
                    start: shift.start,
                    end: shift.end,
                    jobName: shift.job?.name,
                    colorName: shift.job?.colorName
                )
            }

        let monthStart = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let monthShifts = shifts.filter {
            calendar.isDate($0.start, equalTo: .now, toGranularity: .month)
        }
        var dayHours: [Int: Double] = [:]
        for shift in monthShifts {
            dayHours[calendar.component(.day, from: shift.start), default: 0] += shift.workedHours
        }

        return ShiftySnapshot(
            date: .now,
            nextStart: next?.start,
            nextEnd: next?.end,
            nextJobName: next?.job?.name,
            nextColorName: next?.job?.colorName,
            weekHoursWorked: completed.reduce(0) { $0 + $1.workedHours },
            weekEarningsSoFar: PayCalculator.totalEarnings(for: completed, calendar: calendar),
            weekShiftCount: completed.count,
            weekProjectedHours: weekShifts.reduce(0) { $0 + $1.workedHours },
            weekProjectedEarnings: PayCalculator.totalEarnings(for: weekShifts, calendar: calendar),
            weeklyGoal: defaults.double(forKey: SettingsKeys.weeklyGoal),
            payday: payPeriod.end.addingTimeInterval(-1),
            expectedPay: payPeriodEarnings * (1 - takeHomePercent / 100),
            takeHomeApplied: takeHomePercent > 0,
            upcoming: Array(upcoming),
            monthStart: monthStart,
            leadingBlanks: ((calendar.component(.weekday, from: monthStart) - calendar.firstWeekday) + 7) % 7,
            dayHours: dayHours
        )
    }

    static func refreshPolicy(for entry: ShiftySnapshot) -> TimelineReloadPolicy {
        let soon = Date.now.addingTimeInterval(30 * 60)
        if let next = entry.nextStart, next > .now, (next < soon) {
            return .after(next)
        }
        return .after(soon)
    }
}

// MARK: - Job configuration (App Intents)

nonisolated struct JobEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Job"
    static let defaultQuery = JobEntityQuery()

    /// The job's name doubles as its identifier.
    var id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

nonisolated struct JobEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [JobEntity] {
        identifiers.map(JobEntity.init(id:))
    }

    func suggestedEntities() async throws -> [JobEntity] {
        await MainActor.run {
            AppSettings.registerDefaults()
            let schema = Schema([Shift.self, Job.self, ShiftPreset.self])
            let configuration = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier(AppGroup.identifier),
                cloudKitDatabase: .none
            )
            guard let container = try? ModelContainer(for: schema, configurations: [configuration]),
                  let jobs = try? container.mainContext.fetch(FetchDescriptor<Job>())
            else { return [] }
            return jobs.map { JobEntity(id: $0.name) }.sorted { $0.id < $1.id }
        }
    }
}

struct UpNextConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Up Next"
    static let description = IntentDescription("Shows your next shift, optionally for one job.")

    @Parameter(title: "Job")
    var job: JobEntity?
}

// MARK: - Up Next widget

struct UpNextProvider: AppIntentTimelineProvider {
    nonisolated func placeholder(in context: Context) -> ShiftySnapshot {
        .placeholder
    }

    func snapshot(for configuration: UpNextConfigurationIntent, in context: Context) async -> ShiftySnapshot {
        context.isPreview ? .placeholder : SnapshotMaker.make(jobFilter: configuration.job?.id)
    }

    func timeline(for configuration: UpNextConfigurationIntent, in context: Context) async -> Timeline<ShiftySnapshot> {
        let entry = SnapshotMaker.make(jobFilter: configuration.job?.id)
        return Timeline(entries: [entry], policy: SnapshotMaker.refreshPolicy(for: entry))
    }
}

struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftySnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            if let start = entry.nextStart {
                Text("Next: \(start.formatted(.dateTime.weekday(.abbreviated))) \(start.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("No upcoming shifts")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let start = entry.nextStart, let end = entry.nextEnd {
                    Text(entry.nextJobName ?? String(localized: "Next Shift"))
                        .font(.headline)
                        .lineLimit(1)
                    Text(start.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                    Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No upcoming shifts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            circular
        case .systemMedium:
            HStack(spacing: 16) {
                upNext
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                weekStats
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            upNext
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var circular: some View {
        Group {
            if entry.weeklyGoal > 0 {
                Gauge(
                    value: min(entry.weekEarningsSoFar, entry.weeklyGoal),
                    in: 0...max(entry.weeklyGoal, 0.01)
                ) {
                    Text("Goal")
                } currentValueLabel: {
                    Text(entry.weekEarningsSoFar.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircular)
            } else if entry.weekProjectedHours > 0 {
                Gauge(
                    value: min(entry.weekHoursWorked, entry.weekProjectedHours),
                    in: 0...max(entry.weekProjectedHours, 0.01)
                ) {
                    Text("hrs")
                } currentValueLabel: {
                    Text(entry.weekHoursWorked.formatted(.number.precision(.fractionLength(0))))
                } .gaugeStyle(.accessoryCircular)
            } else {
                VStack(spacing: 0) {
                    Text(entry.weekHoursWorked.formatted(.number.precision(.fractionLength(0))))
                        .font(.title3.bold())
                    Text("hrs")
                        .font(.caption2)
                }
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.nextJobName.map { "Up Next · \($0)" } ?? String(localized: "Up Next"))
                .font(.caption.bold())
                .foregroundStyle(entry.nextColor)
                .lineLimit(1)
            if let start = entry.nextStart {
                Text(start.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(.title2.bold())
                Text("in \(Text(start, style: .relative))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No upcoming shifts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Week")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(entry.weekHoursWorked.formatted(.number.precision(.fractionLength(0...1)))) hrs")
                .font(.headline)
            Text(entry.weekEarningsSoFar, format: .currency(code: Locale.currencyCode).precision(.fractionLength(0)))
                .font(.title2.bold())
        }
    }
}

struct ShiftyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ShiftyWidget",
            intent: UpNextConfigurationIntent.self,
            provider: UpNextProvider()
        ) { entry in
            UpNextWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "shifty://home"))
        }
        .configurationDisplayName("Up Next")
        .description("Your next shift and this week's hours and pay.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryRectangular, .accessoryCircular,
        ])
    }
}

// MARK: - Shared simple provider for the other widgets

struct SnapshotProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> ShiftySnapshot {
        .placeholder
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (ShiftySnapshot) -> Void) {
        Task { @MainActor in
            completion(context.isPreview ? .placeholder : SnapshotMaker.make())
        }
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftySnapshot>) -> Void) {
        Task { @MainActor in
            let entry = SnapshotMaker.make()
            completion(Timeline(entries: [entry], policy: SnapshotMaker.refreshPolicy(for: entry)))
        }
    }
}

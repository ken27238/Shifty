//
//  MoreWidgets.swift
//  ShiftyWidgets
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Repeat last shift (interactive)

struct RepeatLastShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Repeat Last Shift"
    static let description = IntentDescription("Logs a copy of your most recent shift today.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppSettings.registerDefaults()

        let schema = Schema([Shift.self, Job.self, ShiftPreset.self])
        let configuration = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let shifts = try context.fetch(FetchDescriptor<Shift>())

        guard let last = shifts.filter({ $0.end <= .now }).max(by: { $0.start < $1.start }) else {
            return .result()
        }

        let calendar = Calendar.app
        let time = calendar.dateComponents([.hour, .minute], from: last.start)
        guard let newStart = calendar.date(
            bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
            second: 0, of: calendar.startOfDay(for: .now)
        ) else { return .result() }

        let copy = Shift(
            start: newStart,
            end: newStart.addingTimeInterval(last.end.timeIntervalSince(last.start)),
            breakMinutes: last.breakMinutes,
            tips: 0,
            notes: last.notes,
            job: last.job
        )
        copy.locationName = last.locationName
        copy.latitude = last.latitude
        copy.longitude = last.longitude
        context.insert(copy)
        try context.save()

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - This Week widget

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftySnapshot

    private var goalOrProjection: (value: Double, total: Double, caption: String)? {
        if entry.weeklyGoal > 0 {
            return (
                entry.weekEarningsSoFar,
                entry.weeklyGoal,
                "\(entry.weekEarningsSoFar.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) of \(entry.weeklyGoal.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) goal"
            )
        }
        if entry.weekProjectedHours > entry.weekHoursWorked {
            return (
                entry.weekHoursWorked,
                entry.weekProjectedHours,
                "\(entry.weekHoursWorked.formatted(.number.precision(.fractionLength(0...1)))) of \(entry.weekProjectedHours.formatted(.number.precision(.fractionLength(0...1)))) hrs"
            )
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                stat(
                    entry.weekHoursWorked.formatted(.number.precision(.fractionLength(0...1))),
                    label: "hrs"
                )
                stat(
                    entry.weekEarningsSoFar.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))),
                    label: "earned"
                )
                if family == .systemMedium {
                    stat(entry.weekShiftCount.formatted(), label: "shifts")
                }
            }

            if let progress = goalOrProjection {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: min(progress.value, progress.total), total: max(progress.total, 0.01))
                    Text(progress.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if family == .systemMedium {
                Spacer(minLength: 0)
                Button(intent: RepeatLastShiftIntent()) {
                    Label("Repeat Last Shift", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stat(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyWeekWidget", provider: SnapshotProvider()) { entry in
            WeekWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "shifty://pay"))
        }
        .configurationDisplayName("This Week")
        .description("Hours, earnings, and progress this week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Payday widget

struct PaydayWidgetView: View {
    var entry: ShiftySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Payday")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if let payday = entry.payday {
                Text(payday.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(payday.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.title2.bold())
                Text(payday, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.expectedPay, format: .currency(code: Locale.currencyCode).precision(.fractionLength(0)))
                        .font(.headline)
                    Text(entry.takeHomeApplied ? "take-home" : "expected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No pay data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PaydayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyPaydayWidget", provider: SnapshotProvider()) { entry in
            PaydayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "shifty://pay"))
        }
        .configurationDisplayName("Payday")
        .description("Your next payday and expected pay.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Schedule widget

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftySnapshot

    private var rowCount: Int {
        family == .systemLarge ? 6 : 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Shifts")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entry.upcoming.isEmpty {
                Spacer()
                Text("No upcoming shifts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.upcoming.prefix(rowCount)) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.color)
                            .frame(width: 3, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(item.jobName ?? String(localized: "Shift"))")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyScheduleWidget", provider: SnapshotProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "shifty://shifts"))
        }
        .configurationDisplayName("Schedule")
        .description("Your next few shifts.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Month widget

struct MonthWidgetView: View {
    var entry: ShiftySnapshot

    private var calendar: Calendar { .app }

    private var dayCount: Int {
        calendar.range(of: .day, in: .month, for: entry.monthStart)?.count ?? 30
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var maxHours: Double {
        max(entry.dayHours.values.max() ?? 0, 8)
    }

    private var today: Int {
        calendar.component(.day, from: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<entry.leadingBlanks, id: \.self) { blank in
                    Color.clear
                        .frame(height: 20)
                        .id("blank-\(blank)")
                }
                ForEach(1...dayCount, id: \.self) { day in
                    let hours = entry.dayHours[day] ?? 0
                    Text("\(day)")
                        .font(.system(size: 11, weight: day == today ? .bold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .background {
                            if hours > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.2 + 0.4 * min(hours / maxHours, 1)))
                            }
                        }
                        .foregroundStyle(day == today ? Color.accentColor : .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyMonthWidget", provider: SnapshotProvider()) { entry in
            MonthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "shifty://calendar"))
        }
        .configurationDisplayName("Month")
        .description("This month at a glance, shaded by hours worked.")
        .supportedFamilies([.systemLarge])
    }
}

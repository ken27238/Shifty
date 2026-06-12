//
//  WatchComplications.swift
//  ShiftyWatchWidgets
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

nonisolated struct WatchEntry: TimelineEntry {
    let date: Date
    let nextStart: Date?
    let nextEnd: Date?
    let nextJobName: String?
    let weekHours: Double
    let weekEarnings: Double
    let projectedHours: Double
    let weeklyGoal: Double

    static let empty = WatchEntry(
        date: .now,
        nextStart: nil, nextEnd: nil, nextJobName: nil,
        weekHours: 0, weekEarnings: 0, projectedHours: 0, weeklyGoal: 0
    )

    static var placeholder: WatchEntry {
        WatchEntry(
            date: .now,
            nextStart: Calendar.current.date(byAdding: .hour, value: 3, to: .now),
            nextEnd: Calendar.current.date(byAdding: .hour, value: 11, to: .now),
            nextJobName: "Cafe",
            weekHours: 12.5,
            weekEarnings: 264,
            projectedHours: 20,
            weeklyGoal: 400
        )
    }
}

// MARK: - Provider

@MainActor
private func makeWatchEntry() -> WatchEntry {
    AppSettings.registerDefaults()

    let schema = Schema.shifty
    // The watch app owns CloudKit; complications read its store locally.
    let configuration = ModelConfiguration(
        schema: schema,
        groupContainer: .identifier(AppGroup.identifier),
        cloudKitDatabase: .none
    )
    guard let container = try? ModelContainer(for: schema, configurations: [configuration]),
          let shifts = try? container.mainContext.fetch(FetchDescriptor<Shift>())
    else { return .empty }

    let calendar = Calendar.app
    let next = shifts.filter { $0.start > .now }.min { $0.start < $1.start }
    let week = calendar.dateInterval(of: .weekOfYear, for: .now)
    let weekShifts = shifts.filter { week?.contains($0.start) ?? false }
    let completed = weekShifts.filter { $0.end <= .now }

    return WatchEntry(
        date: .now,
        nextStart: next?.start,
        nextEnd: next?.end,
        nextJobName: next?.job?.name,
        weekHours: completed.reduce(0) { $0 + $1.workedHours },
        weekEarnings: PayCalculator.totalEarnings(for: completed, calendar: calendar),
        projectedHours: weekShifts.reduce(0) { $0 + $1.workedHours },
        weeklyGoal: UserDefaults.shared.double(forKey: SettingsKeys.weeklyGoal)
    )
}

struct WatchProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> WatchEntry {
        .placeholder
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        Task { @MainActor in
            completion(context.isPreview ? .placeholder : makeWatchEntry())
        }
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task { @MainActor in
            let entry = makeWatchEntry()
            let soon = Date.now.addingTimeInterval(30 * 60)
            let refresh: Date
            if let next = entry.nextStart, next > .now, (next < soon) {
                refresh = next
            } else {
                refresh = soon
            }
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

// MARK: - Up Next complication

struct UpNextComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchEntry

    private var shortTime: String {
        entry.nextStart?.formatted(date: .omitted, time: .shortened) ?? "—"
    }

    private var shortDay: String {
        entry.nextStart?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if entry.nextStart != nil {
                    Text("Next: \(shortDay) \(shortTime)")
                } else {
                    Text("No shifts")
                }
            case .accessoryCorner:
                Text(shortTime)
                    .font(.headline)
                    .widgetLabel {
                        Text(entry.nextJobName.map { "\(shortDay) · \($0)" } ?? shortDay)
                    }
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(shortDay.isEmpty ? "—" : shortDay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(shortTime)
                        .font(.headline)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    if let start = entry.nextStart, let end = entry.nextEnd {
                        Text(entry.nextJobName ?? String(localized: "Next Shift"))
                            .font(.headline)
                            .widgetAccentable()
                            .lineLimit(1)
                        Text(start.formatted(.dateTime.weekday(.wide)))
                            .font(.caption)
                        Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No upcoming shifts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct UpNextComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyWatchUpNext", provider: WatchProvider()) { entry in
            UpNextComplicationView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Your next shift at a glance.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular, .accessoryCorner])
    }
}

// MARK: - This Week complication

struct WeekComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchEntry

    private var hoursText: String {
        entry.weekHours.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var earningsText: String {
        entry.weekEarnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))
    }

    @ViewBuilder
    private var gauge: some View {
        if entry.weeklyGoal > 0 {
            Gauge(value: min(entry.weekEarnings, entry.weeklyGoal), in: 0...max(entry.weeklyGoal, 0.01)) {
                Text("Goal")
            } currentValueLabel: {
                Text(earningsText)
                    .minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Gauge(
                value: min(entry.weekHours, max(entry.projectedHours, 0.01)),
                in: 0...max(entry.projectedHours, 0.01)
            ) {
                Text("hrs")
            } currentValueLabel: {
                Text(entry.weekHours.formatted(.number.precision(.fractionLength(0))))
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("\(hoursText) hrs · \(earningsText)")
            case .accessoryCorner:
                Text(earningsText)
                    .font(.headline)
                    .minimumScaleFactor(0.6)
                    .widgetLabel {
                        Text("\(hoursText) hrs this week")
                    }
            case .accessoryCircular:
                gauge
            default:
                HStack(spacing: 8) {
                    gauge
                    VStack(alignment: .leading, spacing: 1) {
                        Text(earningsText)
                            .font(.headline)
                            .widgetAccentable()
                        Text("\(hoursText) hrs this week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct WeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyWatchWeek", provider: WatchProvider()) { entry in
            WeekComplicationView(entry: entry)
        }
        .configurationDisplayName("This Week")
        .description("Hours and earnings this week.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular, .accessoryCorner])
    }
}

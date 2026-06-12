//
//  ShiftyWidget.swift
//  ShiftyWidgets
//

import WidgetKit
import SwiftUI
import SwiftData

nonisolated struct ShiftEntry: TimelineEntry {
    let date: Date
    let nextShiftStart: Date?
    let nextShiftEnd: Date?
    let nextJobName: String?
    let weekHours: Double
    let weekEarnings: Double

    static let placeholder = ShiftEntry(
        date: .now,
        nextShiftStart: Calendar.current.date(byAdding: .hour, value: 3, to: .now),
        nextShiftEnd: Calendar.current.date(byAdding: .hour, value: 11, to: .now),
        nextJobName: "Cafe",
        weekHours: 18.5,
        weekEarnings: 312
    )

    static let empty = ShiftEntry(
        date: .now,
        nextShiftStart: nil,
        nextShiftEnd: nil,
        nextJobName: nil,
        weekHours: 0,
        weekEarnings: 0
    )
}

struct ShiftProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> ShiftEntry {
        .placeholder
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        Task { @MainActor in
            completion(context.isPreview ? .placeholder : makeEntry())
        }
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        Task { @MainActor in
            let entry = makeEntry()
            // Refresh periodically, or right when the next shift starts.
            let refresh = entry.nextShiftStart.map { min($0, .now.addingTimeInterval(30 * 60)) }
                ?? .now.addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    @MainActor
    private func makeEntry() -> ShiftEntry {
        AppSettings.registerDefaults()

        let schema = Schema([Shift.self, Job.self])
        // Read-only access to the app's store; the app owns CloudKit syncing.
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

        return ShiftEntry(
            date: .now,
            nextShiftStart: next?.start,
            nextShiftEnd: next?.end,
            nextJobName: next?.job?.name,
            weekHours: weekShifts.reduce(0) { $0 + $1.workedHours },
            weekEarnings: PayCalculator.totalEarnings(for: weekShifts, calendar: calendar)
        )
    }
}

struct ShiftyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShiftEntry

    var body: some View {
        switch family {
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

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Up Next")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if let start = entry.nextShiftStart {
                Text(start.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(.title2.bold())
                if let job = entry.nextJobName {
                    Text(job)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
            Text("\(entry.weekHours.formatted(.number.precision(.fractionLength(0...1)))) hrs")
                .font(.headline)
            Text(entry.weekEarnings, format: .currency(code: Locale.currencyCode).precision(.fractionLength(0)))
                .font(.title2.bold())
        }
    }
}

struct ShiftyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShiftyWidget", provider: ShiftProvider()) { entry in
            ShiftyWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your next shift and this week's hours and pay.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

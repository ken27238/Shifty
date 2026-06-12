//
//  WatchRootView.swift
//  ShiftyWatch
//

import SwiftUI
import SwiftData

struct WatchRootView: View {
    var body: some View {
        TabView {
            UpNextView()
            WeekView()
            UpcomingView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Up next

struct UpNextView: View {
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]

    private var currentShift: Shift? {
        shifts.first { $0.start <= .now && $0.end > .now }
    }

    private var nextShift: Shift? {
        shifts.filter { $0.start > .now }.min { $0.start < $1.start }
    }

    private var accent: Color {
        (currentShift ?? nextShift)?.job?.color ?? .accentColor
    }

    private var calendar: Calendar { .app }

    private func relativeDay(of date: Date) -> String {
        if calendar.isDateInToday(date) {
            String(localized: "Today")
        } else if calendar.isDateInTomorrow(date) {
            String(localized: "Tomorrow")
        } else {
            date.formatted(.dateTime.weekday(.wide))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let shift = currentShift {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Now", systemImage: "circle.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        Text(shift.job?.name ?? String(localized: "Shift"))
                            .font(.headline)
                        Text(timerInterval: shift.start...shift.end, countsDown: false)
                            .font(.title2.bold())
                            .monospacedDigit()
                        Text("Ends at \(shift.end.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let shift = nextShift {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shift.job?.name ?? String(localized: "Up Next"))
                            .font(.caption.bold())
                            .foregroundStyle(accent)
                        Text(relativeDay(of: shift.start))
                            .font(.headline)
                        Text(shift.start.formatted(date: .omitted, time: .shortened))
                            .font(.title2.bold())
                        Text("in \(Text(shift.start, style: .relative))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No Upcoming Shifts",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Add shifts on your iPhone.")
                    )
                }
            }
            .navigationTitle("Up Next")
            .containerBackground(accent.gradient, for: .navigation)
        }
    }
}

// MARK: - This week

struct WeekView: View {
    @Query private var shifts: [Shift]

    private var calendar: Calendar { .app }

    private var weekShifts: [Shift] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return shifts.filter { week.contains($0.start) }
    }

    private var completed: [Shift] {
        weekShifts.filter { $0.end <= .now }
    }

    private var hoursWorked: Double {
        completed.reduce(0) { $0 + $1.workedHours }
    }

    private var earnings: Double {
        PayCalculator.totalEarnings(for: completed, calendar: calendar)
    }

    private var projectedHours: Double {
        weekShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var goal: Double {
        UserDefaults.shared.double(forKey: SettingsKeys.weeklyGoal)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if goal > 0 {
                    Gauge(value: min(earnings, goal), in: 0...max(goal, 0.01)) {
                        Text("Goal")
                    } currentValueLabel: {
                        Text(earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                            .minimumScaleFactor(0.5)
                    }
                    .gaugeStyle(.circular)
                } else {
                    Gauge(
                        value: min(hoursWorked, max(projectedHours, 0.01)),
                        in: 0...max(projectedHours, 0.01)
                    ) {
                        Text("hrs")
                    } currentValueLabel: {
                        Text(hoursWorked.formatted(.number.precision(.fractionLength(0))))
                    }
                    .gaugeStyle(.circular)
                }

                Text(earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                    .font(.title3.bold())
                Text("\(hoursWorked.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(completed.count) shifts")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("This Week")
            .containerBackground(Color.accentColor.gradient, for: .navigation)
        }
    }
}

// MARK: - Upcoming list

struct UpcomingView: View {
    @Query(sort: \Shift.start) private var shifts: [Shift]

    private var upcoming: [Shift] {
        Array(shifts.filter { $0.start > .now }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            Group {
                if upcoming.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar",
                        description: Text("Upcoming shifts appear here.")
                    )
                } else {
                    List(upcoming) { shift in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(shift.job?.color ?? Color.secondary)
                                .frame(width: 3, height: 30)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(shift.start.formatted(.dateTime.weekday(.abbreviated))) · \(shift.job?.name ?? String(localized: "Shift"))")
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                Text("\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Upcoming")
            .containerBackground(Color.accentColor.gradient, for: .navigation)
        }
    }
}

#Preview {
    WatchRootView()
        .modelContainer(for: [Shift.self, Job.self, ShiftPreset.self], inMemory: true)
}

//
//  PayView.swift
//  Shifty
//

import SwiftUI
import SwiftData
import Charts

struct PayView: View {
    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"

        var id: Self { self }

        var component: Calendar.Component {
            switch self {
            case .week: .weekOfYear
            case .month: .month
            }
        }
    }

    @Query private var shifts: [Shift]

    @State private var period: Period = .week
    /// Any date inside the period currently being viewed.
    @State private var referenceDate: Date = .now

    private var calendar: Calendar { .current }

    private var interval: DateInterval {
        calendar.dateInterval(of: period.component, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 0)
    }

    private var periodShifts: [Shift] {
        shifts.filter { interval.contains($0.start) }
    }

    private var totalHours: Double {
        periodShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var totalEarnings: Double {
        periodShifts.reduce(0) { $0 + $1.earnings }
    }

    private var totalTips: Double {
        periodShifts.reduce(0) { $0 + $1.tips }
    }

    /// Earnings and hours per job in the period, highest earnings first.
    private var jobBreakdown: [(name: String, color: Color, hours: Double, earnings: Double)] {
        let grouped = Dictionary(grouping: periodShifts) { $0.job?.name ?? String(localized: "No Job") }
        return grouped
            .map { name, shifts in
                (
                    name: name,
                    color: shifts.first?.job?.color ?? Color.gray,
                    hours: shifts.reduce(0) { $0 + $1.workedHours },
                    earnings: shifts.reduce(0) { $0 + $1.earnings }
                )
            }
            .sorted { $0.earnings > $1.earnings }
    }

    /// One chart entry per day per job, so bars stack by job color.
    private var dailyEarnings: [(id: String, day: Date, jobName: String, earnings: Double)] {
        periodShifts
            .map { shift in
                let day = calendar.startOfDay(for: shift.start)
                let jobName = shift.job?.name ?? String(localized: "No Job")
                return (
                    id: "\(day.timeIntervalSinceReferenceDate)-\(jobName)-\(shift.persistentModelID)",
                    day: day,
                    jobName: jobName,
                    earnings: shift.earnings
                )
            }
            .sorted { $0.day < $1.day }
    }

    private var periodTitle: String {
        switch period {
        case .week:
            if calendar.isDate(referenceDate, equalTo: .now, toGranularity: .weekOfYear) {
                return String(localized: "This Week")
            }
            let lastDay = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var isViewingCurrentPeriod: Bool {
        calendar.isDate(referenceDate, equalTo: .now, toGranularity: period.component)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack {
                        Button("Previous", systemImage: "chevron.backward") {
                            step(by: -1)
                        }
                        .labelStyle(.iconOnly)

                        Spacer()
                        Text(periodTitle)
                            .font(.headline)
                        Spacer()

                        Button("Next", systemImage: "chevron.forward") {
                            step(by: 1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(isViewingCurrentPeriod)
                    }
                    .buttonStyle(.borderless)

                    LabeledContent("Earnings") {
                        Text(totalEarnings, format: .currency(code: Locale.currencyCode))
                            .font(.headline)
                    }
                    LabeledContent("Hours") {
                        Text(totalHours.formatted(.number.precision(.fractionLength(0...1))))
                    }
                    if totalTips > 0 {
                        LabeledContent("Tips") {
                            Text(totalTips, format: .currency(code: Locale.currencyCode))
                        }
                    }
                    LabeledContent("Shifts", value: periodShifts.count, format: .number)
                }

                if periodShifts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Pay This Period",
                            systemImage: "banknote",
                            description: Text("Log shifts to see your earnings here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if jobBreakdown.count > 1 {
                        Section("By Job") {
                            ForEach(jobBreakdown, id: \.name) { entry in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(entry.color)
                                        .frame(width: 12, height: 12)
                                        .accessibilityHidden(true)
                                    Text(entry.name)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(entry.earnings, format: .currency(code: Locale.currencyCode))
                                            .font(.subheadline.weight(.medium))
                                        Text("\(entry.hours.formatted(.number.precision(.fractionLength(0...1)))) hrs")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    Section("Earnings by Day") {
                        Chart(dailyEarnings, id: \.id) { entry in
                            BarMark(
                                x: .value("Day", entry.day, unit: .day),
                                y: .value("Earnings", entry.earnings)
                            )
                            .foregroundStyle(by: .value("Job", entry.jobName))
                            .cornerRadius(4)
                        }
                        .chartForegroundStyleScale(
                            domain: jobBreakdown.map(\.name),
                            range: jobBreakdown.map(\.color)
                        )
                        .chartLegend(jobBreakdown.count > 1 ? .visible : .hidden)
                        .chartXAxis {
                            if period == .week {
                                AxisMarks(values: .stride(by: .day)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                                }
                            } else {
                                AxisMarks()
                            }
                        }
                        .frame(height: 200)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Bar chart of earnings per day")
                    }
                }
            }
            .navigationTitle("Pay")
        }
    }

    private func step(by value: Int) {
        guard let newDate = calendar.date(
            byAdding: period.component, value: value, to: referenceDate
        ) else { return }
        withAnimation {
            referenceDate = newDate
        }
    }
}

#Preview {
    PayView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

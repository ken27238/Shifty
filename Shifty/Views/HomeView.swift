//
//  HomeView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]

    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?

    // Declared so the view refreshes when these settings change.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false
    @AppStorage(SettingsKeys.currencyOverride, store: .shared) private var currencyOverride = ""

    private var calendar: Calendar { .app }

    // MARK: Derived shift groups

    private var upcomingShifts: [Shift] {
        shifts.filter { $0.start > .now }.sorted { $0.start < $1.start }
    }

    private var nextShift: Shift? { upcomingShifts.first }

    private var comingUpShifts: [Shift] { Array(upcomingShifts.dropFirst().prefix(4)) }

    private var currentShift: Shift? {
        shifts.first { $0.start <= .now && $0.end > .now }
    }

    private var recentShifts: [Shift] {
        Array(shifts.filter { $0.end <= .now }.prefix(4))
    }

    private var lastCompletedShift: Shift? { recentShifts.first }

    private func shifts(in component: Calendar.Component, of date: Date) -> [Shift] {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }
        return shifts.filter { interval.contains($0.start) }
    }

    private var thisWeekShifts: [Shift] { shifts(in: .weekOfYear, of: .now) }

    private var lastWeekShifts: [Shift] {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: .now) else { return [] }
        return shifts(in: .weekOfYear, of: lastWeek)
    }

    private var weekHoursDelta: Double {
        thisWeekShifts.reduce(0) { $0 + $1.workedHours }
            - lastWeekShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var hasFutureShiftsThisWeek: Bool {
        thisWeekShifts.contains { $0.start > .now }
    }

    private var projectedWeekEarnings: Double {
        PayCalculator.totalEarnings(for: thisWeekShifts, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            Group {
                if shifts.isEmpty {
                    welcome
                } else {
                    content
                }
            }
            .navigationTitle("Shifty")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Shift", systemImage: "plus") {
                        isAddingShift = true
                    }
                }
            }
            .sheet(isPresented: $isAddingShift) {
                ShiftFormView()
            }
            .sheet(item: $shiftBeingEdited) { shift in
                ShiftFormView(shift: shift)
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Welcome to Shifty", systemImage: "clock.badge.checkmark")
        } description: {
            Text("Track your shifts, hours, and pay. Start by logging your first shift.")
        } actions: {
            Button("Add Shift") { isAddingShift = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var content: some View {
        List {
            if let shift = currentShift {
                Section("Happening Now") {
                    shiftButton(shift)
                }
            }

            if let shift = nextShift {
                Section("Up Next") {
                    shiftButton(shift)
                    Text("Starts in \(Text(shift.start, style: .relative))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if currentShift == nil, let last = lastCompletedShift {
                Section {
                    Button {
                        repeatShift(last, daysFromToday: 0)
                    } label: {
                        Label("Repeat Last Shift Today", systemImage: "arrow.counterclockwise.circle")
                    }
                }
            }

            if !comingUpShifts.isEmpty {
                Section("Coming Up") {
                    ForEach(comingUpShifts) { shift in
                        shiftButton(shift)
                    }
                }
            }

            thisWeekSection
            totalsSection

            if !recentShifts.isEmpty {
                recentSection
            }
        }
    }

    // MARK: Sections

    private var thisWeekSection: some View {
        Section("This Week") {
            HStack(spacing: 12) {
                StatTile(
                    title: "Hours",
                    value: thisWeekShifts
                        .reduce(0) { $0 + $1.workedHours }
                        .formatted(.number.precision(.fractionLength(0...1)))
                )
                StatTile(
                    title: "Earnings",
                    value: PayCalculator.totalEarnings(for: thisWeekShifts, calendar: calendar)
                        .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))
                )
                StatTile(
                    title: "Shifts",
                    value: thisWeekShifts.count.formatted()
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Only compare when there is actually a previous week to compare against.
            if !lastWeekShifts.isEmpty, weekHoursDelta != 0 {
                Label {
                    Text("\(abs(weekHoursDelta).formatted(.number.precision(.fractionLength(0...1)))) hrs \(weekHoursDelta > 0 ? "more" : "less") than last week")
                } icon: {
                    Image(systemName: weekHoursDelta > 0 ? "arrow.up" : "arrow.down")
                }
                .font(.footnote)
                .foregroundStyle(weekHoursDelta > 0 ? .green : .red)
            }

            // A $0 projection (e.g. shifts without a job) isn't worth showing.
            if hasFutureShiftsThisWeek, projectedWeekEarnings > 0 {
                Label {
                    Text("On track for \(projectedWeekEarnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) this week")
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Button("View Pay Details") {
                selectedTab = .pay
            }
        }
    }

    private var totalsSection: some View {
        let monthShifts = shifts(in: .month, of: .now)
        let yearShifts = shifts(in: .year, of: .now)
        let allHours = shifts.reduce(0) { $0 + $1.workedHours }

        return Section("Totals") {
            Button {
                selectedTab = .pay
            } label: {
                LabeledContent("This Month") {
                    Text(summary(of: monthShifts))
                }
            }
            .buttonStyle(.plain)
            LabeledContent("This Year") {
                Text(summary(of: yearShifts))
            }
            LabeledContent("All Time") {
                Text("\(shifts.count) shifts · \(allHours.formatted(.number.precision(.fractionLength(0...1)))) hrs")
            }
        }
    }

    private var recentSection: some View {
        Section("Recent") {
            ForEach(recentShifts) { shift in
                shiftButton(shift)
                    .contextMenu {
                        Button("Repeat Today", systemImage: "arrow.counterclockwise") {
                            repeatShift(shift, daysFromToday: 0)
                        }
                        Button("Repeat Tomorrow", systemImage: "calendar.badge.plus") {
                            repeatShift(shift, daysFromToday: 1)
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            withAnimation { modelContext.delete(shift) }
                            refreshWidgets()
                        }
                    }
            }
            Button("See All Shifts") {
                selectedTab = .shifts
            }
        }
    }

    // MARK: Actions

    private func shiftButton(_ shift: Shift) -> some View {
        Button {
            shiftBeingEdited = shift
        } label: {
            ShiftRow(shift: shift)
        }
        .buttonStyle(.plain)
    }

    private func repeatShift(_ shift: Shift, daysFromToday: Int) {
        guard let targetDay = calendar.date(
            byAdding: .day, value: daysFromToday, to: calendar.startOfDay(for: .now)
        ) else { return }
        let time = calendar.dateComponents([.hour, .minute], from: shift.start)
        guard let newStart = calendar.date(
            bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: targetDay
        ) else { return }

        let newShift = Shift(
            start: newStart,
            end: newStart.addingTimeInterval(shift.end.timeIntervalSince(shift.start)),
            breakMinutes: shift.breakMinutes,
            tips: 0,
            notes: shift.notes,
            job: shift.job
        )
        withAnimation {
            modelContext.insert(newShift)
        }
        refreshWidgets()
    }

    private func summary(of shifts: [Shift]) -> String {
        let hours = shifts.reduce(0) { $0 + $1.workedHours }
        let earnings = PayCalculator.totalEarnings(for: shifts, calendar: calendar)
        return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))"
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

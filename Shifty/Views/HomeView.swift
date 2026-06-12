//
//  HomeView.swift
//  Shifty
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct HomeView: View {
    @Binding var selectedTab: AppTab
    /// Set externally (⌘N) to open the new-shift form; consumed on arrival.
    @Binding var addShiftRequest: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]

    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?

    // Declared so the view refreshes when these settings change.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false
    @AppStorage(SettingsKeys.currencyOverride, store: .shared) private var currencyOverride = ""
    @AppStorage(SettingsKeys.weeklyGoal, store: .shared) private var weeklyGoal = 0.0

    private var calendar: Calendar { .app }

    // MARK: Derived shift groups

    private var upcomingShifts: [Shift] {
        shifts.filter { $0.start > .now }.sorted { $0.start < $1.start }
    }

    private var nextShift: Shift? { upcomingShifts.first }

    private var comingUpShifts: [Shift] { Array(upcomingShifts.dropFirst().prefix(3)) }

    private var currentShift: Shift? {
        shifts.first { $0.start <= .now && $0.end > .now }
    }

    private var recentShifts: [Shift] {
        Array(shifts.filter { $0.end <= .now }.prefix(3))
    }

    private var lastCompletedShift: Shift? { recentShifts.first }

    private func shifts(in component: Calendar.Component, of date: Date) -> [Shift] {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }
        return shifts.filter { interval.contains($0.start) }
    }

    private var thisWeekShifts: [Shift] { shifts(in: .weekOfYear, of: .now) }

    private var completedWeekShifts: [Shift] {
        thisWeekShifts.filter { $0.end <= .now }
    }

    private var weekHoursWorked: Double {
        completedWeekShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var weekEarningsSoFar: Double {
        PayCalculator.totalEarnings(for: completedWeekShifts, calendar: calendar)
    }

    private var lastWeekShifts: [Shift] {
        guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: .now) else { return [] }
        return shifts(in: .weekOfYear, of: lastWeek)
    }

    private var weekHoursDelta: Double {
        weekHoursWorked - lastWeekShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var hasFutureShiftsThisWeek: Bool {
        thisWeekShifts.contains { $0.start > .now }
    }

    private var projectedWeekEarnings: Double {
        PayCalculator.totalEarnings(for: thisWeekShifts, calendar: calendar)
    }

    private var projectedWeekHours: Double {
        thisWeekShifts.reduce(0) { $0 + $1.workedHours }
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
            .onAppear { applyAddShiftRequest() }
            .onChange(of: addShiftRequest) { _, _ in applyAddShiftRequest() }
        }
    }

    private func applyAddShiftRequest() {
        guard addShiftRequest else { return }
        addShiftRequest = false
        isAddingShift = true
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                heroCard
                quickActions
                weekCard

                if !comingUpShifts.isEmpty {
                    sectionRows(
                        title: "Coming Up",
                        shifts: comingUpShifts,
                        trailing: .duration
                    )
                }

                if !recentShifts.isEmpty {
                    sectionRows(
                        title: "Recent",
                        shifts: recentShifts,
                        trailing: .earnings,
                        accessory: ("See All", { selectedTab = .shifts })
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private var heroCard: some View {
        if let shift = currentShift {
            HeroCard(
                caption: shift.job.map { "Happening Now · \($0.name)" } ?? "Happening Now",
                color: shift.job?.color ?? .accentColor,
                action: { shiftBeingEdited = shift }
            ) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                        .font(.title3.bold())
                    Spacer()
                    Text(timerInterval: shift.start...shift.end, countsDown: false)
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                Text("Ends at \(shift.end.formatted(date: .omitted, time: .shortened)) · ≈ \(shift.earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LocationSnippet(shift: shift)
            }
        } else if let shift = nextShift {
            HeroCard(
                caption: shift.job.map { "Up Next · \($0.name)" } ?? "Up Next",
                color: shift.job?.color ?? .accentColor,
                action: { shiftBeingEdited = shift }
            ) {
                Text("\(relativeDay(of: shift.start)), \(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                    .font(.title3.bold())
                HStack {
                    Label {
                        Text("Starts in \(Text(shift.start, style: .relative))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    Spacer()
                    if shift.earnings > 0 {
                        Text("≈ \(shift.earnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                LocationSnippet(shift: shift)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Upcoming Shifts")
                    .font(.headline)
                Text("Add a shift or repeat your last one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func relativeDay(of date: Date) -> String {
        if calendar.isDateInToday(date) {
            String(localized: "Today")
        } else if calendar.isDateInTomorrow(date) {
            String(localized: "Tomorrow")
        } else {
            date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        Button {
            if let last = lastCompletedShift {
                repeatShift(last, daysFromToday: 0)
            }
        } label: {
            Label("Repeat Last Shift", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(lastCompletedShift == nil)
    }

    // MARK: Week card

    private var weekCard: some View {
        let monthShifts = shifts(in: .month, of: .now)
        let yearShifts = shifts(in: .year, of: .now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                Button {
                    selectedTab = .pay
                } label: {
                    HStack(spacing: 2) {
                        Text("View Pay")
                        Image(systemName: "chevron.forward")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                weekStat(
                    value: weekHoursWorked.formatted(.number.precision(.fractionLength(0...1))),
                    label: "hours"
                )
                weekStat(
                    value: weekEarningsSoFar.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))),
                    label: "earned"
                )
                weekStat(
                    value: completedWeekShifts.count.formatted(),
                    label: "shifts"
                )
                if hasFutureShiftsThisWeek, projectedWeekEarnings > 0 {
                    Spacer()
                    weekStat(
                        value: projectedWeekEarnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))),
                        label: "on track",
                        muted: true
                    )
                }
            }

            if weeklyGoal > 0 {
                // A goal gives the bar meaning even with nothing scheduled.
                ProgressView(
                    value: min(weekEarningsSoFar, weeklyGoal),
                    total: max(weeklyGoal, 0.01)
                )
                Text("\(weekEarningsSoFar.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) of \(weeklyGoal.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) goal · \(totalsFootnote(month: monthShifts, year: yearShifts))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasFutureShiftsThisWeek {
                ProgressView(
                    value: min(weekHoursWorked, projectedWeekHours),
                    total: max(projectedWeekHours, 0.01)
                )
                Text("\(weekHoursWorked.formatted(.number.precision(.fractionLength(0...1)))) of \(projectedWeekHours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(totalsFootnote(month: monthShifts, year: yearShifts))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !lastWeekShifts.isEmpty, weekHoursDelta != 0 {
                    Label {
                        Text("\(abs(weekHoursDelta).formatted(.number.precision(.fractionLength(0...1)))) hrs \(weekHoursDelta > 0 ? "more" : "less") than last week")
                    } icon: {
                        Image(systemName: weekHoursDelta > 0 ? "arrow.up" : "arrow.down")
                    }
                    .font(.caption)
                    .foregroundStyle(weekHoursDelta > 0 ? .green : .red)
                }
                Text(totalsFootnote(month: monthShifts, year: yearShifts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func weekStat(value: String, label: LocalizedStringKey, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(muted ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func totalsFootnote(month: [Shift], year: [Shift]) -> String {
        let monthName = Date.now.formatted(.dateTime.month(.wide))
        let yearName = Date.now.formatted(.dateTime.year())
        let monthEarnings = PayCalculator.totalEarnings(for: month, calendar: calendar)
            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))
        let yearEarnings = PayCalculator.totalEarnings(for: year, calendar: calendar)
            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))
        return "\(monthName) \(monthEarnings) · \(yearName) \(yearEarnings)"
    }

    // MARK: Row sections

    private enum RowTrailing {
        case duration
        case earnings
    }

    private func sectionRows(
        title: LocalizedStringKey,
        shifts: [Shift],
        trailing: RowTrailing,
        accessory: (label: LocalizedStringKey, action: () -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let accessory {
                    Button(accessory.label, action: accessory.action)
                        .font(.subheadline)
                }
            }

            VStack(spacing: 0) {
                ForEach(shifts) { shift in
                    Button {
                        shiftBeingEdited = shift
                    } label: {
                        compactRow(shift, trailing: trailing)
                    }
                    .buttonStyle(.plain)
                    .padHoverEffect()
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

                    if shift.persistentModelID != shifts.last?.persistentModelID {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func compactRow(_ shift: Shift, trailing: RowTrailing) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(shift.job?.color ?? Color.secondary)
                .frame(width: 3, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(shift.start.formatted(.dateTime.weekday(.abbreviated))) · \(shift.job?.name ?? String(localized: "Shift"))")
                    .font(.subheadline.weight(.medium))
                Text("\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch trailing {
            case .duration:
                Text(Duration.seconds(shift.workedDuration), format: .units(allowed: [.hours, .minutes], width: .narrow))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .earnings:
                Text(shift.earnings, format: .currency(code: Locale.currencyCode))
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

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
        newShift.locationName = shift.locationName
        newShift.latitude = shift.latitude
        newShift.longitude = shift.longitude
        withAnimation {
            modelContext.insert(newShift)
        }
        refreshWidgets()
    }
}

/// A static map of where the shift happens — its own location if set,
/// otherwise the job's — with a directions shortcut.
private struct LocationSnippet: View {
    let shift: Shift

    var body: some View {
        if let coordinate = shift.resolvedCoordinate {
            VStack(alignment: .leading, spacing: 6) {
                Map(
                    initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 900,
                        longitudinalMeters: 900
                    )),
                    interactionModes: []
                ) {
                    Marker(shift.job?.name ?? String(localized: "Shift"), coordinate: coordinate)
                        .tint(shift.job?.color ?? .red)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                HStack {
                    if !shift.resolvedLocationName.isEmpty {
                        Label(shift.resolvedLocationName, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        openInMaps(coordinate: coordinate)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 4)
        }
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        let name = shift.resolvedLocationName
        item.name = name.isEmpty ? (shift.job?.name ?? String(localized: "Shift")) : name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault,
        ])
    }
}

/// A prominent tinted card for the current or next shift.
private struct HeroCard<Content: View>: View {
    let caption: String
    let color: Color
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(color)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padHoverEffect()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits this shift")
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home), addShiftRequest: .constant(false))
        .modelContainer(for: [Shift.self, Job.self, ShiftPreset.self], inMemory: true)
}

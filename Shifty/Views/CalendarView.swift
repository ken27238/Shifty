//
//  CalendarView.swift
//  Shifty
//

import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Drag payload for moving a shift to another day in the grid.
nonisolated struct ShiftDragPayload: Codable, Transferable {
    var id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// A snapshot of a shift used by Copy Day / Repeat Here, so pasting
/// survives the original being edited or deleted.
private struct ShiftTemplate {
    var startHour: Int
    var startMinute: Int
    var duration: TimeInterval
    var breakMinutes: Int
    var notes: String
    var job: Job?

    init(shift: Shift) {
        let components = Calendar.app.dateComponents([.hour, .minute], from: shift.start)
        startHour = components.hour ?? 9
        startMinute = components.minute ?? 0
        duration = shift.end.timeIntervalSince(shift.start)
        breakMinutes = shift.breakMinutes
        notes = shift.notes
        job = shift.job
    }
}

struct CalendarView: View {
    private enum ViewMode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week = "Week"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start) private var shifts: [Shift]

    @State private var displayedMonth: Date =
        Calendar.app.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var displayedWeek: Date =
        Calendar.app.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    @State private var selectedDay: Date = Calendar.app.startOfDay(for: .now)
    @State private var viewMode: ViewMode = .month
    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?
    @State private var isPickingMonth = false
    @State private var copiedDay: [ShiftTemplate] = []
    @State private var exportMessage: String?

    @AppStorage("calendarHeatmapEnabled") private var heatmapEnabled = false
    // Declared so the view refreshes when the week-start setting changes.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0

    private var calendar: Calendar { .app }

    private var shiftsByDay: [Date: [Shift]] {
        Dictionary(grouping: shifts) { calendar.startOfDay(for: $0.start) }
    }

    private var selectedDayShifts: [Shift] {
        shiftsByDay[selectedDay] ?? []
    }

    private var monthShifts: [Shift] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return shifts.filter { interval.contains($0.start) }
    }

    private var weekShifts: [Shift] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: displayedWeek) else { return [] }
        return shifts.filter { interval.contains($0.start) }
    }

    private var lastCompletedShift: Shift? {
        shifts.filter { $0.end <= .now }.max { $0.start < $1.start }
    }

    /// All days shown in the grid: full weeks covering the displayed month.
    private var gridDays: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)
        else { return [] }

        var days: [Date] = []
        var day = firstWeek.start
        while day < month.end || days.count % 7 != 0 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The busiest day's hours this month, for scaling the heatmap.
    private var maxDailyHours: Double {
        let monthDayTotals = monthShifts.reduce(into: [Date: Double]()) { totals, shift in
            totals[calendar.startOfDay(for: shift.start), default: 0] += shift.workedHours
        }
        return max(monthDayTotals.values.max() ?? 0, 8)
    }

    /// Weekday symbols rotated so the locale's first weekday comes first.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var isViewingCurrentPeriod: Bool {
        switch viewMode {
        case .month: calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
        case .week: calendar.isDate(displayedWeek, equalTo: .now, toGranularity: .weekOfYear)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewMode {
                case .month: monthLayout
                case .week: weekLayout
                }
            }
            .navigationTitle("Calendar")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingShift) {
                ShiftFormView(defaultDay: selectedDay)
            }
            .sheet(item: $shiftBeingEdited) { shift in
                ShiftFormView(shift: shift)
            }
            .sheet(isPresented: $isPickingMonth) {
                MonthYearPicker(displayedMonth: $displayedMonth, calendar: calendar)
            }
            .alert(
                "Export to Calendar",
                isPresented: Binding(
                    get: { exportMessage != nil },
                    set: { if !$0 { exportMessage = nil } }
                )
            ) {
                Button("OK") { exportMessage = nil }
            } message: {
                Text(exportMessage ?? "")
            }
        }
    }

    // MARK: Month layout

    private var monthLayout: some View {
        List {
            Section {
                monthGrid
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                if selectedDayShifts.isEmpty {
                    Text("No shifts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedDayShifts) { shift in
                        Button {
                            shiftBeingEdited = shift
                        } label: {
                            ShiftRow(shift: shift, showsDate: false)
                        }
                        .buttonStyle(.plain)
                        .draggable(ShiftDragPayload(id: shift.persistentModelID))
                    }
                    .onDelete { offsets in
                        withAnimation {
                            for index in offsets {
                                modelContext.delete(selectedDayShifts[index])
                            }
                        }
                        refreshWidgets()
                    }
                }
            } header: {
                HStack {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    Spacer()
                    if !selectedDayShifts.isEmpty {
                        Text("\(selectedDayShifts.reduce(0) { $0 + $1.workedHours }.formatted(.number.precision(.fractionLength(0...1)))) hrs")
                    }
                }
            } footer: {
                if !selectedDayShifts.isEmpty {
                    Text("Drag a shift onto a day in the grid to move it.")
                }
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    isPickingMonth = true
                } label: {
                    HStack(spacing: 4) {
                        Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose a month and year")

                Spacer()
                Button("Previous Month", systemImage: "chevron.backward") {
                    step(by: -1)
                }
                Button("Next Month", systemImage: "chevron.forward") {
                    step(by: 1)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)

            if !monthShifts.isEmpty {
                periodSummary(for: monthShifts)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                ForEach(gridDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .gesture(monthSwipe)
    }

    private func dayCell(_ day: Date) -> some View {
        let dayShifts = shiftsByDay[day] ?? []
        return DayCell(
            day: day,
            isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
            isToday: calendar.isDateInToday(day),
            isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
            shifts: dayShifts,
            heatIntensity: heatmapEnabled
                ? min(dayShifts.reduce(0) { $0 + $1.workedHours } / maxDailyHours, 1)
                : 0
        ) {
            withAnimation(.snappy) {
                selectedDay = day
            }
        }
        .contextMenu {
            Button("Add Shift", systemImage: "plus") {
                selectedDay = day
                isAddingShift = true
            }
            if lastCompletedShift != nil {
                Button("Repeat Last Shift Here", systemImage: "arrow.counterclockwise") {
                    repeatLastShift(on: day)
                }
            }
            if !dayShifts.isEmpty {
                Button("Copy Day", systemImage: "doc.on.doc") {
                    copiedDay = dayShifts.map(ShiftTemplate.init)
                }
            }
            if !copiedDay.isEmpty {
                Button("Paste \(copiedDay.count) Shifts", systemImage: "doc.on.clipboard") {
                    paste(on: day)
                }
            }
        }
        .dropDestination(for: ShiftDragPayload.self) { payloads, _ in
            move(payloads, to: day)
        }
    }

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                step(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    // MARK: Week layout

    private var weekLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Text(weekTitle)
                    .font(.headline)
                Spacer()
                Button("Previous Week", systemImage: "chevron.backward") {
                    step(by: -1)
                }
                Button("Next Week", systemImage: "chevron.forward") {
                    step(by: 1)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if !weekShifts.isEmpty {
                periodSummary(for: weekShifts)
                    .padding(.bottom, 4)
            }

            WeekTimeline(
                weekStart: displayedWeek,
                shiftsByDay: shiftsByDay,
                calendar: calendar
            ) { shift in
                shiftBeingEdited = shift
            }
        }
    }

    private var weekTitle: String {
        if calendar.isDate(displayedWeek, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This Week")
        }
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: displayedWeek) else {
            return displayedWeek.formatted(date: .abbreviated, time: .omitted)
        }
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: Shared pieces

    private func periodSummary(for shifts: [Shift]) -> some View {
        HStack {
            Text("\(shifts.reduce(0) { $0 + $1.workedHours }.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(PayCalculator.totalEarnings(for: shifts, calendar: calendar).formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) · \(shifts.count) shifts")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        if !isViewingCurrentPeriod {
            ToolbarItem(placement: .secondaryAction) {
                Button("Today") { goToToday() }
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Toggle("Heatmap", systemImage: "square.grid.3x3.fill", isOn: $heatmapEnabled)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Export Month to Calendar", systemImage: "square.and.arrow.up") {
                exportMonth()
            }
            .disabled(monthShifts.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Shift", systemImage: "plus") {
                isAddingShift = true
            }
        }
    }

    // MARK: Actions

    private func step(by value: Int) {
        withAnimation(.snappy) {
            switch viewMode {
            case .month:
                if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
                    displayedMonth = newMonth
                }
            case .week:
                if let newWeek = calendar.date(byAdding: .weekOfYear, value: value, to: displayedWeek) {
                    displayedWeek = newWeek
                }
            }
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            displayedMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            displayedWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            selectedDay = calendar.startOfDay(for: .now)
        }
    }

    private func insert(_ template: ShiftTemplate, on day: Date) {
        // Skip templates whose job was deleted since copying.
        let job = template.job.flatMap { $0.isDeleted ? nil : $0 }
        guard let start = calendar.date(
            bySettingHour: template.startHour, minute: template.startMinute, second: 0, of: day
        ) else { return }
        let shift = Shift(
            start: start,
            end: start.addingTimeInterval(template.duration),
            breakMinutes: template.breakMinutes,
            tips: 0,
            notes: template.notes,
            job: job
        )
        modelContext.insert(shift)
    }

    private func repeatLastShift(on day: Date) {
        guard let last = lastCompletedShift else { return }
        withAnimation {
            insert(ShiftTemplate(shift: last), on: day)
            selectedDay = day
        }
        refreshWidgets()
    }

    private func paste(on day: Date) {
        withAnimation {
            for template in copiedDay {
                insert(template, on: day)
            }
            selectedDay = day
        }
        refreshWidgets()
    }

    private func move(_ payloads: [ShiftDragPayload], to day: Date) -> Bool {
        var moved = false
        withAnimation {
            for payload in payloads {
                guard let shift = modelContext.model(for: payload.id) as? Shift else { continue }
                let time = calendar.dateComponents([.hour, .minute], from: shift.start)
                guard let newStart = calendar.date(
                    bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day
                ) else { continue }
                let duration = shift.end.timeIntervalSince(shift.start)
                shift.start = newStart
                shift.end = newStart.addingTimeInterval(duration)
                moved = true
            }
            if moved {
                selectedDay = calendar.startOfDay(for: day)
            }
        }
        if moved {
            refreshWidgets()
        }
        return moved
    }

    private func exportMonth() {
        let shiftsToExport = monthShifts
        Task {
            do {
                let count = try await CalendarExporter.export(shifts: shiftsToExport)
                exportMessage = String(localized: "Added \(count) shifts to your calendar.")
            } catch {
                exportMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isInDisplayedMonth: Bool
    let shifts: [Shift]
    /// 0 disables the heatmap; otherwise the fraction of the busiest day.
    let heatIntensity: Double
    let action: () -> Void

    private var textColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return isInDisplayedMonth ? .primary : .secondary.opacity(0.5)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(textColor)
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if heatIntensity > 0 {
                            Circle().fill(Color.accentColor.opacity(0.15 + 0.45 * heatIntensity))
                        }
                    }

                HStack(spacing: 3) {
                    // Filled dots are worked shifts; rings are still scheduled.
                    ForEach(shifts.prefix(3)) { shift in
                        if shift.start > .now {
                            Circle()
                                .strokeBorder(shift.job?.color ?? Color.secondary, lineWidth: 1.2)
                                .frame(width: 5.5, height: 5.5)
                        } else {
                            Circle()
                                .fill(shift.job?.color ?? Color.secondary)
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                }
                .frame(height: 6)
                .opacity(heatIntensity > 0 ? 0 : 1)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(shifts.isEmpty ? Text("No shifts") : Text("\(shifts.count) shifts"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Week timeline

private struct WeekTimeline: View {
    let weekStart: Date
    let shiftsByDay: [Date: [Shift]]
    let calendar: Calendar
    let onTap: (Shift) -> Void

    private let hourHeight: CGFloat = 36
    private let labelWidth: CGFloat = 34

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Weekday header row.
            HStack(spacing: 2) {
                Color.clear.frame(width: labelWidth)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                        Text(day.formatted(.dateTime.day()))
                            .font(.footnote.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : .primary)
                }
            }
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 2) {
                    hourLabels
                    ForEach(days, id: \.self) { day in
                        dayColumn(day)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Group {
                    if hour % 4 == 0, let date = calendar.date(
                        bySettingHour: hour, minute: 0, second: 0, of: weekStart
                    ) {
                        Text(date, format: .dateTime.hour())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: labelWidth, height: hourHeight, alignment: .topTrailing)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(.clear)
                        .frame(height: hourHeight)
                        .overlay(alignment: .top) { Divider() }
                }
            }

            ForEach(shiftsByDay[day] ?? []) { shift in
                shiftBlock(shift, day: day)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            calendar.isDateInToday(day) ? Color.accentColor.opacity(0.05) : Color.clear
        )
    }

    private func shiftBlock(_ shift: Shift, day: Date) -> some View {
        let dayStart = calendar.startOfDay(for: day)
        let startOffset = max(0, shift.start.timeIntervalSince(dayStart)) / 3600 * hourHeight
        let visibleEnd = min(shift.end.timeIntervalSince(dayStart), 24 * 3600)
        let height = max(visibleEnd / 3600 * hourHeight - startOffset, 18)

        return Button {
            onTap(shift)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(shift.job?.name ?? String(localized: "Shift"))
                    .font(.caption2.bold())
                    .lineLimit(1)
                if height > 36 {
                    Text(shift.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .padding(3)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(
                (shift.job?.color ?? Color.secondary).opacity(0.25),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 5, bottomLeadingRadius: 5,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .fill(shift.job?.color ?? Color.secondary)
                .frame(width: 3)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .offset(y: startOffset)
        .accessibilityLabel("\(shift.job?.name ?? "Shift"), \(shift.start.formatted(date: .omitted, time: .shortened)) to \(shift.end.formatted(date: .omitted, time: .shortened))")
    }
}

// MARK: - Month/year picker

private struct MonthYearPicker: View {
    @Binding var displayedMonth: Date
    let calendar: Calendar
    @Environment(\.dismiss) private var dismiss

    @State private var month: Int = 1
    @State private var year: Int = 2026

    private var years: [Int] {
        let current = calendar.component(.year, from: .now)
        return Array((current - 6)...(current + 2))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { value in
                        Text(calendar.monthSymbols[value - 1]).tag(value)
                    }
                }
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { value in
                        Text(value, format: .number.grouping(.never)).tag(value)
                    }
                }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #endif
            .navigationTitle("Go to Month")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        var components = DateComponents()
                        components.year = year
                        components.month = month
                        components.day = 1
                        if let date = calendar.date(from: components) {
                            displayedMonth = date
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                month = calendar.component(.month, from: displayedMonth)
                year = calendar.component(.year, from: displayedMonth)
            }
        }
        .presentationDetents([.height(320)])
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

//
//  CalendarView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start) private var shifts: [Shift]

    @State private var displayedMonth: Date =
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?

    // Declared so the view refreshes when the week-start setting changes.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0

    private var calendar: Calendar { .app }

    private var shiftsByDay: [Date: [Shift]] {
        Dictionary(grouping: shifts) { calendar.startOfDay(for: $0.start) }
    }

    private var selectedDayShifts: [Shift] {
        shiftsByDay[selectedDay] ?? []
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

    /// Weekday symbols rotated so the locale's first weekday comes first.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var isViewingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
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
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                if !isViewingCurrentMonth {
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Today") { goToToday() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Shift", systemImage: "plus") {
                        isAddingShift = true
                    }
                }
            }
            .sheet(isPresented: $isAddingShift) {
                ShiftFormView(defaultDay: selectedDay)
            }
            .sheet(item: $shiftBeingEdited) { shift in
                ShiftFormView(shift: shift)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button("Previous Month", systemImage: "chevron.backward") {
                    stepMonth(by: -1)
                }
                Button("Next Month", systemImage: "chevron.forward") {
                    stepMonth(by: 1)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                ForEach(gridDays, id: \.self) { day in
                    DayCell(
                        day: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                        isToday: calendar.isDateInToday(day),
                        isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                        shifts: shiftsByDay[day] ?? []
                    ) {
                        withAnimation(.snappy) {
                            selectedDay = day
                        }
                    }
                }
            }
        }
    }

    private func stepMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.snappy) {
            displayedMonth = newMonth
        }
    }

    private func goToToday() {
        withAnimation(.snappy) {
            displayedMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
            selectedDay = calendar.startOfDay(for: .now)
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isInDisplayedMonth: Bool
    let shifts: [Shift]
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
                        }
                    }

                HStack(spacing: 3) {
                    ForEach(shifts.prefix(3)) { shift in
                        Circle()
                            .fill(shift.job?.color ?? Color.secondary)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
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

#Preview {
    CalendarView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

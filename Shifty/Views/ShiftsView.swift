//
//  ShiftsView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct ShiftsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]

    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?

    // Declared so the view refreshes when the week-start setting changes.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0

    private var calendar: Calendar { .app }

    /// Shifts grouped by the start of their week, newest week first.
    private var weeks: [(weekStart: Date, shifts: [Shift])] {
        let grouped = Dictionary(grouping: shifts) { shift in
            calendar.dateInterval(of: .weekOfYear, for: shift.start)?.start ?? shift.start
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (weekStart: $0.key, shifts: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if shifts.isEmpty {
                    ContentUnavailableView {
                        Label("No Shifts", systemImage: "clock.badge.questionmark")
                    } description: {
                        Text("Shifts you log will appear here.")
                    } actions: {
                        Button("Add Shift") { isAddingShift = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(weeks, id: \.weekStart) { week in
                            Section {
                                ForEach(week.shifts) { shift in
                                    Button {
                                        shiftBeingEdited = shift
                                    } label: {
                                        ShiftRow(shift: shift)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in
                                    deleteShifts(at: offsets, in: week.shifts)
                                }
                            } header: {
                                WeekHeader(weekStart: week.weekStart, shifts: week.shifts)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shifts")
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

    private func deleteShifts(at offsets: IndexSet, in weekShifts: [Shift]) {
        withAnimation {
            for index in offsets {
                modelContext.delete(weekShifts[index])
            }
        }
        refreshWidgets()
    }
}

private struct WeekHeader: View {
    let weekStart: Date
    let shifts: [Shift]

    private var title: String {
        let calendar = Calendar.app
        if calendar.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This Week")
        }
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
            return weekStart.formatted(date: .abbreviated, time: .omitted)
        }
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var totalHours: Double {
        shifts.reduce(0) { $0 + $1.workedHours }
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(totalHours.formatted(.number.precision(.fractionLength(0...1)))) hrs")
        }
    }
}

#Preview {
    ShiftsView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

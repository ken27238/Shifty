//
//  HomeView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]

    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?

    private var calendar: Calendar { .current }

    private var currentShift: Shift? {
        shifts.first { $0.start <= .now && $0.end > .now }
    }

    private var nextShift: Shift? {
        shifts.filter { $0.start > .now }.min { $0.start < $1.start }
    }

    private var thisWeekShifts: [Shift] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return shifts.filter { week.contains($0.start) }
    }

    private var recentShifts: [Shift] {
        Array(shifts.filter { $0.end <= .now }.prefix(4))
    }

    var body: some View {
        NavigationStack {
            Group {
                if shifts.isEmpty {
                    ContentUnavailableView {
                        Label("Welcome to Shifty", systemImage: "clock.badge.checkmark")
                    } description: {
                        Text("Track your shifts, hours, and pay. Start by logging your first shift.")
                    } actions: {
                        Button("Add Shift") { isAddingShift = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let shift = currentShift {
                            Section("Happening Now") {
                                shiftButton(shift)
                            }
                        } else if let shift = nextShift {
                            Section("Up Next") {
                                shiftButton(shift)
                            }
                        }

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
                                    value: thisWeekShifts
                                        .reduce(0) { $0 + $1.earnings }
                                        .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))
                                )
                                StatTile(
                                    title: "Shifts",
                                    value: thisWeekShifts.count.formatted()
                                )
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)

                            Button("View Pay Details") {
                                selectedTab = .pay
                            }
                        }

                        if !recentShifts.isEmpty {
                            Section("Recent") {
                                ForEach(recentShifts) { shift in
                                    shiftButton(shift)
                                }
                                Button("See All Shifts") {
                                    selectedTab = .shifts
                                }
                            }
                        }
                    }
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

    private func shiftButton(_ shift: Shift) -> some View {
        Button {
            shiftBeingEdited = shift
        } label: {
            ShiftRow(shift: shift)
        }
        .buttonStyle(.plain)
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

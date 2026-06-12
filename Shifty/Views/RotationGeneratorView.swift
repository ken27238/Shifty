//
//  RotationGeneratorView.swift
//  Shifty
//

import SwiftUI
import SwiftData

/// Generates a repeating on/off pattern of shifts from a template,
/// e.g. 4 days on, 4 days off for the next month.
struct RotationGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShiftPreset.name) private var presets: [ShiftPreset]
    @Query(sort: \Job.name) private var jobs: [Job]

    @State private var selectedPreset: ShiftPreset?
    @State private var daysOn = 5
    @State private var daysOff = 2
    @State private var startDate = Calendar.app.startOfDay(for: .now)
    @State private var endDate = Calendar.app.date(byAdding: .weekOfYear, value: 4, to: .now) ?? .now

    private var calendar: Calendar { .app }

    private var generatedDayCount: Int {
        guard endDate > startDate, let preset = selectedPreset else { return 0 }
        let cycle = daysOn + daysOff
        var count = 0
        var day = calendar.startOfDay(for: startDate)
        var index = 0
        while day <= endDate && index < 366 {
            if index % cycle < daysOn, preset.makeShift(on: day, jobs: jobs, calendar: calendar) != nil {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            index += 1
        }
        return count
    }

    var body: some View {
        NavigationStack {
            Form {
                if presets.isEmpty {
                    Section {
                        Text("Create a shift template in Settings first — the rotation repeats a template.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Pattern") {
                        Picker("Template", selection: $selectedPreset) {
                            Text("Choose…").tag(ShiftPreset?.none)
                            ForEach(presets) { preset in
                                Text(preset.name).tag(Optional(preset))
                            }
                        }
                        Stepper(value: $daysOn, in: 1...14) {
                            LabeledContent("Days On") { Text("\(daysOn)") }
                        }
                        Stepper(value: $daysOff, in: 0...14) {
                            LabeledContent("Days Off") { Text("\(daysOff)") }
                        }
                    }

                    Section("Range") {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }

                    Section {
                        Button("Generate \(generatedDayCount) Shifts") {
                            generate()
                        }
                        .disabled(selectedPreset == nil || generatedDayCount == 0)
                    } footer: {
                        Text("The pattern starts on the first day: \(daysOn) on, \(daysOff) off, repeating until the end date.")
                    }
                }
            }
            .navigationTitle("Generate Rotation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func generate() {
        guard let preset = selectedPreset else { return }
        let cycle = daysOn + daysOff
        var day = calendar.startOfDay(for: startDate)
        var index = 0
        withAnimation {
            while day <= endDate && index < 366 {
                if index % cycle < daysOn, let shift = preset.makeShift(on: day, jobs: jobs, calendar: calendar) {
                    modelContext.insert(shift)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                index += 1
            }
        }
        refreshWidgets()
        dismiss()
    }
}

#Preview {
    RotationGeneratorView()
        .modelContainer(for: ShiftyModels.all, inMemory: true)
}

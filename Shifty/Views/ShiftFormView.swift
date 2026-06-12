//
//  ShiftFormView.swift
//  Shifty
//

import SwiftUI
import SwiftData

/// Add a new shift (pass nothing) or edit an existing one (pass `shift`).
struct ShiftFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.name) private var jobs: [Job]

    private let existingShift: Shift?

    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var tips: Double
    @State private var notes: String
    @State private var job: Job?

    init(shift: Shift? = nil, defaultStart: Date? = nil) {
        existingShift = shift
        let defaultStart = defaultStart ?? Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        ) ?? .now
        _start = State(initialValue: shift?.start ?? defaultStart)
        _end = State(initialValue: shift?.end ?? defaultStart.addingTimeInterval(8 * 3600))
        _breakMinutes = State(initialValue: shift?.breakMinutes ?? 0)
        _tips = State(initialValue: shift?.tips ?? 0)
        _notes = State(initialValue: shift?.notes ?? "")
        _job = State(initialValue: shift?.job)
    }

    private var workedDuration: TimeInterval {
        max(0, end.timeIntervalSince(start) - TimeInterval(breakMinutes * 60))
    }

    private var earnings: Double {
        workedDuration / 3600 * (job?.hourlyRate ?? 0) + tips
    }

    private var isValid: Bool {
        end > start && workedDuration > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Job", selection: $job) {
                        Text("None").tag(Job?.none)
                        ForEach(jobs) { job in
                            Text(job.name).tag(Optional(job))
                        }
                    }
                } footer: {
                    if jobs.isEmpty {
                        Text("Add a job in the Jobs tab to track earnings automatically.")
                    }
                }

                Section("Time") {
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end, in: start...)
                    Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                        LabeledContent("Break") {
                            Text("\(breakMinutes) min")
                        }
                    }
                }

                Section("Extras") {
                    LabeledContent("Tips") {
                        TextField(
                            "Tips",
                            value: $tips,
                            format: .currency(code: Locale.currencyCode)
                        )
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section {
                    LabeledContent("Worked") {
                        Text(Duration.seconds(workedDuration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                    }
                    LabeledContent("Earnings") {
                        Text(earnings, format: .currency(code: Locale.currencyCode))
                    }
                }
            }
            .navigationTitle(existingShift == nil ? "New Shift" : "Edit Shift")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        if let shift = existingShift {
            shift.start = start
            shift.end = end
            shift.breakMinutes = breakMinutes
            shift.tips = tips
            shift.notes = notes
            shift.job = job
        } else {
            let shift = Shift(
                start: start,
                end: end,
                breakMinutes: breakMinutes,
                tips: tips,
                notes: notes,
                job: job
            )
            modelContext.insert(shift)
        }
        dismiss()
    }
}

#Preview {
    ShiftFormView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

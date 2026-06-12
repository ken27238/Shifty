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
    @Query(sort: \ShiftPreset.name) private var presets: [ShiftPreset]
    @Query private var allShifts: [Shift]

    /// Archived jobs stay selectable only when already on this shift.
    private var selectableJobs: [Job] {
        jobs.filter { !$0.archived || $0 === job }
    }

    /// Saved shifts whose times collide with the form's times.
    private var overlappingShifts: [Shift] {
        allShifts.filter { other in
            other.persistentModelID != existingShift?.persistentModelID
                && other.start < end && other.end > start
        }
    }

    private let existingShift: Shift?

    @AppStorage(SettingsKeys.tipsEnabled, store: .shared) private var tipsEnabled = true

    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: Int
    @State private var tips: Double
    @State private var mileage: Double
    @State private var expenses: Double
    @State private var notes: String
    @State private var job: Job?
    @State private var locationName: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var isPickingLocation = false
    @State private var didApplyDefaultJob = false

    /// New shifts start on `defaultDay` (today if nil) using the user's
    /// default start time, duration, and break from Settings.
    init(shift: Shift? = nil, defaultDay: Date? = nil) {
        existingShift = shift

        let defaults = UserDefaults.shared
        let startMinutes = defaults.integer(forKey: SettingsKeys.defaultStartMinutes)
        let durationHours = defaults.double(forKey: SettingsKeys.defaultDurationHours)
        let defaultStart = Calendar.app.date(
            bySettingHour: startMinutes / 60,
            minute: startMinutes % 60,
            second: 0,
            of: defaultDay ?? .now
        ) ?? defaultDay ?? .now

        _start = State(initialValue: shift?.start ?? defaultStart)
        _end = State(initialValue: shift?.end ?? defaultStart.addingTimeInterval(durationHours * 3600))
        _breakMinutes = State(initialValue: shift?.breakMinutes ?? defaults.integer(forKey: SettingsKeys.defaultBreakMinutes))
        _tips = State(initialValue: shift?.tips ?? 0)
        _mileage = State(initialValue: shift?.mileage ?? 0)
        _expenses = State(initialValue: shift?.expenses ?? 0)
        _notes = State(initialValue: shift?.notes ?? "")
        _job = State(initialValue: shift?.job)
        _locationName = State(initialValue: shift?.locationName ?? "")
        _latitude = State(initialValue: shift?.latitude)
        _longitude = State(initialValue: shift?.longitude)
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
                        ForEach(selectableJobs) { job in
                            Text(job.name).tag(Optional(job))
                        }
                    }
                } footer: {
                    if jobs.isEmpty {
                        Text("Add a job in Settings to track earnings automatically.")
                    }
                }

                Section {
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end, in: start...)
                    Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                        LabeledContent("Break") {
                            Text("\(breakMinutes) min")
                        }
                    }
                } header: {
                    Text("Time")
                } footer: {
                    if let overlap = overlappingShifts.first {
                        Label {
                            Text("Overlaps with \(overlap.job?.name ?? String(localized: "a shift")) on \(overlap.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(overlap.start.formatted(date: .omitted, time: .shortened)) – \(overlap.end.formatted(date: .omitted, time: .shortened))")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(.orange)
                    }
                }

                Section("Extras") {
                    if tipsEnabled {
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
                    }
                    LabeledContent("Mileage") {
                        TextField("Mileage", value: $mileage, format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    LabeledContent("Expenses") {
                        TextField("Expenses", value: $expenses, format: .currency(code: Locale.currencyCode))
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section {
                    if latitude != nil {
                        Label(locationName.isEmpty ? String(localized: "Custom Location") : locationName,
                              systemImage: "mappin.and.ellipse")
                        Button("Change Location") { isPickingLocation = true }
                        Button("Use Job Location", role: .destructive) {
                            locationName = ""
                            latitude = nil
                            longitude = nil
                        }
                    } else {
                        Button("Set Custom Location", systemImage: "mappin.and.ellipse") {
                            isPickingLocation = true
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    if latitude == nil {
                        if let jobLocation = job?.locationName, !jobLocation.isEmpty {
                            Text("Uses the job's location: \(jobLocation).")
                        } else {
                            Text("Defaults to the job's location when one is set.")
                        }
                    }
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
            .task {
                // Pre-select the default job from Settings for new shifts.
                guard !didApplyDefaultJob, existingShift == nil, job == nil else { return }
                didApplyDefaultJob = true
                let defaultName = UserDefaults.shared.string(forKey: SettingsKeys.defaultJobName) ?? ""
                if !defaultName.isEmpty {
                    job = jobs.first { $0.name == defaultName }
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
                if existingShift == nil, !presets.isEmpty {
                    ToolbarItem(placement: .secondaryAction) {
                        Menu("Use Template", systemImage: "doc.on.doc") {
                            ForEach(presets) { preset in
                                Button(preset.name) { apply(preset) }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $isPickingLocation) {
                LocationPickerView { name, coordinate in
                    locationName = name
                    latitude = coordinate.latitude
                    longitude = coordinate.longitude
                }
            }
        }
    }

    /// Applies a template to the form, keeping the chosen day.
    private func apply(_ preset: ShiftPreset) {
        let calendar = Calendar.app
        if let newStart = calendar.date(
            bySettingHour: preset.startMinutes / 60,
            minute: preset.startMinutes % 60,
            second: 0, of: start
        ) {
            start = newStart
            end = newStart.addingTimeInterval(TimeInterval(preset.durationMinutes * 60))
        }
        breakMinutes = preset.breakMinutes
        if !preset.jobName.isEmpty {
            job = jobs.first { $0.name == preset.jobName }
        }
    }

    private func save() {
        let shift: Shift
        if let existingShift {
            shift = existingShift
        } else {
            shift = Shift(
                start: start,
                end: end,
                breakMinutes: breakMinutes,
                tips: tips,
                notes: notes,
                job: job
            )
            modelContext.insert(shift)
        }
        shift.start = start
        shift.end = end
        shift.breakMinutes = breakMinutes
        shift.tips = tips
        shift.mileage = mileage
        shift.expenses = expenses
        shift.notes = notes
        shift.job = job
        shift.locationName = locationName
        shift.latitude = latitude
        shift.longitude = longitude
        refreshWidgets()
        dismiss()
    }
}

#Preview {
    ShiftFormView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

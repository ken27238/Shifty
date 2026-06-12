//
//  PresetsView.swift
//  Shifty
//

import SwiftUI
import SwiftData

/// Manage reusable shift templates (Settings → Shift Templates).
struct PresetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShiftPreset.name) private var presets: [ShiftPreset]

    @State private var isAddingPreset = false
    @State private var presetBeingEdited: ShiftPreset?

    var body: some View {
        Group {
            if presets.isEmpty {
                ContentUnavailableView {
                    Label("No Templates", systemImage: "doc.on.doc")
                } description: {
                    Text("Save common shifts — like \u{201C}Opening, 9–5 at Cafe\u{201D} — to reuse in the shift form and the rotation generator.")
                } actions: {
                    Button("Add Template") { isAddingPreset = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(presets) { preset in
                        Button {
                            presetBeingEdited = preset
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.body)
                                Text(presetSummary(preset))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        withAnimation {
                            for index in offsets {
                                modelContext.delete(presets[index])
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Shift Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Template", systemImage: "plus") {
                    isAddingPreset = true
                }
            }
        }
        .sheet(isPresented: $isAddingPreset) {
            PresetFormView()
        }
        .sheet(item: $presetBeingEdited) { preset in
            PresetFormView(preset: preset)
        }
    }

    private func presetSummary(_ preset: ShiftPreset) -> String {
        let start = Calendar.app.date(
            bySettingHour: preset.startMinutes / 60,
            minute: preset.startMinutes % 60,
            second: 0, of: .now
        ) ?? .now
        var parts = [
            start.formatted(date: .omitted, time: .shortened),
            "\((Double(preset.durationMinutes) / 60).formatted(.number.precision(.fractionLength(0...1)))) hrs",
        ]
        if !preset.jobName.isEmpty {
            parts.append(preset.jobName)
        }
        return parts.joined(separator: " · ")
    }
}

struct PresetFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.name) private var jobs: [Job]

    private let existingPreset: ShiftPreset?

    @State private var name: String
    @State private var startMinutes: Int
    @State private var durationMinutes: Int
    @State private var breakMinutes: Int
    @State private var jobName: String

    init(preset: ShiftPreset? = nil) {
        existingPreset = preset
        _name = State(initialValue: preset?.name ?? "")
        _startMinutes = State(initialValue: preset?.startMinutes ?? 9 * 60)
        _durationMinutes = State(initialValue: preset?.durationMinutes ?? 8 * 60)
        _breakMinutes = State(initialValue: preset?.breakMinutes ?? 0)
        _jobName = State(initialValue: preset?.jobName ?? "")
    }

    private var startTime: Binding<Date> {
        Binding(
            get: {
                Calendar.app.date(
                    bySettingHour: startMinutes / 60,
                    minute: startMinutes % 60,
                    second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.app.dateComponents([.hour, .minute], from: date)
                startMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && durationMinutes > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                DatePicker("Start Time", selection: startTime, displayedComponents: .hourAndMinute)
                Stepper(value: $durationMinutes, in: 30...16 * 60, step: 30) {
                    LabeledContent("Duration") {
                        Text("\((Double(durationMinutes) / 60).formatted(.number.precision(.fractionLength(0...1)))) hrs")
                    }
                }
                Stepper(value: $breakMinutes, in: 0...240, step: 5) {
                    LabeledContent("Break") {
                        Text("\(breakMinutes) min")
                    }
                }
                Picker("Job", selection: $jobName) {
                    Text("None").tag("")
                    ForEach(jobs.filter { !$0.archived }) { job in
                        Text(job.name).tag(job.name)
                    }
                }
            }
            .navigationTitle(existingPreset == nil ? "New Template" : "Edit Template")
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
        let preset: ShiftPreset
        if let existingPreset {
            preset = existingPreset
        } else {
            preset = ShiftPreset(name: name)
            modelContext.insert(preset)
        }
        preset.name = name
        preset.startMinutes = startMinutes
        preset.durationMinutes = durationMinutes
        preset.breakMinutes = breakMinutes
        preset.jobName = jobName
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PresetsView()
    }
    .modelContainer(for: [Shift.self, Job.self, ShiftPreset.self], inMemory: true)
}

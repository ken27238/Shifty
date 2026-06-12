//
//  JobsView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct JobsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.name) private var jobs: [Job]

    @State private var isAddingJob = false
    @State private var jobBeingEdited: Job?
    @State private var jobPendingDeletion: Job?

    var body: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView {
                    Label("No Jobs", systemImage: "briefcase")
                } description: {
                    Text("Add a job with an hourly rate so your shifts can calculate earnings.")
                } actions: {
                    Button("Add Job") { isAddingJob = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(jobs.filter { !$0.archived }) { job in
                            jobRow(job)
                        }
                    }
                    let archived = jobs.filter(\.archived)
                    if !archived.isEmpty {
                        Section {
                            ForEach(archived) { job in
                                jobRow(job)
                            }
                        } header: {
                            Text("Archived")
                        } footer: {
                            Text("Archived jobs keep their shifts and pay history but don't appear when logging new shifts.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Job", systemImage: "plus") {
                    isAddingJob = true
                }
            }
        }
        .sheet(isPresented: $isAddingJob) {
            JobFormView()
        }
        .sheet(item: $jobBeingEdited) { job in
            JobFormView(job: job)
        }
        .confirmationDialog(
            "Delete this job?",
            isPresented: Binding(
                get: { jobPendingDeletion != nil },
                set: { if !$0 { jobPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: jobPendingDeletion
        ) { job in
            Button("Delete \(job.name)", role: .destructive) {
                withAnimation {
                    modelContext.delete(job)
                }
            }
        } message: { job in
            if (job.shifts ?? []).isEmpty {
                Text("This can't be undone.")
            } else {
                Text("Existing shifts will be kept but lose their job and earnings.")
            }
        }
    }

    private func jobRow(_ job: Job) -> some View {
        Button {
            jobBeingEdited = job
        } label: {
            JobRow(job: job)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button(
                job.archived ? "Unarchive" : "Archive",
                systemImage: job.archived ? "tray.and.arrow.up" : "archivebox"
            ) {
                withAnimation {
                    job.archived.toggle()
                }
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                jobPendingDeletion = job
            }
        }
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(job.color)
                .frame(width: 14, height: 14)
                .opacity(job.archived ? 0.4 : 1)
                .accessibilityHidden(true)
            Text(job.name)
                .font(.body)
                .foregroundStyle(job.archived ? .secondary : .primary)
            Spacer()
            Text(job.hourlyRate, format: .currency(code: Locale.currencyCode))
                .foregroundStyle(.secondary)
            Text("/ hr")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Add a new job (pass nothing) or edit an existing one (pass `job`).
struct JobFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let existingJob: Job?

    @State private var name: String
    // Optional so a new job's field starts empty instead of "$0.00".
    @State private var hourlyRate: Double?
    @State private var colorName: String
    @State private var locationName: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var isPickingLocation = false

    init(job: Job? = nil) {
        existingJob = job
        _name = State(initialValue: job?.name ?? "")
        _hourlyRate = State(initialValue: job?.hourlyRate)
        _colorName = State(initialValue: job?.colorName ?? "blue")
        _locationName = State(initialValue: job?.locationName ?? "")
        _latitude = State(initialValue: job?.latitude)
        _longitude = State(initialValue: job?.longitude)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (hourlyRate ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Hourly Rate") {
                        TextField(
                            "Hourly Rate",
                            value: $hourlyRate,
                            format: .currency(code: Locale.currencyCode)
                        )
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    }
                }

                Section {
                    if latitude != nil {
                        Label(locationName.isEmpty ? String(localized: "Location Set") : locationName,
                              systemImage: "mappin.and.ellipse")
                        Button("Change Location") { isPickingLocation = true }
                        Button("Remove Location", role: .destructive) {
                            locationName = ""
                            latitude = nil
                            longitude = nil
                        }
                    } else {
                        Button("Set Location", systemImage: "mappin.and.ellipse") {
                            isPickingLocation = true
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Shown on a map with your upcoming shift on the Home tab.")
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(Job.paletteOrder, id: \.self) { paletteName in
                            Button {
                                colorName = paletteName
                            } label: {
                                Circle()
                                    .fill(Job.palette[paletteName] ?? .gray)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorName == paletteName {
                                            Image(systemName: "checkmark")
                                                .font(.footnote.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(paletteName.capitalized))
                            .accessibilityAddTraits(
                                colorName == paletteName ? [.isSelected] : []
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(existingJob == nil ? "New Job" : "Edit Job")
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
            .sheet(isPresented: $isPickingLocation) {
                LocationPickerView { name, coordinate in
                    locationName = name
                    latitude = coordinate.latitude
                    longitude = coordinate.longitude
                }
            }
        }
    }

    private func save() {
        let job: Job
        if let existingJob {
            job = existingJob
        } else {
            job = Job(name: name, hourlyRate: max(hourlyRate ?? 0, 0), colorName: colorName)
            modelContext.insert(job)
        }
        job.name = name
        job.hourlyRate = max(hourlyRate ?? 0, 0)
        job.colorName = colorName
        job.locationName = locationName
        job.latitude = latitude
        job.longitude = longitude
        dismiss()
    }
}

#Preview {
    NavigationStack {
        JobsView()
    }
    .modelContainer(for: [Shift.self, Job.self, ShiftPreset.self], inMemory: true)
}

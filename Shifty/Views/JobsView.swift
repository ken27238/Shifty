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
                    ForEach(jobs) { job in
                        Button {
                            jobBeingEdited = job
                        } label: {
                            JobRow(job: job)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                jobPendingDeletion = job
                            }
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
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(job.color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(job.name)
                .font(.body)
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
    @State private var hourlyRate: Double
    @State private var colorName: String

    init(job: Job? = nil) {
        existingJob = job
        _name = State(initialValue: job?.name ?? "")
        _hourlyRate = State(initialValue: job?.hourlyRate ?? 0)
        _colorName = State(initialValue: job?.colorName ?? "blue")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && hourlyRate >= 0
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
        }
    }

    private func save() {
        if let job = existingJob {
            job.name = name
            job.hourlyRate = hourlyRate
            job.colorName = colorName
        } else {
            let job = Job(name: name, hourlyRate: hourlyRate, colorName: colorName)
            modelContext.insert(job)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        JobsView()
    }
    .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

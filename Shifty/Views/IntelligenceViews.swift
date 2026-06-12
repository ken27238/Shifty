//
//  IntelligenceViews.swift
//  Shifty
//

import SwiftUI

/// Describe one shift in plain language; the on-device model fills the form.
struct DescribeShiftView: View {
    @Environment(\.dismiss) private var dismiss
    let jobNames: [String]
    let onResult: (ResolvedShiftDraft) -> Void

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "9 to 5 at the cafe yesterday, 30 min break, $40 tips",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                } footer: {
                    Text("Describe the shift in your own words — date, times, job, break, and tips are picked out for you to review.")
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        if isWorking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Reading…")
                            }
                        } else {
                            Label("Fill Shift", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("Processed on this device by Apple Intelligence; nothing leaves your iPhone.")
                    }
                }
            }
            .navigationTitle("Describe Shift")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func run() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            if let draft = try await ShiftIntelligence.parseShift(from: text, jobNames: jobNames) {
                onResult(draft)
                dismiss()
            } else {
                errorMessage = String(localized: "Couldn't work out the times from that — try including a start and end time.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Paste a schedule (an email, a group chat message, a posted roster) and
/// review the extracted shifts before importing.
struct ScheduleImportView: View {
    @Environment(\.dismiss) private var dismiss
    let jobNames: [String]
    let onImport: ([ResolvedShiftDraft]) -> Void

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var drafts: [ResolvedShiftDraft]?
    @State private var excluded: Set<UUID> = []

    private var selectedDrafts: [ResolvedShiftDraft] {
        (drafts ?? []).filter { !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let drafts {
                    reviewList(drafts)
                } else {
                    pasteForm
                }
            }
            .navigationTitle("Import from Text")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                if drafts != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(selectedDrafts.count)") {
                            onImport(selectedDrafts)
                            dismiss()
                        }
                        .disabled(selectedDrafts.isEmpty)
                    }
                }
            }
        }
    }

    private var pasteForm: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
            } header: {
                Text("Paste your schedule")
            } footer: {
                Text("An email, a message, or a typed-out roster all work. Every shift found is shown for review before anything is saved.")
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    if isWorking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Finding shifts…")
                        }
                    } else {
                        Label("Find Shifts", systemImage: "wand.and.stars")
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else {
                    Text("Processed on this device by Apple Intelligence; nothing leaves your iPhone.")
                }
            }
        }
    }

    private func reviewList(_ drafts: [ResolvedShiftDraft]) -> some View {
        List {
            Section {
                ForEach(drafts) { draft in
                    Button {
                        if excluded.contains(draft.id) {
                            excluded.remove(draft.id)
                        } else {
                            excluded.insert(draft.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: excluded.contains(draft.id) ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(excluded.contains(draft.id) ? .secondary : Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(draft.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(draft.jobName.isEmpty ? String(localized: "Shift") : draft.jobName)")
                                    .font(.subheadline.weight(.medium))
                                Text("\(draft.start.formatted(date: .omitted, time: .shortened)) – \(draft.end.formatted(date: .omitted, time: .shortened))\(draft.breakMinutes > 0 ? " · \(draft.breakMinutes) min break" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Found \(drafts.count) shifts")
            } footer: {
                Text("Tap a shift to leave it out. Import adds the checked shifts; you can edit them afterwards like any other.")
            }

            Section {
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    self.drafts = nil
                    excluded = []
                }
            }
        }
    }

    private func run() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let found = try await ShiftIntelligence.parseSchedule(from: text, jobNames: jobNames)
            if found.isEmpty {
                errorMessage = String(localized: "No shifts found in that text — make sure it includes dates and times.")
            } else {
                drafts = found
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

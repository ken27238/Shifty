//
//  SettingsView.swift
//  Shifty
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Job.name) private var jobs: [Job]
    @Query(sort: \Shift.start) private var allShifts: [Shift]

    // Shift defaults
    @AppStorage(SettingsKeys.defaultStartMinutes, store: .shared) private var defaultStartMinutes = 9 * 60
    @AppStorage(SettingsKeys.defaultDurationHours, store: .shared) private var defaultDurationHours = 8.0
    @AppStorage(SettingsKeys.defaultBreakMinutes, store: .shared) private var defaultBreakMinutes = 0
    @AppStorage(SettingsKeys.defaultJobName, store: .shared) private var defaultJobName = ""
    @AppStorage(SettingsKeys.tipsEnabled, store: .shared) private var tipsEnabled = true

    // Pay
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false
    @AppStorage(SettingsKeys.overtimeWeekly, store: .shared) private var overtimeWeekly = true
    @AppStorage(SettingsKeys.overtimeThreshold, store: .shared) private var overtimeThreshold = 40.0
    @AppStorage(SettingsKeys.overtimeMultiplier, store: .shared) private var overtimeMultiplier = 1.5
    @AppStorage(SettingsKeys.takeHomePercent, store: .shared) private var takeHomePercent = 0.0
    @AppStorage(SettingsKeys.currencyOverride, store: .shared) private var currencyOverride = ""
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0

    // Reminders
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderLeadMinutes") private var reminderLeadMinutes = 60

    // Sync & appearance
    @AppStorage(SettingsKeys.iCloudSyncEnabled, store: .shared) private var iCloudSyncEnabled = true
    @AppStorage(SettingsKeys.appearance, store: .shared) private var appearance = "system"
    @AppStorage(SettingsKeys.accentColorName, store: .shared) private var accentColorName = ""

    @State private var notificationsDenied = false
    @State private var isExportingCSV = false
    @State private var csvDocument = CSVDocument(text: "")
    @State private var isConfirmingDeleteAll = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var defaultStartTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: defaultStartMinutes / 60,
                    minute: defaultStartMinutes % 60,
                    second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                defaultStartMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                jobsSection
                shiftDefaultsSection
                paySection
                remindersSection
                syncSection
                appearanceSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                notificationsDenied = await ReminderScheduler.isAuthorizationDenied()
            }
            .fileExporter(
                isPresented: $isExportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "Shifty Shifts"
            ) { _ in }
            .confirmationDialog(
                "Delete all data?",
                isPresented: $isConfirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All Shifts and Jobs", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This permanently deletes every shift and job. This can't be undone.")
            }
        }
    }

    // MARK: Sections

    private var jobsSection: some View {
        Section {
            NavigationLink {
                JobsView()
            } label: {
                LabeledContent("Jobs") {
                    Text(jobs.count, format: .number)
                }
            }
        } footer: {
            Text("Jobs hold the hourly rate used to calculate earnings for your shifts.")
        }
    }

    private var shiftDefaultsSection: some View {
        Section("New Shift Defaults") {
            DatePicker("Start Time", selection: defaultStartTime, displayedComponents: .hourAndMinute)
            Stepper(value: $defaultDurationHours, in: 0.5...16, step: 0.5) {
                LabeledContent("Duration") {
                    Text("\(defaultDurationHours.formatted(.number.precision(.fractionLength(0...1)))) hrs")
                }
            }
            Stepper(value: $defaultBreakMinutes, in: 0...240, step: 5) {
                LabeledContent("Break") {
                    Text("\(defaultBreakMinutes) min")
                }
            }
            Picker("Default Job", selection: $defaultJobName) {
                Text("None").tag("")
                ForEach(jobs) { job in
                    Text(job.name).tag(job.name)
                }
            }
            Toggle("Track Tips", isOn: $tipsEnabled)
        }
    }

    private var paySection: some View {
        Section {
            Toggle("Overtime Pay", isOn: $overtimeEnabled)
            if overtimeEnabled {
                Picker("Counted Per", selection: $overtimeWeekly) {
                    Text("Week").tag(true)
                    Text("Day").tag(false)
                }
                Stepper(value: $overtimeThreshold, in: 1...80, step: 1) {
                    LabeledContent("After") {
                        Text("\(overtimeThreshold.formatted(.number.precision(.fractionLength(0)))) hrs")
                    }
                }
                Picker("Rate", selection: $overtimeMultiplier) {
                    Text("1.25×").tag(1.25)
                    Text("1.5×").tag(1.5)
                    Text("1.75×").tag(1.75)
                    Text("2×").tag(2.0)
                }
            }
            Stepper(value: $takeHomePercent, in: 0...50, step: 1) {
                LabeledContent("Est. Deductions") {
                    Text(takeHomePercent == 0
                         ? String(localized: "Off")
                         : "\(takeHomePercent.formatted(.number.precision(.fractionLength(0))))%")
                }
            }
            Picker("Currency", selection: $currencyOverride) {
                Text("System Default").tag("")
                ForEach(Locale.commonISOCurrencyCodes, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            .pickerStyle(.navigationLink)
            Picker("Week Starts On", selection: $weekStartDay) {
                Text("System Default").tag(0)
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
            }
        } header: {
            Text("Pay")
        } footer: {
            Text("Overtime applies the higher rate to hours past the threshold. Deductions show an estimated take-home amount in the Pay tab.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Shift Reminders", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { _, enabled in
                    if enabled {
                        Task {
                            _ = await ReminderScheduler.requestAuthorization()
                            notificationsDenied = await ReminderScheduler.isAuthorizationDenied()
                        }
                    }
                }
            if remindersEnabled {
                Picker("Remind Me", selection: $reminderLeadMinutes) {
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if remindersEnabled && notificationsDenied {
                Text("Notifications are turned off for Shifty. Enable them in Settings to get shift reminders.")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
        } header: {
            Text("iCloud")
        } footer: {
            Text("Syncs shifts and jobs across your devices. Changing this takes effect the next time the app launches.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Accent Color", selection: $accentColorName) {
                Text("Default").tag("")
                ForEach(Job.paletteOrder, id: \.self) { name in
                    Text(name.capitalized).tag(name)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button("Export Shifts as CSV", systemImage: "square.and.arrow.up") {
                csvDocument = CSVDocument(text: makeCSV())
                isExportingCSV = true
            }
            .disabled(allShifts.isEmpty)

            Button("Delete All Data", systemImage: "trash", role: .destructive) {
                isConfirmingDeleteAll = true
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    // MARK: Actions

    private func makeCSV() -> String {
        func field(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        var lines = ["Date,Start,End,Break (min),Hours,Job,Hourly Rate,Tips,Earnings,Notes"]
        let adjusted = PayCalculator.earningsByShift(for: allShifts)
        for shift in allShifts {
            lines.append([
                field(shift.start.formatted(date: .numeric, time: .omitted)),
                field(shift.start.formatted(date: .omitted, time: .shortened)),
                field(shift.end.formatted(date: .omitted, time: .shortened)),
                "\(shift.breakMinutes)",
                shift.workedHours.formatted(.number.precision(.fractionLength(0...2))),
                field(shift.job?.name ?? ""),
                (shift.job?.hourlyRate ?? 0).formatted(.number.precision(.fractionLength(0...2))),
                shift.tips.formatted(.number.precision(.fractionLength(0...2))),
                (adjusted[shift.persistentModelID] ?? shift.earnings)
                    .formatted(.number.precision(.fractionLength(0...2))),
                field(shift.notes),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func deleteAllData() {
        withAnimation {
            try? modelContext.delete(model: Shift.self)
            try? modelContext.delete(model: Job.self)
        }
        refreshWidgets()
    }
}

/// Plain-text CSV wrapper for the file exporter.
nonisolated struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Shift.self, Job.self], inMemory: true)
}

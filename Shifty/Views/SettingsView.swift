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
    @AppStorage(SettingsKeys.payCycle, store: .shared) private var payCycle = "weekly"
    @AppStorage(SettingsKeys.payAnchor, store: .shared) private var payAnchor = 0.0
    @AppStorage(SettingsKeys.weeklyGoal, store: .shared) private var weeklyGoal = 0.0
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
    @AppStorage("tipRemindersEnabled") private var tipRemindersEnabled = false
    @AppStorage("weeklySummaryEnabled") private var weeklySummaryEnabled = false

    // Sync & appearance
    @AppStorage(SettingsKeys.iCloudSyncEnabled, store: .shared) private var iCloudSyncEnabled = true
    @AppStorage(SettingsKeys.appearance, store: .shared) private var appearance = "system"
    @AppStorage(SettingsKeys.accentColorName, store: .shared) private var accentColorName = ""

    @State private var notificationsDenied = false
    @State private var isExportingCSV = false
    @State private var csvDocument = CSVDocument(text: "")
    @State private var isImportingCSV = false
    @State private var importMessage: String?
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
                ForEach(jobs.filter { !$0.archived }) { job in
                    Text(job.name).tag(job.name)
                }
            }
            Toggle("Track Tips", isOn: $tipsEnabled)
            NavigationLink("Shift Templates") {
                PresetsView()
            }
        }
    }

    private var anchorPayday: Binding<Date> {
        Binding(
            get: {
                payAnchor > 0 ? Date(timeIntervalSinceReferenceDate: payAnchor) : .now
            },
            set: { date in
                payAnchor = Calendar.app.startOfDay(for: date).timeIntervalSinceReferenceDate
            }
        )
    }

    private var paySection: some View {
        Section {
            Picker("Pay Cycle", selection: $payCycle) {
                Text("Weekly").tag("weekly")
                Text("Every 2 Weeks").tag("biweekly")
                Text("Twice a Month").tag("semimonthly")
                Text("Monthly").tag("monthly")
            }
            if payCycle == "biweekly" {
                DatePicker(
                    "A Recent Payday",
                    selection: anchorPayday,
                    displayedComponents: .date
                )
            }
            LabeledContent("Weekly Goal") {
                TextField(
                    "Weekly Goal",
                    value: $weeklyGoal,
                    format: .currency(code: Locale.currencyCode)
                )
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            }
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
                // Any weekday, so weeks can match an employer's pay schedule.
                ForEach(1...7, id: \.self) { weekday in
                    Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                }
            }
        } header: {
            Text("Pay")
        } footer: {
            Text("The pay cycle drives the Pay tab's pay-period mode and payday countdown. For Every 2 Weeks, set any payday so periods line up, and set Week Starts On to the day your work week begins. A weekly goal (\(0.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) = off) shows progress on Home and in Pay.")
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
            if tipsEnabled {
                Toggle("Tip Reminders", isOn: $tipRemindersEnabled)
                    .onChange(of: tipRemindersEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await ReminderScheduler.requestAuthorization() }
                        }
                    }
            }
            Toggle("Weekly Summary", isOn: $weeklySummaryEnabled)
                .onChange(of: weeklySummaryEnabled) { _, enabled in
                    if enabled {
                        Task { _ = await ReminderScheduler.requestAuthorization() }
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
                csvDocument = CSVDocument(text: CSVDocument.csv(for: allShifts))
                isExportingCSV = true
            }
            .disabled(allShifts.isEmpty)

            Button("Import Shifts from CSV", systemImage: "square.and.arrow.down") {
                isImportingCSV = true
            }

            Button("Delete All Data", systemImage: "trash", role: .destructive) {
                isConfirmingDeleteAll = true
            }
        }
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url):
                importCSV(from: url)
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .alert(
            "Import Shifts",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    // MARK: Actions

    /// Imports shifts from a CSV in this app's export format, creating
    /// jobs by name as needed.
    private func importCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importMessage = String(localized: "Couldn't access that file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            importMessage = String(localized: "Couldn't read that file as text.")
            return
        }

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1, lines[0].hasPrefix("Date,Start,End,Break") else {
            importMessage = String(localized: "That file doesn't match Shifty's CSV format. Export a CSV from Shifty to see the expected columns.")
            return
        }
        // Columns: Date,Start,End,Break,Hours,Job,Rate,Tips[,Mileage,Expenses],Earnings,Notes
        let hasMileageColumns = lines[0].contains("Mileage")

        let parseStyle = Date.FormatStyle(date: .numeric, time: .shortened)
        var imported = 0
        var jobsByName = Dictionary(grouping: jobs, by: \.name).compactMapValues(\.first)

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count >= (hasMileageColumns ? 12 : 10),
                  let start = try? parseStyle.parse("\(fields[0]), \(fields[1])"),
                  var end = try? parseStyle.parse("\(fields[0]), \(fields[2])")
            else { continue }
            if end <= start {
                end = Calendar.app.date(byAdding: .day, value: 1, to: end) ?? end
            }

            var job: Job?
            let jobName = fields[5]
            if !jobName.isEmpty {
                if let existing = jobsByName[jobName] {
                    job = existing
                } else {
                    let newJob = Job(name: jobName, hourlyRate: Double(fields[6]) ?? 0)
                    modelContext.insert(newJob)
                    jobsByName[jobName] = newJob
                    job = newJob
                }
            }

            let shift = Shift(
                start: start,
                end: end,
                breakMinutes: Int(fields[3]) ?? 0,
                tips: Double(fields[7]) ?? 0,
                notes: fields.last ?? "",
                job: job
            )
            if hasMileageColumns {
                shift.mileage = Double(fields[8]) ?? 0
                shift.expenses = Double(fields[9]) ?? 0
            }
            modelContext.insert(shift)
            imported += 1
        }

        refreshWidgets()
        importMessage = String(localized: "Imported \(imported) shifts.")
    }

    /// Splits one CSV line, honoring quoted fields with escaped quotes.
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
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

    @MainActor
    static func csv(for shifts: [Shift]) -> String {
        func field(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        // No digit grouping: separators would collide with the CSV commas.
        let number = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2)).grouping(.never)

        var lines = ["Date,Start,End,Break (min),Hours,Job,Hourly Rate,Tips,Mileage,Expenses,Earnings,Notes"]
        let adjusted = PayCalculator.earningsByShift(for: shifts)
        for shift in shifts {
            lines.append([
                field(shift.start.formatted(date: .numeric, time: .omitted)),
                field(shift.start.formatted(date: .omitted, time: .shortened)),
                field(shift.end.formatted(date: .omitted, time: .shortened)),
                "\(shift.breakMinutes)",
                shift.workedHours.formatted(number),
                field(shift.job?.name ?? ""),
                (shift.job?.hourlyRate ?? 0).formatted(number),
                shift.tips.formatted(number),
                shift.mileage.formatted(number),
                shift.expenses.formatted(number),
                (adjusted[shift.persistentModelID] ?? shift.earnings).formatted(number),
                field(shift.notes),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: ShiftyModels.all, inMemory: true)
}

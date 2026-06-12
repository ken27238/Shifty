//
//  PayView.swift
//  Shifty
//

import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct PayView: View {
    private enum Period: String, CaseIterable, Identifiable {
        case week = "Week"
        case payPeriod = "Pay Period"
        case month = "Month"

        var id: Self { self }
    }

    @Binding var selectedTab: AppTab
    /// Set by other tabs (e.g. tapping a week header in Shifts) to scope
    /// this view to a specific week; consumed and cleared on arrival.
    @Binding var requestedDate: Date?
    /// Set alongside switching to the Shifts tab to filter it to a job.
    @Binding var jobFilterRequest: String?

    @Query private var shifts: [Shift]

    @State private var period: Period = .week
    /// Any date inside the period currently being viewed.
    @State private var referenceDate: Date = .now
    @State private var isExportingCSV = false
    @State private var csvDocument = CSVDocument(text: "")
    @State private var isExportingPDF = false
    @State private var pdfDocument = PDFFileDocument(data: Data())

    // Declared so the view refreshes when these settings change.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0
    @AppStorage(SettingsKeys.payCycle, store: .shared) private var payCycleSetting = "weekly"
    @AppStorage(SettingsKeys.payAnchor, store: .shared) private var payAnchor = 0.0
    @AppStorage(SettingsKeys.weeklyGoal, store: .shared) private var weeklyGoal = 0.0
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false
    @AppStorage(SettingsKeys.overtimeWeekly, store: .shared) private var overtimeWeekly = true
    @AppStorage(SettingsKeys.overtimeThreshold, store: .shared) private var overtimeThreshold = 40.0
    @AppStorage(SettingsKeys.overtimeMultiplier, store: .shared) private var overtimeMultiplier = 1.5
    @AppStorage(SettingsKeys.takeHomePercent, store: .shared) private var takeHomePercent = 0.0
    @AppStorage(SettingsKeys.currencyOverride, store: .shared) private var currencyOverride = ""
    @AppStorage(SettingsKeys.tipsEnabled, store: .shared) private var tipsEnabled = true

    private var calendar: Calendar { .app }

    private var payCycle: PayCycle { PayCycle.load() }

    /// The weekly cycle makes the Pay Period segment redundant.
    private var availablePeriods: [Period] {
        payCycle == .weekly ? [.week, .month] : Period.allCases
    }

    // MARK: Period math

    private func interval(containing date: Date) -> DateInterval {
        let fallback = DateInterval(start: date, duration: 0)
        switch period {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? fallback
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? fallback
        case .payPeriod:
            return PayPeriods.interval(containing: date, cycle: payCycle, calendar: calendar)
        }
    }

    private var interval: DateInterval { interval(containing: referenceDate) }

    private var previousInterval: DateInterval {
        interval(containing: interval.start.addingTimeInterval(-1))
    }

    private func shifts(in interval: DateInterval) -> [Shift] {
        shifts.filter { interval.contains($0.start) }
    }

    private var periodShifts: [Shift] { shifts(in: interval) }

    // MARK: Totals

    private var earningsByShift: [PersistentIdentifier: Double] {
        PayCalculator.earningsByShift(for: periodShifts, calendar: calendar)
    }

    private var totalEarnings: Double {
        earningsByShift.values.reduce(0, +)
    }

    private var totalHours: Double {
        periodShifts.reduce(0) { $0 + $1.workedHours }
    }

    private var totalTips: Double {
        periodShifts.reduce(0) { $0 + $1.tips }
    }

    /// Pay at the base rate, before overtime and tips.
    private var basePay: Double {
        periodShifts.reduce(0) { $0 + $1.workedHours * ($1.job?.hourlyRate ?? 0) }
    }

    private var overtimeExtra: Double {
        max(0, totalEarnings - totalTips - basePay)
    }

    private var previousEarnings: Double {
        PayCalculator.totalEarnings(for: shifts(in: previousInterval), calendar: calendar)
    }

    private var previousHasShifts: Bool {
        !shifts(in: previousInterval).isEmpty
    }

    /// Earnings and hours per job in the period, highest earnings first.
    private var jobBreakdown: [(name: String, jobName: String?, color: Color, hours: Double, earnings: Double)] {
        let adjusted = earningsByShift
        let grouped = Dictionary(grouping: periodShifts) { $0.job?.name ?? String(localized: "No Job") }
        return grouped
            .map { name, shifts in
                (
                    name: name,
                    jobName: shifts.first?.job?.name,
                    color: shifts.first?.job?.color ?? Color.gray,
                    hours: shifts.reduce(0) { $0 + $1.workedHours },
                    earnings: shifts.reduce(0) { $0 + (adjusted[$1.persistentModelID] ?? $1.earnings) }
                )
            }
            .sorted { $0.earnings > $1.earnings }
    }

    /// One chart entry per day per job, so bars stack by job color.
    private var dailyEarnings: [(id: String, day: Date, jobName: String, earnings: Double)] {
        let adjusted = earningsByShift
        return periodShifts
            .map { shift in
                let day = calendar.startOfDay(for: shift.start)
                let jobName = shift.job?.name ?? String(localized: "No Job")
                return (
                    id: "\(day.timeIntervalSinceReferenceDate)-\(jobName)-\(shift.persistentModelID)",
                    day: day,
                    jobName: jobName,
                    earnings: adjusted[shift.persistentModelID] ?? shift.earnings
                )
            }
            .sorted { $0.day < $1.day }
    }

    /// Recent periods at the current granularity, oldest first.
    private var trend: [(start: Date, label: String, earnings: Double)] {
        var items: [(start: Date, label: String, earnings: Double)] = []
        var current = interval
        let count = period == .month ? 6 : 8
        for _ in 0..<count {
            let label = period == .month
                ? current.start.formatted(.dateTime.month(.abbreviated))
                : current.start.formatted(.dateTime.month(.defaultDigits).day())
            items.append((
                start: current.start,
                label: label,
                earnings: PayCalculator.totalEarnings(for: shifts(in: current), calendar: calendar)
            ))
            current = interval(containing: current.start.addingTimeInterval(-1))
        }
        return items.reversed()
    }

    // MARK: Payday

    private var currentPayPeriod: DateInterval {
        PayPeriods.interval(containing: .now, cycle: payCycle, calendar: calendar)
    }

    private var nextPayday: Date {
        currentPayPeriod.end.addingTimeInterval(-1)
    }

    private var expectedPay: Double {
        PayCalculator.totalEarnings(for: shifts(in: currentPayPeriod), calendar: calendar)
    }

    // MARK: Titles

    private var periodTitle: String {
        switch period {
        case .week:
            if calendar.isDate(referenceDate, equalTo: .now, toGranularity: .weekOfYear) {
                return String(localized: "This Week")
            }
            return rangeTitle(interval)
        case .payPeriod:
            return rangeTitle(interval)
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func rangeTitle(_ interval: DateInterval) -> String {
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var isViewingCurrentPeriod: Bool {
        interval.contains(.now)
    }

    var body: some View {
        NavigationStack {
            List {
                pickerSection
                paydaySection
                totalsSection

                if period == .week, weeklyGoal > 0 {
                    goalSection
                }

                if periodShifts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Pay This Period",
                            systemImage: "banknote",
                            description: Text("Log shifts to see your earnings here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if jobBreakdown.count > 1 {
                        byJobSection
                    }
                    chartSection
                }

                trendSection
            }
            .navigationTitle("Pay")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Export Period", systemImage: "square.and.arrow.up") {
                        Button("Export as CSV", systemImage: "tablecells") {
                            csvDocument = CSVDocument(text: CSVDocument.csv(for: periodShifts))
                            isExportingCSV = true
                        }
                        Button("Export as PDF", systemImage: "doc.richtext") {
                            pdfDocument = PDFFileDocument(data: makePDFData())
                            isExportingPDF = true
                        }
                    }
                    .disabled(periodShifts.isEmpty)
                }
            }
            .fileExporter(
                isPresented: $isExportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "Shifty \(periodTitle)"
            ) { _ in }
            .fileExporter(
                isPresented: $isExportingPDF,
                document: pdfDocument,
                contentType: .pdf,
                defaultFilename: "Shifty \(periodTitle)"
            ) { _ in }
            .onAppear { applyRequestedDate() }
            .onChange(of: requestedDate) { _, _ in applyRequestedDate() }
        }
    }

    // MARK: Sections

    private var pickerSection: some View {
        Section {
            Picker("Period", selection: $period) {
                ForEach(availablePeriods) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var paydaySection: some View {
        Section {
            LabeledContent("Next Payday") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(nextPayday.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    Text(nextPayday, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent(takeHomePercent > 0 ? "Expected Take-Home" : "Expected Pay") {
                Text(
                    expectedPay * (1 - takeHomePercent / 100),
                    format: .currency(code: Locale.currencyCode)
                )
                .fontWeight(.medium)
            }
        } footer: {
            Text("Based on your \(cycleDescription) pay cycle.")
        }
    }

    private var cycleDescription: String {
        switch payCycle {
        case .weekly: String(localized: "weekly")
        case .biweekly: String(localized: "biweekly")
        case .semimonthly: String(localized: "twice-monthly")
        case .monthly: String(localized: "monthly")
        }
    }

    private var totalsSection: some View {
        Section {
            HStack {
                Button("Previous", systemImage: "chevron.backward") {
                    step(by: -1)
                }
                .labelStyle(.iconOnly)

                Spacer()
                Text(periodTitle)
                    .font(.headline)
                Spacer()

                Button("Next", systemImage: "chevron.forward") {
                    step(by: 1)
                }
                .labelStyle(.iconOnly)
                .disabled(isViewingCurrentPeriod)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Earnings") {
                    Text(totalEarnings, format: .currency(code: Locale.currencyCode))
                        .font(.headline)
                }
                if previousHasShifts, abs(totalEarnings - previousEarnings) > 0.005 {
                    comparisonLabel
                }
            }

            if overtimeExtra > 0.005 || (tipsEnabled && totalTips > 0) {
                LabeledContent("Base Pay") {
                    Text(basePay, format: .currency(code: Locale.currencyCode))
                }
                if overtimeExtra > 0.005 {
                    LabeledContent("Overtime") {
                        Text("+\(overtimeExtra.formatted(.currency(code: Locale.currencyCode)))")
                            .foregroundStyle(.orange)
                    }
                }
                if tipsEnabled, totalTips > 0 {
                    LabeledContent("Tips") {
                        Text(totalTips, format: .currency(code: Locale.currencyCode))
                    }
                }
            }

            if periodShifts.contains(where: { $0.expenses > 0 }) {
                LabeledContent("Expenses") {
                    Text("−\(periodShifts.reduce(0) { $0 + $1.expenses }.formatted(.currency(code: Locale.currencyCode)))")
                        .foregroundStyle(.secondary)
                }
            }
            if periodShifts.contains(where: { $0.mileage > 0 }) {
                LabeledContent("Mileage") {
                    Text("\(periodShifts.reduce(0) { $0 + $1.mileage }.formatted(.number.precision(.fractionLength(0...1)))) mi")
                }
            }
            if totalHours > 0 {
                LabeledContent("Avg. Hourly Rate") {
                    Text(totalEarnings / totalHours, format: .currency(code: Locale.currencyCode))
                }
            }
            LabeledContent("Hours") {
                Text(totalHours.formatted(.number.precision(.fractionLength(0...1))))
            }
            if takeHomePercent > 0 {
                LabeledContent("Est. Take-Home") {
                    Text(totalEarnings * (1 - takeHomePercent / 100),
                         format: .currency(code: Locale.currencyCode))
                }
            }
            LabeledContent("Shifts", value: periodShifts.count, format: .number)
        }
    }

    private var comparisonLabel: some View {
        let delta = totalEarnings - previousEarnings
        let percent = previousEarnings > 0 ? Int((delta / previousEarnings * 100).rounded()) : nil

        return Label {
            Text("\(abs(delta).formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))\(percent.map { " (\(abs($0))%)" } ?? "") \(delta > 0 ? "more" : "less") than the previous \(periodNoun)")
        } icon: {
            Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
        }
        .font(.footnote)
        .foregroundStyle(delta > 0 ? .green : .red)
    }

    private var periodNoun: String {
        switch period {
        case .week: String(localized: "week")
        case .payPeriod: String(localized: "pay period")
        case .month: String(localized: "month")
        }
    }

    private var goalSection: some View {
        Section("Weekly Goal") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(totalEarnings, weeklyGoal), total: max(weeklyGoal, 0.01))
                Text("\(totalEarnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) of \(weeklyGoal.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) · \(Int(min(totalEarnings / max(weeklyGoal, 0.01), 1) * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var byJobSection: some View {
        Section("By Job") {
            ForEach(jobBreakdown, id: \.name) { entry in
                Button {
                    if let jobName = entry.jobName {
                        jobFilterRequest = jobName
                        selectedTab = .shifts
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(entry.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.earnings, format: .currency(code: Locale.currencyCode))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(entry.hours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(totalEarnings > 0 ? Int((entry.earnings / totalEarnings * 100).rounded()) : 0)%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if entry.jobName != nil {
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(entry.jobName == nil)
                .accessibilityHint(entry.jobName == nil ? "" : "Shows these shifts in the Shifts tab")
            }
        }
    }

    private var chartSection: some View {
        Section("Earnings by Day") {
            Chart(dailyEarnings, id: \.id) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("Earnings", entry.earnings)
                )
                .foregroundStyle(by: .value("Job", entry.jobName))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(
                domain: jobBreakdown.map(\.name),
                range: jobBreakdown.map(\.color)
            )
            .chartLegend(jobBreakdown.count > 1 ? .visible : .hidden)
            .chartXAxis {
                if period == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else {
                    AxisMarks()
                }
            }
            .frame(height: 200)
            .padding(.vertical, 8)
            .accessibilityLabel("Bar chart of earnings per day")
        }
    }

    private var trendSection: some View {
        Section("Trend") {
            Chart(trend, id: \.start) { entry in
                BarMark(
                    x: .value("Period", entry.label),
                    y: .value("Earnings", entry.earnings)
                )
                .foregroundStyle(
                    entry.start == interval.start
                        ? Color.accentColor
                        : Color.accentColor.opacity(0.35)
                )
                .cornerRadius(3)
            }
            .frame(height: 140)
            .padding(.vertical, 8)
            .accessibilityLabel("Bar chart of earnings for recent \(periodNoun)s; the highlighted bar is the displayed \(periodNoun)")
        }
    }

    // MARK: Actions

    private func applyRequestedDate() {
        guard let date = requestedDate else { return }
        period = .week
        referenceDate = date
        requestedDate = nil
    }

    private func step(by value: Int) {
        let newReference = value > 0
            ? interval.end.addingTimeInterval(1)
            : interval.start.addingTimeInterval(-1)
        withAnimation {
            referenceDate = newReference
        }
    }

    /// Renders a one-page pay summary as PDF data (US Letter width).
    private func makePDFData() -> Data {
        let content = PaySummaryPDF(
            periodTitle: periodTitle,
            totalEarnings: totalEarnings,
            totalHours: totalHours,
            totalTips: tipsEnabled ? totalTips : 0,
            basePay: basePay,
            overtimeExtra: overtimeExtra,
            takeHome: takeHomePercent > 0 ? totalEarnings * (1 - takeHomePercent / 100) : nil,
            shiftCount: periodShifts.count,
            breakdown: jobBreakdown.map { ($0.name, $0.hours, $0.earnings) }
        )
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)

        let data = NSMutableData()
        renderer.render { size, render in
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: max(size.height, 792))
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }
}

/// Fixed light styling: PDFs shouldn't inherit the device's dark mode.
private struct PaySummaryPDF: View {
    let periodTitle: String
    let totalEarnings: Double
    let totalHours: Double
    let totalTips: Double
    let basePay: Double
    let overtimeExtra: Double
    let takeHome: Double?
    let shiftCount: Int
    let breakdown: [(name: String, hours: Double, earnings: Double)]

    private var currency: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: Locale.currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shifty Pay Summary")
                    .font(.title.bold())
                Text(periodTitle)
                    .font(.title3)
                    .foregroundStyle(.gray)
            }

            VStack(spacing: 6) {
                row("Earnings", totalEarnings.formatted(currency), bold: true)
                if overtimeExtra > 0.005 || totalTips > 0 {
                    row("Base Pay", basePay.formatted(currency))
                    if overtimeExtra > 0.005 {
                        row("Overtime", "+" + overtimeExtra.formatted(currency))
                    }
                    if totalTips > 0 {
                        row("Tips", totalTips.formatted(currency))
                    }
                }
                if let takeHome {
                    row("Est. Take-Home", takeHome.formatted(currency))
                }
                row("Hours", totalHours.formatted(.number.precision(.fractionLength(0...1))))
                row("Shifts", shiftCount.formatted())
            }

            if breakdown.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("By Job")
                        .font(.headline)
                    ForEach(breakdown, id: \.name) { entry in
                        row(
                            entry.name,
                            "\(entry.hours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(entry.earnings.formatted(currency))"
                        )
                    }
                }
            }

            Text("Generated by Shifty on \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                .font(.footnote)
                .foregroundStyle(.gray)
        }
        .frame(width: 612 - 96, alignment: .leading)
        .padding(48)
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(bold ? .black : .gray)
            Spacer()
            Text(value)
                .fontWeight(bold ? .bold : .regular)
        }
        .font(bold ? .title3 : .body)
    }
}

/// PDF wrapper for the file exporter.
nonisolated struct PDFFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    PayView(
        selectedTab: .constant(.pay),
        requestedDate: .constant(nil),
        jobFilterRequest: .constant(nil)
    )
    .modelContainer(for: [Shift.self, Job.self, ShiftPreset.self], inMemory: true)
}

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

    // MARK: Stats (computed once per render)

    private struct JobSlice {
        let name: String
        let jobName: String?
        let color: Color
        let hours: Double
        let earnings: Double
    }

    private struct DailySlice: Identifiable {
        let id: String
        let day: Date
        let jobName: String
        let earnings: Double
    }

    /// Everything the sections display, derived from one pass over the
    /// shifts plus one overtime-calculator run for the visible period.
    private struct PeriodStats {
        var shifts: [Shift] = []
        var totalEarnings = 0.0
        var hours = 0.0
        var tips = 0.0
        var basePay = 0.0
        var mileage = 0.0
        var expenses = 0.0
        var previousEarnings = 0.0
        var previousHasShifts = false
        var breakdown: [JobSlice] = []
        var daily: [DailySlice] = []
        var trend: [(start: Date, label: String, earnings: Double)] = []

        var overtimeExtra: Double { max(0, totalEarnings - tips - basePay) }
    }

    private func makeStats() -> PeriodStats {
        var stats = PeriodStats()
        let interval = interval
        let previous = previousInterval

        // The trend's older periods, newest first, excluding the visible one.
        var trendIntervals: [DateInterval] = [interval]
        for _ in 1..<(period == .month ? 6 : 8) {
            if let last = trendIntervals.last {
                trendIntervals.append(self.interval(containing: last.start.addingTimeInterval(-1)))
            }
        }
        var trendTotals = [Double](repeating: 0, count: trendIntervals.count)
        var trendShifts = [[Shift]](repeating: [], count: trendIntervals.count)

        var previousShifts: [Shift] = []
        for shift in shifts {
            if interval.contains(shift.start) {
                stats.shifts.append(shift)
                stats.hours += shift.workedHours
                stats.tips += shift.tips
                stats.basePay += shift.workedHours * (shift.job?.hourlyRate ?? 0)
                stats.mileage += shift.mileage
                stats.expenses += shift.expenses
            }
            if previous.contains(shift.start) {
                previousShifts.append(shift)
            }
            for (index, trendInterval) in trendIntervals.enumerated() where trendInterval.contains(shift.start) {
                trendShifts[index].append(shift)
            }
        }

        let adjusted = PayCalculator.earningsByShift(for: stats.shifts, calendar: calendar)
        stats.totalEarnings = adjusted.values.reduce(0, +)
        stats.previousHasShifts = !previousShifts.isEmpty
        stats.previousEarnings = PayCalculator.totalEarnings(for: previousShifts, calendar: calendar)

        for index in trendIntervals.indices {
            trendTotals[index] = index == 0
                ? stats.totalEarnings
                : PayCalculator.totalEarnings(for: trendShifts[index], calendar: calendar)
        }
        stats.trend = Array(zip(trendIntervals, trendTotals).map { trendInterval, total in
            let label = period == .month
                ? trendInterval.start.formatted(.dateTime.month(.abbreviated))
                : trendInterval.start.formatted(.dateTime.month(.defaultDigits).day())
            return (start: trendInterval.start, label: label, earnings: total)
        }.reversed())

        let grouped = Dictionary(grouping: stats.shifts) { $0.job?.name ?? String(localized: "No Job") }
        stats.breakdown = grouped
            .map { name, shifts in
                JobSlice(
                    name: name,
                    jobName: shifts.first?.job?.name,
                    color: shifts.first?.job?.color ?? Color.gray,
                    hours: shifts.reduce(0) { $0 + $1.workedHours },
                    earnings: shifts.reduce(0) { $0 + (adjusted[$1.persistentModelID] ?? $1.earnings) }
                )
            }
            .sorted { $0.earnings > $1.earnings }

        stats.daily = stats.shifts
            .map { shift in
                let day = calendar.startOfDay(for: shift.start)
                let jobName = shift.job?.name ?? String(localized: "No Job")
                return DailySlice(
                    id: "\(day.timeIntervalSinceReferenceDate)-\(jobName)-\(shift.persistentModelID)",
                    day: day,
                    jobName: jobName,
                    earnings: adjusted[shift.persistentModelID] ?? shift.earnings
                )
            }
            .sorted { $0.day < $1.day }

        return stats
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
        let stats = makeStats()

        NavigationStack {
            List {
                pickerSection
                paydaySection
                totalsSection(stats)

                if period == .week, weeklyGoal > 0 {
                    goalSection(total: stats.totalEarnings)
                }

                if stats.shifts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Pay This Period",
                            systemImage: "banknote",
                            description: Text("Log shifts to see your earnings here.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if stats.breakdown.count > 1 {
                        byJobSection(stats)
                    }
                    chartSection(stats)
                }

                trendSection(stats)
            }
            .navigationTitle("Pay")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Export Period", systemImage: "square.and.arrow.up") {
                        Button("Export as CSV", systemImage: "tablecells") {
                            csvDocument = CSVDocument(text: CSVDocument.csv(for: stats.shifts))
                            isExportingCSV = true
                        }
                        Button("Export as PDF", systemImage: "doc.richtext") {
                            pdfDocument = PDFFileDocument(data: makePDFData(stats))
                            isExportingPDF = true
                        }
                    }
                    .disabled(stats.shifts.isEmpty)
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

    private func totalsSection(_ stats: PeriodStats) -> some View {
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

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.totalEarnings, format: .currency(code: Locale.currencyCode))
                        .font(.title.bold())
                    if stats.previousHasShifts, abs(stats.totalEarnings - stats.previousEarnings) > 0.005 {
                        comparisonLabel(stats)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), alignment: .topLeading)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    miniStat("Hours", stats.hours.formatted(.number.precision(.fractionLength(0...1))))
                    miniStat("Shifts", stats.shifts.count.formatted())
                    if stats.hours > 0 {
                        miniStat("Avg. Rate", (stats.totalEarnings / stats.hours)
                            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0...2))))
                    }
                    if stats.overtimeExtra > 0.005 || (tipsEnabled && stats.tips > 0) {
                        miniStat("Base Pay", stats.basePay
                            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                    }
                    if stats.overtimeExtra > 0.005 {
                        miniStat("Overtime", "+\(stats.overtimeExtra.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))", tint: .orange)
                    }
                    if tipsEnabled, stats.tips > 0 {
                        miniStat("Tips", stats.tips
                            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                    }
                    if takeHomePercent > 0 {
                        miniStat("Take-Home", (stats.totalEarnings * (1 - takeHomePercent / 100))
                            .formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))
                    }
                    if stats.expenses > 0 {
                        miniStat("Expenses", "−\(stats.expenses.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))")
                    }
                    if stats.mileage > 0 {
                        miniStat("Mileage", "\(stats.mileage.formatted(.number.precision(.fractionLength(0...1)))) mi")
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func miniStat(_ label: LocalizedStringKey, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.headline)
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonLabel(_ stats: PeriodStats) -> some View {
        let delta = stats.totalEarnings - stats.previousEarnings
        let percent = stats.previousEarnings > 0 ? Int((delta / stats.previousEarnings * 100).rounded()) : nil

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

    private func goalSection(total: Double) -> some View {
        Section("Weekly Goal") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(total, weeklyGoal), total: max(weeklyGoal, 0.01))
                Text("\(total.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) of \(weeklyGoal.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0)))) · \(Int(min(total / max(weeklyGoal, 0.01), 1) * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func byJobSection(_ stats: PeriodStats) -> some View {
        Section("By Job") {
            ForEach(stats.breakdown, id: \.name) { entry in
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
                            Text("\(entry.hours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(stats.totalEarnings > 0 ? Int((entry.earnings / stats.totalEarnings * 100).rounded()) : 0)%")
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

    private func chartSection(_ stats: PeriodStats) -> some View {
        Section("Earnings by Day") {
            Chart(stats.daily) { entry in
                BarMark(
                    x: .value("Day", entry.day, unit: .day),
                    y: .value("Earnings", entry.earnings)
                )
                .foregroundStyle(by: .value("Job", entry.jobName))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(
                domain: stats.breakdown.map(\.name),
                range: stats.breakdown.map(\.color)
            )
            .chartLegend(stats.breakdown.count > 1 ? .visible : .hidden)
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

    private func trendSection(_ stats: PeriodStats) -> some View {
        Section("Trend") {
            Chart(stats.trend, id: \.start) { entry in
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
    private func makePDFData(_ stats: PeriodStats) -> Data {
        let content = PaySummaryPDF(
            periodTitle: periodTitle,
            totalEarnings: stats.totalEarnings,
            totalHours: stats.hours,
            totalTips: tipsEnabled ? stats.tips : 0,
            basePay: stats.basePay,
            overtimeExtra: stats.overtimeExtra,
            takeHome: takeHomePercent > 0 ? stats.totalEarnings * (1 - takeHomePercent / 100) : nil,
            shiftCount: stats.shifts.count,
            breakdown: stats.breakdown.map { ($0.name, $0.hours, $0.earnings) }
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
    .modelContainer(for: ShiftyModels.all, inMemory: true)
}

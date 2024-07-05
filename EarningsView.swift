import SwiftUI
import CoreData
import Charts

struct EarningsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var selectedTimeframe = 0 // Default to "This Week"
    let timeframes = ["This Week", "Bi-Weekly"]
    
    @State private var groupedShifts: [(Date, [Shift])] = []
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    timeframeSelector
                    summaryCards
                    earningsChart
                    shiftBreakdown
                }
                .padding()
            }
            .background(colors.background.edgesIgnoringSafeArea(.all))
            .navigationTitle("Earnings")
            .overlay(loadingOverlay)
            .onAppear(perform: loadData)
        }
        .accentColor(settingsManager.accentColor)
    }
    
    private var timeframeSelector: some View {
        Picker("Timeframe", selection: $selectedTimeframe) {
            ForEach(Array(timeframes.enumerated()), id: \.offset) { index, timeframe in
                Text(timeframe).tag(index)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: selectedTimeframe) { _ in
            loadData()
        }
    }
    
    private var summaryCards: some View {
        HStack {
            SummaryCard(title: "Total Earnings", value: formatCurrency(calculateTotalEarnings()), icon: "dollarsign.circle")
            SummaryCard(title: "Total Hours", value: String(format: "%.1f", calculateTotalHours()), icon: "clock")
            SummaryCard(title: "Avg. Hourly Rate", value: formatCurrency(calculateAverageHourlyRate()), icon: "chart.bar")
        }
    }
    
    private var earningsChart: some View {
        Chart {
            ForEach(groupedShifts, id: \.0) { date, shiftsForDate in
                BarMark(
                    x: .value("Date", date, unit: .day),
                    y: .value("Earnings", calculateEarnings(for: shiftsForDate))
                )
                .foregroundStyle(settingsManager.accentColor)
            }
        }
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.day())
            }
        }
    }
    
    private var shiftBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shift Breakdown")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            ForEach(groupedShifts, id: \.0) { date, shiftsForDate in
                VStack {
                    Text(formatDate(date))
                        .font(.headline)
                        .foregroundColor(colors.text)
                    ForEach(shiftsForDate, id: \.objectID) { shift in
                        NavigationLink(destination: DailyEarningsView(date: date, shifts: shiftsForDate)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                                        .foregroundColor(colors.text)
                                    if let notes = shift.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundColor(colors.secondaryText)
                                    }
                                }
                                Spacer()
                                Text(formatCurrency(calculateEarnings(for: [shift])))
                                    .foregroundColor(settingsManager.accentColor)
                            }
                            .padding(.vertical, 8)
                            .background(colors.secondaryBackground)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
    
    private var loadingOverlay: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
    
    private func loadData() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.updateGroupedShifts()
        }
    }
    
    @MainActor
    private func updateGroupedShifts() {
        Task {
            let filteredShifts = self.filteredShifts()
            let grouped = Dictionary(grouping: filteredShifts) { shift in
                Calendar.current.startOfDay(for: shift.date ?? Date())
            }
            let sortedGrouped = grouped.sorted { $0.key > $1.key }
            self.groupedShifts = sortedGrouped
            self.isLoading = false
            print("Updated grouped shifts: \(self.groupedShifts)")
        }
    }
    
    private func filteredShifts() -> [Shift] {
        let currentDate = Date()
        let calendar = Calendar.current
        
        switch selectedTimeframe {
        case 0: // This Week
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
            print("Filtering shifts for This Week starting from: \(startOfWeek)")
            return shifts.filter { shift in
                guard let shiftDate = shift.date else { return false }
                return shiftDate >= startOfWeek && shiftDate <= currentDate
            }
        case 1: // Bi-Weekly
            let startOfBiWeek = calendar.date(byAdding: .day, value: -14, to: currentDate)!
            print("Filtering shifts for Bi-Weekly starting from: \(startOfBiWeek)")
            return shifts.filter { shift in
                guard let shiftDate = shift.date else { return false }
                return shiftDate >= startOfBiWeek && shiftDate <= currentDate
            }
        default: // Default case to avoid compiler error
            print("Filtering shifts for Default")
            return Array(shifts)
        }
    }
    
    private func calculateTotalEarnings() -> Double {
        filteredShifts().reduce(0) { total, shift in
            total + calculateEarnings(for: [shift])
        }
    }
    
    private func calculateTotalHours() -> Double {
        filteredShifts().reduce(0) { total, shift in
            guard let start = shift.startTime, let end = shift.endTime else { return total }
            return total + end.timeIntervalSince(start) / 3600
        }
    }
    
    private func calculateAverageHourlyRate() -> Double {
        let totalHours = calculateTotalHours()
        guard totalHours > 0 else { return 0 }
        return calculateTotalEarnings() / totalHours
    }
    
    private func calculateEarnings(for shifts: [Shift]) -> Double {
        shifts.reduce(0) { total, shift in
            guard let start = shift.startTime, let end = shift.endTime else { return total }
            let hours = end.timeIntervalSince(start) / 3600
            return total + hours * settingsManager.payRate
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(settingsManager.accentColor)
            Text(title)
                .font(.caption)
                .foregroundColor(colors.secondaryText)
            Text(value)
                .font(.headline)
                .foregroundColor(colors.text)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }
}

struct DailyEarningsView: View {
    let date: Date
    let shifts: [Shift]
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    var body: some View {
        List {
            ForEach(shifts, id: \.objectID) { shift in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                            .foregroundColor(colors.text)
                        if let notes = shift.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(colors.secondaryText)
                        }
                    }
                    Spacer()
                    Text(formatCurrency(calculateEarnings(for: shift)))
                        .foregroundColor(settingsManager.accentColor)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(formatDate(date))
        .background(colors.background.edgesIgnoringSafeArea(.all))
    }
    
    private func calculateEarnings(for shift: Shift) -> Double {
        guard let start = shift.startTime, let end = shift.endTime else { return 0 }
        let hours = end.timeIntervalSince(start) / 3600
        return hours * settingsManager.payRate
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct EarningsView_Previews: PreviewProvider {
    static var previews: some View {
        EarningsView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .previewDisplayName("Light Mode")
        
        EarningsView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
    }
}

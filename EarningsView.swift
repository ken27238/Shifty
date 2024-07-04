import SwiftUI
import CoreData

struct EarningsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var selectedTimeframe = 1 // Default to "This Month"
    let timeframes = ["This Week", "This Month", "This Year", "All Time"]
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Timeframe").foregroundColor(colors.text)) {
                    Picker("Timeframe", selection: $selectedTimeframe) {
                        ForEach(0..<timeframes.count) { index in
                            Text(timeframes[index]).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Summary").foregroundColor(colors.text)) {
                    HStack {
                        Text("Total Earnings")
                        Spacer()
                        Text(formatCurrency(calculateTotalEarnings()))
                            .fontWeight(.bold)
                    }
                    .foregroundColor(colors.text)
                    
                    HStack {
                        Text("Total Hours")
                        Spacer()
                        Text(String(format: "%.1f", calculateTotalHours()))
                    }
                    .foregroundColor(colors.text)
                    
                    HStack {
                        Text("Average Hourly Rate")
                        Spacer()
                        Text(formatCurrency(calculateAverageHourlyRate()))
                    }
                    .foregroundColor(colors.text)
                }
                
                Section(header: Text("Breakdown").foregroundColor(colors.text)) {
                    ForEach(groupedShifts, id: \.0) { date, shiftsForDate in
                        NavigationLink(destination: DailyEarningsView(date: date, shifts: shiftsForDate)) {
                            HStack {
                                Text(formatDate(date))
                                Spacer()
                                Text(formatCurrency(calculateEarnings(for: shiftsForDate)))
                            }
                            .foregroundColor(colors.text)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Earnings")
            .background(colors.background.edgesIgnoringSafeArea(.all))
        }
    }
    
    private var filteredShifts: [Shift] {
        let currentDate = Date()
        let calendar = Calendar.current
        
        switch selectedTimeframe {
        case 0: // This Week
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
            return shifts.filter { $0.date?.compare(startOfWeek) != .orderedAscending }
        case 1: // This Month
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate))!
            return shifts.filter { $0.date?.compare(startOfMonth) != .orderedAscending }
        case 2: // This Year
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: currentDate))!
            return shifts.filter { $0.date?.compare(startOfYear) != .orderedAscending }
        default: // All Time
            return Array(shifts)
        }
    }
    
    private var groupedShifts: [(Date, [Shift])] {
        let grouped = Dictionary(grouping: filteredShifts) { shift in
            Calendar.current.startOfDay(for: shift.date ?? Date())
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    private func calculateTotalEarnings() -> Double {
        filteredShifts.reduce(0) { total, shift in
            total + calculateEarnings(for: [shift])
        }
    }
    
    private func calculateTotalHours() -> Double {
        filteredShifts.reduce(0) { total, shift in
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

struct DailyEarningsView: View {
    let date: Date
    let shifts: [Shift]
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    var body: some View {
        List {
            ForEach(shifts, id: \.self) { shift in
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
                        .foregroundColor(colors.text)
                }
            }
        }
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

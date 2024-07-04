import SwiftUI
import CoreData

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        NavigationView {
            List {
                todayShiftSection
                nextShiftSection
                weekSummarySection
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Home")
        }
        .background(Color.background.edgesIgnoringSafeArea(.all))
    }
    
    private var todayShiftSection: some View {
        Section(header: Label("Today's Shift", systemImage: "calendar.day.timeline.left")) {
            if let todayShift = todayShift {
                shiftRow(shift: todayShift)
            } else {
                Label("No shift scheduled for today", systemImage: "calendar.badge.exclamationmark")
                    .foregroundColor(Color.secondaryText)
            }
        }
    }
    
    private var nextShiftSection: some View {
        Section(header: Label("Next Shift", systemImage: "calendar.badge.clock")) {
            if let nextShift = nextShift {
                shiftRow(shift: nextShift)
            } else {
                Label("No upcoming shifts", systemImage: "calendar.badge.minus")
                    .foregroundColor(Color.secondaryText)
            }
        }
    }
    
    private var weekSummarySection: some View {
        Section(header: Label("This Week", systemImage: "calendar.week")) {
            HStack {
                Label("Total Shifts", systemImage: "number.circle")
                Spacer()
                Text("\(shiftsThisWeek.count)")
                    .foregroundColor(Color.secondaryText)
            }
            HStack {
                Label("Total Hours", systemImage: "clock")
                Spacer()
                Text(String(format: "%.1f", totalHoursThisWeek))
                    .foregroundColor(Color.secondaryText)
            }
            HStack {
                Label("Total Earnings", systemImage: "dollarsign.circle")
                Spacer()
                Text(formatCurrency(totalEarningsThisWeek))
                    .foregroundColor(Color.secondaryText)
            }
        }
    }
    
    private func shiftRow(shift: Shift) -> some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundColor(Color.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(shift.date ?? Date(), style: .date)
                    .foregroundColor(Color.text)
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.subheadline)
                    .foregroundColor(Color.secondaryText)
            }
            Spacer()
            Text(formatCurrency(calculateEarnings(for: shift)))
                .font(.callout)
                .foregroundColor(Color.secondaryText)
        }
    }
    
    private var todayShift: Shift? {
        let today = Calendar.current.startOfDay(for: Date())
        return shifts.first { Calendar.current.isDate($0.date ?? Date(), inSameDayAs: today) }
    }
    
    private var nextShift: Shift? {
        let now = Date()
        return shifts.first { ($0.date ?? Date()) > now }
    }
    
    private var shiftsThisWeek: [Shift] {
        let calendar = Calendar.current
        let weekRange = calendar.dateInterval(of: .weekOfYear, for: Date())!
        return shifts.filter { shift in
            guard let shiftDate = shift.date else { return false }
            return weekRange.contains(shiftDate)
        }
    }
    
    private var totalHoursThisWeek: Double {
        shiftsThisWeek.reduce(0) { total, shift in
            let duration = shift.endTime?.timeIntervalSince(shift.startTime ?? Date()) ?? 0
            return total + (duration / 3600) // Convert seconds to hours
        }
    }
    
    private var totalEarningsThisWeek: Double {
        totalHoursThisWeek * settingsManager.payRate
    }
    
    private func calculateEarnings(for shift: Shift) -> Double {
        guard let start = shift.startTime, let end = shift.endTime else { return 0 }
        let duration = end.timeIntervalSince(start) / 3600 // in hours
        return duration * settingsManager.payRate
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(SettingsManager())
            .environment(\.colorScheme, .light)
        
        HomeView()
            .environmentObject(SettingsManager())
            .environment(\.colorScheme, .dark)
    }
}

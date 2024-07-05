import SwiftUI
import CoreData
import Charts

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var isRefreshing = false
    @State private var showingAddShift = false
    @State private var selectedTab: Int?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    quickGlanceSummaryCard
                    upcomingShiftsSection
                    weeklyOverviewChart
                    quickActionsRow
                    Divider()
                    weekSummarySection
                    personalizedInsightSection
                    recentActivitySection
                }
                .padding()
            }
            .navigationTitle("Home")
            .background(colors.background.edgesIgnoringSafeArea(.all))
            .refreshable {
                await refreshData()
            }
            .sheet(isPresented: $showingAddShift) {
                NavigationView {
                    ShiftFormView(shift: nil, isNewShift: true)
                }
            }
            .onAppear {
                Task {
                    await refreshData()
                }
            }
        }
        .accentColor(settingsManager.accentColor)
    }
    
    private var quickGlanceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Summary")
                .font(.headline)
            HStack {
                VStack(alignment: .leading) {
                    Label(todayShift?.startTime?.formatted(date: .omitted, time: .shortened) ?? "No shift today", systemImage: "clock")
                    Label("\(totalHoursThisWeek, specifier: "%.1f") hours this week", systemImage: "timer")
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(totalEarningsThisWeek, format: .currency(code: settingsManager.currency))
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("This Week")
                        .font(.caption)
                        .foregroundColor(colors.secondaryText)
                }
            }
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }
    
    private var upcomingShiftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Shifts")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(upcomingShifts) { shift in
                        UpcomingShiftCard(shift: shift)
                    }
                }
            }
        }
    }
    
    private var weeklyOverviewChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekly Overview")
                .font(.headline)
            Chart(weeklyChartData) { data in
                BarMark(
                    x: .value("Day", data.day),
                    y: .value("Hours", data.hours)
                )
                .foregroundStyle(settingsManager.accentColor)
            }
            .frame(height: 200)
            Text("Total Earnings: \(totalEarningsThisWeek, format: .currency(code: settingsManager.currency))")
                .font(.subheadline)
        }
    }
    
    private var quickActionsRow: some View {
        HStack(spacing: 20) {
            QuickActionButton(title: "New Shift", systemImage: "plus.circle") {
                showingAddShift = true
            }
            NavigationLink(destination: CalendarView(), tag: 1, selection: $selectedTab) {
                QuickActionButton(title: "Calendar", systemImage: "calendar") {
                    selectedTab = 1
                }
            }
            NavigationLink(destination: EarningsView(), tag: 2, selection: $selectedTab) {
                QuickActionButton(title: "Earnings", systemImage: "dollarsign.circle") {
                    selectedTab = 2
                }
            }
        }
    }
    
    private var weekSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Week")
                .font(.headline)
            HStack {
                Label("Total Shifts", systemImage: "number.circle")
                Spacer()
                Text("\(shiftsThisWeek.count)")
                    .foregroundColor(colors.secondaryText)
            }
            HStack {
                Label("Total Hours", systemImage: "clock")
                Spacer()
                Text(String(format: "%.1f", totalHoursThisWeek))
                    .foregroundColor(colors.secondaryText)
            }
            HStack {
                Label("Total Earnings", systemImage: "dollarsign.circle")
                Spacer()
                Text(formatCurrency(totalEarningsThisWeek))
                    .foregroundColor(colors.secondaryText)
            }
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }
    
    private var personalizedInsightSection: some View {
        Text(personalizedInsight)
            .font(.subheadline)
            .padding()
            .background(colors.secondaryBackground)
            .cornerRadius(10)
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)
            if let lastShift = shifts.first {
                shiftRow(shift: lastShift)
            } else {
                Text("No recent activity")
                    .foregroundColor(colors.secondaryText)
            }
        }
    }
    
    private func shiftRow(shift: Shift) -> some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundColor(settingsManager.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(shift.date ?? Date(), style: .date)
                    .foregroundColor(colors.text)
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.subheadline)
                    .foregroundColor(colors.secondaryText)
            }
            Spacer()
            Text(formatCurrency(calculateEarnings(for: shift)))
                .font(.callout)
                .foregroundColor(colors.secondaryText)
        }
    }
    
    private func refreshData() async {
        isRefreshing = true
        
        await MainActor.run {
            // Refresh FetchRequest
            viewContext.reset()
            try? viewContext.setQueryGenerationFrom(.current)
            
            // Manually trigger FetchRequest update
            shifts.nsSortDescriptors = [NSSortDescriptor(keyPath: \Shift.date, ascending: true)]
        }
        
        // Simulate a brief delay for user feedback
        try? await Task.sleep(for: .seconds(0.5))
        
        isRefreshing = false
    }
    
    private var todayShift: Shift? {
        let today = Calendar.current.startOfDay(for: Date())
        return shifts.first { Calendar.current.isDate($0.date ?? Date(), inSameDayAs: today) }
    }
    
    private var upcomingShifts: [Shift] {
        let now = Date()
        return Array(shifts.filter { ($0.date ?? Date()) > now }.prefix(3))
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
    
    private var weeklyChartData: [WeeklyChartData] {
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: Date())
        return (0..<7).map { dayOffset in
            let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            let dayShifts = shifts.filter { calendar.isDate($0.date ?? Date(), inSameDayAs: day) }
            let hours = dayShifts.reduce(0.0) { total, shift in
                total + (shift.endTime?.timeIntervalSince(shift.startTime ?? Date()) ?? 0) / 3600
            }
            return WeeklyChartData(day: calendar.shortWeekdaySymbols[dayOffset], hours: hours)
        }
    }
    
    private var personalizedInsight: String {
        if totalHoursThisWeek > 40 {
            return "You've worked overtime this week! Great job!"
        } else if shiftsThisWeek.count > 5 {
            return "Busy week! You've worked \(shiftsThisWeek.count) shifts."
        } else {
            return "You've earned \(formatCurrency(totalEarningsThisWeek)) this week."
        }
    }
}

struct UpcomingShiftCard: View {
    let shift: Shift
    @Environment(\.appColor) private var colors
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(shift.date ?? Date(), style: .date)
                .font(.caption)
                .foregroundColor(colors.secondaryText)
            Text(shift.startTime ?? Date(), style: .time)
                .font(.headline)
            Text(shift.endTime ?? Date(), style: .time)
                .font(.subheadline)
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }
}

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(settingsManager.accentColor)
        }
    }
}

struct WeeklyChartData: Identifiable {
    let id = UUID()
    let day: String
    let hours: Double
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components)!
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .light)
        
        HomeView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .dark)
    }
}

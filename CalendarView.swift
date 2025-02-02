import SwiftUI
import CoreData

struct CalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var showingAddShift = false
    @State private var showingShiftDetail: Shift?
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                monthHeader
                dayOfWeekHeader
                monthGrid
                Divider()
                selectedDateShifts
            }
            .background(colors.background.edgesIgnoringSafeArea(.all))
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddShift = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(settingsManager.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showingAddShift) {
                NavigationView {
                    ShiftFormView(shift: nil, isNewShift: true, preselectedDate: selectedDate)
                }
            }
            .sheet(item: $showingShiftDetail) { shift in
                NavigationView {
                    ShiftFormView(shift: shift, isNewShift: false)
                }
            }
        }
        .accentColor(settingsManager.accentColor)
    }
    
    private var monthHeader: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(settingsManager.accentColor)
            }
            Spacer()
            Text(dateFormatter.string(from: currentMonth))
                .font(.headline)
                .foregroundColor(colors.text)
            Spacer()
            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(settingsManager.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var dayOfWeekHeader: some View {
        HStack {
            ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .foregroundColor(colors.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var monthGrid: some View {
        let daysInMonth = calendar.daysInMonth(for: currentMonth)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(daysInMonth, id: \.self) { date in
                if let date = date {
                    DayCell(date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            shifts: shiftsForDate(date),
                            colors: colors,
                            accentColor: settingsManager.accentColor)
                    .onTapGesture {
                        selectedDate = date
                    }
                } else {
                    Color.clear
                }
            }
        }
        .padding()
    }
    
    private var selectedDateShifts: some View {
        List {
            Section(header: Text(selectedDate, style: .date)
                .textCase(.none)
                .foregroundColor(settingsManager.accentColor)
                .font(.headline)
            ) {
                if let shifts = shiftsForDate(selectedDate), !shifts.isEmpty {
                    ForEach(shifts) { shift in
                        ShiftRow(shift: shift, colors: colors)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingShiftDetail = shift
                            }
                    }
                } else {
                    Text("No shifts scheduled")
                        .foregroundColor(colors.secondaryText)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newDate
        }
    }
    
    private func shiftsForDate(_ date: Date) -> [Shift]? {
        shifts.filter { shift in
            calendar.isDate(shift.date ?? Date(), inSameDayAs: date)
        }
    }
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let shifts: [Shift]?
    let colors: AppColor
    let accentColor: Color
    
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .overlay(
                    Circle()
                        .stroke(isToday ? accentColor : Color.clear, lineWidth: 1)
                )
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(isToday ? .headline : .body)
                    .foregroundColor(textColor)
                if let shifts = shifts, !shifts.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(shifts.count, 3), id: \.self) { _ in
                            Circle()
                                .fill(dotColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private var backgroundColor: Color {
        isSelected ? accentColor.opacity(0.2) : Color.clear
    }
    
    private var textColor: Color {
        if isSelected {
            return accentColor
        } else if isToday {
            return accentColor
        } else {
            return colors.text
        }
    }
    
    private var dotColor: Color {
        isSelected ? accentColor : colors.secondaryText
    }
}

struct ShiftRow: View {
    let shift: Shift
    let colors: AppColor
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.headline)
                    .foregroundColor(colors.text)
                if let notes = shift.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundColor(colors.secondaryText)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(calculateEarnings()))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(settingsManager.accentColor)
                Text(formatDuration())
                    .font(.caption)
                    .foregroundColor(colors.secondaryText)
            }
        }
    }
    
    private func calculateEarnings() -> Double {
        guard let start = shift.startTime, let end = shift.endTime else { return 0 }
        let duration = end.timeIntervalSince(start) / 3600 // in hours
        return duration * settingsManager.payRate
    }
    
    private func formatDuration() -> String {
        guard let start = shift.startTime, let end = shift.endTime else { return "N/A" }
        let duration = end.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .previewDisplayName("Light Mode")
        
        CalendarView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
    }
}

extension Calendar {
    func daysInMonth(for date: Date) -> [Date?] {
        guard let range = self.range(of: .day, in: .month, for: date),
              let firstDayOfMonth = self.date(from: dateComponents([.year, .month], from: date)) else {
            return []
        }
        
        let firstWeekday = component(.weekday, from: firstDayOfMonth)
        
        return (1..<firstWeekday).map { _ in nil } + range.map { day -> Date? in
            self.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)
        }
    }
}

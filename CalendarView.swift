import SwiftUI
import CoreData

struct CalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    
    @EnvironmentObject var settingsManager: SettingsManager
    
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
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddShift = true }) {
                        Image(systemName: "plus")
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
    }
    
    private var monthHeader: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(dateFormatter.string(from: currentMonth))
                .font(.headline)
            Spacer()
            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
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
                    .foregroundColor(.secondary)
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
                            shifts: shiftsForDate(date))
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
            Section(header: Text(selectedDate, style: .date).textCase(.none)) {
                if let shifts = shiftsForDate(selectedDate), !shifts.isEmpty {
                    ForEach(shifts) { shift in
                        ShiftRow(shift: shift)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingShiftDetail = shift
                            }
                    }
                } else {
                    Text("No shifts scheduled")
                        .foregroundColor(.secondary)
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
    
    @EnvironmentObject var settingsManager: SettingsManager
    
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(isToday ? .headline : .body)
                    .foregroundColor(isSelected ? .white : (isToday ? .accentColor : .primary))
                if let shifts = shifts, !shifts.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<min(shifts.count, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? .white : Color.accentColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct ShiftRow: View {
    let shift: Shift
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.headline)
                if let notes = shift.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(calculateEarnings()))
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(formatDuration())
                    .font(.caption)
                    .foregroundColor(.secondary)
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

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView()
            .environmentObject(SettingsManager())
    }
}

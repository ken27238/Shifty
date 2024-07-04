import SwiftUI

struct ShiftListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var showingAddShift = false
    @State private var showingShiftDetail: Shift?

    var body: some View {
        NavigationView {
            List {
                summarySection
                
                ForEach(groupedShifts.keys.sorted(), id: \.self) { date in
                    Section(header: Text(formatDate(date)).foregroundColor(Color.text)) {
                        ForEach(groupedShifts[date] ?? []) { shift in
                            ShiftRowView(shift: shift)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    showingShiftDetail = shift
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteShift(shift)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        showingShiftDetail = shift
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color.accent)
                                }
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Shifts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddShift = true }) {
                        Label("Add Shift", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddShift) {
                NavigationView {
                    ShiftFormView(shift: nil, isNewShift: true)
                }
            }
            .sheet(item: $showingShiftDetail) { shift in
                NavigationView {
                    ShiftFormView(shift: shift, isNewShift: false)
                }
            }
        }
        .background(Color.background.edgesIgnoringSafeArea(.all))
    }

    private var summarySection: some View {
        Section(header: Text("Summary").foregroundColor(Color.text)) {
            HStack {
                Label("Total Shifts", systemImage: "number.circle")
                Spacer()
                Text("\(shifts.count)")
                    .fontWeight(.semibold)
            }
            .foregroundColor(Color.text)
            HStack {
                Label("Total Hours", systemImage: "clock")
                Spacer()
                Text(String(format: "%.1f", totalHours))
                    .fontWeight(.semibold)
            }
            .foregroundColor(Color.text)
            HStack {
                Label("Total Earnings", systemImage: "dollarsign.circle")
                Spacer()
                Text(formatCurrency(totalEarnings))
                    .fontWeight(.semibold)
            }
            .foregroundColor(Color.text)
        }
    }

    private var groupedShifts: [Date: [Shift]] {
        Dictionary(grouping: shifts) { shift in
            Calendar.current.startOfDay(for: shift.date ?? Date())
        }
    }

    private var totalHours: Double {
        shifts.reduce(0) { total, shift in
            let duration = shift.endTime?.timeIntervalSince(shift.startTime ?? Date()) ?? 0
            return total + (duration / 3600) // Convert seconds to hours
        }
    }

    private var totalEarnings: Double {
        totalHours * settingsManager.payRate
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private func deleteShift(_ shift: Shift) {
        viewContext.delete(shift)
        do {
            try viewContext.save()
        } catch {
            print("Error deleting shift: \(error)")
        }
    }
}

struct ShiftRowView: View {
    let shift: Shift
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.date ?? Date(), style: .date)
                    .font(.headline)
                    .foregroundColor(Color.text)
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.subheadline)
                    .foregroundColor(Color.secondaryText)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(calculateEarnings()))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.text)
                
                Text(formatDuration())
                    .font(.caption)
                    .foregroundColor(Color.secondaryText)
            }
        }
        .padding(.vertical, 4)
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

struct ShiftListView_Previews: PreviewProvider {
    static var previews: some View {
        ShiftListView()
            .environmentObject(SettingsManager())
            .environment(\.colorScheme, .light)
        
        ShiftListView()
            .environmentObject(SettingsManager())
            .environment(\.colorScheme, .dark)
    }
}

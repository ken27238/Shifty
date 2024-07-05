import SwiftUI

struct ShiftListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: false)],
        animation: .default)
    private var shifts: FetchedResults<Shift>
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors

    @State private var showingAddShift = false
    @State private var showingShiftDetail: Shift?
    @State private var isRefreshing = false
    @State private var selectedShifts: Set<Shift> = []
    @State private var isEditMode: EditMode = .inactive
    @State private var showingBatchDeleteAlert = false
    @State private var loadedShifts = 20

    var body: some View {
        NavigationView {
            List {
                summarySection
                
                ForEach(Array(groupedShifts.keys.sorted().prefix(loadedShifts)), id: \.self) { date in
                    Section(header: Text(formatDate(date))
                        .foregroundColor(settingsManager.accentColor)
                        .font(.headline)
                    ) {
                        ForEach(groupedShifts[date] ?? []) { shift in
                            ShiftRowView(shift: shift, colors: colors, isSelected: selectedShifts.contains(shift))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isEditMode == .active {
                                        toggleShiftSelection(shift)
                                    } else {
                                        showingShiftDetail = shift
                                    }
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
                                    .tint(settingsManager.accentColor)
                                }
                        }
                    }
                }
                
                if loadedShifts < groupedShifts.keys.count {
                    Button("Load More") {
                        loadMoreShifts()
                    }
                    .foregroundColor(settingsManager.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Shifts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                        .foregroundColor(settingsManager.accentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddShift = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(settingsManager.accentColor)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if isEditMode == .active {
                        Button("Delete Selected") {
                            showingBatchDeleteAlert = true
                        }
                        .foregroundColor(.red)
                        .disabled(selectedShifts.isEmpty)
                    }
                }
            }
            .environment(\.editMode, $isEditMode)
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
            .alert("Delete Shifts", isPresented: $showingBatchDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    batchDeleteShifts()
                }
            } message: {
                Text("Are you sure you want to delete \(selectedShifts.count) shifts?")
            }
            .refreshable {
                await refreshData()
            }
        }
        .background(colors.background.edgesIgnoringSafeArea(.all))
        .accentColor(settingsManager.accentColor)
    }

    private var summarySection: some View {
        Section(header: Text("Summary")
            .foregroundColor(settingsManager.accentColor)
            .font(.headline)
        ) {
            SummaryRowView(title: "Total Shifts", value: "\(shifts.count)", icon: "number.circle")
            SummaryRowView(title: "Total Hours", value: String(format: "%.1f", totalHours), icon: "clock")
            SummaryRowView(title: "Total Earnings", value: formatCurrency(totalEarnings), icon: "dollarsign.circle")
            SummaryRowView(title: "Average Shift Duration", value: formatDuration(averageShiftDuration), icon: "hourglass")
            SummaryRowView(title: "Most Common Day", value: mostCommonShiftDay, icon: "calendar")
        }
    }

    private var groupedShifts: [Date: [Shift]] {
        Dictionary(grouping: Array(shifts)) { shift in
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

    private var averageShiftDuration: TimeInterval {
        guard !shifts.isEmpty else { return 0 }
        return totalHours * 3600 / Double(shifts.count)
    }

    private var mostCommonShiftDay: String {
        let dayCount = shifts.reduce(into: [Int: Int]()) { counts, shift in
            if let weekday = Calendar.current.dateComponents([.weekday], from: shift.date ?? Date()).weekday {
                counts[weekday, default: 0] += 1
            }
        }
        let mostCommonDay = dayCount.max(by: { $0.value < $1.value })?.key ?? 1
        let dateFormatter = DateFormatter()
        return dateFormatter.weekdaySymbols[mostCommonDay - 1]
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func deleteShift(_ shift: Shift) {
        viewContext.delete(shift)
        do {
            try viewContext.save()
        } catch {
            print("Error deleting shift: \(error)")
        }
    }

    private func toggleShiftSelection(_ shift: Shift) {
        if selectedShifts.contains(shift) {
            selectedShifts.remove(shift)
        } else {
            selectedShifts.insert(shift)
        }
    }

    private func batchDeleteShifts() {
        for shift in selectedShifts {
            viewContext.delete(shift)
        }
        do {
            try viewContext.save()
            selectedShifts.removeAll()
            isEditMode = .inactive
        } catch {
            print("Error batch deleting shifts: \(error)")
        }
    }

    private func refreshData() async {
        isRefreshing = true
        
        await MainActor.run {
            viewContext.reset()
            try? viewContext.setQueryGenerationFrom(.current)
            shifts.nsSortDescriptors = [NSSortDescriptor(keyPath: \Shift.date, ascending: false)]
        }
        
        try? await Task.sleep(for: .seconds(0.5))
        
        isRefreshing = false
    }

    private func loadMoreShifts() {
        loadedShifts += 20
    }
}

struct SummaryRowView: View {
    let title: String
    let value: String
    let icon: String
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(colors.text)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(settingsManager.accentColor)
        }
    }
}

struct ShiftRowView: View {
    let shift: Shift
    let colors: AppColor
    let isSelected: Bool
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        HStack {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(settingsManager.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.date ?? Date(), style: .date)
                    .font(.headline)
                    .foregroundColor(colors.text)
                Text("\(shift.startTime ?? Date(), style: .time) - \(shift.endTime ?? Date(), style: .time)")
                    .font(.subheadline)
                    .foregroundColor(colors.secondaryText)
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
        .padding(.vertical, 4)
        .background(isSelected ? settingsManager.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
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

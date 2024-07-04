import SwiftUI

struct EarningsDetailView: View {
    let date: Date
    
    // In a real app, you'd fetch this data from Core Data
    @State private var shift: Shift?
    @State private var earnings: Double = 0.0
    @State private var hours: Double = 0.0
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Shift Details")) {
                    LabeledContent("Date", value: date, format: .dateTime.day().month().year())
                    LabeledContent("Start Time", value: shift?.startTime ?? Date(), format: .dateTime.hour().minute())
                    LabeledContent("End Time", value: shift?.endTime ?? Date(), format: .dateTime.hour().minute())
                    LabeledContent("Duration", value: formatDuration(hours: hours))
                }
                
                Section(header: Text("Earnings")) {
                    LabeledContent("Total Earnings", value: earnings, format: .currency(code: "USD"))
                    LabeledContent("Hourly Rate", value: calculateHourlyRate(), format: .currency(code: "USD"))
                }
                
                Section(header: Text("Notes")) {
                    Text(shift?.notes ?? "No notes for this shift")
                }
                
                Section(header: Text("Actions")) {
                    Button("Edit Shift") {
                        // Implement edit functionality
                    }
                    Button("Delete Shift", role: .destructive) {
                        // Implement delete functionality
                    }
                }
            }
            .navigationTitle("Shift Details")
        }
        .onAppear {
            loadShiftData()
        }
    }
    
    private func loadShiftData() {
        // In a real app, you'd fetch this data from Core Data
        // This is just mock data for illustration
        shift = Shift(context: PersistenceController.shared.container.viewContext)
        shift?.date = date
        shift?.startTime = date.addingTimeInterval(9 * 3600) // 9 AM
        shift?.endTime = date.addingTimeInterval(17 * 3600) // 5 PM
        shift?.notes = "Regular shift"
        
        hours = 8.0
        earnings = 120.0
    }
    
    private func formatDuration(hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int((hours.truncatingRemainder(dividingBy: 1) * 60).rounded())
        return String(format: "%d hours %02d minutes", wholeHours, minutes)
    }
    
    private func calculateHourlyRate() -> Double {
        guard hours > 0 else { return 0 }
        return earnings / hours
    }
}

struct EarningsDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EarningsDetailView(date: Date())
    }
}

import SwiftUI

struct ShiftDetailView: View {
    let shift: Shift
    
    var body: some View {
        List {
            Section(header: Text("Shift Details")) {
                LabeledContent("Date", value: shift.date ?? Date(), format: .dateTime.day().month().year())
                LabeledContent("Start Time", value: shift.startTime ?? Date(), format: .dateTime.hour().minute())
                LabeledContent("End Time", value: shift.endTime ?? Date(), format: .dateTime.hour().minute())
                LabeledContent("Duration", value: formatDuration(start: shift.startTime, end: shift.endTime))
            }
            
            Section(header: Text("Notes")) {
                Text(shift.notes ?? "No notes")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Shift Details")
    }
    
    private func formatDuration(start: Date?, end: Date?) -> String {
        guard let start = start, let end = end else { return "N/A" }
        let duration = end.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%d hours %02d minutes", hours, minutes)
    }
}

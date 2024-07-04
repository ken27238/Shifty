import SwiftUI

struct ShiftFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String
    
    let shift: Shift?
    let isNewShift: Bool
    
    init(shift: Shift?, isNewShift: Bool, preselectedDate: Date? = nil) {
        self.shift = shift
        self.isNewShift = isNewShift
        
        let initialDate = shift?.date ?? preselectedDate ?? Date()
        _date = State(initialValue: initialDate)
        _startTime = State(initialValue: shift?.startTime ?? initialDate)
        _endTime = State(initialValue: shift?.endTime ?? initialDate.addingTimeInterval(3600)) // Default to 1 hour shift
        _notes = State(initialValue: shift?.notes ?? "")
    }
    
    var body: some View {
        Form {
            Section(header: Text("Shift Details")) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
            }
            
            Section(header: Text("Notes")) {
                TextEditor(text: $notes)
                    .frame(height: 100)
            }
        }
        .navigationTitle(isNewShift ? "Add Shift" : "Edit Shift")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveShift()
                }
            }
        }
    }
    
    private func saveShift() {
        let shiftToSave: Shift
        if isNewShift {
            shiftToSave = Shift(context: viewContext)
        } else {
            shiftToSave = shift ?? Shift(context: viewContext)
        }
        
        shiftToSave.date = date
        shiftToSave.startTime = startTime
        shiftToSave.endTime = endTime
        shiftToSave.notes = notes
        
        do {
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            print("Error saving shift: \(error)")
        }
    }
}

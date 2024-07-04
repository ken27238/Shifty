import SwiftUI

struct ShiftFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String
    @State private var selectedDuration: Double = 0
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    let shift: Shift?
    let isNewShift: Bool
    
    init(shift: Shift?, isNewShift: Bool, preselectedDate: Date? = nil) {
        self.shift = shift
        self.isNewShift = isNewShift
        
        let initialDate = shift?.date ?? preselectedDate ?? Date()
        _date = State(initialValue: initialDate)
        _startTime = State(initialValue: shift?.startTime ?? initialDate)
        _endTime = State(initialValue: shift?.endTime ?? initialDate.addingTimeInterval(3600))
        _notes = State(initialValue: shift?.notes ?? "")
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                dateSection
                timeSection
                durationSection
                notesSection
                
                if !isNewShift {
                    deleteButton
                }
            }
            .padding()
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
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading) {
            Label("Date", systemImage: "calendar")
                .font(.headline)
            DatePicker("Shift date", selection: $date, displayedComponents: .date)
                .datePickerStyle(GraphicalDatePickerStyle())
                .labelsHidden()
                .accessibilityLabel("Shift date")
                .accessibilityHint("Double tap to select the date for this shift")
        }
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading) {
            Label("Time", systemImage: "clock")
                .font(.headline)
            HStack {
                DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("Start time")
                DatePicker("End time", selection: $endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel("End time")
            }
        }
        .onChange(of: endTime) { newValue in
            if newValue < startTime {
                endTime = startTime.addingTimeInterval(3600)
            }
        }
    }
    
    private var durationSection: some View {
        VStack(alignment: .leading) {
            Label("Duration", systemImage: "stopwatch")
                .font(.headline)
            Picker("Duration", selection: $selectedDuration) {
                Text("1h").tag(3600.0)
                Text("2h").tag(7200.0)
                Text("4h").tag(14400.0)
                Text("8h").tag(28800.0)
                Text("Custom").tag(0.0)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedDuration) { newValue in
                if newValue > 0 {
                    endTime = startTime.addingTimeInterval(newValue)
                }
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                if notes.isEmpty {
                    Text("Enter any additional notes here...")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            Text("\(notes.count)/500 characters")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var deleteButton: some View {
        Button(action: deleteShift) {
            Label("Delete Shift", systemImage: "trash")
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func saveShift() {
        if !validateInput() {
            showingAlert = true
            alertMessage = "Please check your input and try again."
            return
        }
        
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
            showingAlert = true
            alertMessage = "Error saving shift: \(error.localizedDescription)"
        }
    }
    
    private func deleteShift() {
        guard let shiftToDelete = shift else { return }
        
        viewContext.delete(shiftToDelete)
        
        do {
            try viewContext.save()
            presentationMode.wrappedValue.dismiss()
        } catch {
            showingAlert = true
            alertMessage = "Error deleting shift: \(error.localizedDescription)"
        }
    }
    
    private func validateInput() -> Bool {
        guard endTime > startTime else {
            return false
        }
        
        guard notes.count <= 500 else {
            return false
        }
        
        // Add any other validation rules here
        
        return true
    }
}

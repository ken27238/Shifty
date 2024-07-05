import SwiftUI

struct ShiftFormView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var notes: String
    @State private var selectedDuration: Double
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
        _endTime = State(initialValue: shift?.endTime ?? initialDate.addingTimeInterval(3600)) // Default to 1 hour
        _notes = State(initialValue: shift?.notes ?? "")
        _selectedDuration = State(initialValue: 0)
    }
    
    var body: some View {
        Form {
            dateSection
            timeSection
            durationSection
            notesSection
            
            if !isNewShift {
                deleteSection
            }
        }
        .navigationTitle(isNewShift ? "Add Shift" : "Edit Shift")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveShift()
                }
                .disabled(!isFormValid)
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            if isNewShift {
                endTime = startTime.addingTimeInterval(settingsManager.defaultShiftDuration * 3600)
            }
        }
    }
    
    private var dateSection: some View {
        Section(header: Text("Date").foregroundColor(settingsManager.accentColor)) {
            DatePicker("Shift date", selection: $date, displayedComponents: .date)
                .datePickerStyle(DefaultDatePickerStyle())
                .accentColor(settingsManager.accentColor)
        }
    }
    
    private var timeSection: some View {
        Section(header: Text("Time").foregroundColor(settingsManager.accentColor)) {
            DatePicker("Start time", selection: $startTime, displayedComponents: .hourAndMinute)
                .accentColor(settingsManager.accentColor)
            DatePicker("End time", selection: $endTime, displayedComponents: .hourAndMinute)
                .accentColor(settingsManager.accentColor)
        }
    }
    
    private var durationSection: some View {
        Section(header: Text("Duration").foregroundColor(settingsManager.accentColor)) {
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
            
            Text("Shift duration: \(formattedDuration)")
                .foregroundColor(colors.secondaryText)
        }
    }
    
    private var notesSection: some View {
        Section(header: Text("Notes").foregroundColor(settingsManager.accentColor)) {
            TextEditor(text: $notes)
                .frame(height: 100)
            
            Text("\(notes.count)/500 characters")
                .font(.caption)
                .foregroundColor(colors.secondaryText)
        }
    }
    
    private var deleteSection: some View {
        Section {
            Button(action: deleteShift) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Shift")
                }
                .foregroundColor(.red)
            }
        }
    }
    
    private var isFormValid: Bool {
        return endTime > startTime && notes.count <= 500
    }
    
    private var formattedDuration: String {
        let duration = endTime.timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%d hours %02d minutes", hours, minutes)
    }
    
    private func saveShift() {
        let shiftToSave = isNewShift ? Shift(context: viewContext) : (shift ?? Shift(context: viewContext))
        
        shiftToSave.date = date
        shiftToSave.startTime = startTime
        shiftToSave.endTime = endTime
        shiftToSave.notes = notes
        
        do {
            try viewContext.save()
            dismiss()
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
            dismiss()
        } catch {
            showingAlert = true
            alertMessage = "Error deleting shift: \(error.localizedDescription)"
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var tempPayRate: String = ""
    @State private var tempDefaultShiftDuration: Double = 8.0
    @State private var showingResetAlert = false
    
    let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CNY"]
    let payPeriods = ["Weekly", "Bi-Weekly", "Monthly"]

    var body: some View {
        NavigationView {
            Form {
                appearanceSection
                defaultShiftSettingsSection
                earningsSection
                notificationsSection
                exportSection
                resetSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                }
            }
            .onAppear {
                tempPayRate = String(format: "%.2f", settingsManager.payRate)
                tempDefaultShiftDuration = settingsManager.defaultShiftDuration
            }
            .alert(isPresented: $showingResetAlert) {
                Alert(
                    title: Text("Reset Settings"),
                    message: Text("Are you sure you want to reset all settings to default values?"),
                    primaryButton: .destructive(Text("Reset")) {
                        settingsManager.reset()
                        tempPayRate = String(format: "%.2f", settingsManager.payRate)
                        tempDefaultShiftDuration = settingsManager.defaultShiftDuration
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            Toggle("Dark Mode", isOn: $settingsManager.isDarkMode)
        }
    }
    
    private var defaultShiftSettingsSection: some View {
        Section(header: Text("Default Shift Settings")) {
            HStack {
                Text("Pay Rate")
                Spacer()
                TextField("Pay Rate", text: $tempPayRate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            Stepper(value: $tempDefaultShiftDuration, in: 0.5...24, step: 0.5) {
                Text("Default Duration: \(tempDefaultShiftDuration, specifier: "%.1f") hours")
            }
        }
    }
    
    private var earningsSection: some View {
        Section(header: Text("Earnings")) {
            Picker("Currency", selection: $settingsManager.currency) {
                ForEach(currencies, id: \.self) {
                    Text($0)
                }
            }
            Picker("Pay Period", selection: $settingsManager.payPeriod) {
                ForEach(payPeriods, id: \.self) {
                    Text($0)
                }
            }
            Toggle("Include Taxes", isOn: $settingsManager.includeTaxes)
        }
    }
    
    private var notificationsSection: some View {
        Section(header: Text("Notifications")) {
            Toggle("Shift Reminders", isOn: $settingsManager.shiftReminders)
            if settingsManager.shiftReminders {
                Stepper(value: $settingsManager.reminderTime, in: 5...120, step: 5) {
                    Text("Remind \(settingsManager.reminderTime) minutes before")
                }
            }
        }
    }
    
    private var exportSection: some View {
        Section(header: Text("Export Data")) {
            Button("Export as CSV") {
                // Implement CSV export functionality
            }
            Button("Export as PDF") {
                // Implement PDF export functionality
            }
        }
    }
    
    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                showingResetAlert = true
            }
            .foregroundColor(.red)
        }
    }
    
    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }
            Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://www.example.com/terms")!)
            Link("Contact Support", destination: URL(string: "https://www.example.com/support")!)
        }
    }
    
    private func saveSettings() {
        if let payRate = Double(tempPayRate) {
            settingsManager.payRate = payRate
        }
        settingsManager.defaultShiftDuration = tempDefaultShiftDuration
        presentationMode.wrappedValue.dismiss()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager())
    }
}

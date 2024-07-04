import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var tempPayRate: String = ""
    @State private var tempDefaultShiftDuration: Double = 8.0
    @State private var showingResetAlert = false
    
    let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CNY"]
    let payPeriods = ["Weekly", "Bi-Weekly", "Monthly"]
    let accentColors: [Color] = [.blue, .red, .green, .orange, .purple, .pink]

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
        Section(header: Text("Appearance").foregroundColor(Color.text)) {
            Picker("Color Scheme", selection: $settingsManager.colorScheme) {
                Text("Light").tag(AppColorScheme.light)
                Text("Dark").tag(AppColorScheme.dark)
                Text("System").tag(AppColorScheme.unspecified)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Picker("Accent Color", selection: $settingsManager.accentColor) {
                ForEach(accentColors.indices, id: \.self) { index in
                    HStack {
                        Circle()
                            .fill(accentColors[index])
                            .frame(width: 20, height: 20)
                        Text("Color \(index + 1)")
                    }
                    .tag(index)
                }
            }
        }
    }
    
    private var defaultShiftSettingsSection: some View {
        Section(header: Text("Default Shift Settings").foregroundColor(Color.text)) {
            HStack {
                Text("Pay Rate")
                Spacer()
                TextField("Pay Rate", text: $tempPayRate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: tempPayRate) { newValue in
                        if let payRate = Double(newValue) {
                            settingsManager.payRate = payRate
                        }
                    }
            }
            .foregroundColor(Color.text)
            Stepper(value: $tempDefaultShiftDuration, in: 0.5...24, step: 0.5) {
                Text("Default Duration: \(tempDefaultShiftDuration, specifier: "%.1f") hours")
            }
            .onChange(of: tempDefaultShiftDuration) { newValue in
                settingsManager.defaultShiftDuration = newValue
            }
            .foregroundColor(Color.text)
        }
    }
    
    private var earningsSection: some View {
        Section(header: Text("Earnings").foregroundColor(Color.text)) {
            Picker("Currency", selection: $settingsManager.currency) {
                ForEach(currencies, id: \.self) {
                    Text($0)
                }
            }
            .foregroundColor(Color.text)
            Picker("Pay Period", selection: $settingsManager.payPeriod) {
                ForEach(payPeriods, id: \.self) {
                    Text($0)
                }
            }
            .foregroundColor(Color.text)
            Toggle("Include Taxes", isOn: $settingsManager.includeTaxes)
                .foregroundColor(Color.text)
        }
    }
    
    private var notificationsSection: some View {
        Section(header: Text("Notifications").foregroundColor(Color.text)) {
            Toggle("Shift Reminders", isOn: $settingsManager.shiftReminders)
                .foregroundColor(Color.text)
            if settingsManager.shiftReminders {
                Stepper(value: $settingsManager.reminderTime, in: 5...120, step: 5) {
                    Text("Remind \(settingsManager.reminderTime) minutes before")
                }
                .foregroundColor(Color.text)
            }
        }
    }
    
    private var exportSection: some View {
        Section(header: Text("Export Data").foregroundColor(Color.text)) {
            Button("Export as CSV") {
                // Implement CSV export functionality
            }
            .foregroundColor(Color.accent)
            Button("Export as PDF") {
                // Implement PDF export functionality
            }
            .foregroundColor(Color.accent)
        }
    }
    
    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                showingResetAlert = true
            }
            .foregroundColor(Color.red)
        }
    }
    
    private var aboutSection: some View {
        Section(header: Text("About").foregroundColor(Color.text)) {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }
            .foregroundColor(Color.text)
            Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
                .foregroundColor(Color.accent)
            Link("Terms of Service", destination: URL(string: "https://www.example.com/terms")!)
                .foregroundColor(Color.accent)
            Link("Contact Support", destination: URL(string: "https://www.example.com/support")!)
                .foregroundColor(Color.accent)
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
            .environment(\.colorScheme, .light)
        
        SettingsView()
            .environmentObject(SettingsManager())
            .environment(\.colorScheme, .dark)
    }
}

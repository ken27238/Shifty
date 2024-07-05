import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    @Environment(\.dismiss) var dismiss
    
    @State private var tempPayRate: String = ""
    @State private var tempDefaultShiftDuration: Double = 8.0
    @State private var showingResetAlert = false
    @State private var showingPayRateAlert = false
    @State private var showingCurrencyAlert = false
    @State private var isDarkMode: Bool = false
    @State private var tempAccentColor: Color = .blue
    
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
            .background(colors.background)
            .onAppear(perform: loadInitialValues)
            .alert("Reset Settings", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive, action: resetSettings)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to reset all settings to default values?")
            }
            .alert("Change Pay Rate", isPresented: $showingPayRateAlert) {
                Button("Confirm", action: savePayRate)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to change the pay rate to \(tempPayRate)?")
            }
            .alert("Change Currency", isPresented: $showingCurrencyAlert) {
                Button("Confirm", action: saveCurrency)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Changing the currency will not convert existing earnings. Are you sure?")
            }
        }
    }
    
    private var appearanceSection: some View {
        Section {
            Toggle("Dark Mode", isOn: $isDarkMode)
                .onChange(of: isDarkMode) { newValue in
                    settingsManager.colorScheme = newValue ? .dark : .light
                }
            
            ColorPicker("Accent Color", selection: $tempAccentColor, supportsOpacity: false)
                .onChange(of: tempAccentColor) { newValue in
                    settingsManager.accentColor = newValue
                }
        } header: {
            Label("Appearance", systemImage: "paintpalette")
        }
    }
    
    private var defaultShiftSettingsSection: some View {
        Section {
            HStack {
                Text("Pay Rate")
                Spacer()
                TextField("Pay Rate", text: $tempPayRate)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: tempPayRate) { _ in validatePayRate() }
                    .accessibilityLabel("Pay Rate")
                    .accessibilityHint("Enter your hourly pay rate")
            }
            
            Stepper(value: $tempDefaultShiftDuration, in: 0.5...24, step: 0.5) {
                Text("Default Duration: \(tempDefaultShiftDuration, specifier: "%.1f") hours")
            }
            .accessibilityLabel("Default Shift Duration")
            .accessibilityValue("\(tempDefaultShiftDuration) hours")
            .accessibilityHint("Adjust the default shift duration")
        } header: {
            Label("Default Shift Settings", systemImage: "clock")
        }
    }
    
    private var earningsSection: some View {
        Section {
            Picker("Currency", selection: $settingsManager.currency) {
                ForEach(currencies, id: \.self) { Text($0) }
            }
            .onChange(of: settingsManager.currency) { _ in showingCurrencyAlert = true }
            
            Picker("Pay Period", selection: $settingsManager.payPeriod) {
                ForEach(payPeriods, id: \.self) { Text($0) }
            }
            
            Toggle("Include Taxes", isOn: $settingsManager.includeTaxes)
                .accessibilityHint("Toggle to include or exclude taxes in earnings calculations")
        } header: {
            Label("Earnings", systemImage: "dollarsign.circle")
        }
    }
    
    private var notificationsSection: some View {
        Section {
            Toggle("Shift Reminders", isOn: $settingsManager.shiftReminders)
                .accessibilityHint("Toggle to enable or disable shift reminders")
            
            if settingsManager.shiftReminders {
                Stepper(value: $settingsManager.reminderTime, in: 5...120, step: 5) {
                    Text("Remind \(settingsManager.reminderTime) minutes before")
                }
                .accessibilityLabel("Reminder Time")
                .accessibilityValue("\(settingsManager.reminderTime) minutes before shift")
                .accessibilityHint("Adjust how many minutes before a shift to receive a reminder")
            }
        } header: {
            Label("Notifications", systemImage: "bell")
        }
    }
    
    private var exportSection: some View {
        Section {
            Button(action: exportCSV) {
                Label("Export as CSV", systemImage: "square.and.arrow.up")
            }
            
            Button(action: exportPDF) {
                Label("Export as PDF", systemImage: "doc.text")
            }
        } header: {
            Label("Export Data", systemImage: "arrow.up.doc")
        }
    }
    
    private var resetSection: some View {
        Section {
            Button("Reset to Defaults") {
                showingResetAlert = true
            }
            .foregroundColor(.red)
            .accessibilityHint("Reset all settings to their default values")
        }
    }
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }
            
            Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://www.example.com/terms")!)
            Link("Contact Support", destination: URL(string: "https://www.example.com/support")!)
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }
    
    private func loadInitialValues() {
        tempPayRate = String(format: "%.2f", settingsManager.payRate)
        tempDefaultShiftDuration = settingsManager.defaultShiftDuration
        isDarkMode = settingsManager.colorScheme == .dark
        tempAccentColor = settingsManager.accentColor
    }
    
    private func validatePayRate() {
        guard let payRate = Double(tempPayRate), payRate > 0 else {
            // Show error for invalid pay rate
            return
        }
        showingPayRateAlert = true
    }
    
    private func savePayRate() {
        if let payRate = Double(tempPayRate) {
            settingsManager.payRate = payRate
        }
    }
    
    private func saveCurrency() {
        // Currency is already saved in settingsManager, just close the alert
    }
    
    private func resetSettings() {
        settingsManager.reset()
        loadInitialValues()
    }
    
    private func exportCSV() {
        // Implement CSV export functionality
    }
    
    private func exportPDF() {
        // Implement PDF export functionality
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .light)
        
        SettingsView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .dark)
    }
}

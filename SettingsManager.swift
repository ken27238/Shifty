import SwiftUI
import Combine

enum AppColorScheme: String {
    case light
    case dark
    case unspecified
}

class SettingsManager: ObservableObject {
    private let defaults = UserDefaults.standard
    
    // MARK: - Appearance
    @Published var colorScheme: AppColorScheme {
        didSet {
            defaults.set(colorScheme.rawValue, forKey: "colorScheme")
        }
    }
    
    @Published var accentColorIndex: Int {
        didSet {
            defaults.set(accentColorIndex, forKey: "accentColorIndex")
        }
    }
    
    @Published var accentColor: Color
    
    let accentColors: [Color] = [.blue, .red, .green, .orange, .purple, .pink]
    
    // MARK: - Default Shift Settings
    @Published var payRate: Double {
        didSet {
            defaults.set(payRate, forKey: "payRate")
        }
    }
    
    @Published var defaultShiftDuration: Double {
        didSet {
            defaults.set(defaultShiftDuration, forKey: "defaultShiftDuration")
        }
    }
    
    // MARK: - Earnings
    @Published var currency: String {
        didSet {
            defaults.set(currency, forKey: "currency")
        }
    }
    
    @Published var payPeriod: String {
        didSet {
            defaults.set(payPeriod, forKey: "payPeriod")
        }
    }
    
    @Published var includeTaxes: Bool {
        didSet {
            defaults.set(includeTaxes, forKey: "includeTaxes")
        }
    }
    
    // MARK: - Notifications
    @Published var shiftReminders: Bool {
        didSet {
            defaults.set(shiftReminders, forKey: "shiftReminders")
        }
    }
    
    @Published var reminderTime: Int {
        didSet {
            defaults.set(reminderTime, forKey: "reminderTime")
        }
    }
    
    // MARK: - Initialization
    init() {
        let colorSchemeString = defaults.string(forKey: "colorScheme") ?? ""
        self.colorScheme = AppColorScheme(rawValue: colorSchemeString) ?? .unspecified
        
        let tempAccentColorIndex = defaults.integer(forKey: "accentColorIndex")
        self.accentColorIndex = tempAccentColorIndex
        self.accentColor = accentColors[safe: tempAccentColorIndex] ?? .blue
        
        self.payRate = defaults.double(forKey: "payRate")
        self.defaultShiftDuration = defaults.double(forKey: "defaultShiftDuration")
        self.currency = defaults.string(forKey: "currency") ?? "USD"
        self.payPeriod = defaults.string(forKey: "payPeriod") ?? "Bi-Weekly"
        self.includeTaxes = defaults.bool(forKey: "includeTaxes")
        self.shiftReminders = defaults.bool(forKey: "shiftReminders")
        self.reminderTime = defaults.integer(forKey: "reminderTime")
        
        // Set default values if not already set
        if self.payRate == 0 {
            self.payRate = 15.0 // Default pay rate
        }
        if self.defaultShiftDuration == 0 {
            self.defaultShiftDuration = 8.0 // Default shift duration
        }
        if self.reminderTime == 0 {
            self.reminderTime = 30 // Default reminder time (30 minutes before shift)
        }
    }
    
    // MARK: - Reset to Defaults
    func reset() {
        colorScheme = .unspecified
        accentColorIndex = 0
        accentColor = accentColors[0]
        payRate = 15.0
        defaultShiftDuration = 8.0
        currency = "USD"
        payPeriod = "Bi-Weekly"
        includeTaxes = false
        shiftReminders = true
        reminderTime = 30
    }
    
    // MARK: - Helper Methods
    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    func calculateEarnings(hours: Double) -> Double {
        var earnings = hours * payRate
        if includeTaxes {
            // Apply a simple tax calculation (e.g., 20% tax rate)
            // In a real app, you'd want a more sophisticated tax calculation
            earnings *= 0.8
        }
        return earnings
    }
}

// Extension to safely access array elements
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

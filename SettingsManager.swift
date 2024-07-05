import SwiftUI
import Combine
import UserNotifications

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
    
    @Published var accentColor: Color {
        didSet {
            if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(accentColor), requiringSecureCoding: false) {
                defaults.set(colorData, forKey: "accentColor")
            }
        }
    }
    
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
        
        if let colorData = defaults.data(forKey: "accentColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
            self.accentColor = Color(color)
        } else {
            self.accentColor = .blue // Default accent color
        }
        
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
        accentColor = .blue
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
    
    // MARK: - Notification Methods
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.shiftReminders = granted
                if granted {
                    print("Notification permission granted")
                } else if let error = error {
                    print("Error requesting notification permission: \(error.localizedDescription)")
                } else {
                    print("Notification permission denied")
                }
            }
        }
    }
    
    func scheduleNotification(for shift: Shift) {
        guard shiftReminders, let shiftStart = shift.startTime else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Shift"
        content.body = "Your shift starts in \(reminderTime) minutes"
        content.sound = .default
        
        let triggerDate = Calendar.current.date(byAdding: .minute, value: -reminderTime, to: shiftStart)!
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: shift.objectID.uriRepresentation().absoluteString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    func removeNotification(for shift: Shift) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [shift.objectID.uriRepresentation().absoluteString])
    }
}

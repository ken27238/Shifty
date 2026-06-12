//
//  Shift.swift
//  Shifty
//

import Foundation
import SwiftData

// CloudKit sync requires every property to have a default value
// and relationships to be optional.
@Model
final class Shift {
    var start: Date = Date.now
    var end: Date = Date.now
    /// Unpaid break, subtracted from worked time.
    var breakMinutes: Int = 0
    var tips: Double = 0
    var notes: String = ""
    var job: Job?

    init(
        start: Date,
        end: Date,
        breakMinutes: Int = 0,
        tips: Double = 0,
        notes: String = "",
        job: Job? = nil
    ) {
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.tips = tips
        self.notes = notes
        self.job = job
    }

    var workedDuration: TimeInterval {
        max(0, end.timeIntervalSince(start) - TimeInterval(breakMinutes * 60))
    }

    var workedHours: Double {
        workedDuration / 3600
    }

    /// Base earnings without overtime rules; use PayCalculator for adjusted totals.
    var earnings: Double {
        workedHours * (job?.hourlyRate ?? 0) + tips
    }
}

extension Locale {
    /// The currency for money formatting: the user's override, or the locale's.
    static var currencyCode: String {
        if let override = UserDefaults.shared.string(forKey: SettingsKeys.currencyOverride),
           !override.isEmpty {
            return override
        }
        return Locale.current.currency?.identifier ?? "USD"
    }
}

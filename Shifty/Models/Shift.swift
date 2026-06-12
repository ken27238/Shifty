//
//  Shift.swift
//  Shifty
//

import Foundation
import SwiftData

@Model
final class Shift {
    var start: Date
    var end: Date
    /// Unpaid break, subtracted from worked time.
    var breakMinutes: Int
    var tips: Double
    var notes: String
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

    var earnings: Double {
        workedHours * (job?.hourlyRate ?? 0) + tips
    }
}

extension Locale {
    /// The user's currency, falling back to USD when the locale has none.
    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

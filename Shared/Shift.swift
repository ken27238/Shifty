//
//  Shift.swift
//  Shifty
//

import Foundation
import SwiftData
import CoreLocation

// CloudKit sync requires every property to have a default value
// and relationships to be optional.
@Model
final class Shift {
    var start: Date = Date.now
    var end: Date = Date.now
    /// Unpaid break, subtracted from worked time.
    var breakMinutes: Int = 0
    var tips: Double = 0
    /// Commute or work miles, tracked for tax records.
    var mileage: Double = 0
    /// Out-of-pocket expenses, tracked separately from earnings.
    var expenses: Double = 0
    var notes: String = ""
    /// Optional override of the job's location for this one shift.
    var locationName: String = ""
    var latitude: Double?
    var longitude: Double?
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

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The shift's own location when set, otherwise the job's.
    var resolvedCoordinate: CLLocationCoordinate2D? {
        coordinate ?? job?.coordinate
    }

    var resolvedLocationName: String {
        locationName.isEmpty ? (job?.locationName ?? "") : locationName
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

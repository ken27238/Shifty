//
//  PayCalculator.swift
//  Shifty
//

import Foundation
import SwiftData

nonisolated struct OvertimeRules {
    var enabled: Bool
    var weekly: Bool
    var threshold: Double
    var multiplier: Double

    static func load(from defaults: UserDefaults = .shared) -> OvertimeRules {
        OvertimeRules(
            enabled: defaults.bool(forKey: SettingsKeys.overtimeEnabled),
            weekly: defaults.bool(forKey: SettingsKeys.overtimeWeekly),
            threshold: defaults.double(forKey: SettingsKeys.overtimeThreshold),
            multiplier: defaults.double(forKey: SettingsKeys.overtimeMultiplier)
        )
    }
}

/// Earnings math with optional overtime rules applied.
///
/// Overtime is allocated chronologically within each period (week or day):
/// hours beyond the threshold are paid at the shift's own rate × multiplier.
enum PayCalculator {
    /// Overtime-adjusted earnings per shift, keyed by persistent ID.
    static func earningsByShift(
        for shifts: [Shift],
        rules: OvertimeRules = .load(),
        calendar: Calendar = .app
    ) -> [PersistentIdentifier: Double] {
        guard rules.enabled, rules.threshold > 0, rules.multiplier > 1 else {
            return Dictionary(uniqueKeysWithValues: shifts.map { ($0.persistentModelID, $0.earnings) })
        }

        let component: Calendar.Component = rules.weekly ? .weekOfYear : .day
        let grouped = Dictionary(grouping: shifts) {
            calendar.dateInterval(of: component, for: $0.start)?.start ?? $0.start
        }

        var result: [PersistentIdentifier: Double] = [:]
        for periodShifts in grouped.values {
            var hoursSoFar = 0.0
            for shift in periodShifts.sorted(by: { $0.start < $1.start }) {
                let hours = shift.workedHours
                let rate = shift.job?.hourlyRate ?? 0
                let regularHours = max(0, min(hours, rules.threshold - hoursSoFar))
                let overtimeHours = hours - regularHours
                result[shift.persistentModelID] =
                    regularHours * rate + overtimeHours * rate * rules.multiplier + shift.tips
                hoursSoFar += hours
            }
        }
        return result
    }

    static func totalEarnings(
        for shifts: [Shift],
        rules: OvertimeRules = .load(),
        calendar: Calendar = .app
    ) -> Double {
        earningsByShift(for: shifts, rules: rules, calendar: calendar).values.reduce(0, +)
    }
}

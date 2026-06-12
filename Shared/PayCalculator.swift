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

/// How often the user gets paid; drives the Pay tab's pay-period mode
/// and the payday countdown.
nonisolated enum PayCycle: String {
    case weekly
    case biweekly
    case semimonthly
    case monthly

    static func load(from defaults: UserDefaults = .shared) -> PayCycle {
        PayCycle(rawValue: defaults.string(forKey: SettingsKeys.payCycle) ?? "") ?? .weekly
    }
}

nonisolated enum PayPeriods {
    /// The biweekly anchor: a payday the user told us about, or a fixed
    /// deterministic Monday (Jan 1, 2001) until they set one.
    static func anchor(from defaults: UserDefaults = .shared, calendar: Calendar) -> Date {
        let timestamp = defaults.double(forKey: SettingsKeys.payAnchor)
        let date = timestamp > 0
            ? Date(timeIntervalSinceReferenceDate: timestamp)
            : Date(timeIntervalSinceReferenceDate: 0)
        return calendar.startOfDay(for: date)
    }

    static func interval(
        containing date: Date,
        cycle: PayCycle,
        calendar: Calendar = .app,
        defaults: UserDefaults = .shared
    ) -> DateInterval {
        let fallback = DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        switch cycle {
        case .weekly:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? fallback
        case .monthly:
            return calendar.dateInterval(of: .month, for: date) ?? fallback
        case .biweekly:
            let anchor = anchor(from: defaults, calendar: calendar)
            let days = calendar.dateComponents(
                [.day], from: anchor, to: calendar.startOfDay(for: date)
            ).day ?? 0
            let periodIndex = Int(floor(Double(days) / 14))
            guard let start = calendar.date(byAdding: .day, value: periodIndex * 14, to: anchor),
                  let end = calendar.date(byAdding: .day, value: 14, to: start)
            else { return fallback }
            return DateInterval(start: start, end: end)
        case .semimonthly:
            // First half: 1st–15th; second half: 16th–end of month.
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let day = components.day,
                  let month = calendar.dateInterval(of: .month, for: date)
            else { return fallback }
            guard let mid = calendar.date(from: DateComponents(
                year: components.year, month: components.month, day: 16
            )) else { return fallback }
            return day <= 15
                ? DateInterval(start: month.start, end: mid)
                : DateInterval(start: mid, end: month.end)
        }
    }
}

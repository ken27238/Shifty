//
//  ShiftyTests.swift
//  ShiftyTests
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Shifty

@MainActor
struct PayCalculatorTests {
    /// Deterministic Gregorian calendar, Monday week start, fixed zone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// The container must outlive the context, so tests hold the container.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: .shifty,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func shiftDurationSubtractsBreaks() throws {
        let shift = Shift(
            start: date(2026, 6, 8, 9),
            end: date(2026, 6, 8, 17),
            breakMinutes: 30
        )
        #expect(shift.workedHours == 7.5)
    }

    @Test func baseEarningsIncludeTips() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let job = Job(name: "Cafe", hourlyRate: 20)
        context.insert(job)
        let shift = Shift(
            start: date(2026, 6, 8, 9),
            end: date(2026, 6, 8, 17),
            tips: 35,
            job: job
        )
        context.insert(shift)
        #expect(shift.earnings == 8 * 20 + 35)
    }

    @Test func weeklyOvertimeAppliesPastThreshold() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let job = Job(name: "Warehouse", hourlyRate: 10)
        context.insert(job)
        // Two shifts in one week: 24 + 24 = 48 hours; 8 beyond a 40-hour threshold.
        let first = Shift(start: date(2026, 6, 8, 0), end: date(2026, 6, 9, 0), job: job)
        let second = Shift(start: date(2026, 6, 10, 0), end: date(2026, 6, 11, 0), job: job)
        context.insert(first)
        context.insert(second)

        let rules = OvertimeRules(enabled: true, weekly: true, threshold: 40, multiplier: 1.5)
        let total = PayCalculator.totalEarnings(for: [first, second], rules: rules, calendar: calendar)
        // 40h at $10 plus 8h at $15.
        #expect(abs(total - (400 + 120)) < 0.001)
    }

    @Test func dailyOvertimeAppliesPerDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let job = Job(name: "Site", hourlyRate: 10)
        context.insert(job)
        // 12 hours in one day with an 8-hour daily threshold.
        let shift = Shift(start: date(2026, 6, 8, 6), end: date(2026, 6, 8, 18), job: job)
        context.insert(shift)

        let rules = OvertimeRules(enabled: true, weekly: false, threshold: 8, multiplier: 2)
        let total = PayCalculator.totalEarnings(for: [shift], rules: rules, calendar: calendar)
        // 8h at $10 plus 4h at $20.
        #expect(abs(total - (80 + 80)) < 0.001)
    }

    @Test func disabledOvertimeMatchesBaseEarnings() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let job = Job(name: "Cafe", hourlyRate: 18)
        context.insert(job)
        let shift = Shift(start: date(2026, 6, 8, 0), end: date(2026, 6, 10, 0), tips: 12, job: job)
        context.insert(shift)

        let rules = OvertimeRules(enabled: false, weekly: true, threshold: 40, multiplier: 1.5)
        let total = PayCalculator.totalEarnings(for: [shift], rules: rules, calendar: calendar)
        #expect(abs(total - shift.earnings) < 0.001)
    }
}

@MainActor
struct PayPeriodsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func defaults(anchor: Date?) -> UserDefaults {
        let suite = UserDefaults(suiteName: "PayPeriodsTests-\(UUID().uuidString)")!
        if let anchor {
            suite.set(anchor.timeIntervalSinceReferenceDate, forKey: SettingsKeys.payAnchor)
        }
        return suite
    }

    @Test func biweeklyPeriodsAreFourteenDaysFromAnchor() throws {
        let anchor = date(2026, 6, 1) // a Monday
        let suite = defaults(anchor: anchor)

        let interval = PayPeriods.interval(
            containing: date(2026, 6, 20), cycle: .biweekly,
            calendar: calendar, defaults: suite
        )
        #expect(interval.start == date(2026, 6, 15))
        #expect(interval.end == date(2026, 6, 29))
        #expect(interval.contains(date(2026, 6, 20)))
    }

    @Test func biweeklyAnchorIsThePeriodStart() throws {
        // A period of Sunday June 7 through Saturday June 20 is anchored
        // by entering June 7 — the first day, not the payday.
        let suite = defaults(anchor: date(2026, 6, 7))

        let interval = PayPeriods.interval(
            containing: date(2026, 6, 12), cycle: .biweekly,
            calendar: calendar, defaults: suite
        )
        #expect(interval.start == date(2026, 6, 7))
        #expect(interval.end == date(2026, 6, 21))
    }

    @Test func biweeklyHandlesDatesBeforeAnchor() throws {
        let anchor = date(2026, 6, 1)
        let suite = defaults(anchor: anchor)

        let interval = PayPeriods.interval(
            containing: date(2026, 5, 25), cycle: .biweekly,
            calendar: calendar, defaults: suite
        )
        #expect(interval.start == date(2026, 5, 18))
        #expect(interval.end == date(2026, 6, 1))
    }

    @Test func semimonthlySplitsAtTheSixteenth() throws {
        let suite = defaults(anchor: nil)

        let firstHalf = PayPeriods.interval(
            containing: date(2026, 6, 10), cycle: .semimonthly,
            calendar: calendar, defaults: suite
        )
        #expect(firstHalf.start == date(2026, 6, 1))
        #expect(firstHalf.end == date(2026, 6, 16))

        let secondHalf = PayPeriods.interval(
            containing: date(2026, 6, 16), cycle: .semimonthly,
            calendar: calendar, defaults: suite
        )
        #expect(secondHalf.start == date(2026, 6, 16))
        #expect(secondHalf.end == date(2026, 7, 1))
    }

    @Test func weeklyMatchesCalendarWeek() throws {
        let suite = defaults(anchor: nil)
        let interval = PayPeriods.interval(
            containing: date(2026, 6, 10), cycle: .weekly,
            calendar: calendar, defaults: suite
        )
        // June 10, 2026 is a Wednesday; Monday-start week is June 8–15.
        #expect(interval.start == date(2026, 6, 8))
        #expect(interval.end == date(2026, 6, 15))
    }
}

@MainActor
struct LocationFallbackTests {
    @Test func shiftFallsBackToJobLocation() throws {
        let container = try ModelContainer(
            for: .shifty,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let job = Job(name: "Cafe", hourlyRate: 20)
        job.locationName = "Blue Bottle"
        job.latitude = 37.776
        job.longitude = -122.423
        context.insert(job)

        let shift = Shift(start: .now, end: .now.addingTimeInterval(3600), job: job)
        context.insert(shift)

        #expect(shift.resolvedLocationName == "Blue Bottle")
        #expect(shift.resolvedCoordinate?.latitude == 37.776)

        // A custom location overrides the job's.
        shift.locationName = "Pop-Up Site"
        shift.latitude = 40.0
        shift.longitude = -75.0
        #expect(shift.resolvedLocationName == "Pop-Up Site")
        #expect(shift.resolvedCoordinate?.latitude == 40.0)
    }
}

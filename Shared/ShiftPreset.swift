//
//  ShiftPreset.swift
//  Shifty
//

import Foundation
import SwiftData

// CloudKit sync requires every property to have a default value.
/// A reusable shift pattern ("Opening shift, 9–5 at Cafe") used by the
/// shift form and the rotation generator.
@Model
final class ShiftPreset {
    var name: String = ""
    /// Minutes from midnight.
    var startMinutes: Int = 9 * 60
    var durationMinutes: Int = 8 * 60
    var breakMinutes: Int = 0
    /// Loose reference by name, like the default-job setting.
    var jobName: String = ""

    init(
        name: String,
        startMinutes: Int = 9 * 60,
        durationMinutes: Int = 8 * 60,
        breakMinutes: Int = 0,
        jobName: String = ""
    ) {
        self.name = name
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.breakMinutes = breakMinutes
        self.jobName = jobName
    }

    /// A concrete shift on the given day; the job is resolved by name.
    func makeShift(on day: Date, jobs: [Job], calendar: Calendar = .app) -> Shift? {
        guard let start = calendar.date(
            bySettingHour: startMinutes / 60,
            minute: startMinutes % 60,
            second: 0,
            of: day
        ) else { return nil }
        return Shift(
            start: start,
            end: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            breakMinutes: breakMinutes,
            job: jobs.first { $0.name == jobName }
        )
    }
}

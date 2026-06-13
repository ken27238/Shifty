//
//  DemoData.swift
//  Shifty
//

import Foundation
import SwiftData

/// Seeds a few jobs and shifts when launched with `-seedDemoData`, used
/// for screenshots and previewing wide layouts. No-op unless the store is
/// empty, so it never disturbs real data.
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemoData")
    }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard isRequested else { return }
        guard (try? context.fetch(FetchDescriptor<Job>()))?.isEmpty ?? false else { return }

        let cafe = Job(name: "Cafe", hourlyRate: 20, colorName: "teal")
        let warehouse = Job(name: "Warehouse", hourlyRate: 24, colorName: "purple")
        context.insert(cafe)
        context.insert(warehouse)

        let calendar = Calendar.app
        let today = calendar.startOfDay(for: .now)

        // Five recent/this-week shifts plus a couple upcoming.
        let plan: [(day: Int, startHour: Int, hours: Int, job: Job, tips: Double)] = [
            (-3, 9, 8, cafe, 42),
            (-2, 6, 8, warehouse, 0),
            (-1, 9, 8, cafe, 55),
            (0, 9, 8, cafe, 38),
            (1, 6, 9, warehouse, 0),
            (2, 9, 8, cafe, 0),
        ]
        for entry in plan {
            guard let day = calendar.date(byAdding: .day, value: entry.day, to: today),
                  let start = calendar.date(bySettingHour: entry.startHour, minute: 0, second: 0, of: day)
            else { continue }
            let shift = Shift(
                start: start,
                end: start.addingTimeInterval(TimeInterval(entry.hours * 3600)),
                breakMinutes: 30,
                tips: entry.tips,
                job: entry.job
            )
            context.insert(shift)
        }
        try? context.save()
    }
}

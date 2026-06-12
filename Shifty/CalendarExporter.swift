//
//  CalendarExporter.swift
//  Shifty
//

import EventKit
import Foundation

/// Exports shifts as events to the user's default Apple Calendar.
@MainActor
enum CalendarExporter {
    enum ExportError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                String(localized: "Calendar access was denied. You can allow it in Settings.")
            }
        }
    }

    /// Returns the number of events created.
    static func export(shifts: [Shift]) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else {
            throw ExportError.accessDenied
        }

        for shift in shifts {
            let event = EKEvent(eventStore: store)
            event.title = shift.job.map { "\($0.name) Shift" } ?? String(localized: "Shift")
            event.startDate = shift.start
            event.endDate = shift.end
            event.notes = shift.notes.isEmpty ? nil : shift.notes
            event.calendar = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        return shifts.count
    }
}

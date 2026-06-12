//
//  ShiftIntelligence.swift
//  Shifty
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A model-extracted shift, resolved to concrete dates and ready to
/// pre-fill the form or import. The model only ever proposes drafts;
/// nothing is saved without the user confirming.
struct ResolvedShiftDraft: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var breakMinutes: Int
    var tips: Double
    var jobName: String
    var notes: String
}

#if canImport(FoundationModels)
@Generable
struct ShiftDraft {
    @Guide(description: "Calendar date of the shift as yyyy-MM-dd. Resolve relative phrases like 'yesterday' or 'last Tuesday' using the current date from the instructions.")
    var date: String

    @Guide(description: "Start time as 24-hour HH:mm.")
    var startTime: String

    @Guide(description: "End time as 24-hour HH:mm.")
    var endTime: String

    @Guide(description: "Unpaid break in minutes. 0 if not mentioned.")
    var breakMinutes: Int

    @Guide(description: "Tips earned, as a plain number. 0 if not mentioned.")
    var tips: Double

    @Guide(description: "The job or workplace name. Use the closest known job name from the instructions when one matches; empty string if no workplace is mentioned.")
    var jobName: String

    @Guide(description: "Any other detail worth keeping as a note. Empty string if none.")
    var notes: String
}

@Generable
struct ShiftDraftList {
    @Guide(description: "Every distinct work shift found in the text, in order.")
    var shifts: [ShiftDraft]
}
#endif

/// On-device Apple Intelligence extraction of shifts from natural language.
enum ShiftIntelligence {
    /// Whether the device supports and has enabled Apple Intelligence.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    /// Parses a single described shift, e.g. "9 to 5 at the cafe yesterday".
    static func parseShift(from text: String, jobNames: [String]) async throws -> ResolvedShiftDraft? {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: instructions(jobNames: jobNames))
        let response = try await session.respond(to: text, generating: ShiftDraft.self)
        return resolve(response.content)
        #else
        return nil
        #endif
    }

    /// Parses a pasted schedule that may contain many shifts.
    static func parseSchedule(from text: String, jobNames: [String]) async throws -> [ResolvedShiftDraft] {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: instructions(jobNames: jobNames))
        let response = try await session.respond(to: text, generating: ShiftDraftList.self)
        return response.content.shifts.compactMap(resolve)
        #else
        return []
        #endif
    }

    #if canImport(FoundationModels)
    private static func instructions(jobNames: [String]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: .now)
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))

        var lines = [
            "You extract work shifts from text someone wrote about their job schedule.",
            "Today is \(weekday), \(today).",
            "Resolve relative dates against today. If no year is given, use the current year.",
            "If no date is mentioned at all, use today.",
            "Times are 24-hour. '9 to 5' means 09:00 to 17:00 unless context says otherwise.",
        ]
        if !jobNames.isEmpty {
            lines.append("Known job names: \(jobNames.joined(separator: ", ")). Prefer the closest known name for the workplace.")
        }
        return lines.joined(separator: "\n")
    }

    private static func resolve(_ draft: ShiftDraft) -> ResolvedShiftDraft? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let start = formatter.date(from: "\(draft.date) \(draft.startTime)"),
              var end = formatter.date(from: "\(draft.date) \(draft.endTime)")
        else { return nil }
        // Overnight shifts end the next day.
        if end <= start {
            end = Calendar.app.date(byAdding: .day, value: 1, to: end) ?? end
        }

        return ResolvedShiftDraft(
            start: start,
            end: end,
            breakMinutes: max(draft.breakMinutes, 0),
            tips: max(draft.tips, 0),
            jobName: draft.jobName,
            notes: draft.notes
        )
    }
    #endif
}

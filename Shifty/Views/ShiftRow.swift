//
//  ShiftRow.swift
//  Shifty
//

import SwiftUI

/// A list row summarizing one shift. Set `showsDate` to false in contexts
/// where the date is already clear (e.g. a single day in the calendar).
struct ShiftRow: View {
    let shift: Shift
    var showsDate = true
    /// Fade future shifts so history and plans read differently (used in the main list).
    var dimsUpcoming = false
    /// Show an OT badge when part of this shift was paid at the overtime rate.
    var overtime = false

    private var isInProgress: Bool {
        shift.start <= .now && shift.end > .now
    }

    private var isUpcoming: Bool {
        shift.start > .now
    }

    private var timeRange: String {
        "\(shift.start.formatted(date: .omitted, time: .shortened)) – \(shift.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(shift.job?.color ?? Color.secondary)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(showsDate
                         ? shift.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                         : timeRange)
                        .font(.headline)
                    if isInProgress {
                        StatusBadge(text: "Now", color: .green)
                    }
                    if overtime {
                        StatusBadge(text: "OT", color: .orange)
                    }
                }

                HStack(spacing: 4) {
                    if showsDate {
                        if let job = shift.job {
                            Text(job.name)
                            Text("·")
                        }
                        Text(timeRange)
                    } else if let job = shift.job {
                        Text(job.name)
                    }
                    if !shift.notes.isEmpty {
                        Image(systemName: "note.text")
                            .accessibilityLabel("Has notes")
                    }
                    if shift.tips > 0 {
                        Image(systemName: "banknote")
                            .accessibilityLabel("Has tips")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shift.earnings, format: .currency(code: Locale.currencyCode))
                    .font(.headline)
                Text(Duration.seconds(shift.workedDuration), format: .units(allowed: [.hours, .minutes], width: .narrow))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(dimsUpcoming && isUpcoming ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct StatusBadge: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

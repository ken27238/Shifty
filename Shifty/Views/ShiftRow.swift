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
                if showsDate {
                    Text(shift.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.headline)
                    HStack(spacing: 4) {
                        if let job = shift.job {
                            Text(job.name)
                            Text("·")
                        }
                        Text(timeRange)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text(timeRange)
                        .font(.headline)
                    if let job = shift.job {
                        Text(job.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

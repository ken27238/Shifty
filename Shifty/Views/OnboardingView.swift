//
//  OnboardingView.swift
//  Shifty
//

import SwiftUI
import SwiftData

/// First-launch setup: a quick pitch and the one thing that makes the app
/// work well from day one — a job with an hourly rate.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let onFinish: () -> Void

    private enum Field {
        case name
        case rate
    }

    @State private var jobName = ""
    // Optional so the field starts empty instead of a "$0.00" to type around.
    @State private var hourlyRate: Double?
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Welcome to Shifty")
                        .font(.largeTitle.bold())
                    Text("Track your shifts, hours, and pay — all in one place.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "calendar",
                        title: "Plan and log shifts",
                        detail: "A calendar, repeat actions, and rotation patterns do the busywork."
                    )
                    featureRow(
                        icon: "banknote",
                        title: "Know your pay",
                        detail: "Overtime, tips, and pay periods — see what your check should say."
                    )
                    featureRow(
                        icon: "bell",
                        title: "Stay on schedule",
                        detail: "Shift reminders, widgets, and Siri keep your week in view."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Set up your first job")
                        .font(.headline)
                    Text("Earnings are calculated from a job's hourly rate. You can add more jobs later in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Job name (e.g. Cafe)", text: $jobName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .rate }
                    LabeledContent("Hourly Rate") {
                        TextField(
                            "Hourly Rate",
                            value: $hourlyRate,
                            format: .currency(code: Locale.currencyCode)
                        )
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .labelsHidden()
                        .focused($focusedField, equals: .rate)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    }
                }
                .padding(16)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 8) {
                    Button {
                        finish(creatingJob: true)
                    } label: {
                        Text("Get Started")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Skip for Now") {
                        finish(creatingJob: false)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled()
    }

    private func featureRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finish(creatingJob: Bool) {
        let trimmed = jobName.trimmingCharacters(in: .whitespaces)
        if creatingJob, !trimmed.isEmpty {
            modelContext.insert(Job(name: trimmed, hourlyRate: max(hourlyRate ?? 0, 0)))
            // First job becomes the default so new shifts pick up its rate.
            UserDefaults.shared.set(trimmed, forKey: SettingsKeys.defaultJobName)
        }
        onFinish()
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .modelContainer(for: ShiftyModels.all, inMemory: true)
}

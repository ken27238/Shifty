//
//  ShiftsView.swift
//  Shifty
//

import SwiftUI
import SwiftData

struct ShiftsView: View {
    @Binding var selectedTab: AppTab
    /// Set alongside switching to the Pay tab to scope it to a week.
    @Binding var payRequestDate: Date?
    /// Set by other tabs (e.g. tapping a job in Pay) to filter this list;
    /// consumed and cleared on arrival.
    @Binding var jobFilterRequest: String?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shift.start, order: .reverse) private var shifts: [Shift]
    @Query(sort: \Job.name) private var jobs: [Job]

    // Declared so the view refreshes when these settings change.
    @AppStorage(SettingsKeys.weekStartDay, store: .shared) private var weekStartDay = 0
    @AppStorage(SettingsKeys.overtimeEnabled, store: .shared) private var overtimeEnabled = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Wide layouts edit shifts in a trailing inspector instead of a sheet.
    private var isRegularWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    /// Sheet presentation, used only at compact widths.
    private var sheetShift: Binding<Shift?> {
        Binding(
            get: { isRegularWidth ? nil : shiftBeingEdited },
            set: { shiftBeingEdited = $0 }
        )
    }

    /// Inspector presentation, used only at regular widths.
    private var isInspectorPresented: Binding<Bool> {
        Binding(
            get: { isRegularWidth && shiftBeingEdited != nil },
            set: { if !$0 { shiftBeingEdited = nil } }
        )
    }

    @State private var isAddingShift = false
    @State private var shiftBeingEdited: Shift?
    @State private var searchText = ""
    @State private var jobFilterName: String?
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<PersistentIdentifier>()
    @State private var isPickingJumpDate = false
    @State private var isImportingFromText = false
    @State private var jumpDate: Date = .now
    @State private var scrollTarget: Date?

    private var calendar: Calendar { .app }

    private var filteredShifts: [Shift] {
        shifts.filter { shift in
            if let jobFilterName, shift.job?.name != jobFilterName {
                return false
            }
            if !searchText.isEmpty {
                let haystack = "\(shift.job?.name ?? "") \(shift.notes)"
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    /// Shifts grouped by the start of their week — newest week first,
    /// but chronological within each week.
    private var weeks: [(weekStart: Date, shifts: [Shift])] {
        let grouped = Dictionary(grouping: filteredShifts) { shift in
            calendar.dateInterval(of: .weekOfYear, for: shift.start)?.start ?? shift.start
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (weekStart: $0.key, shifts: $0.value.sorted { $0.start < $1.start }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if shifts.isEmpty {
                    emptyState
                } else if filteredShifts.isEmpty {
                    ContentUnavailableView.search
                } else {
                    shiftList
                }
            }
            .navigationTitle("Shifts")
            .searchable(text: $searchText, prompt: "Job or notes")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingShift) {
                ShiftFormView()
            }
            .sheet(item: sheetShift) { shift in
                ShiftFormView(shift: shift)
            }
            .inspector(isPresented: isInspectorPresented) {
                if let shift = shiftBeingEdited {
                    ShiftFormView(shift: shift)
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 460)
                }
            }
            .sheet(isPresented: $isPickingJumpDate) {
                jumpDateSheet
            }
            .sheet(isPresented: $isImportingFromText) {
                ScheduleImportView(
                    jobNames: jobs.filter { !$0.archived }.map(\.name)
                ) { drafts in
                    importDrafts(drafts)
                }
            }
            .onAppear { applyJobFilterRequest() }
            .onChange(of: jobFilterRequest) { _, _ in applyJobFilterRequest() }
        }
    }

    private func applyJobFilterRequest() {
        guard let request = jobFilterRequest else { return }
        jobFilterName = request
        jobFilterRequest = nil
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Shifts", systemImage: "clock.badge.questionmark")
        } description: {
            Text("Shifts you log will appear here.")
        } actions: {
            Button("Add Shift") { isAddingShift = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var shiftList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(weeks, id: \.weekStart) { week in
                    weekSection(week)
                        .id(week.weekStart)
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }

    private func weekSection(_ week: (weekStart: Date, shifts: [Shift])) -> some View {
        // Flag shifts that earned overtime so rows can badge them.
        let adjusted = PayCalculator.earningsByShift(for: week.shifts, calendar: calendar)

        return Section {
            ForEach(week.shifts) { shift in
                Button {
                    guard !editMode.isEditing else { return }
                    shiftBeingEdited = shift
                } label: {
                    ShiftRow(
                        shift: shift,
                        dimsUpcoming: true,
                        overtime: (adjusted[shift.persistentModelID] ?? 0) > shift.earnings + 0.005
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        duplicate(shift)
                    }
                    .tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(shift)
                    }
                }
                .contextMenu {
                    Button("Repeat Today", systemImage: "arrow.counterclockwise") {
                        repeatShift(shift, daysFromToday: 0)
                    }
                    Button("Repeat Tomorrow", systemImage: "calendar.badge.plus") {
                        repeatShift(shift, daysFromToday: 1)
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        duplicate(shift)
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(shift)
                    }
                }
            }
        } header: {
            WeekHeader(weekStart: week.weekStart, shifts: week.shifts, calendar: calendar) {
                payRequestDate = week.weekStart
                selectedTab = .pay
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            if !shifts.isEmpty {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
            }
        }
        if editMode.isEditing && !selection.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Delete \(selection.count) Shifts", systemImage: "trash", role: .destructive) {
                    deleteSelected()
                }
            }
        }
        #endif
        ToolbarItemGroup(placement: .primaryAction) {
            filterMenu
            Button("Add Shift", systemImage: "plus") {
                isAddingShift = true
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button("Jump to Date", systemImage: "calendar") {
                isPickingJumpDate = true
            }
        }
        if ShiftIntelligence.isAvailable {
            ToolbarItem(placement: .secondaryAction) {
                Button("Import from Text", systemImage: "wand.and.stars") {
                    isImportingFromText = true
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Job", selection: $jobFilterName) {
                Text("All Jobs").tag(String?.none)
                ForEach(jobs.filter { !$0.archived }) { job in
                    Text(job.name).tag(Optional(job.name))
                }
            }
        } label: {
            Label(
                "Filter by Job",
                systemImage: jobFilterName == nil
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .disabled(jobs.isEmpty)
    }

    private var jumpDateSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Jump to Date", selection: $jumpDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle("Jump to Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { isPickingJumpDate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        isPickingJumpDate = false
                        jump(to: jumpDate)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Actions

    private func jump(to date: Date) {
        guard let targetWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return }
        // Exact week if present, otherwise the nearest older one.
        let destination = weeks.first { $0.weekStart <= targetWeek }?.weekStart ?? weeks.last?.weekStart
        scrollTarget = destination
    }

    private func duplicate(_ shift: Shift) {
        let copy = Shift(
            start: shift.start,
            end: shift.end,
            breakMinutes: shift.breakMinutes,
            tips: 0,
            notes: shift.notes,
            job: shift.job
        )
        copy.locationName = shift.locationName
        copy.latitude = shift.latitude
        copy.longitude = shift.longitude
        withAnimation {
            modelContext.insert(copy)
        }
        refreshWidgets()
    }

    private func repeatShift(_ shift: Shift, daysFromToday: Int) {
        guard let targetDay = calendar.date(
            byAdding: .day, value: daysFromToday, to: calendar.startOfDay(for: .now)
        ) else { return }
        let time = calendar.dateComponents([.hour, .minute], from: shift.start)
        guard let newStart = calendar.date(
            bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: targetDay
        ) else { return }

        let newShift = Shift(
            start: newStart,
            end: newStart.addingTimeInterval(shift.end.timeIntervalSince(shift.start)),
            breakMinutes: shift.breakMinutes,
            tips: 0,
            notes: shift.notes,
            job: shift.job
        )
        newShift.locationName = shift.locationName
        newShift.latitude = shift.latitude
        newShift.longitude = shift.longitude
        withAnimation {
            modelContext.insert(newShift)
        }
        refreshWidgets()
    }

    /// Saves model-extracted shifts, matching jobs by name.
    private func importDrafts(_ drafts: [ResolvedShiftDraft]) {
        let activeJobs = jobs.filter { !$0.archived }
        withAnimation {
            for draft in drafts {
                let shift = Shift(
                    start: draft.start,
                    end: draft.end,
                    breakMinutes: draft.breakMinutes,
                    tips: draft.tips,
                    notes: draft.notes,
                    job: activeJobs.first {
                        $0.name.localizedCaseInsensitiveCompare(draft.jobName) == .orderedSame
                    }
                )
                modelContext.insert(shift)
            }
        }
        refreshWidgets()
    }

    private func delete(_ shift: Shift) {
        withAnimation {
            modelContext.delete(shift)
        }
        refreshWidgets()
    }

    private func deleteSelected() {
        withAnimation {
            for id in selection {
                if let shift = shifts.first(where: { $0.persistentModelID == id }) {
                    modelContext.delete(shift)
                }
            }
            selection.removeAll()
            editMode = .inactive
        }
        refreshWidgets()
    }
}

private struct WeekHeader: View {
    let weekStart: Date
    let shifts: [Shift]
    let calendar: Calendar
    let onTap: () -> Void

    private var title: String {
        if calendar.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) {
            return String(localized: "This Week")
        }
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
            return weekStart.formatted(date: .abbreviated, time: .omitted)
        }
        let lastDay = interval.end.addingTimeInterval(-1)
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var totalHours: Double {
        shifts.reduce(0) { $0 + $1.workedHours }
    }

    private var totalEarnings: Double {
        PayCalculator.totalEarnings(for: shifts, calendar: calendar)
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                Image(systemName: "chevron.forward")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Spacer()
                Text("\(totalHours.formatted(.number.precision(.fractionLength(0...1)))) hrs · \(totalEarnings.formatted(.currency(code: Locale.currencyCode).precision(.fractionLength(0))))")
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows this week in the Pay tab")
    }
}

#Preview {
    ShiftsView(
        selectedTab: .constant(.shifts),
        payRequestDate: .constant(nil),
        jobFilterRequest: .constant(nil)
    )
    .modelContainer(for: ShiftyModels.all, inMemory: true)
}

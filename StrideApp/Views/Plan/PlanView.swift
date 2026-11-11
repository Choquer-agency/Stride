import SwiftUI
import SwiftData
import PostHog

struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var planSync = PlanSyncService.shared
    @State private var selectedWeekNumber: Int
    @State private var selectedWorkout: Workout?
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var showAnalysisSheet = false
    @State private var showCoachChat = false
    @State private var showCoachInbox = false  // v2 Phase 2
    @State private var prefillEditInstruction: String?

    let plan: TrainingPlan
    let readOnly: Bool

    // MARK: - Init (compute starting week immediately to avoid week-1 flash)
    init(plan: TrainingPlan, readOnly: Bool = false, onOpenProfile: @escaping () -> Void = {}) {
        self.plan = plan
        self.readOnly = readOnly
        self.onOpenProfile = onOpenProfile
        
        // Determine the correct starting week: current week > last week (if plan past) > first week
        let initialWeek: Int
        if let currentWeek = plan.currentWeek {
            initialWeek = currentWeek.weekNumber
        } else if plan.startDate < Date(), let lastWeek = plan.sortedWeeks.last {
            // Plan has started but today isn't in any week — show last week (plan is finished)
            initialWeek = lastWeek.weekNumber
        } else if let firstWeek = plan.sortedWeeks.first {
            // Plan hasn't started yet — show first week
            initialWeek = firstWeek.weekNumber
        } else {
            initialWeek = 1
        }
        
        _selectedWeekNumber = State(initialValue: initialWeek)
    }
    
    // MARK: - Computed Properties
    private var completedWorkoutsCount: Int {
        plan.completedWorkouts
    }
    
    private var selectedWeek: Week? {
        plan.sortedWeeks.first { $0.weekNumber == selectedWeekNumber }
    }
    
    private var totalWeeks: Int {
        plan.sortedWeeks.count
    }
    
    /// Whether all active (non-rest) workouts in the selected week are completed
    private var allWorkoutsCompleted: Bool {
        guard let week = selectedWeek else { return false }
        let active = week.workouts.filter { $0.workoutType != .rest }
        guard !active.isEmpty else { return false }
        return active.allSatisfy { $0.isCompleted }
    }
    
    /// Whether there is a next week to navigate to
    private var hasNextWeek: Bool {
        plan.sortedWeeks.contains { $0.weekNumber > selectedWeekNumber }
    }
    
    // MARK: - Body
    var body: some View {
        designBody
        .background { if readOnly { PlanPageBackdrop().ignoresSafeArea() } }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            if !readOnly {
                await planSync.reconcile(context: modelContext)
                await RunPullService.shared.reconcile(context: modelContext)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailView(
                workout: workout,
                onComplete: {
                    toggleWorkoutCompletion(workout)
                }
            ).preferredColorScheme(appearance.colorScheme)
        }
        .alert("Plan Options", isPresented: $showDeleteConfirmation) {
            Button("Archive Plan") {
                archivePlan()
            }
            Button("Delete Permanently", role: .destructive) {
                deletePlan()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Archive keeps your plan in Previous Plans. Delete removes it permanently.")
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            PlanEditInputView(plan: plan, initialInstructions: prefillEditInstruction)
                .preferredColorScheme(.light)
                .onDisappear {
                    prefillEditInstruction = nil
                }
        }
        .sheet(isPresented: $showCoachChat) {
            CoachChatView(trainingPlanId: nil).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showCoachInbox) {
            CoachInboxView().preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $showAnalysisSheet) {
            PerformanceAnalysisView(plan: plan) { instruction in
                prefillEditInstruction = instruction
                showEditSheet = true
            }.preferredColorScheme(.light)
        }
    }
    
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @ObservedObject private var auth = AuthService.shared
    @State private var selectedDate: Date? = nil
    @State private var showCoachTools = false
    var onOpenProfile: () -> Void = {}
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var ink: Color { appearance.foreground }
    private var muted: Color { appearance.secondary }
    private var weekDays: [Date] {
        guard let monday = selectedWeek?.mondayStart else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday) }
    }
    private var focusedDate: Date {
        if let selectedDate, weekDays.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }) { return selectedDate }
        return PlanDayScrollTarget.date(in: weekDays, today: Date()) ?? Date()
    }
    private func sessions(on date: Date) -> [Workout] {
        TrainingSessionSelection.onDay(date, workouts: selectedWeek?.sortedWorkouts ?? [])
    }
    private var focusedSessions: [Workout] { sessions(on: focusedDate).sorted { ($0.workoutType == .rest ? 1 : 0) < ($1.workoutType == .rest ? 1 : 0) } }
    private func isRun(_ workout: Workout) -> Bool {
        ![WorkoutType.rest, .gym, .crossTraining, .mobility].contains(workout.workoutType)
    }
    private var weekRuns: [Workout] { selectedWeek?.sortedWorkouts.filter(isRun) ?? [] }
    private var plannedKm: Double { weekRuns.reduce(0) { $0 + ($1.distanceKm ?? 0) } }
    private var completedKm: Double { weekRuns.filter(\.isCompleted).reduce(0) { $0 + ($1.actualDistanceKm ?? $1.distanceKm ?? 0) } }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func eyebrow(_ text: String) -> some View { Text(text).font(.runEyebrow(9)).tracking(1.2).foregroundStyle(muted) }
    private var initials: String {
        switch auth.authState {
        case .signedIn(let user), .needsProfile(let user):
            let letters = (user.name ?? user.displayName ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            return letters.isEmpty ? "You" : letters.uppercased()
        default: return "You"
        }
    }
    private var designHeader: some View {
        StridePageHeader(profileAction: onOpenProfile, redUsesDarkLogo: true)
    }
    private var raceHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                eyebrow(readOnly ? "ARCHIVED PLAN" : (plan.isHabitBlock ? "YOUR PLAN / BUILD THE HABIT" : "YOUR PLAN / ROAD TO RACE"))
                Spacer()
                planOptions
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text((plan.raceName?.isEmpty == false ? plan.raceName! : (plan.isHabitBlock ? "TRAINING BLOCK" : plan.displayDistance)).uppercased())
                        .font(.barlowCondensed(size: 43)).lineLimit(1).minimumScaleFactor(0.55)
                    Text(plan.raceDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.inter(size: 12)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(max(0, plan.daysUntilRace))").font(.barlowCondensed(size: 40)).monospacedDigit()
                    eyebrow("DAYS TO GO").font(.runEyebrow(8))
                }
            }
        }
    }
    private var planOptions: some View {
        Menu {
            if !readOnly {
                Button { showCoachChat = true } label: { Label("Ask Coach", systemImage: "bubble.left.and.text.bubble.right") }
                Button { showCoachInbox = true } label: { Label("Coach inbox", systemImage: "tray.full") }
                Button { showCoachTools = true } label: { Label("Check-in & active focuses", systemImage: "checklist") }
                Button { PostHogSDK.shared.capture("plan_edit_started"); showEditSheet = true } label: { Label("Edit Plan", systemImage: "pencil") }
                Button { showAnalysisSheet = true } label: { Label("Analyze Performance", systemImage: "chart.bar.xaxis") }.disabled(plan.completedWorkouts < 3)
                Divider()
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Archive or Delete Plan", systemImage: "archivebox") }
            } else { Text("Archived plan · Read only") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 30, height: 24).foregroundStyle(muted)
        }.accessibilityLabel("Plan options")
    }
    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("THIS WEEK / DISTANCE")
            HStack(alignment: .bottom, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(number(completedKm)).font(.barlowCondensed(size: 47))
                    Text("/ \(number(plannedKm))").font(.barlowCondensed(size: 27)).foregroundStyle(muted)
                    eyebrow("KM")
                }.lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(weekDays, id: \.self) { date in
                        let distance = sessions(on: date).filter(isRun).reduce(0) { $0 + ($1.distanceKm ?? 0) }
                        let maxDistance = max(1, weekRuns.compactMap(\.distanceKm).max() ?? 1)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Calendar.current.isDate(date, inSameDayAs: focusedDate) ? Color.stridePrimary : ink.opacity(0.10))
                            .frame(width: 13, height: max(3, 46 * distance / maxDistance))
                    }
                }.frame(height: 49).accessibilityLabel("Planned daily distances for the selected week")
            }
            Rectangle().fill(ink.opacity(0.09)).frame(height: 0.5)
            HStack {
                Circle().fill(Color.stridePrimary).frame(width: 4, height: 4)
                eyebrow("\(weekRuns.filter(\.isCompleted).count) / \(weekRuns.count) RUNS COMPLETE")
                Spacer()
                eyebrow("\(number(max(0, plannedKm - completedKm))) KM TO GO")
            }
        }.padding(18).background { glass }
    }
    private var glass: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(ink.opacity(appearance == .white ? 0.09 : 0.23), lineWidth: 0.6))
    }
    private var dayPicker: some View {
        TabView(selection: $selectedWeekNumber) {
            ForEach(plan.sortedWeeks, id: \.weekNumber) { week in
                weekCalendar(for: week)
                    .tag(week.weekNumber)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 128)
        .onChange(of: selectedWeekNumber) { _, _ in
            selectedDate = nil
            Haptics.selection()
        }
        .accessibilityHint("Swipe left for the next full week, right for the previous week. Double tap the week heading to return to this week.")
    }
    private func weekCalendar(for week: Week) -> some View {
        let days: [Date] = week.mondayStart.map { monday in
            (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday) }
        } ?? []
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("WEEK \(week.weekNumber)")
                    .font(.barlowCondensed(size: 23, weight: .semibold))
                    .onTapGesture(count: 2) { returnToCurrentWeek() }
                    .accessibilityHint("Double tap to return to the current week")
                eyebrow(week.dateRange.uppercased())
                Spacer()
                HStack(spacing: 14) {
                    Button { changeWeek(forward: false) } label: { Image(systemName: "chevron.left") }
                        .disabled(plan.sortedWeeks.first?.weekNumber == week.weekNumber).accessibilityLabel("Previous week")
                    Button { changeWeek(forward: true) } label: { Image(systemName: "chevron.right") }
                        .disabled(plan.sortedWeeks.last?.weekNumber == week.weekNumber).accessibilityLabel("Next week")
                }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(muted)
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { date in
                    weekDayButton(date, in: week)
                }
            }
        }
        .padding(.bottom, 7)
    }
    private func weekDayButton(_ date: Date, in week: Week) -> some View {
        let selected = week.weekNumber == selectedWeekNumber && Calendar.current.isDate(date, inSameDayAs: focusedDate)
        let today = Calendar.current.isDateInToday(date)
        let complete = TrainingSessionSelection.isDayComplete(date, workouts: week.sortedWorkouts)
        let accent: Color = today ? .stridePrimary : (complete ? .blue : ink)
        let emphasized = selected || today
        let fill = emphasized ? accent : (complete ? Color.blue.opacity(0.10) : ink.opacity(0.025))
        let border = today ? Color.stridePrimary : (complete ? Color.blue.opacity(0.55) : ink.opacity(0.10))
        return Button {
            if selectedWeekNumber != week.weekNumber { selectedWeekNumber = week.weekNumber }
            selectedDate = date
            Haptics.selection()
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow))).font(.runEyebrow(9))
                Text(date.formatted(.dateTime.day())).font(.barlowCondensed(size: 25))
                Group {
                    if today { Text("TODAY").font(.runEyebrow(6)) }
                    else if complete { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                    else { Circle().frame(width: 3, height: 3) }
                }
                .frame(height: 10)
                .foregroundStyle(emphasized ? Color.white : (complete ? Color.blue : muted))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .foregroundStyle(emphasized ? Color.white : (complete ? Color.blue : ink))
            .background(RoundedRectangle(cornerRadius: 18).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(border, lineWidth: today ? 1.2 : 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(today ? "Today" : (complete ? "Completed" : "Planned"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func returnToCurrentWeek() {
        guard let current = plan.currentWeek else { return }
        withAnimation(.easeInOut(duration: 0.32)) {
            selectedWeekNumber = current.weekNumber
            selectedDate = Date()
        }
    }
    private func changeWeek(forward: Bool) {
        guard let next = TrainingSessionSelection.adjacentWeek(current: selectedWeekNumber, weeks: plan.sortedWeeks.map(\.weekNumber), forward: forward) else { return }
        withAnimation(.easeInOut(duration: 0.32)) { selectedWeekNumber = next }
    }
    private var focusedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                eyebrow(focusedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                Spacer()
                let count = focusedSessions.filter { $0.workoutType != .rest }.count
                eyebrow("\(count) SESSION\(count == 1 ? "" : "S")")
            }
            if focusedSessions.isEmpty {
                Label("REST DAY", systemImage: "bed.double").font(.barlowCondensed(size: 27)).padding(.vertical, 18)
            }
            ForEach(focusedSessions, id: \.id) { workout in
                Button { selectWorkout(workout) } label: { sessionRow(workout) }.buttonStyle(.plain)
            }
        }
    }
    private func sessionTint(_ workout: Workout) -> Color {
        switch workout.workoutType {
        case .gym, .crossTraining: return .purple
        case .longRun: return .orange
        case .mobility: return .teal
        default: return workout.typeColor
        }
    }
    private func sessionRow(_ workout: Workout) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 2).fill(sessionTint(workout)).frame(width: 3, height: 44)
            Image(systemName: workout.workoutType.icon).font(.system(size: 20)).foregroundStyle(sessionTint(workout))
                .frame(width: 34, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title.uppercased()).font(.barlowCondensed(size: 27)).lineLimit(2)
                Text(workout.paceDescription ?? workout.durationDisplay ?? workout.workoutType.displayName)
                    .font(.inter(size: 12)).foregroundStyle(muted).lineLimit(1)
                if workout.isCompleted {
                    Label("COMPLETED", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(sessionTint(workout))
                }
            }
            Spacer(minLength: 0)
            if let km = workout.distanceKm {
                VStack(spacing: 1) { Text(number(km)).font(.barlowCondensed(size: 29)); eyebrow("KM") }
            }
            Image(systemName: "arrow.up.right").font(.system(size: 16)).foregroundStyle(Color.stridePrimary)
        }.padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.10)).frame(height: 0.5) }
            .contentShape(Rectangle())
    }
    private var designBody: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: geometry.size.height < 720 ? 12 : 24) {
                    designHeader
                    raceHeading
                    weeklyOverview
                    dayPicker
                    focusedSection
                    if !readOnly && planSync.pendingServerPlan != nil { serverPlanUpdateCard }
                    if allWorkoutsCompleted && hasNextWeek { nextWeekCard }
                }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 16)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
        }.foregroundStyle(ink)
            .sheet(isPresented: $showCoachTools) {
                ScrollView { VStack(spacing: 16) { CheckinInviteCardView(); ActiveFocusesCardView() }.padding(20) }
                    .preferredColorScheme(.light)
                    .presentationDetents([.medium, .large])
            }
    }

    // MARK: - Server Plan Update Card
    private var serverPlanUpdateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.stridePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your coach updated your plan")
                        .font(.interSemibold(15))
                    if let note = planSync.pendingServerPlan?.changeNote, !note.isEmpty {
                        Text(note)
                            .font(.interBody(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("A newer version of your plan is available")
                            .font(.interBody(13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation { planSync.applyPendingServerPlan(context: modelContext) }
                    // Runs pulled while the old plan was in place (e.g. a run
                    // the coach logged server-side) get matched to the new
                    // plan's sessions right away, not on the next cold launch.
                    Task { await RunPullService.shared.reconcile(context: modelContext) }
                } label: {
                    Text("Apply update")
                        .font(.interSemibold(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.stridePrimary)

                Button {
                    withAnimation { planSync.dismissPendingServerPlan() }
                } label: {
                    Text("Keep mine")
                        .font(.interSemibold(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.stridePrimary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.stridePrimary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Next Week Card
    private var nextWeekCard: some View {
        Button(action: {
            goToNextWeek()
        }) {
            HStack {
                Text("Go to Next Week")
                    .font(.inter(size: 16, weight: .semibold))
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.stridePrimary)
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    private func archivePlan() {
        plan.isArchived = true
        plan.archivedAt = Date()
        plan.archiveReason = .abandoned
        try? modelContext.save()
    }

    private func deletePlan() {
        // Run history lives in RunLog — safe to cascade-delete all plan/week/workout objects
        modelContext.delete(plan)
        try? modelContext.save()
    }
    
    private func goToNextWeek() {
        guard hasNextWeek else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let next = plan.sortedWeeks.first(where: { $0.weekNumber > selectedWeekNumber }) { selectedWeekNumber = next.weekNumber; selectedDate = nil }
        }
        Haptics.selection()
    }
    
    private func selectWorkout(_ workout: Workout) {
        selectedWorkout = workout
    }
    
    private func toggleWorkoutCompletion(_ workout: Workout) {
        guard !readOnly else { return }
        workout.toggleCompletion()

        if workout.isCompleted {
            PostHogSDK.shared.capture("workout_marked_complete", properties: [
                "workout_type": workout.workoutTypeRaw ?? "unknown",
            ])
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(workout.isCompleted ? .success : .warning)

        // Save changes
        try? modelContext.save()
    }
}

// MARK: - Today Anchor Key
struct TodayAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Week Scroll Tracking
struct WeekScrollData: Equatable {
    let weekNumber: Int
    let centerX: CGFloat
}

struct WeekScrollPreferenceKey: PreferenceKey {
    static var defaultValue: [WeekScrollData] = []
    
    static func reduce(value: inout [WeekScrollData], nextValue: () -> [WeekScrollData]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Week Pill View
/// Week pill colour language (Bryce, Sep 2026): the CURRENT week is always
/// the red bubble, wherever you've scrolled — tap it to get home. The week
/// you're viewing is the dark bubble; when that's the current week the red
/// bubble gets a dark ring.
struct WeekPillView: View {
    let weekNumber: Int
    let isSelected: Bool
    var isCurrentWeek: Bool = false
    let isRaceWeek: Bool
    
    // Ratio approximately 26:35 (w:h)
    private let pillWidth: CGFloat = 36
    private let pillHeight: CGFloat = 48
    
    var body: some View {
        Text("W\(weekNumber)")
            .font(.inter(size: 13, weight: (isSelected || isCurrentWeek) ? .bold : .medium))
            .foregroundColor(foregroundColor)
            .frame(width: pillWidth, height: pillHeight)
            .background(
                RoundedRectangle(cornerRadius: pillWidth / 2, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: pillWidth / 2, style: .continuous)
                    .stroke(Color.primary, lineWidth: (isSelected && isCurrentWeek) ? 2 : 0)
            )
    }
    
    private var foregroundColor: Color {
        if isCurrentWeek {
            return .white
        } else if isSelected {
            return Color(.systemBackground)
        } else if isRaceWeek {
            return .stridePrimary
        } else {
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        if isCurrentWeek {
            return .stridePrimary
        } else if isSelected {
            return .primary
        } else {
            return Color(.tertiarySystemBackground)
        }
    }
}

#Preview {
    NavigationStack {
        PlanView(plan: {
            let plan = TrainingPlan(
                raceType: .marathon,
                raceDate: Date().addingTimeInterval(86400 * 84),
                raceName: "Boston Marathon",
                goalTime: "3:30:00",
                currentWeeklyMileage: 50,
                longestRecentRun: 20,
                fitnessLevel: .intermediate,
                startDate: Date()
            )
            return plan
        }())
    }
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}


/// The current week returns to today; other weeks start at their first visible day.
enum PlanDayScrollTarget {
    static func date(in days: [Date], today: Date, calendar: Calendar = .current) -> Date? {
        days.first(where: { calendar.isDate($0, inSameDayAs: today) }) ?? days.min()
    }
}

// Shared with the floating tab bar so the texture continues to the screen edge.
struct PlanPageBackdrop: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                appearance.background
                Ellipse().fill(Color.stridePrimary.opacity(appearance == .white ? 0.055 : 0.12))
                    .frame(width: geometry.size.width * 0.9, height: 230).blur(radius: 65).offset(x: 100, y: -120)
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 0.0, to: size.width, by: 4) {
                        for y in stride(from: 0.0, to: size.height, by: 4) { dots.addEllipse(in: CGRect(x: x, y: y, width: 0.65, height: 0.65)) }
                    }
                    context.fill(dots, with: .color(appearance.foreground.opacity(appearance == .white ? 0.08 : 0.10)))
                    for index in 0..<10 {
                        let inset = CGFloat(index) * 12
                        let path = Path(ellipseIn: CGRect(x: size.width * 0.30 + inset, y: 115 + inset * 0.3, width: size.width * 0.8 - inset, height: 210 - inset * 0.4))
                        context.stroke(path, with: .color(appearance.foreground.opacity(0.025)), lineWidth: 0.5)
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Shared selection rules keep the lobby and calendar scoped to the right day.
enum TrainingSessionSelection {
    static func onDay(_ date: Date, workouts: [Workout], calendar: Calendar = .current) -> [Workout] {
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = calendar.dateComponents([.year, .month, .day], from: date)
        return workouts.filter {
            let scheduled = utc.dateComponents([.year, .month, .day], from: $0.date)
            return scheduled.year == selected.year && scheduled.month == selected.month && scheduled.day == selected.day
        }
    }
    static func isDayComplete(_ date: Date, workouts: [Workout], today: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = onDay(date, workouts: workouts, calendar: calendar)
        let active = day.filter { $0.workoutType != .rest }
        if !active.isEmpty { return active.allSatisfy(\.isCompleted) }
        return day.contains { $0.workoutType == .rest }
            && calendar.startOfDay(for: date) < calendar.startOfDay(for: today)
    }
    static func isRun(_ workout: Workout) -> Bool {
        ![WorkoutType.rest, .gym, .crossTraining, .mobility].contains(workout.workoutType)
    }
    static func lobby(workouts: [Workout], flexible: Bool, today: Date = Date(), calendar: Calendar = .current) -> [Workout] {
        workouts.filter { workout in
            guard workout.workoutType != .rest else { return false }
            let isToday = onDay(today, workouts: [workout], calendar: calendar).count == 1
            return flexible ? (isRun(workout) && !workout.isCompleted) || (isToday && !isRun(workout)) : isToday
        }.sorted {
            if isRun($0) != isRun($1) { return isRun($0) }
            return $0.date < $1.date
        }
    }
    static func preferred(in workouts: [Workout], selectedID: UUID?, fallbackID: UUID?) -> Workout? {
        workouts.first { $0.id == selectedID } ?? workouts.first { $0.id == fallbackID }
            ?? workouts.first { !$0.isCompleted } ?? workouts.first
    }
    static func adjacentWeek(current: Int, weeks: [Int], forward: Bool) -> Int? {
        let sorted = weeks.sorted()
        guard let index = sorted.firstIndex(of: current) else { return nil }
        let next = index + (forward ? 1 : -1)
        return sorted.indices.contains(next) ? sorted[next] : nil
    }
}

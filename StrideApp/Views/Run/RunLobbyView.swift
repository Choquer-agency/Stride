import SwiftUI
import SwiftData

struct RunLobbyView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Query(filter: #Predicate<TrainingPlan> { $0.isArchived == false }, sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]

    var onStartPlannedWorkout: (Workout) -> Void
    var onStartFreeRun: () -> Void

    // Blinking indicator animation
    @State private var indicatorVisible: Bool = true

    // MARK: - Computed Properties

    private var isConnected: Bool {
        bluetoothManager.connectedDevice != nil
    }

    private var isConnecting: Bool {
        !isConnected && (bluetoothManager.connectionState == "Connecting..."
            || bluetoothManager.connectionState.hasPrefix("Reconnecting")
            || bluetoothManager.isScanning)
    }

    /// Today's running workout from the active plan (excludes rest, gym, cross-training)
    private var todaysWorkout: Workout? {
        guard let plan = plans.first,
              let currentWeek = plan.currentWeek else { return nil }
        return currentWeek.sortedWorkouts.first { workout in
            workout.isToday
            && workout.workoutType != .rest
            && workout.workoutType != .gym
            && workout.workoutType != .crossTraining
        }
    }

    /// Formatted date string like "Sat Feb 7"
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Logo
                StrideLogoView(height: 40)
                    .padding(.top, 48)

                // Connection Status Row (floating, no card)
                connectionStatusRow
                    .padding(.top, 32)

                // Today's Workout Section
                if isConnected {
                    todaysWorkoutSection
                        .padding(.top, 75)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 100) // Space for tab bar
        }
        .background(Color(.systemBackground))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isConnected)
        .onAppear {
            startBlinkingAnimation()
        }
    }

    // MARK: - Connection Status Row

    private var connectionStatusRow: some View {
        HStack(spacing: 8) {
            // Treadmill icon
            TreadmillIconView(size: 20, color: .primary)

            // Device name
            Text("Assault Runner")
                .font(.inter(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: true, vertical: false)

            // Status text
            Text(connectionLabel)
                .font(.inter(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            // Blinking indicator dot
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .opacity(shouldBlink ? (indicatorVisible ? 1.0 : 0.3) : 1.0)
        }
        .fixedSize(horizontal: true, vertical: false) // Size to content, never truncate
    }

    // MARK: - Today's Workout Section

    private var todaysWorkoutSection: some View {
        VStack(spacing: 6) {
            // Section Header (centered, lighter color to match Figma)
            Text("Today's Workout.")
                .font(.inter(size: 20, weight: .medium))
                .foregroundColor(Color(.tertiaryLabel))

            Text(todayDateString)
                .font(.inter(size: 15, weight: .regular))
                .foregroundColor(Color(.quaternaryLabel))

            // Workout Cards
            VStack(spacing: 12) {
                if let workout = todaysWorkout {
                    plannedWorkoutCard(workout: workout)
                }

                freeRunButton
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Planned Workout Card

    private func plannedWorkoutCard(workout: Workout) -> some View {
        Button {
            onStartPlannedWorkout(workout)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    Image(systemName: workout.workoutType.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.stridePrimary)

                    Text(workout.workoutType.displayName)
                        .font(.inter(size: 13, weight: .semibold))
                        .foregroundColor(.stridePrimary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                // Workout title
                Text(workout.title)
                    .font(.inter(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                // Workout details row
                HStack(spacing: 16) {
                    if let distance = workout.distanceDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "ruler")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(distance)
                                .font(.inter(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let duration = workout.durationDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(duration)
                                .font(.inter(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let pace = workout.paceDescription {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(pace)
                                .font(.inter(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.strideCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.stridePrimary.opacity(0.3), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Free Run Button

    private var freeRunButton: some View {
        Button {
            onStartFreeRun()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .medium))

                Text("Free Run")
                    .font(.inter(size: 16, weight: .semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.strideBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private var connectionLabel: String {
        if isConnected {
            return "Connected"
        } else if isConnecting {
            return "Connecting"
        } else {
            return "Disconnected"
        }
    }

    private var indicatorColor: Color {
        isConnected ? .green : .red
    }

    /// Only blink when connecting (not when solidly connected or disconnected)
    private var shouldBlink: Bool {
        isConnecting
    }

    private func startBlinkingAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            indicatorVisible = false
        }
    }

}

#Preview {
    RunLobbyView(
        onStartPlannedWorkout: { _ in },
        onStartFreeRun: { }
    )
    .environmentObject(BluetoothManager())
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}

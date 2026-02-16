import SwiftUI
import SwiftData

struct ArchivedPlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TrainingPlan> { $0.isArchived == true },
        sort: \TrainingPlan.createdAt,
        order: .reverse
    ) private var archivedPlans: [TrainingPlan]

    var body: some View {
        Group {
            if archivedPlans.isEmpty {
                ContentUnavailableView(
                    "No Previous Plans",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Plans you archive or replace will appear here.")
                )
            } else {
                List {
                    ForEach(archivedPlans) { plan in
                        NavigationLink {
                            PlanView(plan: plan, readOnly: true)
                        } label: {
                            ArchivedPlanRow(plan: plan)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            modelContext.delete(archivedPlans[index])
                        }
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("Previous Plans")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Archived Plan Row
struct ArchivedPlanRow: View {
    let plan: TrainingPlan

    private var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let start = formatter.string(from: plan.startDate)
        let end = formatter.string(from: plan.raceDate)
        return "\(start) - \(end)"
    }

    private var reasonColor: Color {
        switch plan.archiveReason {
        case .completed: return .green
        case .replaced: return .blue
        case .abandoned: return .orange
        case .none: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.raceName ?? plan.displayDistance)
                .font(.inter(size: 16, weight: .semibold))

            Text(dateRangeString)
                .font(.inter(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let reason = plan.archiveReason {
                    Text(reason.displayName)
                        .font(.inter(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(reasonColor.opacity(0.12))
                        .foregroundStyle(reasonColor)
                        .clipShape(Capsule())
                }

                Text("\(plan.completedWorkouts)/\(plan.totalWorkouts) completed")
                    .font(.inter(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ArchivedPlansView()
    }
    .modelContainer(for: TrainingPlan.self, inMemory: true)
}

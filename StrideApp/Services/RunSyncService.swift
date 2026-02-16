import Foundation
import SwiftData
import os.log

private let syncLog = Logger(subsystem: "com.stride.app", category: "RunSync")

@MainActor
class RunSyncService {
    static let shared = RunSyncService()

    private var isSyncing = false
    private var modelContainer: ModelContainer?

    private var baseURL: String { APIConfiguration.serverURL }

    // MARK: - Setup

    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    // MARK: - Sync Pending Runs

    func syncPendingRuns() {
        guard !isSyncing else { return }
        guard AuthService.shared.currentToken != nil else { return }
        guard let container = modelContainer else {
            syncLog.warning("RunSyncService: No ModelContainer configured")
            return
        }

        isSyncing = true

        Task {
            defer { isSyncing = false }

            do {
                let context = ModelContext(container)
                let predicate = #Predicate<RunLog> { $0.syncedToServer == false }
                let descriptor = FetchDescriptor<RunLog>(predicate: predicate)
                let unsyncedRuns = try context.fetch(descriptor)

                guard !unsyncedRuns.isEmpty else {
                    syncLog.info("No unsynced runs to upload")
                    return
                }

                syncLog.info("Syncing \(unsyncedRuns.count) runs to server")

                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let payloads = unsyncedRuns.map { run in
                    RunSyncPayload(
                        id: run.id.uuidString,
                        completedAt: dateFormatter.string(from: run.completedAt),
                        distanceKm: run.distanceKm,
                        durationSeconds: run.durationSeconds,
                        avgPaceSecPerKm: run.avgPaceSecPerKm,
                        kmSplitsJson: run.kmSplitsJSON,
                        feedbackRating: run.feedbackRating,
                        notes: run.notes,
                        plannedWorkoutTitle: run.plannedWorkoutTitle,
                        plannedWorkoutType: run.plannedWorkoutTypeRaw,
                        plannedDistanceKm: run.plannedDistanceKm,
                        completionScore: run.completionScore,
                        planName: run.planName,
                        weekNumber: run.weekNumber,
                        dataSource: run.dataSource,
                        treadmillBrand: run.treadmillBrand,
                        shoeId: run.shoeId?.uuidString
                    )
                }

                let batchRequest = RunBatchSyncRequest(runs: payloads)
                let response = try await postSync(batchRequest)

                syncLog.info("Sync complete: \(response.syncedCount) synced, \(response.alreadyExisted) already existed")

                // Mark all as synced
                for run in unsyncedRuns {
                    run.syncedToServer = true
                }
                try context.save()

            } catch {
                syncLog.error("Run sync failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Network

    private func postSync(_ request: RunBatchSyncRequest) async throws -> RunBatchSyncResponse {
        let url = URL(string: "\(baseURL)/api/runs/sync")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthService.shared.currentToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RunSyncError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            AuthService.shared.signOut()
            throw RunSyncError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw RunSyncError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(RunBatchSyncResponse.self, from: data)
    }
}

// MARK: - Errors

enum RunSyncError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Authentication required"
        case .httpError(let code): return "Server error (\(code))"
        }
    }
}

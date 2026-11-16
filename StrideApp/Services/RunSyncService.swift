import Foundation
import SwiftData
import os.log

private let syncLog = Logger(subsystem: "com.stride.app", category: "RunSync")

@MainActor
class RunSyncService {
    static let shared = RunSyncService()

    private var isSyncing = false
    private var modelContainer: ModelContainer?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private let retryDelays: [Duration] = [.seconds(15), .seconds(60), .seconds(180)]

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
                let owner = AuthService.shared.currentUserID ?? "unknown"
                let backfillKey = "run_metrics_backfilled_ids_\(owner)"
                var backfilled = Set(UserDefaults.standard.stringArray(forKey: backfillKey) ?? [])
                let allRuns = try context.fetch(FetchDescriptor<RunLog>())
                let unsyncedRuns = allRuns.filter { run in
                    if run.originatedFromServer { return false }
                    if !run.syncedToServer { return true }
                    let hasRichData = run.routeJSON != nil || run.elevationGainMeters != nil
                        || run.elevationLossMeters != nil || run.speedSamplesJSON != nil
                        || run.inclineSamplesJSON != nil || run.cadenceSamplesJSON != nil
                        || run.powerSamplesJSON != nil || run.weatherJSON != nil
                    return hasRichData && !backfilled.contains(run.id.uuidString)
                }

                guard !unsyncedRuns.isEmpty else {
                    syncLog.info("No unsynced runs to upload")
                    clearRetry()
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
                        elevationGainM: run.elevationGainMeters,
                        elevationLossM: run.elevationLossMeters,
                        metricsJson: buildMetrics(for: run),
                        metricsBackfillOnly: run.syncedToServer,
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
                        shoeId: run.shoeId?.uuidString,
                        avgHeartRate: run.avgHeartRate,
                        maxHeartRate: run.maxHeartRate,
                        hrSamplesJson: run.hrSamplesJSON
                    )
                }

                let batchRequest = RunBatchSyncRequest(runs: payloads)
                let response = try await postSync(batchRequest)

                syncLog.info("Sync complete: \(response.syncedCount) synced, \(response.alreadyExisted) already existed")

                // Mark all as synced
                for run in unsyncedRuns {
                    run.syncedToServer = true
                    if response.metricsStored { backfilled.insert(run.id.uuidString) }
                }
                try context.save()
                if response.metricsStored {
                    UserDefaults.standard.set(Array(backfilled), forKey: backfillKey)
                }
                clearRetry()

            } catch {
                syncLog.error("Run sync failed: \(error.localizedDescription)")
                if shouldRetry(error) { scheduleRetry() }
            }
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let syncError = error as? RunSyncError {
            switch syncError {
            case .unauthorized: return false
            case .httpError(let status): return status == 429 || status >= 500
            case .invalidResponse: return true
            }
        }
        return error is URLError
    }

    private func scheduleRetry() {
        guard retryTask == nil, retryAttempt < retryDelays.count else { return }
        let delay = retryDelays[retryAttempt]
        retryAttempt += 1
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            self?.syncPendingRuns()
        }
    }

    private func clearRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
    }

    private func decodeJSON<T: Decodable>(_ raw: String?, as type: T.Type) -> T? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func buildMetrics(for run: RunLog) -> RunSyncMetrics {
        let route = decodeJSON(run.routeJSON, as: [RoutePoint].self)
        let speed = decodeJSON(run.speedSamplesJSON, as: [RunSpeedSample].self)
        let incline = decodeJSON(run.inclineSamplesJSON, as: [RunInclineSample].self)
        let treadmill: RunTreadmillMetrics? = run.dataSource == "bluetooth_ftms"
            ? RunTreadmillMetrics(device: run.treadmillBrand, speedSamples: speed, inclineSamples: incline)
            : nil
        let sortedSplits = run.decodedKmSplits.sorted { $0.kilometer < $1.kilometer }
        let enriched = sortedSplits.map { split -> RunMetricSplit in
            let end = RunHistoryMetrics.elapsedSeconds(split.time)
            let start: Double? = split.kilometer == 1 ? 0 : sortedSplits.first {
                $0.kilometer == split.kilometer - 1
            }.flatMap { RunHistoryMetrics.elapsedSeconds($0.time) }
            let segment: [RoutePoint] = {
                guard let route, let start, let end else { return [] }
                return route.filter { $0.timestamp >= start && $0.timestamp <= end }
            }()
            let pairs = zip(segment, segment.dropFirst())
            let gain = segment.count > 1 ? pairs.reduce(0.0) { $0 + max(0, $1.1.altitude - $1.0.altitude) } : nil
            let loss = segment.count > 1 ? zip(segment, segment.dropFirst()).reduce(0.0) {
                $0 + max(0, $1.0.altitude - $1.1.altitude)
            } : nil
            return RunMetricSplit(
                kilometer: split.kilometer, pace: split.pace, time: split.time,
                hr: RunHistoryMetrics.splitHeartRate(split, allSplits: sortedSplits, samples: run.decodedHRSamples),
                elevationGainM: gain, elevationLossM: loss, elevationM: segment.last?.altitude
            )
        }
        return RunSyncMetrics(
            routePoints: route,
            elevationProfile: route?.map { RunElevationSample(t: $0.timestamp, elevationM: $0.altitude) },
            treadmill: treadmill,
            splits: enriched.isEmpty ? nil : enriched,
            cadenceSamples: decodeJSON(run.cadenceSamplesJSON, as: [RunNumericSample].self),
            powerSamples: decodeJSON(run.powerSamplesJSON, as: [RunNumericSample].self),
            weather: run.weatherJSON.flatMap { raw in
                guard let data = raw.data(using: .utf8),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return AnyJSONDict(raw: value)
            },
            coachNotes: run.coachNotes,
            shoeName: run.shoeName,
            plannedWorkoutId: run.plannedWorkoutId?.uuidString,
            plannedDurationMinutes: run.plannedDurationMinutes,
            plannedPaceDescription: run.plannedPaceDescription
        )
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
            AuthService.shared.handleUnauthorized()
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

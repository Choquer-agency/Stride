import Foundation
import SwiftData

/// Pre-generates today's pre-run motivational intro in the background so that
/// tapping Start Run plays instantly.
///
/// Strategy: on each foreground/launch, look up today's planned workout from
/// SwiftData (if any) and prefetch an intro matching that specific workout.
/// If there's no planned workout for today, prefetch a generic free-run intro
/// instead. The cache is keyed by date + time-of-day + workout signature, so a
/// mismatched request at Start Run time (e.g. user picks free run even though
/// a planned workout was prefetched) falls through to a live fetch rather than
/// playing the wrong intro.
@MainActor
final class PreRunIntroPrefetcher {
    static let shared = PreRunIntroPrefetcher()

    private let cacheKey = "pre_run_intro_cache_v2"
    private var inFlight = false

    struct CachedIntro: Codable {
        let text: String
        let dateString: String       // yyyy-MM-dd in user's local tz
        let timeOfDay: String        // early morning / morning / afternoon / evening / night
        let signature: String        // PreRunCoachRequest.cacheSignature
        let generatedAt: Date
    }

    private init() {}

    // MARK: - Public API

    /// Fire-and-forget warm-up. Queries SwiftData for today's planned workout
    /// and prefetches an intro for it. If the user has NO planned workout
    /// scheduled today, this no-ops — for free runs we can't prefetch since
    /// the distance/duration is chosen interactively in the run lobby, so the
    /// user will wait for the live fetch the moment they hit Start.
    func warmUpIfNeeded(container: ModelContainer) {
        if inFlight {
            print("[PreRunPrefetch] Skipped — warm-up already in flight")
            return
        }
        guard let workout = todaysPlannedWorkout(container: container) else {
            print("[PreRunPrefetch] Skipped — no planned workout scheduled for today")
            return
        }
        print("[PreRunPrefetch] Warming up for today's workout: \(workout.title) (\(workout.workoutType.displayName))")
        inFlight = true
        Task { [weak self] in
            guard let self else { return }
            await self.fetchAndCache(container: container)
            self.inFlight = false
        }
    }

    /// Returns cached intro text only if it matches today's date, current
    /// time-of-day bucket, AND the workout signature of the provided request.
    /// Any mismatch → nil → caller should live-fetch.
    func cachedIntro(matching request: PreRunCoachRequest) -> String? {
        guard let cached = load() else { return nil }
        let today = Self.todayString()
        let bucket = Self.currentTimeOfDay()
        guard cached.dateString == today,
              cached.timeOfDay == bucket,
              cached.signature == request.cacheSignature else {
            return nil
        }
        return cached.text
    }

    // MARK: - Private

    private func fetchAndCache(container: ModelContainer) async {
        guard let request = buildRequest(container: container) else {
            print("[PreRunPrefetch] Planned workout disappeared between guard and build — aborting warm-up")
            return
        }

        // Skip if we already have a hit for this exact request.
        if let cached = load(),
           cached.dateString == Self.todayString(),
           cached.timeOfDay == request.timeOfDay,
           cached.signature == request.cacheSignature {
            print("[PreRunPrefetch] Already cached for today's context (\(cached.signature))")
            return
        }

        do {
            let text = try await APIService.shared.preRunCoach(request: request)
            let cached = CachedIntro(
                text: text,
                dateString: Self.todayString(),
                timeOfDay: request.timeOfDay ?? "",
                signature: request.cacheSignature,
                generatedAt: Date()
            )
            save(cached)
            print("[PreRunPrefetch] Cached intro for signature '\(request.cacheSignature)' (\(text.count) chars); pre-warming audio")
            await ElevenLabsTTSService.shared.prefetchText(text)
            print("[PreRunPrefetch] Audio pre-warm complete")
        } catch {
            print("[PreRunPrefetch] Warm-up failed: \(error)")
        }
    }

    private func buildRequest(container: ModelContainer) -> PreRunCoachRequest? {
        guard let workout = todaysPlannedWorkout(container: container) else { return nil }
        let athleteName: String? = {
            if case .signedIn(let user) = AuthService.shared.authState { return user.name }
            if case .needsProfile(let user) = AuthService.shared.authState { return user.name }
            return nil
        }()
        return PreRunCoachRequest(
            athleteName: athleteName,
            workoutType: workout.workoutType.displayName,
            workoutTitle: workout.title,
            targetDistanceKm: workout.distanceKm,
            targetDurationMinutes: workout.durationMinutes,
            targetPace: workout.paceDescription,
            isFreeRun: false,
            goalRace: nil,
            weeksToRace: nil,
            timeOfDay: Self.currentTimeOfDay()
        )
    }

    /// Fetch today's planned workout, if the user has an active plan with one
    /// scheduled for the current date. Mirrors RunLobbyView.todaysWorkout so
    /// the prefetch targets the same run the user is likely to tap.
    private func todaysPlannedWorkout(container: ModelContainer) -> Workout? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let plan = try? context.fetch(descriptor).first,
              let week = plan.currentWeek else {
            return nil
        }
        return week.sortedWorkouts.first { workout in
            workout.isToday
            && workout.workoutType != .rest
            && workout.workoutType != .gym
            && workout.workoutType != .crossTraining
        }
    }

    // MARK: - Persistence

    private func load() -> CachedIntro? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedIntro.self, from: data)
    }

    private func save(_ cached: CachedIntro) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Time helpers

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func currentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<9:   return "early morning"
        case 9..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default:      return "night"
        }
    }
}

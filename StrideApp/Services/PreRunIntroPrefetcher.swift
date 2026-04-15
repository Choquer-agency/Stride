import Foundation

/// Pre-generates today's pre-run motivational intro in the background so that
/// tapping Start Run plays instantly.
///
/// Strategy: on each foreground/launch, check whether we already have a cached
/// intro for today's date + time-of-day bucket. If not, call the API to get
/// Claude's text, then pre-warm the ElevenLabs audio cache for that exact text.
/// The cache is keyed generically (no workout-specific fields) so it covers the
/// most common case — a free run started from the lobby.
@MainActor
final class PreRunIntroPrefetcher {
    static let shared = PreRunIntroPrefetcher()

    private let cacheKey = "pre_run_intro_cache_v1"
    private var inFlight = false

    struct CachedIntro: Codable {
        let text: String
        let dateString: String       // yyyy-MM-dd in user's local tz
        let timeOfDay: String        // matches the bucket sent to the server
        let generatedAt: Date
    }

    private init() {}

    // MARK: - Public API

    /// Fire-and-forget warm-up. Safe to call repeatedly — no-ops if the cache
    /// already covers today's bucket, or if a warm-up is already in flight.
    func warmUpIfNeeded() {
        if inFlight { return }
        if cachedIntroForCurrentBucket() != nil {
            print("[PreRunPrefetch] Today's intro already cached")
            return
        }
        inFlight = true
        Task { [weak self] in
            guard let self else { return }
            await self.fetchAndCache()
            self.inFlight = false
        }
    }

    /// Returns the cached intro text if it still matches today's date + bucket,
    /// otherwise nil. The caller is expected to fall back to a live fetch.
    func cachedIntroForCurrentBucket() -> String? {
        guard let cached = load() else { return nil }
        if cached.dateString == Self.todayString() && cached.timeOfDay == Self.currentTimeOfDay() {
            return cached.text
        }
        return nil
    }

    // MARK: - Private

    private func fetchAndCache() async {
        let timeOfDay = Self.currentTimeOfDay()
        let athleteName: String? = {
            if case .signedIn(let user) = AuthService.shared.authState { return user.name }
            if case .needsProfile(let user) = AuthService.shared.authState { return user.name }
            return nil
        }()

        // Intentionally generic — free run, no workout specifics. The goal here
        // is to have SOMETHING cached for the common case, not to exactly match
        // every possible workout choice.
        let request = PreRunCoachRequest(
            athleteName: athleteName,
            workoutType: nil,
            workoutTitle: nil,
            targetDistanceKm: nil,
            targetDurationMinutes: nil,
            targetPace: nil,
            isFreeRun: true,
            goalRace: nil,
            weeksToRace: nil,
            timeOfDay: timeOfDay
        )

        do {
            let text = try await APIService.shared.preRunCoach(request: request)
            let cached = CachedIntro(
                text: text,
                dateString: Self.todayString(),
                timeOfDay: timeOfDay,
                generatedAt: Date()
            )
            save(cached)
            print("[PreRunPrefetch] Cached intro text (\(text.count) chars); pre-warming audio")

            // Pre-warm the ElevenLabs audio cache so the MP3 is on disk before
            // the user taps Start Run. This is the expensive leg time-wise.
            await ElevenLabsTTSService.shared.prefetchText(text)
            print("[PreRunPrefetch] Audio pre-warm complete")
        } catch {
            print("[PreRunPrefetch] Warm-up failed: \(error)")
        }
    }

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

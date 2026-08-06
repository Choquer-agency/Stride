import Foundation

// MARK: - API Configuration
enum APIConfiguration {
    static let serverURLKey = "stride_server_url"
    static let defaultDeviceURL = "https://stridecoach.app"
    static let simulatorURL = "http://localhost:8000"
    
    static var serverURL: String {
        get {
            return UserDefaults.standard.string(forKey: serverURLKey) ?? defaultDeviceURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: serverURLKey)
        }
    }
}

// MARK: - API Service
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    
    // Configure this to your FastAPI server URL
    private var baseURL: String {
        APIConfiguration.serverURL
    }
    
    @Published var isLoading = false
    @Published var streamingContent = ""
    @Published var error: String?
    
    init() {}
    
    // MARK: - Auth Header
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = AuthService.shared.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func checkForUnauthorized(_ response: URLResponse) {
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            AuthService.shared.signOut()
        }
    }

    // MARK: - Analyze Conflicts
    func analyzeConflicts(request: TrainingPlanRequest) async throws -> ConflictAnalysisResponse {
        let url = URL(string: "\(baseURL)/api/analyze-conflicts")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &urlRequest)

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw APIServiceError.serverError(apiError.detail)
            }
            throw APIServiceError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ConflictAnalysisResponse.self, from: data)
    }
    
    // MARK: - Generate Plan (Streaming)
    func generatePlan(
        request: TrainingPlanRequest,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/generate-plan")!

        var urlRequest = URLRequest(url: url)
        // Generous idle timeout — the coach thinks before the first token streams.
        urlRequest.timeoutInterval = 300
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &urlRequest)
        
        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
            
            isLoading = true
            streamingContent = ""
            error = nil
            
            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIServiceError.invalidResponse
            }
            
            var fullContent = ""
            
            for try await line in bytes.lines {
                // Parse SSE format: "data: {...}"
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if let data = jsonString.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                        
                        if let content = chunk.content {
                            fullContent += content
                            streamingContent = fullContent
                            onChunk(content)
                        }
                        
                        if chunk.done == true {
                            isLoading = false
                            onComplete(fullContent)
                            return
                        }
                        
                        if let errorMsg = chunk.error {
                            throw APIServiceError.serverError(errorMsg)
                        }
                    }
                }
            }
            
            // Stream ended without explicit done signal
            isLoading = false
            onComplete(fullContent)
            
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            onError(error)
        }
    }
    
    // MARK: - Edit Plan (Streaming)
    func editPlan(
        request: PlanEditRequest,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/edit-plan")!

        var urlRequest = URLRequest(url: url)
        // Generous idle timeout — the coach thinks before the first token streams.
        urlRequest.timeoutInterval = 300
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &urlRequest)

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)

            isLoading = true
            streamingContent = ""
            error = nil

            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIServiceError.invalidResponse
            }

            var fullContent = ""

            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))

                    if let data = jsonString.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {

                        if let content = chunk.content {
                            fullContent += content
                            streamingContent = fullContent
                            onChunk(content)
                        }

                        if chunk.done == true {
                            isLoading = false
                            onComplete(fullContent)
                            return
                        }

                        if let errorMsg = chunk.error {
                            throw APIServiceError.serverError(errorMsg)
                        }
                    }
                }
            }

            isLoading = false
            onComplete(fullContent)

        } catch {
            isLoading = false
            self.error = error.localizedDescription
            onError(error)
        }
    }

    // MARK: - Analyze Performance (Streaming)
    func analyzePerformance(
        request: PerformanceAnalysisRequest,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/analyze-performance")!

        var urlRequest = URLRequest(url: url)
        // Generous idle timeout — the coach thinks before the first token streams.
        urlRequest.timeoutInterval = 300
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &urlRequest)

        do {
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)

            isLoading = true
            streamingContent = ""
            error = nil

            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIServiceError.invalidResponse
            }

            var fullContent = ""

            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))

                    if let data = jsonString.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {

                        if let content = chunk.content {
                            fullContent += content
                            streamingContent = fullContent
                            onChunk(content)
                        }

                        if chunk.done == true {
                            isLoading = false
                            onComplete(fullContent)
                            return
                        }

                        if let errorMsg = chunk.error {
                            throw APIServiceError.serverError(errorMsg)
                        }
                    }
                }
            }

            isLoading = false
            onComplete(fullContent)

        } catch {
            isLoading = false
            self.error = error.localizedDescription
            onError(error)
        }
    }

    // MARK: - Pre-Run AI Coach

    /// Fetch a short motivational intro to play before the countdown.
    /// Short timeout so a slow/dead backend never blocks the run from starting —
    /// the caller should fall back to the bundled countdown on any throw.
    func preRunCoach(request: PreRunCoachRequest, timeout: TimeInterval = 6.0) async throws -> String {
        let url = URL(string: "\(baseURL)/api/pre-run-coach")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeout
        addAuthHeader(to: &urlRequest)
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let token = AuthService.shared.currentToken
        print("[PreRunCoach] JWT in keychain: \(token == nil ? "MISSING" : "present (len=\(token!.count))")")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[PreRunCoach] \(http.statusCode) from server. Body: \(body)")
        }
        // Intentionally do NOT call checkForUnauthorized here — the pre-run intro is
        // non-critical and a transient 401 shouldn't sign the user out of the app.
        guard http.statusCode == 200 else {
            throw APIServiceError.httpError(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(PreRunCoachResponse.self, from: data)
        return decoded.text
    }

    // MARK: - Post-Run AI Coach

    func postRunCoach(
        request: PostRunCoachRequest,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/post-run-coach")!

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &urlRequest)

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)

            isLoading = true
            streamingContent = ""
            error = nil

            let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse {
                    checkForUnauthorized(response)
                    throw APIServiceError.httpError(httpResponse.statusCode)
                }
                throw APIServiceError.invalidResponse
            }

            var fullContent = ""

            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))

                    if let data = jsonString.data(using: .utf8),
                       let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {

                        if let content = chunk.content {
                            fullContent += content
                            streamingContent = fullContent
                            onChunk(content)
                        }

                        if chunk.done == true {
                            isLoading = false
                            onComplete(fullContent)
                            return
                        }

                        if let errorMsg = chunk.error {
                            throw APIServiceError.serverError(errorMsg)
                        }
                    }
                }
            }

            isLoading = false
            onComplete(fullContent)

        } catch {
            isLoading = false
            self.error = error.localizedDescription
            onError(error)
        }
    }

    // MARK: - Build Analysis Request from TrainingPlan
    static func buildAnalysisRequest(from plan: TrainingPlan) -> PerformanceAnalysisRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Collect completed workouts with actual data
        let completedWorkouts: [CompletedWorkoutData] = plan.weeks
            .flatMap { $0.workouts }
            .filter { $0.isCompleted && $0.workoutType != .rest }
            .sorted { $0.date < $1.date }
            .map { workout in
                CompletedWorkoutData(
                    date: dateFormatter.string(from: workout.date),
                    workoutType: workout.workoutType.rawValue,
                    plannedDistanceKm: workout.distanceKm,
                    actualDistanceKm: workout.actualDistanceKm,
                    plannedPaceDescription: workout.paceDescription,
                    actualAvgPaceSecPerKm: workout.actualAvgPaceSecPerKm,
                    completionScore: workout.completionScore,
                    feedbackRating: workout.feedbackRating
                )
            }

        // Compute weeks into plan
        let daysSinceStart = Calendar.current.dateComponents([.day], from: plan.startDate, to: Date()).day ?? 0
        let weeksIntoPlan = max(1, daysSinceStart / 7 + 1)

        return PerformanceAnalysisRequest(
            raceType: plan.raceType.rawValue,
            raceDate: dateFormatter.string(from: plan.raceDate),
            startDate: dateFormatter.string(from: plan.startDate),
            goalTime: plan.goalTime,
            customDistanceKm: plan.customDistanceKm,
            currentWeeklyMileage: plan.currentWeeklyMileage,
            fitnessLevel: plan.fitnessLevel.rawValue,
            completedWorkouts: completedWorkouts,
            weeksIntoPlan: weeksIntoPlan,
            totalPlanWeeks: plan.totalWeeks,
            currentPlanContent: plan.rawPlanContent ?? ""
        )
    }

    // MARK: - Build Edit Request from TrainingPlan
    static func buildEditRequest(from plan: TrainingPlan, editInstructions: String) -> PlanEditRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return PlanEditRequest(
            raceType: plan.raceType.rawValue,
            raceDate: dateFormatter.string(from: plan.raceDate),
            raceName: plan.raceName,
            goalTime: plan.goalTime,
            customDistanceKm: plan.customDistanceKm,
            startDate: dateFormatter.string(from: plan.startDate),
            currentPlanContent: plan.rawPlanContent ?? "",
            editInstructions: editInstructions
        )
    }

    // MARK: - Build Request from Onboarding Data
    static func buildRequest(from data: OnboardingData) -> TrainingPlanRequest {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return TrainingPlanRequest(
            raceType: data.raceType.rawValue,
            raceDate: dateFormatter.string(from: data.raceDate),
            raceName: data.raceName.isEmpty ? nil : data.raceName,
            goalTime: data.goalTime.isEmpty ? nil : data.goalTime,
            customDistanceKm: data.raceType == .custom ? data.customDistanceKm : nil,
            terrainType: data.isUltraDistance ? data.terrainType?.rawValue : nil,
            elevationGainM: data.isUltraDistance ? data.elevationGainM : nil,
            currentWeeklyMileage: data.currentWeeklyMileage,
            longestRecentRun: data.longestRecentRun,
            recentRaceTimes: data.recentRaceTimes.isEmpty ? nil : data.recentRaceTimes,
            recentRuns: data.recentRuns.isEmpty ? nil : data.recentRuns,
            fitnessLevel: data.fitnessLevel.rawValue,
            startDate: dateFormatter.string(from: data.startDate),
            restDays: data.restDays.map { $0.rawValue },
            longRunDay: data.longRunDay.rawValue,
            doubleDaysAllowed: data.doubleDaysAllowed,
            crossTrainingDays: nil,
            runningDaysPerWeek: data.runningDaysPerWeek,
            gymDaysPerWeek: data.gymDaysPerWeek,
            yearsRunning: data.yearsRunning,
            previousInjuries: data.previousInjuries.isEmpty ? nil : data.previousInjuries,
            previousExperience: data.previousExperience.isEmpty ? nil : data.previousExperience,
            planMode: data.planMode?.rawValue,
            recommendedGoalTime: data.recommendedGoalTime
        )
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(type: LeaderboardType, filter: LeaderboardFilter, userAgeGroup: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> LeaderboardResponse {
        var components: URLComponents

        if type.isDistanceBased {
            components = URLComponents(string: "\(baseURL)/api/community/leaderboards/yearly-distance")!
        } else {
            components = URLComponents(string: "\(baseURL)/api/community/leaderboards/best-time")!
            components.queryItems = [URLQueryItem(name: "category", value: type.categoryParam)]
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))

        if let gender = filter.genderParam {
            queryItems.append(URLQueryItem(name: "gender", value: gender))
        }
        if filter.isAgeGroup, let ageGroup = userAgeGroup {
            queryItems.append(URLQueryItem(name: "age_group", value: ageGroup))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }

        return try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    }

    // MARK: - Achievements

    func fetchAchievementDefinitions() async throws -> [AchievementDefinition] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/achievements")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([AchievementDefinition].self, from: data)
    }

    func fetchMyAchievements() async throws -> [UserAchievement] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/achievements/mine")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([UserAchievement].self, from: data)
    }

    func fetchUnnotifiedAchievements() async throws -> [UserAchievement] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/achievements/unnotified")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([UserAchievement].self, from: data)
    }

    func markAchievementsNotified(ids: [String]) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/achievements/mark-notified")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body = AchievementMarkNotifiedRequest(achievementIds: ids)
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    func fetchStreak() async throws -> UserStreakResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/streak")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(UserStreakResponse.self, from: data)
    }

    // MARK: - Challenges

    func fetchChallenges(status: String = "active") async throws -> [ChallengeResponse] {
        var components = URLComponents(string: "\(baseURL)/api/community/challenges")!
        components.queryItems = [URLQueryItem(name: "status", value: status)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([ChallengeResponse].self, from: data)
    }

    func fetchChallengeDetail(id: String) async throws -> ChallengeDetailResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/challenges/\(id)")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ChallengeDetailResponse.self, from: data)
    }

    func joinChallenge(id: String) async throws -> JoinChallengeResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/challenges/\(id)/join")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(JoinChallengeResponse.self, from: data)
    }

    // MARK: - Events

    func fetchEvents(status: String = "active") async throws -> [EventResponse] {
        var components = URLComponents(string: "\(baseURL)/api/community/events")!
        components.queryItems = [URLQueryItem(name: "status", value: status)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([EventResponse].self, from: data)
    }

    func fetchEventDetail(id: String) async throws -> EventDetailResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/events/\(id)")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(EventDetailResponse.self, from: data)
    }

    func registerForEvent(id: String) async throws -> EventRegistrationApiResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/events/\(id)/register")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(EventRegistrationApiResponse.self, from: data)
    }

    func unregisterFromEvent(id: String) async throws -> [String: Bool] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/events/\(id)/register")!)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([String: Bool].self, from: data)
    }
    // MARK: - Social

    func searchUsers(query: String, limit: Int = 20) async throws -> [UserSearchResult] {
        var components = URLComponents(string: "\(baseURL)/api/community/users/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([UserSearchResult].self, from: data)
    }

    func fetchUserProfile(userId: String) async throws -> UserProfileResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/users/\(userId)")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(UserProfileResponse.self, from: data)
    }

    func followUser(userId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/users/\(userId)/follow")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    func unfollowUser(userId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/users/\(userId)/follow")!)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    func fetchFollowers(userId: String, limit: Int = 20, offset: Int = 0) async throws -> [UserSearchResult] {
        var components = URLComponents(string: "\(baseURL)/api/community/users/\(userId)/followers")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([UserSearchResult].self, from: data)
    }

    func fetchFollowing(userId: String, limit: Int = 20, offset: Int = 0) async throws -> [UserSearchResult] {
        var components = URLComponents(string: "\(baseURL)/api/community/users/\(userId)/following")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([UserSearchResult].self, from: data)
    }

    func fetchActivityFeed(followingOnly: Bool = true, limit: Int = 20, offset: Int = 0) async throws -> [ActivityFeedItem] {
        var components = URLComponents(string: "\(baseURL)/api/community/feed")!
        components.queryItems = [
            URLQueryItem(name: "following_only", value: followingOnly ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([ActivityFeedItem].self, from: data)
    }

    func createTeam(name: String, description: String?) async throws -> TeamResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/teams")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body = TeamCreateRequest(name: name, description: description)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(TeamResponse.self, from: data)
    }

    func joinTeam(inviteCode: String) async throws -> TeamResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/teams/join")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body = TeamJoinRequestBody(inviteCode: inviteCode)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(TeamResponse.self, from: data)
    }

    func fetchMyTeams() async throws -> [TeamResponse] {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/teams")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([TeamResponse].self, from: data)
    }

    func fetchTeamDetail(teamId: String) async throws -> TeamDetailResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/teams/\(teamId)")!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(TeamDetailResponse.self, from: data)
    }

    func leaveTeam(teamId: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/community/teams/\(teamId)/leave")!)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    // MARK: - Shoes

    func fetchShoes(includeRetired: Bool = false) async throws -> [ShoeResponse] {
        var components = URLComponents(string: "\(baseURL)/api/shoes")!
        if includeRetired {
            components.queryItems = [URLQueryItem(name: "include_retired", value: "true")]
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([ShoeResponse].self, from: data)
    }

    func createShoe(name: String, isDefault: Bool) async throws -> ShoeResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/shoes")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body = ShoeCreateRequest(name: name, isDefault: isDefault)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ShoeResponse.self, from: data)
    }

    func updateShoe(id: String, name: String? = nil, isDefault: Bool? = nil, isRetired: Bool? = nil) async throws -> ShoeResponse {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/shoes/\(id)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let body = ShoeUpdateRequest(name: name, isDefault: isDefault, isRetired: isRetired)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ShoeResponse.self, from: data)
    }

    func deleteShoe(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/shoes/\(id)")!)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    func uploadShoePhoto(id: String, imageData: Data) async throws -> ShoeResponse {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/api/shoes/\(id)/photo")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"shoe.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ShoeResponse.self, from: data)
    }

    // MARK: - v2 Coaching: Devices, Feedback, Inbox, Pause/Resume

    /// Register the iOS APNs device token with the backend.
    /// Called by PushNotificationManager.didRegister(deviceToken:).
    func registerDeviceToken(hex: String, platform: String = "ios") async throws {
        let url = URL(string: "\(baseURL)/api/devices/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let payload: [String: String] = ["token": hex, "platform": platform]
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    /// Submit 👍 / 👎 / 🙏 feedback for a coaching event.
    /// Used by CoachFeedbackRow during the first-3-events trust-building UX.
    func submitCoachingFeedback(eventId: UUID, feedback: String, note: String? = nil) async throws {
        let url = URL(string: "\(baseURL)/api/coach/feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = [
            "event_id": eventId.uuidString.lowercased(),
            "feedback": feedback,
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    /// Fetch recent coaching events for the inbox.
    func fetchCoachingInbox(limit: Int = 20, before: Date? = nil) async throws -> [CoachingInboxItem] {
        var components = URLComponents(string: "\(baseURL)/api/coach/inbox")!
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let before = before {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            items.append(URLQueryItem(name: "before", value: iso.string(from: before)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(CoachingInboxResponse.self, from: data)
        return envelope.items
    }

    /// Pause the coach for a duration (in days) or until manual resume.
    func pauseCoach(durationDays: Int? = nil, untilResume: Bool = false) async throws {
        let url = URL(string: "\(baseURL)/api/coach/pause")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = [:]
        if let d = durationDays { payload["duration_days"] = d }
        if untilResume { payload["until_resume"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    /// Resume the coach (clears pause state).
    func resumeCoach() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/coach/resume")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    // MARK: - v2 Phase 1: Garmin

    /// Build the URL the user opens to start Garmin OAuth. Includes the JWT as a
    /// query param so the GET endpoint (which expects a Bearer header) can authenticate
    /// the redirect-style flow. SFSafariViewController doesn't carry our auth headers.
    func garminConnectURL() -> URL? {
        guard let token = AuthService.shared.currentToken else { return nil }
        // Pass the token via Authorization header isn't possible for browser redirects,
        // so we use a query-param shaped URL the backend accepts via a thin shim.
        // For now, we just route the user to /api/garmin/connect — the iOS SFSafariView
        // will hit the protected endpoint, get a 401, and the user must already have a
        // valid auth cookie/session. (Phase 1.1 follow-up: short-lived bearer-in-query.)
        var components = URLComponents(string: "\(baseURL)/api/garmin/connect")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    func garminStatus() async throws -> GarminStatusDTO {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/garmin/status")!)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GarminStatusDTO.self, from: data)
    }

    func garminRefresh() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/garmin/refresh")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    func garminDisconnect() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/garmin/disconnect")!)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    // MARK: - v2 Phase 2: Weekly Review

    /// Manually trigger a weekly review (admin/debug). Returns the new event_id, or
    /// nil if the pipeline skipped (no plan, recent post-race, etc.).
    func runWeeklyReview(forceFlag: Bool = false, weekOffset: Int = 0) async throws -> UUID? {
        let url = URL(string: "\(baseURL)/api/coach/run-weekly-review")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = [:]
        if forceFlag { payload["force"] = true }
        if weekOffset != 0 { payload["week_offset"] = weekOffset }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(RunWeeklyReviewResponseDTO.self, from: data)
        return envelope.eventId
    }

    /// SSE stream of a weekly review's text. The backend either replays a saved
    /// `llm_output` (typical case after cron) or — once Phase 2.1 wires live
    /// streaming — pipes from the LLM directly.
    func getOrStreamReview(
        eventId: UUID,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/coach/get-or-stream-review/\(eventId.uuidString.lowercased())")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse, http.statusCode == 425 {
                    throw APIServiceError.serverError("Review still generating — try again in a moment.")
                }
                throw APIServiceError.invalidResponse
            }
            var fullContent = ""
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                guard let data = jsonString.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else { continue }
                if let content = chunk.content {
                    fullContent += content
                    onChunk(content)
                }
                if chunk.done == true {
                    onComplete(fullContent)
                    return
                }
                if let errorMsg = chunk.error {
                    throw APIServiceError.serverError(errorMsg)
                }
            }
            onComplete(fullContent)
        } catch {
            onError(error)
        }
    }

    /// Mark a coaching event as read (clears unread badge in inbox).
    func markCoachingEventRead(eventId: UUID) async throws {
        let url = URL(string: "\(baseURL)/api/coach/event/\(eventId.uuidString.lowercased())/mark-read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)
        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
    }

    // MARK: - v2 Phase 3: Plan adjustments + post-run check

    /// List pending plan adjustments for the current user, sorted by expires_at asc.
    func pendingAdjustments() async throws -> [PlanAdjustmentDTO] {
        let url = URL(string: "\(baseURL)/api/coach/plan/pending-adjustments")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(PendingAdjustmentsResponseDTO.self, from: data)
        return envelope.items
    }

    /// Mark a plan adjustment as accepted server-side. iOS has already applied
    /// the diff to its local SwiftData TrainingPlan before calling this.
    func acceptAdjustment(id: UUID, appliedDiffActual: [String: Any]? = nil) async throws {
        let url = URL(string: "\(baseURL)/api/coach/plan/accept-adjustment")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = ["adjustment_id": id.uuidString.lowercased()]
        if let actual = appliedDiffActual {
            payload["applied_diff_actual"] = actual
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    /// Reject a plan adjustment with optional reason. Triggers 72h cool-down
    /// for the flag types that produced the proposal.
    func rejectAdjustment(id: UUID, reason: String? = nil) async throws {
        let url = URL(string: "\(baseURL)/api/coach/plan/reject-adjustment")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = ["adjustment_id": id.uuidString.lowercased()]
        if let r = reason, !r.isEmpty { payload["reason"] = r }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
    }

    // MARK: - v2 Phase 4: Wellness check-ins

    /// Submit a wellness check-in. Backend fires concern-check pipeline if applicable.
    func submitWellnessCheckin(
        entryMethod: String,
        sleepQuality: Int? = nil,
        soreness: Int? = nil,
        motivation: Int? = nil,
        stress: Int? = nil,
        energy: Int? = nil,
        sorenessAreas: [String]? = nil,
        notes: String? = nil
    ) async throws -> WellnessCheckinResponseDTO {
        let url = URL(string: "\(baseURL)/api/wellness/checkin")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = ["entry_method": entryMethod]
        if let v = sleepQuality { payload["sleep_quality"] = v }
        if let v = soreness { payload["soreness"] = v }
        if let v = motivation { payload["motivation"] = v }
        if let v = stress { payload["stress"] = v }
        if let v = energy { payload["energy"] = v }
        if let v = sorenessAreas, !v.isEmpty { payload["soreness_areas"] = v }
        if let v = notes, !v.isEmpty { payload["notes"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WellnessCheckinResponseDTO.self, from: data)
    }

    /// Today's morning entry (if any) + pre/post-run entries. iOS reads this on
    /// Run tab open to decide whether to show the morning card or pre-run check.
    func getWellnessToday() async throws -> WellnessTodayDTO {
        let url = URL(string: "\(baseURL)/api/wellness/today")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WellnessTodayDTO.self, from: data)
    }

    /// Rolling 7/28/90 day trend aggregate.
    func getWellnessTrends(window: Int = 7) async throws -> WellnessTrendsDTO {
        let url = URL(string: "\(baseURL)/api/wellness/trends?window=\(window)")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(WellnessTrendsDTO.self, from: data)
    }

    // MARK: - v2 Phase 5: Coach chat

    /// SSE-stream a chat message. Emits text chunks via `onChunk`. The trailing
    /// payload includes `coach_message_id` and (when present) `related_adjustment_id`
    /// via `onMeta`. `onComplete` fires with the full assembled text.
    func coachChat(
        message: String,
        trainingPlanId: UUID? = nil,
        relatedEventId: UUID? = nil,
        onChunk: @escaping (String) -> Void,
        onMeta: @escaping ([String: String]) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        let url = URL(string: "\(baseURL)/api/coach/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = ["message": message]
        if let p = trainingPlanId { payload["training_plan_id"] = p.uuidString.lowercased() }
        if let e = relatedEventId { payload["related_event_id"] = e.uuidString.lowercased() }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                    throw APIServiceError.serverError("Slow down — wait between messages or hit daily cap.")
                }
                throw APIServiceError.invalidResponse
            }

            var fullContent = ""
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                guard let data = jsonString.data(using: .utf8) else { continue }

                if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                    if let content = chunk.content {
                        fullContent += content
                        onChunk(content)
                    }
                    if chunk.done == true {
                        onComplete(fullContent)
                        return
                    }
                    if let errorMsg = chunk.error {
                        throw APIServiceError.serverError(errorMsg)
                    }
                }

                // Trailing meta payload
                if let envelope = try? JSONDecoder().decode(ChatStreamMetaEnvelope.self, from: data) {
                    onMeta(envelope.meta.mapValues { $0 })
                }
            }
            onComplete(fullContent)
        } catch {
            onError(error)
        }
    }

    /// Paginated chat history for the inbox / chat thread.
    func coachChatHistory(
        trainingPlanId: UUID? = nil,
        limit: Int = 50,
        before: Date? = nil
    ) async throws -> CoachChatHistoryDTO {
        var components = URLComponents(string: "\(baseURL)/api/coach/chat/history")!
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let p = trainingPlanId { items.append(URLQueryItem(name: "training_plan_id", value: p.uuidString.lowercased())) }
        if let b = before {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            items.append(URLQueryItem(name: "before", value: iso.string(from: b)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CoachChatHistoryDTO.self, from: data)
    }

    /// Dynamic suggested-prompt chips for the chat empty/idle state.
    func coachChatSuggestions() async throws -> [String] {
        let url = URL(string: "\(baseURL)/api/coach/chat/suggestions")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct R: Decodable { let items: [String] }
        return try JSONDecoder().decode(R.self, from: data).items
    }

    /// Recent entries for Stats history list.
    func getWellnessHistory(limit: Int = 30) async throws -> [WellnessEntryDTO] {
        let url = URL(string: "\(baseURL)/api/wellness/history?limit=\(limit)")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct H: Decodable { let items: [WellnessEntryDTO] }
        return try decoder.decode(H.self, from: data).items
    }

    /// Manually trigger the post-run check for a Garmin workout. Returns the new
    /// coaching_event id, or nil if the pipeline produced no event.
    func runPostRunCheckAdmin(workoutId: UUID, raceEventId: UUID? = nil, force: Bool = false) async throws -> UUID? {
        let url = URL(string: "\(baseURL)/api/coach/run-post-run-check")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var payload: [String: Any] = ["workout_id": workoutId.uuidString.lowercased(), "force": force]
        if let race = raceEventId {
            payload["race_event_id"] = race.uuidString.lowercased()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct R: Decodable { let event_id: UUID? }
        return try JSONDecoder().decode(R.self, from: data).event_id
    }

    // MARK: - v2 Phase 6: Nutrition

    func parseMealPhoto(imageData: Data, mealType: String? = nil, upload: Bool = true) async throws -> ParsedMealDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/parse-photo")!
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"meal.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        if let m = mealType {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"meal_type\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(m)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"upload\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(upload)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ParsedMealDTO.self, from: data)
    }

    func parseMealText(description: String, mealType: String? = nil) async throws -> ParsedMealDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/parse-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = ["description": description]
        if let m = mealType { payload["meal_type"] = m }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(ParsedMealDTO.self, from: data)
    }

    func logMeal(
        mealType: String,
        entryMethod: String,
        parsedItems: [[String: Any]],
        totals: (calories: Int?, carbs: Double?, protein: Double?, fat: Double?, fiber: Double?),
        photoUrl: String? = nil,
        rawDescription: String? = nil,
        confidence: Double? = nil,
        editedAfterParse: Bool = false
    ) async throws -> LogMealResponseDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/log")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = [
            "meal_type": mealType,
            "entry_method": entryMethod,
            "parsed_items": parsedItems,
            "edited_after_parse": editedAfterParse,
        ]
        if let v = totals.calories { payload["total_calories"] = v }
        if let v = totals.carbs { payload["total_carbs_g"] = v }
        if let v = totals.protein { payload["total_protein_g"] = v }
        if let v = totals.fat { payload["total_fat_g"] = v }
        if let v = totals.fiber { payload["total_fiber_g"] = v }
        if let v = photoUrl { payload["photo_url"] = v }
        if let v = rawDescription { payload["raw_description"] = v }
        if let v = confidence { payload["confidence"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LogMealResponseDTO.self, from: data)
    }

    func getNutritionToday() async throws -> NutritionTodayDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/today")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(NutritionTodayDTO.self, from: data)
    }

    func addHydration(glasses: Int = 1, electrolyteServings: Int = 0) async throws -> HydrationDTO {
        let url = URL(string: "\(baseURL)/api/hydration/add")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "glasses": glasses,
            "electrolyte_servings": electrolyteServings,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(HydrationDTO.self, from: data)
    }

    func getNutritionTemplates() async throws -> [TemplateDTO] {
        let url = URL(string: "\(baseURL)/api/nutrition/templates")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct E: Decodable { let items: [TemplateDTO] }
        return try JSONDecoder().decode(E.self, from: data).items
    }

    func logFromTemplate(templateId: UUID, mealType: String) async throws -> LogMealResponseDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/log-template")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "template_id": templateId.uuidString.lowercased(),
            "meal_type": mealType,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LogMealResponseDTO.self, from: data)
    }

    func getRaceFuelingPlan(eventId: UUID) async throws -> RaceFuelingPlanDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/race-fueling-plan/\(eventId.uuidString.lowercased())")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceFuelingPlanDTO.self, from: data)
    }

    func regenerateRaceFuelingPlan(eventId: UUID) async throws -> RaceFuelingPlanDTO {
        let url = URL(string: "\(baseURL)/api/nutrition/race-fueling-plan/\(eventId.uuidString.lowercased())/regenerate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceFuelingPlanDTO.self, from: data)
    }

    // MARK: - v2 Phase 8: Race-prep logistics checklist

    func getRaceLogisticsChecklist(eventId: UUID) async throws -> RaceLogisticsChecklistDTO {
        let url = URL(string: "\(baseURL)/api/race-prep/checklist/\(eventId.uuidString.lowercased())")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceLogisticsChecklistDTO.self, from: data)
    }

    func regenerateRaceLogisticsChecklist(eventId: UUID) async throws -> RaceLogisticsChecklistDTO {
        let url = URL(string: "\(baseURL)/api/race-prep/checklist/\(eventId.uuidString.lowercased())/regenerate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceLogisticsChecklistDTO.self, from: data)
    }

    func toggleRaceLogisticsItem(
        eventId: UUID,
        itemIndex: Int,
        completed: Bool,
        athleteNote: String? = nil
    ) async throws -> RaceLogisticsChecklistDTO {
        let url = URL(string: "\(baseURL)/api/race-prep/checklist/\(eventId.uuidString.lowercased())/item/\(itemIndex)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = ["completed": completed]
        if let note = athleteNote { payload["athlete_note"] = note }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceLogisticsChecklistDTO.self, from: data)
    }

    func updateRaceGoals(
        eventId: UUID,
        aGoalSeconds: Int? = nil,
        bGoalSeconds: Int? = nil,
        cGoalSeconds: Int? = nil
    ) async throws -> RaceLogisticsChecklistDTO {
        let url = URL(string: "\(baseURL)/api/race-prep/goals/\(eventId.uuidString.lowercased())")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = [:]
        if let v = aGoalSeconds { payload["a_goal_seconds"] = v }
        if let v = bGoalSeconds { payload["b_goal_seconds"] = v }
        if let v = cGoalSeconds { payload["c_goal_seconds"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RaceLogisticsChecklistDTO.self, from: data)
    }

    // MARK: - v2 Phase 9: Strength logging

    func getStrengthLibrary(category: String? = nil) async throws -> [StrengthExerciseDTO] {
        var components = URLComponents(string: "\(baseURL)/api/strength/library")!
        if let cat = category {
            components.queryItems = [URLQueryItem(name: "category", value: cat)]
        }
        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct E: Decodable { let items: [StrengthExerciseDTO] }
        return try JSONDecoder().decode(E.self, from: data).items
    }

    func logQuickStrengthSession(date: Date? = nil, perceivedEffort: Int? = nil) async throws -> StrengthSessionDTO {
        let url = URL(string: "\(baseURL)/api/strength/log-quick")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = [:]
        if let d = date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            payload["date"] = f.string(from: d)
        }
        if let e = perceivedEffort { payload["perceived_effort"] = e }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(StrengthSessionDTO.self, from: data)
    }

    func logDetailedStrengthSession(
        sets: [[String: Any]],
        date: Date? = nil,
        durationMinutes: Int? = nil,
        notes: String? = nil
    ) async throws -> StrengthSessionDTO {
        let url = URL(string: "\(baseURL)/api/strength/log-detailed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        var payload: [String: Any] = ["sets": sets]
        if let d = date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            payload["date"] = f.string(from: d)
        }
        if let dur = durationMinutes { payload["duration_minutes"] = dur }
        if let n = notes { payload["notes"] = n }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(StrengthSessionDTO.self, from: data)
    }

    func getStrengthProgression(exerciseId: UUID, limit: Int = 10) async throws -> [StrengthProgressionPointDTO] {
        var components = URLComponents(string: "\(baseURL)/api/strength/progression")!
        components.queryItems = [
            URLQueryItem(name: "exercise_id", value: exerciseId.uuidString.lowercased()),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct E: Decodable { let items: [StrengthProgressionPointDTO] }
        return try JSONDecoder().decode(E.self, from: data).items
    }

    func getStrengthSessions(days: Int = 30) async throws -> [StrengthSessionListItemDTO] {
        var components = URLComponents(string: "\(baseURL)/api/strength/sessions")!
        components.queryItems = [URLQueryItem(name: "days", value: String(days))]
        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        struct E: Decodable { let items: [StrengthSessionListItemDTO] }
        return try JSONDecoder().decode(E.self, from: data).items
    }

    func getLastSet(exerciseId: UUID) async throws -> LastSetDTO? {
        var components = URLComponents(string: "\(baseURL)/api/strength/last-set")!
        components.queryItems = [URLQueryItem(name: "exercise_id", value: exerciseId.uuidString.lowercased())]
        var request = URLRequest(url: components.url!)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        if data.isEmpty || (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces) == "null" {
            return nil
        }
        return try? JSONDecoder().decode(LastSetDTO.self, from: data)
    }
}

// MARK: - v2 Phase 9 Strength DTOs

struct StrengthExerciseDTO: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: String
    let equipment: String
    let youtubeDemoUrl: String?
    let defaultSetCount: Int
    let defaultRepRange: String

    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment
        case youtubeDemoUrl = "youtube_demo_url"
        case defaultSetCount = "default_set_count"
        case defaultRepRange = "default_rep_range"
    }
}

struct StrengthSessionDTO: Codable {
    let id: UUID
    let date: String
    let quickLogged: Bool

    enum CodingKeys: String, CodingKey {
        case id, date
        case quickLogged = "quick_logged"
    }
}

struct StrengthSessionListItemDTO: Codable, Identifiable {
    let id: String
    let date: String
    let quickLogged: Bool
    let perceivedEffort: Int?
    let durationMinutes: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, date, notes
        case quickLogged = "quick_logged"
        case perceivedEffort = "perceived_effort"
        case durationMinutes = "duration_minutes"
    }
}

struct StrengthProgressionPointDTO: Codable {
    let date: String?
    let reps: Int
    let weightKg: Double?
    let rpe: Int?

    enum CodingKeys: String, CodingKey {
        case date, reps, rpe
        case weightKg = "weight_kg"
    }
}

struct LastSetDTO: Codable {
    let reps: Int
    let weightKg: Double?
    let rpe: Int?

    enum CodingKeys: String, CodingKey {
        case reps, rpe
        case weightKg = "weight_kg"
    }
}

// MARK: - v2 Phase 8 Race-prep DTOs

struct RaceLogisticsChecklistDTO: Codable {
    let id: UUID
    let eventId: UUID
    let generatedAt: Date
    let items: [RaceLogisticsItemDTO]
    let weatherForecast: AnyJSONDict?
    let courseIntel: AnyJSONDict?
    let aGoalSeconds: Int?
    let bGoalSeconds: Int?
    let cGoalSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case generatedAt = "generated_at"
        case items
        case weatherForecast = "weather_forecast"
        case courseIntel = "course_intel"
        case aGoalSeconds = "a_goal_seconds"
        case bGoalSeconds = "b_goal_seconds"
        case cGoalSeconds = "c_goal_seconds"
    }
}

struct RaceLogisticsItemDTO: Codable, Identifiable {
    let label: String
    let detail: String?
    let category: String?
    let completed: Bool
    let athleteNote: String?

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, detail, category, completed
        case athleteNote = "athlete_note"
    }
}

// MARK: - v2 Phase 3 Plan Adjustment DTOs

/// Mirror of backend PlanAdjustment for iOS consumption.
struct PlanAdjustmentDTO: Codable, Identifiable {
    let id: UUID
    let proposedAt: Date
    let expiresAt: Date
    let status: String
    let summaryText: String
    let structuredDiff: AnyJSONDict
    let affectedWorkoutIds: [UUID]?
    let triggerEventId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case proposedAt = "proposed_at"
        case expiresAt = "expires_at"
        case status
        case summaryText = "summary_text"
        case structuredDiff = "structured_diff"
        case affectedWorkoutIds = "affected_workout_ids"
        case triggerEventId = "trigger_event_id"
    }
}

private struct PendingAdjustmentsResponseDTO: Decodable {
    let items: [PlanAdjustmentDTO]
}

/// Loose JSON dict — `structured_diff` shape is LLM-defined and varies.
/// AdjustmentReviewSheet inspects known keys ("workouts" array of from/to swaps)
/// and falls back to a raw display for unknown shapes.
struct AnyJSONDict: Codable {
    let raw: [String: Any]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyJSONValue].self) {
            self.raw = dict.mapValues { $0.unwrapped }
        } else {
            self.raw = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let wrapped = raw.mapValues { AnyJSONValue.wrap($0) }
        try container.encode(wrapped)
    }

    /// Convenience: decode the v2 standard `workouts` shape.
    /// Each entry has `date: String`, `from: dict?`, `to: dict?`.
    var workoutEdits: [WorkoutEdit] {
        guard let arr = raw["workouts"] as? [Any] else { return [] }
        return arr.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            let date = dict["date"] as? String ?? ""
            let from = (dict["from"] as? [String: Any]).map(WorkoutSnapshot.init(dict:))
            let to = (dict["to"] as? [String: Any]).map(WorkoutSnapshot.init(dict:))
            return WorkoutEdit(date: date, from: from, to: to)
        }
    }
}

struct WorkoutEdit: Identifiable {
    let date: String
    let from: WorkoutSnapshot?
    let to: WorkoutSnapshot?
    var id: String { date }
}

struct WorkoutSnapshot {
    let title: String?
    let type: String?
    let distanceKm: Double?
    let pace: String?

    init(dict: [String: Any]) {
        self.title = dict["title"] as? String
        self.type = dict["type"] as? String
        self.distanceKm = (dict["distance_km"] as? Double) ?? (dict["distance_km"] as? Int).map(Double.init)
        self.pace = dict["pace"] as? String
    }
}

/// Internal shim for round-tripping arbitrary JSON values through Codable.
struct AnyJSONValue: Codable {
    let unwrapped: Any

    private init(_ value: Any) { self.unwrapped = value }

    /// Static factory to avoid init-label ambiguity with Codable's `init(from:)`.
    static func wrap(_ value: Any) -> AnyJSONValue { AnyJSONValue(value) }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.unwrapped = NSNull() }
        else if let v = try? c.decode(Bool.self) { self.unwrapped = v }
        else if let v = try? c.decode(Int.self) { self.unwrapped = v }
        else if let v = try? c.decode(Double.self) { self.unwrapped = v }
        else if let v = try? c.decode(String.self) { self.unwrapped = v }
        else if let v = try? c.decode([AnyJSONValue].self) { self.unwrapped = v.map { $0.unwrapped } }
        else if let v = try? c.decode([String: AnyJSONValue].self) { self.unwrapped = v.mapValues { $0.unwrapped } }
        else { self.unwrapped = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch unwrapped {
        case is NSNull: try c.encodeNil()
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]:
            let mapped = v.map { AnyJSONValue.wrap($0) }
            try c.encode(mapped)
        case let v as [String: Any]:
            let mapped = v.mapValues { AnyJSONValue.wrap($0) }
            try c.encode(mapped)
        default: try c.encodeNil()
        }
    }
}

// MARK: - v2 Phase 2 DTOs

private struct RunWeeklyReviewResponseDTO: Decodable {
    let eventId: UUID?
    let skipped: Bool
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case skipped
    }
}

// MARK: - v2 Phase 4 Wellness DTOs

struct WellnessCheckinResponseDTO: Codable {
    let id: UUID
    let entryMethod: String
    let date: String
    let isConcerning: Bool
    let isSerious: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case entryMethod = "entry_method"
        case date
        case isConcerning = "is_concerning"
        case isSerious = "is_serious"
    }
}

struct WellnessEntryDTO: Codable, Identifiable {
    let id: UUID
    let entryMethod: String
    let sleepQuality: Int?
    let soreness: Int?
    let motivation: Int?
    let stress: Int?
    let energy: Int?
    let sorenessAreas: [String]
    let notes: String?
    let submittedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case entryMethod = "entry_method"
        case sleepQuality = "sleep_quality"
        case soreness, motivation, stress, energy
        case sorenessAreas = "soreness_areas"
        case notes
        case submittedAt = "submitted_at"
    }
}

struct WellnessTodayDTO: Codable {
    let morning: WellnessEntryDTO?
    let preRun: [WellnessEntryDTO]
    let postRun: [WellnessEntryDTO]
    let needsMorning: Bool
    let needsPreRun: Bool

    enum CodingKeys: String, CodingKey {
        case morning
        case preRun = "pre_run"
        case postRun = "post_run"
        case needsMorning = "needs_morning"
        case needsPreRun = "needs_pre_run"
    }
}

struct WellnessTrendsDTO: Codable {
    let windowDays: Int
    let current: WellnessAggregateDTO
    let prior: WellnessAggregateDTO
    let deltas: [String: Double]
    let frequentSorenessAreas: [WellnessAreaCount]
    let anyPainKeywordDays: Int

    enum CodingKeys: String, CodingKey {
        case windowDays = "window_days"
        case current, prior, deltas
        case frequentSorenessAreas = "frequent_soreness_areas"
        case anyPainKeywordDays = "any_pain_keyword_days"
    }
}

struct WellnessAggregateDTO: Codable {
    let n: Int
    let sleepQualityAvg: Double?
    let sorenessAvg: Double?
    let motivationAvg: Double?
    let stressAvg: Double?
    let frequentSorenessAreas: [WellnessAreaCount]
    let anyPainKeywordDays: Int
    let notesConcatenated: String?

    enum CodingKeys: String, CodingKey {
        case n
        case sleepQualityAvg = "sleep_quality_avg"
        case sorenessAvg = "soreness_avg"
        case motivationAvg = "motivation_avg"
        case stressAvg = "stress_avg"
        case frequentSorenessAreas = "frequent_soreness_areas"
        case anyPainKeywordDays = "any_pain_keyword_days"
        case notesConcatenated = "notes_concatenated"
    }
}

struct WellnessAreaCount: Codable, Identifiable {
    let area: String
    let count: Int
    var id: String { area }
}

// MARK: - v2 Phase 5 Chat DTOs

struct CoachChatMessageDTO: Codable, Identifiable {
    let id: UUID
    let sentAt: Date
    let role: String
    let content: String
    let relatedEventId: UUID?
    let relatedAdjustmentId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case sentAt = "sent_at"
        case role, content
        case relatedEventId = "related_event_id"
        case relatedAdjustmentId = "related_adjustment_id"
    }
}

struct CoachChatHistoryDTO: Codable {
    let items: [CoachChatMessageDTO]
    let summary: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items, summary
        case hasMore = "has_more"
    }
}

/// Trailing SSE payload from /api/coach/chat — `data: {"meta": {...}}`.
struct ChatStreamMetaEnvelope: Decodable {
    let meta: [String: String]
}

// MARK: - v2 Phase 6 Nutrition DTOs

struct ParsedMealItemDTO: Codable {
    let name: String?
    let estimatedQuantity: String?
    let calories: Int?
    let carbsG: Double?
    let proteinG: Double?
    let fatG: Double?
    let fiberG: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case estimatedQuantity = "estimated_quantity"
        case calories
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }
}

struct ParsedMealDTO: Codable {
    let items: [ParsedMealItemDTO]
    let totalCalories: Int
    let totalCarbsG: Double
    let totalProteinG: Double
    let totalFatG: Double
    let totalFiberG: Double
    let confidence: Double
    let notes: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case items
        case totalCalories = "total_calories"
        case totalCarbsG = "total_carbs_g"
        case totalProteinG = "total_protein_g"
        case totalFatG = "total_fat_g"
        case totalFiberG = "total_fiber_g"
        case confidence, notes
        case photoUrl = "photo_url"
    }
}

struct LogMealResponseDTO: Codable {
    let id: UUID
    let loggedAt: Date
    let mealType: String

    enum CodingKeys: String, CodingKey {
        case id
        case loggedAt = "logged_at"
        case mealType = "meal_type"
    }
}

struct NutritionTotalsDTO: Codable {
    let calories: Int
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    let mealCount: Int
    let meals: [NutritionMealDTO]?

    enum CodingKeys: String, CodingKey {
        case calories
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case mealCount = "meal_count"
        case meals
    }
}

struct NutritionMealDTO: Codable, Identifiable {
    let id: String
    let loggedAt: String?
    let mealType: String
    let totalCalories: Int
    let totalCarbsG: Double
    let totalProteinG: Double
    let totalFatG: Double

    enum CodingKeys: String, CodingKey {
        case id
        case loggedAt = "logged_at"
        case mealType = "meal_type"
        case totalCalories = "total_calories"
        case totalCarbsG = "total_carbs_g"
        case totalProteinG = "total_protein_g"
        case totalFatG = "total_fat_g"
    }
}

struct NutritionTargetsDTO: Codable {
    let carbsGFloor: Double
    let proteinGFloor: Double
    let fatGFloor: Double
    let calorieFloorLeaSafety: Int
    let plannedWorkoutType: String?

    enum CodingKeys: String, CodingKey {
        case carbsGFloor = "carbs_g_floor"
        case proteinGFloor = "protein_g_floor"
        case fatGFloor = "fat_g_floor"
        case calorieFloorLeaSafety = "calorie_floor_lea_safety"
        case plannedWorkoutType = "planned_workout_type"
    }
}

struct NutritionTodayDTO: Codable {
    let totals: NutritionTotalsDTO
    let targets: NutritionTargetsDTO
    let gap: NutritionGapDTO?
}

struct NutritionGapDTO: Codable {
    let anyShortfall: Bool

    enum CodingKeys: String, CodingKey {
        case anyShortfall = "any_shortfall"
    }
}

struct HydrationDTO: Codable {
    let glassesLogged: Int
    let estimatedMl: Int
    let electrolyteServings: Int

    enum CodingKeys: String, CodingKey {
        case glassesLogged = "glasses_logged"
        case estimatedMl = "estimated_ml"
        case electrolyteServings = "electrolyte_servings"
    }
}

struct TemplateDTO: Codable, Identifiable {
    let id: UUID
    let name: String
    let totalCalories: Int?
    let totalCarbsG: Double?
    let totalProteinG: Double?
    let totalFatG: Double?
    let useCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case totalCalories = "total_calories"
        case totalCarbsG = "total_carbs_g"
        case totalProteinG = "total_protein_g"
        case totalFatG = "total_fat_g"
        case useCount = "use_count"
    }
}

struct RaceFuelingPlanDTO: Codable {
    let id: UUID
    let eventId: UUID
    let generatedAt: Date
    let threeDaysBefore: AnyJSONDict?
    let raceMorning: AnyJSONDict?
    let duringRace: AnyJSONDict?
    let postRace: AnyJSONDict?
    let weatherForecast: AnyJSONDict?
    let courseNotes: String?
    let athleteEdits: AnyJSONDict?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case generatedAt = "generated_at"
        case threeDaysBefore = "three_days_before"
        case raceMorning = "race_morning"
        case duringRace = "during_race"
        case postRace = "post_race"
        case weatherForecast = "weather_forecast"
        case courseNotes = "course_notes"
        case athleteEdits = "athlete_edits"
    }
}

// MARK: - v2 Phase 1 Garmin DTOs

struct GarminStatusDTO: Codable {
    let connected: Bool
    let connectedAt: Date?
    let disconnectedAt: Date?
    let backfillStatus: String?
    let backfillProgress: Int

    enum CodingKeys: String, CodingKey {
        case connected
        case connectedAt = "connected_at"
        case disconnectedAt = "disconnected_at"
        case backfillStatus = "backfill_status"
        case backfillProgress = "backfill_progress"
    }
}

// MARK: - v2 Coaching DTOs

struct CoachingInboxResponse: Codable {
    let items: [CoachingInboxItem]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

struct CoachingInboxItem: Codable, Identifiable {
    let id: UUID
    let eventType: String
    let triggeredAt: Date
    let notificationDelivered: Bool
    let hasLlmOutput: Bool
    let flagsThatFired: [String]
    let athleteFeedback: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case triggeredAt = "triggered_at"
        case notificationDelivered = "notification_delivered"
        case hasLlmOutput = "has_llm_output"
        case flagsThatFired = "flags_that_fired"
        case athleteFeedback = "athlete_feedback"
        case summary
    }
}

// MARK: - API Service Error
enum APIServiceError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .parsingError:
            return "Failed to parse response"
        }
    }
}

// MARK: - Onboarding Data Container
struct OnboardingData {
    // Step 1: Goal
    var raceType: RaceType = .marathon
    var raceDate: Date = Date().addingTimeInterval(86400 * 84) // 12 weeks
    var raceName: String = ""
    var goalTime: String = ""
    var customDistanceKm: Double? = nil
    var terrainType: TerrainType? = nil
    var elevationGainM: Int? = nil

    // Step 2: Fitness
    var currentWeeklyMileage: Int = 0
    var longestRecentRun: Int = 0
    var recentRaceTimes: String = ""
    var recentRuns: String = ""
    var fitnessLevel: FitnessLevel = .intermediate

    // Step 3: Schedule
    var startDate: Date = Date()
    var restDays: Set<DayOfWeek> = []
    var longRunDay: DayOfWeek = .sunday
    var doubleDaysAllowed: Bool = false
    var runningDaysPerWeek: Int = 5
    var gymDaysPerWeek: Int = 2

    // Step 4: History
    var yearsRunning: Int = 0
    var previousInjuries: String = ""
    var previousExperience: String = ""

    // Step 5: Conflict Resolution (optional)
    var planMode: PlanMode? = nil
    var recommendedGoalTime: String? = nil

    // MARK: - Computed Helpers

    /// Whether the custom distance qualifies as ultra (50km+)
    var isUltraDistance: Bool {
        raceType == .custom && (customDistanceKm ?? 0) >= 50
    }

    // Validation
    var isStep1Valid: Bool {
        let baseValid = !raceName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !goalTime.trimmingCharacters(in: .whitespaces).isEmpty &&
            raceDate > startDate
        if raceType == .custom {
            return baseValid && (customDistanceKm ?? 0) > 0
        }
        return baseValid
    }

    var isStep2Valid: Bool {
        currentWeeklyMileage >= 0 && longestRecentRun >= 0
    }

    var isStep3Valid: Bool {
        let availableDays = 7 - restDays.count
        let totalSessions = runningDaysPerWeek + gymDaysPerWeek
        return totalSessions <= availableDays || doubleDaysAllowed
    }

    var isStep4Valid: Bool {
        yearsRunning >= 0
    }
}

// MARK: - Interactive Weekly Check-in

/// A single check-in question, served verbatim from the backend.
struct CheckinQuestion: Codable, Identifiable, Equatable {
    let id: String
    let type: String            // scale_1_5 | multiple_choice | yes_no | free_text
    let text: String
    let options: [String]?
    let lowLabel: String?
    let highLabel: String?
    let optional: Bool?
    let targeted: Bool?
    let followUpIfYes: CheckinFollowUp?

    struct CheckinFollowUp: Codable, Equatable {
        let id: String
        let type: String
        let text: String
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, options, optional, targeted
        case lowLabel = "low_label"
        case highLabel = "high_label"
        case followUpIfYes = "follow_up_if_yes"
    }
}

/// An answer value — int (scale), bool (yes/no), or string (choice / free text).
enum CheckinAnswerValue: Codable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }

    var jsonValue: Any {
        switch self {
        case .int(let v): return v
        case .bool(let v): return v
        case .string(let v): return v
        }
    }
}

struct WeeklyCheckinDTO: Codable {
    struct Questions: Codable {
        let version: Int?
        let questions: [CheckinQuestion]?
    }

    let id: String?
    let weekEnding: String?
    let status: String
    let questions: Questions?
    let answers: [String: CheckinAnswerValue]?
    let reviewEventId: String?

    enum CodingKeys: String, CodingKey {
        case id, status, questions, answers
        case weekEnding = "week_ending"
        case reviewEventId = "review_event_id"
    }

    var questionList: [CheckinQuestion] { questions?.questions ?? [] }
    var isOpen: Bool { status == "invited" || status == "in_progress" }
}

extension APIService {

    /// This week's check-in (status "none" when there isn't one).
    func fetchCurrentCheckin() async throws -> WeeklyCheckinDTO {
        let url = URL(string: "\(baseURL)/api/coach/checkin/current")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(WeeklyCheckinDTO.self, from: data)
    }

    /// Final submit — fires the weekly review server-side with these answers.
    func submitCheckin(id: String, answers: [String: CheckinAnswerValue]) async throws -> WeeklyCheckinDTO {
        try await sendCheckinAnswers(id: id, answers: answers, path: "submit", method: "POST")
    }

    /// Partial save so a half-finished check-in survives app restarts.
    func saveCheckinAnswers(id: String, answers: [String: CheckinAnswerValue]) async throws -> WeeklyCheckinDTO {
        try await sendCheckinAnswers(id: id, answers: answers, path: "answers", method: "PATCH")
    }

    private func sendCheckinAnswers(
        id: String,
        answers: [String: CheckinAnswerValue],
        path: String,
        method: String
    ) async throws -> WeeklyCheckinDTO {
        let url = URL(string: "\(baseURL)/api/coach/checkin/\(id)/\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        let payload: [String: Any] = ["answers": answers.mapValues { $0.jsonValue }]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(WeeklyCheckinDTO.self, from: data)
    }

    /// Pin the athlete's check-in day (0=Monday .. 6=Sunday) — computed from the
    /// active plan's rest day whenever a plan is created or edited.
    func registerCheckinDay(_ dayOfWeek: Int) async {
        guard (0...6).contains(dayOfWeek) else { return }
        let url = URL(string: "\(baseURL)/api/coach/checkin-day")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["day_of_week": dayOfWeek])
        // Fire-and-forget: the Sunday default covers failures.
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Server-side Plan Store (pull + backfill)

struct RemotePlanDTO: Codable {
    let id: String?
    let updatedAt: String?
    let source: String?
    let rawPlanContent: String?
    let raceType: String?
    let raceDate: String?
    let raceName: String?
    let goalTime: String?
    let customDistanceKm: Double?
    let startDate: String?
    let changeNote: String?

    enum CodingKeys: String, CodingKey {
        case id, source
        case updatedAt = "updated_at"
        case rawPlanContent = "raw_plan_content"
        case raceType = "race_type"
        case raceDate = "race_date"
        case raceName = "race_name"
        case goalTime = "goal_time"
        case customDistanceKm = "custom_distance_km"
        case startDate = "start_date"
        case changeNote = "change_note"
    }

    var exists: Bool { id != nil && rawPlanContent != nil }
}

extension APIService {

    /// The server's copy of the athlete's active plan (empty DTO when none).
    func fetchRemotePlan() async throws -> RemotePlanDTO {
        let url = URL(string: "\(baseURL)/api/plans/active")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(RemotePlanDTO.self, from: data)
    }

    /// Backfill the device's active plan to the server (plans created before
    /// server-side persistence existed). Fire-and-forget semantics for callers.
    func syncPlanToServer(
        clientPlanId: String,
        rawPlanContent: String,
        raceType: String,
        raceDate: Date,
        raceName: String?,
        goalTime: String?,
        customDistanceKm: Double?,
        startDate: Date
    ) async throws -> RemotePlanDTO {
        let url = URL(string: "\(baseURL)/api/plans/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone.current

        var payload: [String: Any] = [
            "client_plan_id": clientPlanId,
            "raw_plan_content": rawPlanContent,
            "race_type": raceType,
            "race_date": dayFormatter.string(from: raceDate),
            "start_date": dayFormatter.string(from: startDate),
        ]
        if let v = raceName, !v.isEmpty { payload["race_name"] = v }
        if let v = goalTime, !v.isEmpty { payload["goal_time"] = v }
        if let v = customDistanceKm { payload["custom_distance_km"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(RemotePlanDTO.self, from: data)
    }
}

// MARK: - Server Run Pull (server → phone bridge)

/// A run record as stored server-side — including runs logged or corrected
/// by the coach outside the app.
struct ServerRunDTO: Codable, Identifiable {
    let id: String
    let completedAt: String
    let distanceKm: Double
    let durationSeconds: Double
    let avgPaceSecPerKm: Double
    let kmSplitsJson: String?
    let feedbackRating: Int?
    let notes: String?
    let plannedWorkoutTitle: String?
    let plannedWorkoutType: String?
    let plannedDistanceKm: Double?
    let completionScore: Int?
    let planName: String?
    let weekNumber: Int?
    let dataSource: String
    let treadmillBrand: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case completedAt = "completed_at"
        case distanceKm = "distance_km"
        case durationSeconds = "duration_seconds"
        case avgPaceSecPerKm = "avg_pace_sec_per_km"
        case kmSplitsJson = "km_splits_json"
        case feedbackRating = "feedback_rating"
        case plannedWorkoutTitle = "planned_workout_title"
        case plannedWorkoutType = "planned_workout_type"
        case plannedDistanceKm = "planned_distance_km"
        case completionScore = "completion_score"
        case planName = "plan_name"
        case weekNumber = "week_number"
        case dataSource = "data_source"
        case treadmillBrand = "treadmill_brand"
    }

    var completedAtDate: Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: completedAt) { return d }
        let plain = ISO8601DateFormatter()
        return plain.date(from: completedAt)
    }
}

extension APIService {
    /// Recent server-side runs (default: last 30 days).
    func fetchServerRuns(limit: Int = 50) async throws -> [ServerRunDTO] {
        let url = URL(string: "\(baseURL)/api/runs?limit=\(limit)")!
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        checkForUnauthorized(response)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([ServerRunDTO].self, from: data)
    }
}

import Foundation

// MARK: - API Configuration
enum APIConfiguration {
    static let serverURLKey = "stride_server_url"
    static let defaultDeviceURL = "https://unground-repeated-velda.ngrok-free.dev"
    static let simulatorURL = "http://localhost:8000"
    
    static var serverURL: String {
        get {
            #if targetEnvironment(simulator)
            return simulatorURL
            #else
            return UserDefaults.standard.string(forKey: serverURLKey) ?? defaultDeviceURL
            #endif
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
    
    // Validation
    var isStep1Valid: Bool {
        !raceName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !goalTime.trimmingCharacters(in: .whitespaces).isEmpty &&
        raceDate > startDate
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

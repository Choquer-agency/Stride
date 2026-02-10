import Foundation

// MARK: - API Configuration
enum APIConfiguration {
    static let serverURLKey = "stride_server_url"
    static let defaultDeviceURL = "http://10.50.0.200:8000"
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
    
    // MARK: - Analyze Conflicts
    func analyzeConflicts(request: TrainingPlanRequest) async throws -> ConflictAnalysisResponse {
        let url = URL(string: "\(baseURL)/api/analyze-conflicts")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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

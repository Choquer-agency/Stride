import Foundation

/// Errors that can occur when calling the API
enum APIError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String)
    case parseError(String)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue."
        case .invalidURL:
            return "Invalid API URL."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "Error \(statusCode): \(message)"
        case .parseError(let details):
            return "Failed to parse response: \(details)"
        case .serverError(let message):
            return message
        }
    }
}

/// HTTP client for the Stride backend API
class APIClient {
    static let shared = APIClient()
    
    // TODO: Update this to your Railway deployment URL
    #if DEBUG
    private let baseURL = "http://localhost:3000"
    #else
    private let baseURL = "https://your-app.up.railway.app"  // Replace with your Railway URL
    #endif
    
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    // MARK: - Configuration
    
    var isAuthenticated: Bool {
        return AuthManager.shared.getStoredToken() != nil
    }
    
    // MARK: - HTTP Methods
    
    func get(_ path: String) async throws -> [String: Any] {
        return try await request(method: "GET", path: path)
    }
    
    func post(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        return try await request(method: "POST", path: path, body: body)
    }
    
    func put(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        return try await request(method: "PUT", path: path, body: body)
    }
    
    func delete(_ path: String) async throws -> [String: Any] {
        return try await request(method: "DELETE", path: path)
    }
    
    // MARK: - Typed Requests
    
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await requestData(method: "GET", path: path)
        return try decoder.decode(type, from: data)
    }
    
    func getArray<T: Decodable>(_ path: String, as type: T.Type) async throws -> [T] {
        let data = try await requestData(method: "GET", path: path)
        return try decoder.decode([T].self, from: data)
    }
    
    func post<T: Decodable, B: Encodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        let bodyData = try encoder.encode(body)
        let data = try await requestData(method: "POST", path: path, body: bodyData)
        return try decoder.decode(type, from: data)
    }
    
    // MARK: - Private Methods
    
    private func request(method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var bodyData: Data?
        if let body = body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        }
        
        let data = try await requestData(method: method, path: path, body: bodyData)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Try parsing as array
            if let _ = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return ["data": try JSONSerialization.jsonObject(with: data)]
            }
            throw APIError.parseError("Invalid JSON response")
        }
        
        return json
    }
    
    private func requestData(method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add auth token if available
        if let token = AuthManager.shared.getStoredToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: 0, message: "Invalid response")
        }
        
        // Handle error status codes
        if httpResponse.statusCode == 401 {
            // Token expired or invalid
            AuthManager.shared.signOut()
            throw APIError.notAuthenticated
        }
        
        if httpResponse.statusCode >= 400 {
            // Try to parse error message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                throw APIError.serverError(errorMessage)
            }
            throw APIError.httpError(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        
        return data
    }
}

// MARK: - Convenience Extensions

extension APIClient {
    /// Check if the API is reachable
    func healthCheck() async -> Bool {
        do {
            let response = try await get("/health")
            return response["status"] as? String == "ok"
        } catch {
            return false
        }
    }
}

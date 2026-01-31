import Foundation

/// Errors that can occur when interacting with Neon
enum NeonError: Error, LocalizedError {
    case notConfigured
    case invalidConnectionString
    case networkError(Error)
    case httpError(statusCode: Int, message: String)
    case parseError(String)
    case queryError(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Neon database is not configured. Please add your connection string in Settings."
        case .invalidConnectionString:
            return "Invalid Neon connection string format."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP error \(statusCode): \(message)"
        case .parseError(let details):
            return "Failed to parse response: \(details)"
        case .queryError(let message):
            return "Query error: \(message)"
        }
    }
}

/// Result from a Neon SQL query
struct NeonQueryResult {
    let columns: [String]
    let rows: [[Any?]]
    let rowCount: Int
    
    /// Get rows as dictionaries for easier access
    var rowDictionaries: [[String: Any?]] {
        return rows.map { row in
            var dict: [String: Any?] = [:]
            for (index, column) in columns.enumerated() {
                if index < row.count {
                    dict[column] = row[index]
                }
            }
            return dict
        }
    }
}

/// HTTP client for Neon serverless PostgreSQL
class NeonClient {
    
    static let shared = NeonClient()
    
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
    }
    
    // MARK: - Configuration
    
    /// Check if Neon is configured
    var isConfigured: Bool {
        return NeonKeyManager.isConfigured
    }
    
    /// Get the current user ID
    var userId: String {
        return NeonKeyManager.getUserId()
    }
    
    // MARK: - Query Execution
    
    /// Execute a SQL query and return results
    func query(_ sql: String, params: [Any?] = []) async throws -> NeonQueryResult {
        guard let connectionString = NeonKeyManager.getConnectionString() else {
            throw NeonError.notConfigured
        }
        
        // Parse connection string to get the HTTP endpoint
        guard let endpoint = buildNeonEndpoint(from: connectionString) else {
            throw NeonError.invalidConnectionString
        }
        
        // Build request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization from connection string password
        if let password = extractPassword(from: connectionString) {
            request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        }
        
        // Build request body
        let body: [String: Any] = [
            "query": sql,
            "params": params.map { paramToJSON($0) }
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Execute request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NeonError.networkError(error)
        }
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NeonError.httpError(statusCode: 0, message: "Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NeonError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        // Parse response
        return try parseQueryResult(data)
    }
    
    /// Execute a SQL query that doesn't return results (INSERT, UPDATE, DELETE)
    func execute(_ sql: String, params: [Any?] = []) async throws {
        _ = try await query(sql, params: params)
    }
    
    // MARK: - Convenience Methods
    
    /// Insert a row and return the inserted ID
    func insert(_ sql: String, params: [Any?] = []) async throws -> UUID? {
        let result = try await query(sql + " RETURNING id", params: params)
        if let firstRow = result.rows.first,
           let idString = firstRow.first as? String,
           let uuid = UUID(uuidString: idString) {
            return uuid
        }
        return nil
    }
    
    /// Test the connection
    func testConnection() async throws -> Bool {
        do {
            let result = try await query("SELECT 1 as test")
            return result.rowCount == 1
        } catch {
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    /// Build the Neon HTTP SQL endpoint from connection string
    private func buildNeonEndpoint(from connectionString: String) -> URL? {
        // Connection string format: postgresql://user:password@ep-xxx.region.neon.tech/database
        // HTTP endpoint format: https://ep-xxx.region.neon.tech/sql
        
        guard let url = URL(string: connectionString),
              let host = url.host else {
            return nil
        }
        
        return URL(string: "https://\(host)/sql")
    }
    
    /// Extract password from connection string
    private func extractPassword(from connectionString: String) -> String? {
        guard let url = URL(string: connectionString) else {
            return nil
        }
        return url.password
    }
    
    /// Convert Swift value to JSON-compatible format
    private func paramToJSON(_ value: Any?) -> Any {
        guard let value = value else {
            return NSNull()
        }
        
        switch value {
        case let uuid as UUID:
            return uuid.uuidString
        case let date as Date:
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        case let array as [Any]:
            return array.map { paramToJSON($0) }
        case let dict as [String: Any]:
            return dict.mapValues { paramToJSON($0) }
        default:
            return value
        }
    }
    
    /// Parse Neon query result
    private func parseQueryResult(_ data: Data) throws -> NeonQueryResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeonError.parseError("Invalid JSON response")
        }
        
        // Check for error
        if let error = json["error"] as? String {
            throw NeonError.queryError(error)
        }
        
        // Parse fields (columns)
        guard let fields = json["fields"] as? [[String: Any]] else {
            throw NeonError.parseError("Missing fields in response")
        }
        
        let columns = fields.compactMap { $0["name"] as? String }
        
        // Parse rows
        guard let rows = json["rows"] as? [[Any]] else {
            // Empty result is valid
            return NeonQueryResult(columns: columns, rows: [], rowCount: 0)
        }
        
        // Convert rows to proper types
        let parsedRows: [[Any?]] = rows.map { row in
            row.map { value in
                if value is NSNull {
                    return nil
                }
                return value
            }
        }
        
        return NeonQueryResult(columns: columns, rows: parsedRows, rowCount: parsedRows.count)
    }
}

// MARK: - Model Serialization Helpers

extension NeonClient {
    
    /// Encode a Codable object to JSONB string for storage
    func encodeToJSONB<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NeonError.parseError("Failed to encode to JSON string")
        }
        return string
    }
    
    /// Decode a JSONB string to a Codable object
    func decodeFromJSONB<T: Decodable>(_ jsonString: String, as type: T.Type) throws -> T {
        guard let data = jsonString.data(using: .utf8) else {
            throw NeonError.parseError("Invalid JSON string")
        }
        return try decoder.decode(type, from: data)
    }
    
    /// Safely extract a UUID from a row dictionary
    func extractUUID(_ dict: [String: Any?], key: String) -> UUID? {
        if let value = dict[key] as? String {
            return UUID(uuidString: value)
        }
        return nil
    }
    
    /// Safely extract a Date from a row dictionary
    func extractDate(_ dict: [String: Any?], key: String) -> Date? {
        if let value = dict[key] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        return nil
    }
    
    /// Safely extract a Double from a row dictionary
    func extractDouble(_ dict: [String: Any?], key: String) -> Double? {
        if let value = dict[key] {
            if let doubleValue = value as? Double {
                return doubleValue
            }
            if let intValue = value as? Int {
                return Double(intValue)
            }
            if let stringValue = value as? String {
                return Double(stringValue)
            }
        }
        return nil
    }
    
    /// Safely extract an Int from a row dictionary
    func extractInt(_ dict: [String: Any?], key: String) -> Int? {
        if let value = dict[key] {
            if let intValue = value as? Int {
                return intValue
            }
            if let doubleValue = value as? Double {
                return Int(doubleValue)
            }
            if let stringValue = value as? String {
                return Int(stringValue)
            }
        }
        return nil
    }
    
    /// Safely extract a String from a row dictionary
    func extractString(_ dict: [String: Any?], key: String) -> String? {
        return dict[key] as? String
    }
    
    /// Safely extract a Bool from a row dictionary
    func extractBool(_ dict: [String: Any?], key: String) -> Bool? {
        if let value = dict[key] {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let intValue = value as? Int {
                return intValue != 0
            }
            if let stringValue = value as? String {
                return stringValue.lowercased() == "true" || stringValue == "1"
            }
        }
        return nil
    }
    
    /// Safely extract a String array from a row dictionary
    func extractStringArray(_ dict: [String: Any?], key: String) -> [String]? {
        if let value = dict[key] {
            if let array = value as? [String] {
                return array
            }
            // PostgreSQL arrays come as strings like {val1,val2}
            if let stringValue = value as? String {
                let trimmed = stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                if trimmed.isEmpty {
                    return []
                }
                return trimmed.components(separatedBy: ",")
            }
        }
        return nil
    }
    
    /// Safely extract an Int array from a row dictionary
    func extractIntArray(_ dict: [String: Any?], key: String) -> [Int]? {
        if let stringArray = extractStringArray(dict, key: key) {
            return stringArray.compactMap { Int($0) }
        }
        return nil
    }
}

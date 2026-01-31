import Foundation
import Security

/// Manages secure storage and retrieval of Neon database credentials
class NeonKeyManager {
    
    private static let keychainService = "com.stride.neon"
    private static let connectionStringAccount = "neon_connection_string"
    private static let userIdAccount = "neon_user_id"
    
    // MARK: - Connection String Management
    
    /// Get the Neon connection string from Keychain
    static func getConnectionString() -> String? {
        return loadFromKeychain(account: connectionStringAccount)
    }
    
    /// Save the Neon connection string to Keychain
    static func saveConnectionString(_ connectionString: String) -> Bool {
        guard validateConnectionString(connectionString) else {
            print("❌ Invalid Neon connection string format")
            return false
        }
        return saveToKeychain(value: connectionString, account: connectionStringAccount)
    }
    
    /// Remove the Neon connection string from Keychain
    static func removeConnectionString() {
        deleteFromKeychain(account: connectionStringAccount)
        print("🗑️ Removed Neon connection string")
    }
    
    // MARK: - User ID Management
    
    /// Get or create a unique user ID for this device
    static func getUserId() -> String {
        // Try to load existing user ID
        if let existingId = loadFromKeychain(account: userIdAccount) {
            return existingId
        }
        
        // Generate new user ID
        let newId = UUID().uuidString
        _ = saveToKeychain(value: newId, account: userIdAccount)
        print("🆔 Generated new Neon user ID: \(newId)")
        return newId
    }
    
    // MARK: - Keychain Operations
    
    private static func saveToKeychain(value: String, account: String) -> Bool {
        // Delete existing value first
        deleteFromKeychain(account: account)
        
        guard let data = value.data(using: .utf8) else {
            print("❌ Failed to encode value for Keychain")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Saved to Keychain: \(account)")
            return true
        } else {
            print("❌ Failed to save to Keychain: \(status)")
            return false
        }
    }
    
    private static func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        
        return nil
    }
    
    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Validation
    
    /// Validate Neon connection string format
    /// Expected format: postgresql://user:password@host/database or project URL
    static func validateConnectionString(_ connectionString: String) -> Bool {
        // Check for postgresql:// or postgres:// prefix
        let hasValidPrefix = connectionString.hasPrefix("postgresql://") || 
                            connectionString.hasPrefix("postgres://")
        
        // Check for neon.tech domain (typical for Neon)
        let hasNeonDomain = connectionString.contains("neon.tech") ||
                           connectionString.contains("neon.com")
        
        // Basic length check
        let hasMinLength = connectionString.count > 30
        
        return hasValidPrefix && hasNeonDomain && hasMinLength
    }
    
    // MARK: - Configuration Status
    
    /// Check if Neon is configured
    static var isConfigured: Bool {
        return getConnectionString() != nil
    }
    
    /// Get masked connection string for display
    static func getMaskedConnectionString() -> String? {
        guard let connectionString = getConnectionString() else {
            return nil
        }
        
        // Mask the password portion
        if let atIndex = connectionString.firstIndex(of: "@") {
            let beforeAt = connectionString[connectionString.startIndex..<atIndex]
            if let colonIndex = beforeAt.lastIndex(of: ":") {
                let prefix = String(connectionString[...colonIndex])
                let suffix = String(connectionString[atIndex...])
                return prefix + "****" + suffix
            }
        }
        
        // If we can't parse, just mask most of it
        if connectionString.count > 20 {
            let prefix = String(connectionString.prefix(15))
            let suffix = String(connectionString.suffix(10))
            return prefix + "..." + suffix
        }
        
        return "****"
    }
    
    // MARK: - Parse Connection Details
    
    /// Parse the connection string to extract host and database for API calls
    static func parseConnectionDetails() -> (host: String, database: String, password: String)? {
        guard let connectionString = getConnectionString() else {
            return nil
        }
        
        // Format: postgresql://user:password@host/database?sslmode=require
        guard let url = URL(string: connectionString) else {
            return nil
        }
        
        guard let host = url.host,
              let password = url.password,
              let database = url.path.dropFirst().isEmpty ? nil : String(url.path.dropFirst()) else {
            return nil
        }
        
        return (host: host, database: database, password: password)
    }
}

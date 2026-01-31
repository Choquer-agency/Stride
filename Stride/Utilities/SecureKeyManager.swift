import Foundation
import Security

/// Manages secure storage and retrieval of the OpenAI API key
class SecureKeyManager {
    
    private static let keychainService = "com.stride.apikeys"
    private static let keychainAccount = "openai_api_key"
    
    // MARK: - API Key Retrieval
    
    /// Get the OpenAI API key from multiple sources in priority order
    /// Priority: 1. Keychain, 2. Environment Variable, 3. Hardcoded (dev only)
    static func getOpenAIAPIKey() -> String? {
        // First, check keychain (most secure)
        if let keychainKey = loadFromKeychain() {
            print("🔑 Loaded API key from Keychain")
            return keychainKey
        }
        
        // Second, check environment variable (Xcode scheme)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            print("🔑 Loaded API key from Environment Variable")
            // Save to keychain for future use
            _ = saveToKeychain(envKey)
            return envKey
        }
        
        // Third, check for hardcoded key (dev testing only - not recommended for production)
        #if DEBUG
        // Developers can paste their key here for quick testing
        // let hardcodedKey = "sk-your-openai-key-here"
        // if !hardcodedKey.isEmpty && hardcodedKey.hasPrefix("sk-") {
        //     print("🔑 Using hardcoded API key (DEV MODE)")
        //     return hardcodedKey
        // }
        #endif
        
        print("⚠️ No API key found in any source")
        return nil
    }
    
    // MARK: - Keychain Operations
    
    /// Save API key to keychain
    static func saveToKeychain(_ apiKey: String) -> Bool {
        // Delete existing key first
        deleteFromKeychain()
        
        guard let data = apiKey.data(using: .utf8) else {
            print("❌ Failed to encode API key")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Saved API key to Keychain")
            return true
        } else {
            print("❌ Failed to save API key to Keychain: \(status)")
            return false
        }
    }
    
    /// Load API key from keychain
    static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        
        return nil
    }
    
    /// Delete API key from keychain
    static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Validation
    
    /// Validate that an API key has the correct format
    static func validateAPIKey(_ key: String) -> Bool {
        // OpenAI API keys start with "sk-" and are typically 51+ characters
        return key.hasPrefix("sk-") && key.count > 20
    }
    
    // MARK: - User-Facing API Key Management
    
    /// Check if API key is configured
    static var isAPIKeyConfigured: Bool {
        return getOpenAIAPIKey() != nil
    }
    
    /// Update the API key (save to keychain)
    static func updateAPIKey(_ newKey: String) -> Bool {
        guard validateAPIKey(newKey) else {
            print("❌ Invalid API key format")
            return false
        }
        
        return saveToKeychain(newKey)
    }
    
    /// Remove the API key
    static func removeAPIKey() {
        deleteFromKeychain()
        print("🗑️ Removed API key")
    }
    
    /// Get masked version of API key for display (e.g., "sk-...xnQ")
    static func getMaskedAPIKey() -> String? {
        guard let key = getOpenAIAPIKey() else {
            return nil
        }
        
        if key.count > 10 {
            let prefix = String(key.prefix(5))
            let suffix = String(key.suffix(3))
            return "\(prefix)...\(suffix)"
        }
        
        return "sk-***"
    }
}

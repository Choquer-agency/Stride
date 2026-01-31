import Foundation
import Combine
import AuthenticationServices
import Security

/// Manages Apple Sign-In authentication
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var currentUser: User?
    @Published var authError: String?
    
    private let keychainService = "com.stride.auth"
    private let tokenKey = "apple_identity_token"
    private let userIdKey = "user_id"
    
    struct User: Codable {
        let id: String
        let email: String?
        let displayName: String?
        let createdAt: String?
    }
    
    override init() {
        super.init()
        // Check if we have a stored token
        if let _ = getStoredToken() {
            isAuthenticated = true
            // Fetch user info
            Task {
                await fetchCurrentUser()
            }
        }
    }
    
    // MARK: - Apple Sign-In
    
    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
        
        isLoading = true
        authError = nil
    }
    
    func signOut() {
        deleteStoredToken()
        deleteStoredUserId()
        
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    // MARK: - Token Management
    
    func getStoredToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        
        return nil
    }
    
    private func storeToken(_ token: String) {
        deleteStoredToken()
        
        guard let data = token.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteStoredToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - User ID Management
    
    func getStoredUserId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let userId = String(data: data, encoding: .utf8) {
            return userId
        }
        
        return nil
    }
    
    private func storeUserId(_ userId: String) {
        deleteStoredUserId()
        
        guard let data = userId.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteStoredUserId() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - API Calls
    
    private func authenticateWithBackend(
        identityToken: String,
        authorizationCode: String,
        email: String?,
        fullName: PersonNameComponents?
    ) async {
        do {
            var body: [String: Any] = [
                "identityToken": identityToken,
                "authorizationCode": authorizationCode
            ]
            
            if let email = email {
                body["email"] = email
            }
            
            if let fullName = fullName {
                var nameDict: [String: String] = [:]
                if let givenName = fullName.givenName {
                    nameDict["givenName"] = givenName
                }
                if let familyName = fullName.familyName {
                    nameDict["familyName"] = familyName
                }
                if !nameDict.isEmpty {
                    body["fullName"] = nameDict
                }
            }
            
            let response = try await APIClient.shared.post("/auth/apple", body: body)
            
            if let userData = response["user"] as? [String: Any],
               let userId = userData["id"] as? String {
                // Store token and user ID
                storeToken(identityToken)
                storeUserId(userId)
                
                let user = User(
                    id: userId,
                    email: userData["email"] as? String,
                    displayName: userData["displayName"] as? String,
                    createdAt: userData["createdAt"] as? String
                )
                
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.authError = "Sign in failed: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func fetchCurrentUser() async {
        guard let token = getStoredToken() else { return }
        
        do {
            let response = try await APIClient.shared.get("/auth/me")
            
            if let userId = response["id"] as? String {
                let user = User(
                    id: userId,
                    email: response["email"] as? String,
                    displayName: response["displayName"] as? String,
                    createdAt: response["createdAt"] as? String
                )
                
                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                }
            }
        } catch {
            // Token might be expired
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUser = nil
            }
        }
    }
    
    func deleteAccount() async throws {
        try await APIClient.shared.delete("/auth/account")
        signOut()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            DispatchQueue.main.async {
                self.authError = "Invalid credential type"
                self.isLoading = false
            }
            return
        }
        
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authCodeData, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.authError = "Failed to get identity token"
                self.isLoading = false
            }
            return
        }
        
        Task {
            await authenticateWithBackend(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                email: credential.email,
                fullName: credential.fullName
            )
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    self.authError = nil // User canceled, not an error
                case .failed:
                    self.authError = "Sign in failed"
                case .invalidResponse:
                    self.authError = "Invalid response from Apple"
                case .notHandled:
                    self.authError = "Sign in not handled"
                case .unknown:
                    self.authError = "An unknown error occurred"
                case .notInteractive:
                    self.authError = "Not interactive"
                @unknown default:
                    self.authError = "Sign in error"
                }
            } else {
                self.authError = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}

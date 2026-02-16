import Foundation
import AuthenticationServices
import PostHog

// MARK: - Auth State

enum AuthState: Equatable {
    case unknown
    case signedOut
    case signedIn(UserResponse)
    case needsProfile(UserResponse)

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.signedOut, .signedOut):
            return true
        case (.signedIn(let a), .signedIn(let b)):
            return a.id == b.id
        case (.needsProfile(let a), .needsProfile(let b)):
            return a.id == b.id
        default:
            return false
        }
    }

    var stateKey: String {
        switch self {
        case .unknown: return "unknown"
        case .signedOut: return "signedOut"
        case .signedIn: return "signedIn"
        case .needsProfile: return "needsProfile"
        }
    }
}

// MARK: - Auth Service

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var authState: AuthState = .unknown
    @Published var isLoading = false
    @Published var error: String?

    private static let cachedUserKey = "cached_user_response"

    private var token: String? {
        get { KeychainService.load(key: "jwt_token") }
        set {
            if let value = newValue {
                _ = KeychainService.save(key: "jwt_token", value: value)
            } else {
                KeychainService.delete(key: "jwt_token")
            }
        }
    }

    var currentToken: String? { token }

    private var baseURL: String { APIConfiguration.serverURL }

    // MARK: - User Cache

    private func saveCachedUser(_ user: UserResponse) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
        }
    }

    private func loadCachedUser() -> UserResponse? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(UserResponse.self, from: data)
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
    }

    // MARK: - Check Auth State

    func checkAuthState() async {
        guard token != nil else {
            clearCachedUser()
            authState = .signedOut
            return
        }

        // Instant load from cache for returning users
        if let cached = loadCachedUser() {
            authState = cached.hasCompletedProfile ? .signedIn(cached) : .needsProfile(cached)
            // Validate token in the background
            refreshProfileInBackground()
            return
        }

        // No cache (first launch after sign-in) — must fetch
        do {
            let user = try await fetchProfile()
            saveCachedUser(user)
            authState = user.hasCompletedProfile ? .signedIn(user) : .needsProfile(user)
        } catch {
            self.token = nil
            authState = .signedOut
        }
    }

    // MARK: - Background Refresh

    private func refreshProfileInBackground() {
        Task {
            do {
                let user = try await fetchProfile()
                saveCachedUser(user)
                authState = user.hasCompletedProfile ? .signedIn(user) : .needsProfile(user)
            } catch let error as AuthError where error == .unauthorized {
                signOut()
            } catch {
                // Network error — keep using cached data
            }
        }
    }

    // MARK: - Email Auth

    func registerEmail(email: String, password: String, name: String?) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let body = EmailRegisterRequest(email: email, password: password, name: name)
        let response: TokenResponse = try await postJSON("/auth/register", body: body)
        handleAuthResponse(response)
    }

    func loginEmail(email: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let body = EmailLoginRequest(email: email, password: password)
        let response: TokenResponse = try await postJSON("/auth/login", body: body)
        handleAuthResponse(response)
    }

    // MARK: - Google Auth

    func signInWithGoogle(idToken: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let body = GoogleAuthRequest(idToken: idToken)
        let response: TokenResponse = try await postJSON("/auth/google", body: body)
        handleAuthResponse(response)
    }

    // MARK: - Apple Auth

    func signInWithApple(identityToken: String, userIdentifier: String, fullName: String?, email: String?) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let body = AppleAuthRequest(
            identityToken: identityToken,
            userIdentifier: userIdentifier,
            fullName: fullName,
            email: email
        )
        let response: TokenResponse = try await postJSON("/auth/apple", body: body)
        handleAuthResponse(response)
    }

    // MARK: - Profile

    func fetchProfile() async throws -> UserResponse {
        let url = URL(string: "\(baseURL)/auth/me")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkForAuthError(response)

        return try JSONDecoder().decode(UserResponse.self, from: data)
    }

    func updateProfile(_ profileUpdate: ProfileUpdateRequest) async throws -> UserResponse {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/auth/profile")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        request.httpBody = try JSONEncoder().encode(profileUpdate)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkForAuthError(response)

        let user = try JSONDecoder().decode(UserResponse.self, from: data)
        saveCachedUser(user)
        authState = user.hasCompletedProfile ? .signedIn(user) : .needsProfile(user)
        return user
    }

    // MARK: - Sign Out

    func signOut() {
        token = nil
        clearCachedUser()
        authState = .signedOut
        PostHogSDK.shared.reset()
    }

    // MARK: - Helpers

    private func handleAuthResponse(_ response: TokenResponse) {
        token = response.accessToken
        let user = response.user
        saveCachedUser(user)
        authState = user.hasCompletedProfile ? .signedIn(user) : .needsProfile(user)

        // Identify user in PostHog
        PostHogSDK.shared.identify(
            String(user.id),
            userProperties: [
                "email": user.email,
                "name": user.name ?? "",
                "auth_provider": user.authProvider,
            ]
        )
    }

    func addAuthHeader(to request: inout URLRequest) {
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body
    ) async throws -> Response {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AuthError.unauthorized
        }

        if httpResponse.statusCode == 409 {
            // Email already exists
            if let apiError = try? JSONDecoder().decode(APIErrorDetail.self, from: data) {
                throw AuthError.conflict(apiError.detail)
            }
            throw AuthError.conflict("Account already exists")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorDetail.self, from: data) {
                throw AuthError.serverError(apiError.detail)
            }
            throw AuthError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func checkForAuthError(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            signOut()
            throw AuthError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Auth Error

enum AuthError: LocalizedError, Equatable {
    case invalidResponse
    case unauthorized
    case conflict(String)
    case httpError(Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Invalid email or password"
        case .conflict(let msg): return msg
        case .httpError(let code): return "Server error (\(code))"
        case .serverError(let msg): return msg
        }
    }
}

// MARK: - API Error Detail (for decoding backend error responses)

private struct APIErrorDetail: Decodable {
    let detail: String
}

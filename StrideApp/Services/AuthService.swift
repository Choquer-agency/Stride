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

    @Published private(set) var needsReauthentication = false
    private var protectedWorkouts = Set<UUID>()
    private var memoryToken: String?

    var currentUserID: String? {
        switch authState {
        case .signedIn(let user), .needsProfile(let user): return user.id
        default: return nil
        }
    }

    func beginWorkoutProtection(_ id: UUID) {
        protectedWorkouts.insert(id)
    }

    func endWorkoutProtection(_ id: UUID) {
        protectedWorkouts.remove(id)
        if protectedWorkouts.isEmpty, needsReauthentication { signOut() }
    }

    /// An expired session must not unmount a run or its unsaved summary.
    func handleUnauthorized() {
        needsReauthentication = true
        // A cold launch may receive a 401 before the run container mounts.
        if let owner = currentUserID, let checkpoint = RunRecoveryStore.load(ownerID: owner),
           checkpoint.result.distanceKm > 0 || checkpoint.result.durationSeconds > 0 {
            protectedWorkouts.insert(checkpoint.result.sessionID)
        }
        guard protectedWorkouts.isEmpty else { return }
        signOut()
    }

    private var token: String? {
        get {
            if let memoryToken { return memoryToken }
            guard let value = KeychainService.load(key: "jwt_token") else { return nil }
            memoryToken = value
            // Migrate returning users to background-readable protection as well.
            _ = KeychainService.save(key: "jwt_token", value: value)
            return value
        }
        set {
            memoryToken = newValue
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
            // Device protection may temporarily deny a read; that is not a logout.
            if case .unavailable = KeychainService.read(key: "jwt_token"), let cached = loadCachedUser() {
                authState = cached.hasCompletedProfile ? .signedIn(cached) : .needsProfile(cached)
                return
            }
            guard protectedWorkouts.isEmpty else { return }
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
        } catch let error as AuthError where error == .unauthorized {
            handleUnauthorized()
        } catch {
            // Keep valid credentials on network failures or cancellation.
            self.error = error.localizedDescription
            if protectedWorkouts.isEmpty { authState = .signedOut }
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
                handleUnauthorized()
            } catch {
                // Network error — keep using cached data
            }
        }
    }

    // Legacy callers must not start a non-Apple session or mutate an existing one.
    func registerEmail(email: String, password: String, name: String?) async throws {
        throw AuthError.serverError("Use Sign in with Apple to continue.")
    }

    func loginEmail(email: String, password: String) async throws {
        throw AuthError.serverError("Use Sign in with Apple to continue.")
    }

    func signInWithGoogle(idToken: String) async throws {
        throw AuthError.serverError("Use Sign in with Apple to continue.")
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

    func deleteAccount() async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let url = URL(string: "\(baseURL)/auth/account")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeader(to: &request)
        let (_, response) = try await URLSession.shared.data(for: request)
        try checkForAuthError(response)
        signOut()
    }

    func signOut() {
        protectedWorkouts.removeAll()
        needsReauthentication = false
        token = nil
        clearCachedUser()
        authState = .signedOut
        PostHogSDK.shared.reset()
    }

    // MARK: - Helpers

    private func handleAuthResponse(_ response: TokenResponse) {
        needsReauthentication = false
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
            // Surface the actual server reason (e.g. "Invalid Apple identity token")
            // rather than defaulting to the email-login wording.
            if let apiError = try? JSONDecoder().decode(APIErrorDetail.self, from: data) {
                throw AuthError.serverError(apiError.detail)
            }
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
            handleUnauthorized()
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
        case .unauthorized: return "Your session has expired. Please sign in with Apple."
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

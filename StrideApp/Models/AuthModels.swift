import Foundation

// MARK: - Auth Request Models

struct EmailRegisterRequest: Codable {
    let email: String
    let password: String
    let name: String?
}

struct EmailLoginRequest: Codable {
    let email: String
    let password: String
}

struct GoogleAuthRequest: Codable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

struct AppleAuthRequest: Codable {
    let identityToken: String
    let userIdentifier: String
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case userIdentifier = "user_identifier"
        case fullName = "full_name"
        case email
    }
}

struct ProfileUpdateRequest: Codable {
    var name: String?
    var dateOfBirth: String?
    var gender: String?
    var heightCm: Double?
    var profilePhotoBase64: String?
    var leaderboardOptIn: Bool?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case dateOfBirth = "date_of_birth"
        case gender
        case heightCm = "height_cm"
        case profilePhotoBase64 = "profile_photo_base64"
        case leaderboardOptIn = "leaderboard_opt_in"
        case displayName = "display_name"
    }
}

// MARK: - Auth Response Models

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: UserResponse

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

struct UserResponse: Codable {
    let id: String
    let email: String
    let name: String?
    let authProvider: String
    let profilePhotoBase64: String?
    let dateOfBirth: String?
    let gender: String?
    let heightCm: Double?
    let hasCompletedProfile: Bool
    let leaderboardOptIn: Bool
    let displayName: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, name
        case authProvider = "auth_provider"
        case profilePhotoBase64 = "profile_photo_base64"
        case dateOfBirth = "date_of_birth"
        case gender
        case heightCm = "height_cm"
        case hasCompletedProfile = "has_completed_profile"
        case leaderboardOptIn = "leaderboard_opt_in"
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

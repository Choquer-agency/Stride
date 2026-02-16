import Foundation

struct ShoeResponse: Codable {
    let id: String
    let name: String
    let photoUrl: String?
    let isDefault: Bool
    let totalDistanceKm: Double
    let isRetired: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case photoUrl = "photo_url"
        case isDefault = "is_default"
        case totalDistanceKm = "total_distance_km"
        case isRetired = "is_retired"
        case createdAt = "created_at"
    }
}

struct ShoeCreateRequest: Codable {
    let name: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isDefault = "is_default"
    }
}

struct ShoeUpdateRequest: Codable {
    let name: String?
    let isDefault: Bool?
    let isRetired: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case isDefault = "is_default"
        case isRetired = "is_retired"
    }
}

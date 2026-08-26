import Foundation
import SwiftData

@Model
final class Shoe {
    var id: UUID
    var name: String
    var photoURL: String?
    var photoData: Data?
    var isDefault: Bool
    var totalDistanceKm: Double
    var isRetired: Bool
    var createdAt: Date
    /// "outdoor" | "indoor" — outdoor runs only offer outdoor shoes, etc.
    var usageRaw: String = "outdoor"

    var usage: ShoeUsage {
        get { ShoeUsage(rawValue: usageRaw) ?? .outdoor }
        set { usageRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        photoURL: String? = nil,
        photoData: Data? = nil,
        isDefault: Bool = false,
        totalDistanceKm: Double = 0.0,
        isRetired: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.photoURL = photoURL
        self.photoData = photoData
        self.isDefault = isDefault
        self.totalDistanceKm = totalDistanceKm
        self.isRetired = isRetired
        self.createdAt = createdAt
    }
}

enum ShoeUsage: String, CaseIterable {
    case outdoor, indoor
    var displayName: String { rawValue.capitalized }
}

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

    /// Recommended lifespan in km (0 = unset → derived from model name).
    var recommendedMaxKm: Double = 0

    var effectiveMaxKm: Double {
        recommendedMaxKm > 0 ? recommendedMaxKm : Shoe.defaultMaxKm(forName: name)
    }

    var lifeFraction: Double {
        let maxKm = effectiveMaxKm
        return maxKm > 0 ? totalDistanceKm / maxKm : 0
    }

    /// Per-model lifespans from published durability data:
    /// Alphafly ~250 mi (Nike), Streakfly ~350 km (ZoomX flat),
    /// Zoom Fly ~550 km (plated trainer), Vomero ~400 mi median.
    static func defaultMaxKm(forName name: String) -> Double {
        let n = name.lowercased()
        if n.contains("alphafly") || n.contains("alpha fly") { return 400 }
        if n.contains("streakfly") || n.contains("streak fly") { return 350 }
        if n.contains("vaporfly") || n.contains("vapor fly") { return 400 }
        if n.contains("zoom fly") || n.contains("zoomfly") { return 550 }
        if n.contains("vomero") { return 650 }
        return 600   // sensible daily-trainer default
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

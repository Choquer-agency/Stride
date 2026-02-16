import Foundation
import SwiftUI

// MARK: - Event Response

struct EventResponse: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let eventType: String
    let distanceCategory: String?
    let distanceKm: Double?
    let startsAt: String
    let endsAt: String
    let registrationOpensAt: String?
    let registrationClosesAt: String?
    let maxParticipants: Int?
    let sponsorName: String?
    let sponsorLogoUrl: String?
    let bannerImageUrl: String?
    let primaryColor: String?
    let accentColor: String?
    let isFeatured: Bool
    let participantCount: Int
    let isRegistered: Bool
    let yourBestTimeSeconds: Int?
    let yourTotalDistanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case eventType = "event_type"
        case distanceCategory = "distance_category"
        case distanceKm = "distance_km"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case registrationOpensAt = "registration_opens_at"
        case registrationClosesAt = "registration_closes_at"
        case maxParticipants = "max_participants"
        case sponsorName = "sponsor_name"
        case sponsorLogoUrl = "sponsor_logo_url"
        case bannerImageUrl = "banner_image_url"
        case primaryColor = "primary_color"
        case accentColor = "accent_color"
        case isFeatured = "is_featured"
        case participantCount = "participant_count"
        case isRegistered = "is_registered"
        case yourBestTimeSeconds = "your_best_time_seconds"
        case yourTotalDistanceKm = "your_total_distance_km"
    }

    var typeLabel: String {
        switch eventType {
        case "race": return "Race"
        case "virtual_race": return "Virtual Race"
        case "group_run": return "Group Run"
        default: return "Event"
        }
    }

    var typeIcon: String {
        switch eventType {
        case "race": return "flag.checkered"
        case "virtual_race": return "globe"
        case "group_run": return "person.3"
        default: return "calendar"
        }
    }

    var parsedStartDate: Date? {
        ISO8601DateFormatter().date(from: startsAt)
    }

    var parsedEndDate: Date? {
        ISO8601DateFormatter().date(from: endsAt)
    }

    var timeRemaining: String {
        guard let endDate = parsedEndDate else { return "" }
        let now = Date()
        if endDate < now { return "Ended" }

        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
        if let days = components.day, days > 0 {
            return "\(days)d \(components.hour ?? 0)h left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h \(components.minute ?? 0)m left"
        }
        return "\(components.minute ?? 0)m left"
    }

    var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let start = parsedStartDate, let end = parsedEndDate else { return "" }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    var parsedPrimaryColor: Color? {
        guard let hex = primaryColor else { return nil }
        return Color(hex: hex)
    }

    var parsedAccentColor: Color? {
        guard let hex = accentColor else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - Event Detail Response

struct EventDetailResponse: Codable {
    let id: String
    let title: String
    let description: String?
    let eventType: String
    let distanceCategory: String?
    let distanceKm: Double?
    let startsAt: String
    let endsAt: String
    let registrationOpensAt: String?
    let registrationClosesAt: String?
    let maxParticipants: Int?
    let sponsorName: String?
    let sponsorLogoUrl: String?
    let bannerImageUrl: String?
    let primaryColor: String?
    let accentColor: String?
    let isFeatured: Bool
    let participantCount: Int
    let isRegistered: Bool
    let yourBestTimeSeconds: Int?
    let yourTotalDistanceKm: Double?
    let leaderboard: [LeaderboardEntry]

    enum CodingKeys: String, CodingKey {
        case id, title, description, leaderboard
        case eventType = "event_type"
        case distanceCategory = "distance_category"
        case distanceKm = "distance_km"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case registrationOpensAt = "registration_opens_at"
        case registrationClosesAt = "registration_closes_at"
        case maxParticipants = "max_participants"
        case sponsorName = "sponsor_name"
        case sponsorLogoUrl = "sponsor_logo_url"
        case bannerImageUrl = "banner_image_url"
        case primaryColor = "primary_color"
        case accentColor = "accent_color"
        case isFeatured = "is_featured"
        case participantCount = "participant_count"
        case isRegistered = "is_registered"
        case yourBestTimeSeconds = "your_best_time_seconds"
        case yourTotalDistanceKm = "your_total_distance_km"
    }

    var isRace: Bool { eventType == "race" || eventType == "virtual_race" }

    var parsedEndDate: Date? {
        ISO8601DateFormatter().date(from: endsAt)
    }

    var timeRemaining: String {
        guard let endDate = parsedEndDate else { return "" }
        let now = Date()
        if endDate < now { return "Ended" }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
        if let days = components.day, days > 0 {
            return "\(days)d \(components.hour ?? 0)h left"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h \(components.minute ?? 0)m left"
        }
        return "\(components.minute ?? 0)m left"
    }
}

// MARK: - Registration Response

struct EventRegistrationApiResponse: Codable {
    let registered: Bool?
    let error: String?
}

// Color(hex:) is defined in Utilities/Extensions.swift

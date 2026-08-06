import Foundation
import CoreLocation
import os.log

private let routeLog = Logger(subsystem: "com.stride.app", category: "RouteAnalyzer")

// MARK: - Data Types

struct TurnaroundResult {
    let turnaroundIndex: Int
    let turnaroundDistance: Double // meters from start to turnaround
}

struct ElevationSegment {
    let distanceAhead: Double   // meters from current position
    let altitude: Double        // smoothed altitude at this point
}

struct Hill {
    let distanceAhead: Double   // meters to hill start from current position
    let length: Double          // hill length in meters
    let elevationGain: Double   // total gain (positive) or loss (negative for downhill)
    let avgGrade: Double        // average grade as fraction (0.05 = 5%)
    let isUphill: Bool
}

// MARK: - RouteAnalyzer

/// Pure-function geometry utilities for route analysis during outdoor runs.
/// Stateless — all methods are static.
enum RouteAnalyzer {

    // MARK: - Turnaround Detection

    /// Detect if the runner has turned around on an out-and-back route.
    /// Returns the index of the turnaround point, or nil if not detected.
    static func detectTurnaround(routePoints: [RoutePoint], currentIndex: Int) -> TurnaroundResult? {
        // Need enough points to analyze
        guard currentIndex >= 30 else { return nil }
        guard routePoints.count > currentIndex else { return nil }

        // Compute cumulative distance to ensure minimum outbound distance
        let totalDistance = cumulativeDistance(routePoints: routePoints, upTo: currentIndex)
        guard totalDistance >= 500 else { return nil } // minimum 500m before checking

        // Compute dominant heading over the last 200m
        let recentHeading = dominantHeadingTrailing(routePoints: routePoints, endIndex: currentIndex, trailingMeters: 200)
        guard let recent = recentHeading else { return nil }

        // Match the current position to an older point on the same path. Comparing
        // against the route's first heading fails on curved out-and-backs.
        let currentPoint = routePoints[currentIndex]
        let currentCoord = CLLocation(latitude: currentPoint.latitude, longitude: currentPoint.longitude)
        let searchEnd = currentIndex - 30
        guard searchEnd > 1 else { return nil }
        var matchedIndex: Int?
        var matchedDistance = Double.greatestFiniteMagnitude
        for i in stride(from: 0, through: searchEnd, by: 3) {
            let p = routePoints[i]
            let dist = currentCoord.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if dist < matchedDistance {
                matchedDistance = dist
                matchedIndex = i
            }
        }
        guard let match = matchedIndex, matchedDistance < 45 else { return nil }

        let outboundHeading = dominantHeading(
            routePoints: routePoints,
            startIndex: match,
            maxDistanceMeters: 120
        )
        guard let outbound = outboundHeading else { return nil }
        let angleDiff = angularDifference(outbound, recent)
        guard angleDiff > 135 else { return nil }

        // On a retraced route the turnaround lies between the matching outbound
        // and current return samples, even when the route bends around the start.
        let turnaroundIdx = match + (currentIndex - match) / 2

        let turnaroundDist = cumulativeDistance(routePoints: routePoints, upTo: turnaroundIdx)
        routeLog.info("Turnaround detected at index \(turnaroundIdx), distance \(turnaroundDist)m, angle diff \(angleDiff)°")
        return TurnaroundResult(turnaroundIndex: turnaroundIdx, turnaroundDistance: turnaroundDist)
    }

    // MARK: - Elevation Lookahead

    /// On the return leg, match the current position to the closest outbound point,
    /// then project upcoming elevation by walking backward through outbound points.
    /// Returns smoothed elevation segments ahead of the runner.
    static func elevationLookahead(
        outboundPoints: ArraySlice<RoutePoint>,
        currentPosition: RoutePoint,
        lookaheadMeters: Double = 800
    ) -> [ElevationSegment] {
        guard outboundPoints.count >= 10 else { return [] }

        // Find the closest outbound point to current position
        let currentCoord = CLLocation(latitude: currentPosition.latitude, longitude: currentPosition.longitude)
        var bestIndex = outboundPoints.startIndex
        var bestDist = Double.greatestFiniteMagnitude

        // Sample every 3rd point for efficiency, then refine
        for i in stride(from: outboundPoints.startIndex, to: outboundPoints.endIndex, by: 3) {
            let p = outboundPoints[i]
            let d = currentCoord.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }

        // Refine around best match
        let refineStart = max(outboundPoints.startIndex, bestIndex - 3)
        let refineEnd = min(outboundPoints.endIndex, bestIndex + 4)
        for i in refineStart..<refineEnd {
            let p = outboundPoints[i]
            let d = currentCoord.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }

        // If closest match is too far away, we've deviated from the outbound path
        guard bestDist < 150 else { return [] }

        // Walk backward from match point toward start, accumulating distance and altitude
        var segments: [ElevationSegment] = []
        var accumulatedDistance: Double = 0

        var i = bestIndex - 1
        while i >= outboundPoints.startIndex && accumulatedDistance < lookaheadMeters {
            let curr = outboundPoints[i]
            let next = outboundPoints[i + 1]
            let segDist = haversineDistance(
                lat1: curr.latitude, lon1: curr.longitude,
                lat2: next.latitude, lon2: next.longitude
            )
            accumulatedDistance += segDist
            segments.append(ElevationSegment(distanceAhead: accumulatedDistance, altitude: curr.altitude))
            i -= 1
        }

        // Drop GPS altitude spikes (jumps > 15m vs neighbors) before smoothing,
        // otherwise the moving average can be pulled off a real grade by a single bad sample.
        let despiked = despikeElevation(segments: segments, maxDeltaMeters: 15)
        return smoothElevation(segments: despiked, windowMeters: 50)
    }

    /// Replace altitude outliers (> maxDeltaMeters from the median of immediate neighbors)
    /// with the neighbor median. Keeps distance-ahead untouched.
    private static func despikeElevation(segments: [ElevationSegment], maxDeltaMeters: Double) -> [ElevationSegment] {
        guard segments.count >= 3 else { return segments }
        var cleaned = segments
        for i in 1..<(segments.count - 1) {
            let prev = segments[i - 1].altitude
            let next = segments[i + 1].altitude
            let neighborMedian = (prev + next) / 2
            if abs(segments[i].altitude - neighborMedian) > maxDeltaMeters {
                cleaned[i] = ElevationSegment(
                    distanceAhead: segments[i].distanceAhead,
                    altitude: neighborMedian
                )
            }
        }
        return cleaned
    }

    // MARK: - Hill Detection

    /// Detect significant hills from an elevation lookahead profile.
    /// A hill is a sustained grade >= minGrade over >= minLength with >= minGain elevation change.
    /// Uses net elevation over a distance window rather than requiring every GPS
    /// sample to exceed the grade threshold. This resists brief flats and noise.
    static func detectHills(
        in segments: [ElevationSegment],
        minGrade: Double = 0.025,
        minLength: Double = 70,
        minGain: Double = 4
    ) -> [Hill] {
        guard segments.count >= 2 else { return [] }

        var candidates: [Hill] = []
        for start in 0..<(segments.count - 1) {
            for end in (start + 1)..<segments.count {
                let length = segments[end].distanceAhead - segments[start].distanceAhead
                guard length >= minLength else { continue }
                let change = segments[end].altitude - segments[start].altitude
                let grade = change / length
                if abs(change) >= minGain && abs(grade) >= minGrade {
                    candidates.append(Hill(
                        distanceAhead: segments[start].distanceAhead,
                        length: length,
                        elevationGain: abs(change),
                        avgGrade: abs(grade),
                        isUphill: change > 0
                    ))
                }
                break
            }
        }

        // Collapse overlapping windows, retaining the strongest representative.
        var merged: [Hill] = []
        for candidate in candidates {
            if let last = merged.last,
               last.isUphill == candidate.isUphill,
               candidate.distanceAhead <= last.distanceAhead + last.length {
                if candidate.avgGrade > last.avgGrade { merged[merged.count - 1] = candidate }
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }

    // MARK: - Geometry Helpers

    /// Haversine distance between two coordinates in meters.
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// Bearing from point 1 to point 2 in degrees (0-360).
    private static func bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLon = (lon2 - lon1) * .pi / 180
        let lat1r = lat1 * .pi / 180
        let lat2r = lat2 * .pi / 180
        let y = sin(dLon) * cos(lat2r)
        let x = cos(lat1r) * sin(lat2r) - sin(lat1r) * cos(lat2r) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Angular difference between two headings (0-180 degrees).
    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    /// Compute the dominant heading over the first `maxDistanceMeters` of the route.
    private static func dominantHeading(routePoints: [RoutePoint], startIndex: Int, maxDistanceMeters: Double) -> Double? {
        var dist: Double = 0
        var endIndex = startIndex

        for i in (startIndex + 1)..<routePoints.count {
            let prev = routePoints[i - 1]
            let curr = routePoints[i]
            dist += haversineDistance(lat1: prev.latitude, lon1: prev.longitude, lat2: curr.latitude, lon2: curr.longitude)
            endIndex = i
            if dist >= maxDistanceMeters { break }
        }

        guard endIndex > startIndex else { return nil }
        let start = routePoints[startIndex]
        let end = routePoints[endIndex]
        return bearing(lat1: start.latitude, lon1: start.longitude, lat2: end.latitude, lon2: end.longitude)
    }

    /// Compute the dominant heading over the trailing `trailingMeters` ending at `endIndex`.
    private static func dominantHeadingTrailing(routePoints: [RoutePoint], endIndex: Int, trailingMeters: Double) -> Double? {
        var dist: Double = 0
        var startIdx = endIndex

        var i = endIndex
        while i > 0 && dist < trailingMeters {
            let curr = routePoints[i]
            let prev = routePoints[i - 1]
            dist += haversineDistance(lat1: prev.latitude, lon1: prev.longitude, lat2: curr.latitude, lon2: curr.longitude)
            startIdx = i - 1
            i -= 1
        }

        guard startIdx < endIndex else { return nil }
        let start = routePoints[startIdx]
        let end = routePoints[endIndex]
        return bearing(lat1: start.latitude, lon1: start.longitude, lat2: end.latitude, lon2: end.longitude)
    }

    /// Cumulative distance along route points up to the given index.
    static func cumulativeDistance(routePoints: [RoutePoint], upTo index: Int) -> Double {
        var dist: Double = 0
        for i in 1...min(index, routePoints.count - 1) {
            let prev = routePoints[i - 1]
            let curr = routePoints[i]
            dist += haversineDistance(lat1: prev.latitude, lon1: prev.longitude, lat2: curr.latitude, lon2: curr.longitude)
        }
        return dist
    }

    /// Smooth elevation segments with a distance-based moving average.
    private static func smoothElevation(segments: [ElevationSegment], windowMeters: Double) -> [ElevationSegment] {
        guard segments.count >= 3 else { return segments }

        var smoothed: [ElevationSegment] = []
        for i in 0..<segments.count {
            let centerDist = segments[i].distanceAhead
            var sumAlt: Double = 0
            var count: Double = 0

            for j in 0..<segments.count {
                if abs(segments[j].distanceAhead - centerDist) <= windowMeters / 2 {
                    sumAlt += segments[j].altitude
                    count += 1
                }
            }

            smoothed.append(ElevationSegment(
                distanceAhead: centerDist,
                altitude: count > 0 ? sumAlt / count : segments[i].altitude
            ))
        }
        return smoothed
    }
}

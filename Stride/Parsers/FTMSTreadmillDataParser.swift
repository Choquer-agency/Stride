import Foundation

/// Parser for FTMS Treadmill Data characteristic (0x2ACD)
/// Based on Bluetooth FTMS specification v1.0
struct FTMSTreadmillDataParser {
    
    /// Parse FTMS 0x2ACD characteristic data
    static func parse(data: Data, timestamp: Date = Date()) -> ParsedTreadmillSample {
        let rawHex = data.map { String(format: "%02x", $0) }.joined()
        
        guard data.count >= 2 else {
            return ParsedTreadmillSample(
                timestamp: timestamp,
                rawHex: rawHex,
                flags: 0,
                instantaneousSpeedKmh: nil,
                averageSpeedKmh: nil,
                totalDistanceMeters: nil,
                inclinationPercent: nil,
                rampAngleDegrees: nil,
                positiveElevationGain: nil,
                negativeElevationGain: nil,
                instantaneousPace: nil,
                averagePace: nil,
                totalEnergy: nil,
                energyPerHour: nil,
                energyPerMinute: nil,
                heartRate: nil,
                metabolicEquivalent: nil,
                elapsedTime: nil,
                remainingTime: nil
            )
        }
        
        // Read flags (first 2 bytes, little-endian)
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        
        var offset = 2
        
        // Parse fields based on flags
        var instantaneousSpeed: Double? = nil
        var averageSpeed: Double? = nil
        var totalDistance: Double? = nil
        var inclination: Double? = nil
        var rampAngle: Double? = nil
        var positiveElevation: Double? = nil
        var negativeElevation: Double? = nil
        var instantaneousPace: Double? = nil
        var averagePace: Double? = nil
        var totalEnergy: Int? = nil
        var energyPerHour: Int? = nil
        var energyPerMinute: Int? = nil
        var heartRate: Int? = nil
        var metabolicEquivalent: Double? = nil
        var elapsedTime: Int? = nil
        var remainingTime: Int? = nil
        
        // Bit 0: More Data (if 0, instantaneous speed is present)
        if (flags & 0x0001) == 0 {
            if offset + 2 <= data.count {
                let rawValue = readUInt16(data, offset: offset)
                instantaneousSpeed = Double(rawValue) * 0.01 // 0.01 km/h resolution
                offset += 2
            }
        }
        
        // Bit 1: Average Speed Present
        if (flags & 0x0002) != 0 {
            if offset + 2 <= data.count {
                let rawValue = readUInt16(data, offset: offset)
                averageSpeed = Double(rawValue) * 0.01
                offset += 2
            }
        }
        
        // Bit 2: Total Distance Present
        if (flags & 0x0004) != 0 {
            if offset + 3 <= data.count {
                let rawValue = readUInt24(data, offset: offset)
                totalDistance = Double(rawValue) // 1 meter resolution
                offset += 3
            }
        }
        
        // Bit 3: Inclination and Ramp Angle Setting Present
        if (flags & 0x0008) != 0 {
            if offset + 4 <= data.count {
                let inclinationRaw = readInt16(data, offset: offset)
                inclination = Double(inclinationRaw) * 0.1 // 0.1% resolution
                offset += 2
                
                let rampRaw = readInt16(data, offset: offset)
                rampAngle = Double(rampRaw) * 0.1 // 0.1 degree resolution
                offset += 2
            }
        }
        
        // Bit 4: Elevation Gain Present
        if (flags & 0x0010) != 0 {
            if offset + 4 <= data.count {
                let posElevRaw = readUInt16(data, offset: offset)
                positiveElevation = Double(posElevRaw) // 1 meter resolution
                offset += 2
                
                let negElevRaw = readUInt16(data, offset: offset)
                negativeElevation = Double(negElevRaw)
                offset += 2
            }
        }
        
        // Bit 5: Instantaneous Pace Present
        if (flags & 0x0020) != 0 {
            if offset + 1 <= data.count {
                let paceRaw = data[offset]
                instantaneousPace = Double(paceRaw) // seconds per km
                offset += 1
            }
        }
        
        // Bit 6: Average Pace Present
        if (flags & 0x0040) != 0 {
            if offset + 1 <= data.count {
                let avgPaceRaw = data[offset]
                averagePace = Double(avgPaceRaw)
                offset += 1
            }
        }
        
        // Bit 7: Expended Energy Present
        if (flags & 0x0080) != 0 {
            if offset + 2 <= data.count {
                totalEnergy = Int(readUInt16(data, offset: offset)) // kcal
                offset += 2
            }
            if offset + 2 <= data.count {
                energyPerHour = Int(readUInt16(data, offset: offset))
                offset += 2
            }
            if offset + 1 <= data.count {
                energyPerMinute = Int(data[offset])
                offset += 1
            }
        }
        
        // Bit 8: Heart Rate Present
        if (flags & 0x0100) != 0 {
            if offset + 1 <= data.count {
                heartRate = Int(data[offset])
                offset += 1
            }
        }
        
        // Bit 9: Metabolic Equivalent Present
        if (flags & 0x0200) != 0 {
            if offset + 1 <= data.count {
                let metRaw = data[offset]
                metabolicEquivalent = Double(metRaw) * 0.1
                offset += 1
            }
        }
        
        // Bit 10: Elapsed Time Present
        if (flags & 0x0400) != 0 {
            if offset + 2 <= data.count {
                elapsedTime = Int(readUInt16(data, offset: offset)) // seconds
                offset += 2
            }
        }
        
        // Bit 11: Remaining Time Present
        if (flags & 0x0800) != 0 {
            if offset + 2 <= data.count {
                remainingTime = Int(readUInt16(data, offset: offset))
                offset += 2
            }
        }
        
        return ParsedTreadmillSample(
            timestamp: timestamp,
            rawHex: rawHex,
            flags: flags,
            instantaneousSpeedKmh: instantaneousSpeed,
            averageSpeedKmh: averageSpeed,
            totalDistanceMeters: totalDistance,
            inclinationPercent: inclination,
            rampAngleDegrees: rampAngle,
            positiveElevationGain: positiveElevation,
            negativeElevationGain: negativeElevation,
            instantaneousPace: instantaneousPace,
            averagePace: averagePace,
            totalEnergy: totalEnergy,
            energyPerHour: energyPerHour,
            energyPerMinute: energyPerMinute,
            heartRate: heartRate,
            metabolicEquivalent: metabolicEquivalent,
            elapsedTime: elapsedTime,
            remainingTime: remainingTime
        )
    }
    
    // MARK: - Helper Functions
    
    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private static func readInt16(_ data: Data, offset: Int) -> Int16 {
        let unsigned = readUInt16(data, offset: offset)
        return Int16(bitPattern: unsigned)
    }
    
    private static func readUInt24(_ data: Data, offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16)
    }
}


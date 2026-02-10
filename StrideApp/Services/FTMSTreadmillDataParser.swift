import Foundation

struct FTMSTreadmillDataParser {

    static func parse(data: Data, timestamp: Date = Date()) -> ParsedTreadmillSample {
        let rawHex = data.map { String(format: "%02x", $0) }.joined()

        guard data.count >= 2 else {
            return ParsedTreadmillSample(
                timestamp: timestamp, rawHex: rawHex, flags: 0,
                instantaneousSpeedKmh: nil, averageSpeedKmh: nil,
                totalDistanceMeters: nil, inclinationPercent: nil,
                rampAngleDegrees: nil, positiveElevationGain: nil,
                negativeElevationGain: nil, instantaneousPace: nil,
                averagePace: nil, totalEnergy: nil, energyPerHour: nil,
                energyPerMinute: nil, heartRate: nil,
                metabolicEquivalent: nil, elapsedTime: nil, remainingTime: nil
            )
        }

        // --- Read 2-byte flags (little-endian) ---
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

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

        // ---------------------------------------------------------------
        // Bit 0: "More Data" -- INVERTED LOGIC
        //   Flag = 0 -> Instantaneous Speed IS present (2 bytes, UInt16)
        //   Flag = 1 -> Instantaneous Speed is NOT present
        // ---------------------------------------------------------------
        if (flags & 0x0001) == 0 {
            if offset + 2 <= data.count {
                let raw = readUInt16(data, offset: offset)
                instantaneousSpeed = Double(raw) * 0.01  // resolution: 0.01 km/h
                offset += 2
            }
        }

        // Bit 1: Average Speed (2 bytes, UInt16, 0.01 km/h)
        if (flags & 0x0002) != 0 {
            if offset + 2 <= data.count {
                let raw = readUInt16(data, offset: offset)
                averageSpeed = Double(raw) * 0.01
                offset += 2
            }
        }

        // Bit 2: Total Distance (3 bytes, UInt24, 1 meter)
        if (flags & 0x0004) != 0 {
            if offset + 3 <= data.count {
                let raw = readUInt24(data, offset: offset)
                totalDistance = Double(raw)  // 1 meter resolution
                offset += 3
            }
        }

        // Bit 3: Inclination (Int16, 0.1%) + Ramp Angle (Int16, 0.1 deg)
        if (flags & 0x0008) != 0 {
            if offset + 4 <= data.count {
                let incRaw = readInt16(data, offset: offset)
                inclination = Double(incRaw) * 0.1
                offset += 2
                let rampRaw = readInt16(data, offset: offset)
                rampAngle = Double(rampRaw) * 0.1
                offset += 2
            }
        }

        // Bit 4: Positive Elevation Gain (UInt16, 1m) + Negative (UInt16, 1m)
        if (flags & 0x0010) != 0 {
            if offset + 4 <= data.count {
                positiveElevation = Double(readUInt16(data, offset: offset))
                offset += 2
                negativeElevation = Double(readUInt16(data, offset: offset))
                offset += 2
            }
        }

        // Bit 5: Instantaneous Pace (1 byte, UInt8, sec/km)
        if (flags & 0x0020) != 0 {
            if offset + 1 <= data.count {
                instantaneousPace = Double(data[offset])
                offset += 1
            }
        }

        // Bit 6: Average Pace (1 byte, UInt8, sec/km)
        if (flags & 0x0040) != 0 {
            if offset + 1 <= data.count {
                averagePace = Double(data[offset])
                offset += 1
            }
        }

        // Bit 7: Expended Energy -- 3 sub-fields
        //   Total Energy (UInt16, kcal)
        //   Energy per Hour (UInt16, kcal/h)
        //   Energy per Minute (UInt8, kcal/min)
        if (flags & 0x0080) != 0 {
            if offset + 2 <= data.count {
                totalEnergy = Int(readUInt16(data, offset: offset))
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

        // Bit 8: Heart Rate (1 byte, UInt8, bpm)
        if (flags & 0x0100) != 0 {
            if offset + 1 <= data.count {
                heartRate = Int(data[offset])
                offset += 1
            }
        }

        // Bit 9: Metabolic Equivalent (1 byte, UInt8, 0.1 MET)
        if (flags & 0x0200) != 0 {
            if offset + 1 <= data.count {
                metabolicEquivalent = Double(data[offset]) * 0.1
                offset += 1
            }
        }

        // Bit 10: Elapsed Time (2 bytes, UInt16, seconds)
        if (flags & 0x0400) != 0 {
            if offset + 2 <= data.count {
                elapsedTime = Int(readUInt16(data, offset: offset))
                offset += 2
            }
        }

        // Bit 11: Remaining Time (2 bytes, UInt16, seconds)
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

    // MARK: - Byte Reading Helpers (Little-Endian)

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readInt16(_ data: Data, offset: Int) -> Int16 {
        return Int16(bitPattern: readUInt16(data, offset: offset))
    }

    private static func readUInt24(_ data: Data, offset: Int) -> UInt32 {
        return UInt32(data[offset])
             | (UInt32(data[offset + 1]) << 8)
             | (UInt32(data[offset + 2]) << 16)
    }
}

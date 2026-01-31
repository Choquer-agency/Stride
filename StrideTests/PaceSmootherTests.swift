import XCTest
@testable import Stride

/// Test cases for PaceSmoother to verify it handles erratic treadmill data
class PaceSmootherTests: XCTestCase {
    
    func testSmootherReducesFluctuations() {
        let smoother = PaceSmoother()
        
        // Simulate erratic treadmill data bouncing between slow and fast
        // (like the issue described: 13 min/km to 28 sec/km)
        let speeds: [Double] = [
            2.0,  // Normal walking speed (2 m/s = 8:20 min/km pace)
            0.06, // Glitch: Very slow (28 min/km pace)
            2.0,  // Back to normal
            30.0, // Glitch: Very fast (2:00 min/km pace)
            2.0,  // Back to normal
            0.05, // Another glitch
            2.0   // Back to normal
        ]
        
        var smoothedPaces: [Double] = []
        
        for speed in speeds {
            let result = smoother.addSample(speedMps: speed)
            smoothedPaces.append(result.smoothedPace)
            print("Raw speed: \(speed) m/s → Smoothed pace: \(result.smoothedPace) sec/km")
        }
        
        // Verify smoothing behavior:
        // 1. Smoothed pace should not have extreme jumps
        for i in 1..<smoothedPaces.count {
            let change = abs(smoothedPaces[i] - smoothedPaces[i-1])
            let percentChange = (change / smoothedPaces[i-1]) * 100
            
            // Smoothed pace should not change more than 50% between samples
            // (raw data can change by 1000%+)
            XCTAssertLessThan(percentChange, 50, 
                "Pace changed too drastically: \(smoothedPaces[i-1]) → \(smoothedPaces[i])")
        }
        
        // 2. Very low speeds should be filtered out (return previous value)
        // The smoother should maintain a reasonable pace when encountering glitches
        let finalPace = smoothedPaces.last ?? 0
        XCTAssertGreaterThan(finalPace, 400) // Should be reasonable walking pace (not glitched)
        XCTAssertLessThan(finalPace, 700)    // Should be in normal walking range
    }
    
    func testSmootherHandlesConsistentSpeed() {
        let smoother = PaceSmoother()
        
        // Consistent speed should stabilize quickly
        let consistentSpeed = 3.0 // 5:33 min/km pace
        let expectedPace = 1000.0 / consistentSpeed
        
        var result = (smoothedPace: 0.0, smoothedSpeed: 0.0)
        
        // Feed 10 consistent samples
        for _ in 0..<10 {
            result = smoother.addSample(speedMps: consistentSpeed)
        }
        
        // After 10 samples, should be very close to actual pace
        let paceError = abs(result.smoothedPace - expectedPace)
        XCTAssertLessThan(paceError, 10, "Smoothed pace should converge to actual pace")
    }
    
    func testSmootherFiltersLowSpeeds() {
        let smoother = PaceSmoother()
        
        // Add a valid sample first
        let validResult = smoother.addSample(speedMps: 2.5)
        XCTAssertGreaterThan(validResult.smoothedPace, 0)
        
        // Now add an invalid low speed
        let invalidResult = smoother.addSample(speedMps: 0.05)
        
        // Should return the previous valid pace, not calculate from the low speed
        XCTAssertEqual(invalidResult.smoothedPace, validResult.smoothedPace,
                      "Low speed should not update the smoothed pace")
    }
    
    func testSmootherReset() {
        let smoother = PaceSmoother()
        
        // Add samples
        _ = smoother.addSample(speedMps: 2.0)
        _ = smoother.addSample(speedMps: 2.5)
        
        // Reset
        smoother.reset()
        
        // After reset, should start fresh
        let result = smoother.getCurrentSmoothed()
        XCTAssertEqual(result.smoothedPace, 0, "After reset, pace should be 0")
        XCTAssertEqual(result.smoothedSpeed, 0, "After reset, speed should be 0")
    }
}




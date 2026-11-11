import Foundation

/// Wraps the existing BluetoothManager to conform to RunDataProvider.
/// Converts ParsedTreadmillSample → RunSample for the unified RunViewModel pipeline.
final class BluetoothRunDataProvider: RunDataProvider {
    var onRunSample: ((RunSample) -> Void)?
    let dataSourceType: String = "bluetooth_ftms"

    var deviceName: String? {
        bluetoothManager.connectedDevice?.name
    }

    private let bluetoothManager: BluetoothManager
    private var previousDistance: Double?
    private var workoutDistance: Double = 0
    private var paused = false

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    func start() {
        TreadmillRawCapture.shared.begin(deviceName: deviceName)
        previousDistance = bluetoothManager.latestDistanceMeters
        workoutDistance = 0
        paused = false
        bluetoothManager.onTreadmillData = { [weak self] sample in
            guard let self else { return }
            if let total = sample.totalDistanceMeters {
                if !self.paused, let previous = self.previousDistance, total >= previous {
                    self.workoutDistance += total - previous
                }
                // Console resets rebase the odometer without erasing the workout.
                self.previousDistance = total
            }
            guard !self.paused else { return }
            let runSample = RunSample(
                timestamp: sample.timestamp,
                speedMps: sample.speedMps,
                totalDistanceMeters: sample.totalDistanceMeters == nil ? nil : self.workoutDistance,
                elapsedTime: sample.elapsedTime.map { TimeInterval($0) },
                heartRate: sample.heartRate,
                coordinate: nil,
                altitudeMeters: nil
            )
            self.onRunSample?(runSample)
        }
    }

    func stop() {
        TreadmillRawCapture.shared.end()
        previousDistance = bluetoothManager.latestDistanceMeters
        workoutDistance = 0
        paused = false
        bluetoothManager.onTreadmillData = nil
    }

    func pause() {
        paused = true
    }

    func resume() {
        previousDistance = bluetoothManager.latestDistanceMeters
        paused = false
    }
}

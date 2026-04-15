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

    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    func start() {
        bluetoothManager.onTreadmillData = { [weak self] sample in
            guard let self else { return }
            let runSample = RunSample(
                timestamp: sample.timestamp,
                speedMps: sample.speedMps,
                totalDistanceMeters: sample.totalDistanceMeters,
                elapsedTime: sample.elapsedTime.map { TimeInterval($0) },
                heartRate: sample.heartRate,
                coordinate: nil,
                altitudeMeters: nil
            )
            self.onRunSample?(runSample)
        }
    }

    func stop() {
        bluetoothManager.onTreadmillData = nil
    }

    func pause() {
        // Treadmill controls its own pacing — no-op
    }

    func resume() {
        // Treadmill controls its own pacing — no-op
    }
}

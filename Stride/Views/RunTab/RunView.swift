import SwiftUI

/// Main run screen - shows scan view or workout view
struct RunView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var workoutManager: WorkoutManager
    @State private var showingSummary = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if workoutManager.isRecording && workoutManager.isBaselineTest {
                    // Show baseline test workout view
                    BaselineTestWorkoutView(
                        workoutManager: workoutManager,
                        baselineManager: BaselineAssessmentManager(
                            storageManager: workoutManager.storageManager,
                            hrZonesManager: HeartRateZonesManager()
                        ),
                        goalDistance: nil // Could be passed from goal context
                    )
                } else if workoutManager.isRecording {
                    // Show normal live workout
                    LiveWorkoutView(workoutManager: workoutManager)
                } else if let session = workoutManager.currentSession, !workoutManager.isRecording {
                    // Show summary after workout
                    WorkoutSummaryView(session: session, workoutManager: workoutManager)
                } else if bluetoothManager.connectedDevice != nil {
                    // Connected but not recording
                    connectedView
                } else {
                    // Not connected - show scanning message
                    scanningView
                }
            }
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Connection status indicator
                    if !workoutManager.isRecording && workoutManager.currentSession == nil {
                        Circle()
                            .fill(bluetoothManager.connectedDevice != nil ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !workoutManager.isRecording && workoutManager.currentSession == nil {
                        Button("Test") {
                            workoutManager.startTestWorkout()
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onAppear {
                // Auto-connect to system-paired device when view appears if not connected
                if bluetoothManager.connectedDevice == nil {
                    bluetoothManager.connectToSystemPairedDevice()
                }
            }
            .onDisappear {
                // Stop any manual scanning if user navigates away
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                }
            }
        }
    }
    
    private var connectedView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Connection status
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.stridePrimary)
                
                Text("Ready to run")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let device = bluetoothManager.connectedDevice {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // FTMS status warning
            if !bluetoothManager.isFTMSSupported {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("This device does not expose FTMS treadmill data")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            
            // Start running button
            Button(action: {
                workoutManager.startWorkout()
            }) {
                Text("Start running")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(bluetoothManager.isFTMSSupported ? .stridePrimary : Color.gray)
                    .foregroundColor(.strideBlack)
                    .cornerRadius(16)
            }
            .disabled(!bluetoothManager.isFTMSSupported)
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private var scanningView: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                Spacer()
                
                VStack(spacing: 16) {
                    // Stride logo at 30% screen width
                    Image("StrideLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width * 0.3)
                        .foregroundColor(BrandAssets.brandPrimary)
                    
                    Text("Assault Runner Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    Text("To connect your Assault Runner:")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text("1.")
                                .fontWeight(.semibold)
                            Text("Open Settings > Bluetooth on your iPhone")
                        }
                        HStack(alignment: .top) {
                            Text("2.")
                                .fontWeight(.semibold)
                            Text("Turn on your Assault Runner and press the Bluetooth button")
                        }
                        HStack(alignment: .top) {
                            Text("3.")
                                .fontWeight(.semibold)
                            Text("Pair it in your iPhone's Bluetooth settings")
                        }
                        HStack(alignment: .top) {
                            Text("4.")
                                .fontWeight(.semibold)
                            Text("Return to this app - it will connect automatically")
                        }
                    }
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                }
                .multilineTextAlignment(.leading)
                
                Button(action: {
                    bluetoothManager.connectToSystemPairedDevice()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Connection")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.stridePrimary)
                    .foregroundColor(.strideBlack)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                }
                
                Spacer()
            }
        }
    }
}


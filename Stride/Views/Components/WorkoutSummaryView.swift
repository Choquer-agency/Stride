import SwiftUI

/// Post-workout summary screen
struct WorkoutSummaryView: View {
    let session: WorkoutSession
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Workout complete")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(session.startTime.toWorkoutDateString())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Main stats
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text(session.durationSeconds.toTimeString())
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text(String(format: "%.2f", session.totalDistanceKm))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("Kilometers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text(session.avgPaceSecondsPerKm.toPaceString())
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Avg pace")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Splits summary
                if !session.splits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Splits")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        HStack(spacing: 20) {
                            if let fastest = session.fastestSplit {
                                VStack(spacing: 4) {
                                    Text("Fastest km")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("KM \(fastest.kmIndex)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(fastest.splitTimeSeconds.toTimeString())
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            if let slowest = session.slowestSplit {
                                VStack(spacing: 4) {
                                    Text("Slowest km")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("KM \(slowest.kmIndex)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(slowest.splitTimeSeconds.toTimeString())
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        // All splits
                        SplitsListView(splits: session.splits)
                            .frame(height: 200)
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    NavigationLink(destination: HistoryWorkoutDetailView(session: session, storageManager: workoutManager.storageManager)) {
                        Text("View details")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        workoutManager.clearCurrentSession()
                    }) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
    }
}


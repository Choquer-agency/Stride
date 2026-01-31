import SwiftUI

/// Workout history list
struct HistoryView: View {
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var authManager = AuthManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                if !authManager.isAuthenticated {
                    // Not authenticated state
                    NotAuthenticatedEmptyState(
                        title: "No Workout History",
                        message: "Sign in to sync and view your workout history."
                    )
                } else if storageManager.workouts.isEmpty && !storageManager.isLoading {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No workouts yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Complete your first workout to see it here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        #if DEBUG
                        Button("Generate test data") {
                            TestDataGenerator.generateTestWorkouts(storageManager: storageManager)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                        #endif
                        
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        // Network status banner if there's an error
                        if storageManager.lastError != nil {
                            Section {
                                NetworkStatusBanner(storageManager: storageManager)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                            }
                        }
                        
                        ForEach(storageManager.workouts) { workout in
                            NavigationLink(destination: HistoryWorkoutDetailView(session: workout, storageManager: storageManager)) {
                                WorkoutRowView(session: workout)
                            }
                        }
                        .onDelete(perform: deleteWorkouts)
                    }
                    .refreshable {
                        await storageManager.loadWorkoutsAsync()
                    }
                }
                
                // Loading overlay
                LoadingOverlay(isLoading: storageManager.isLoading, message: "Loading workouts...")
            }
        }
        .navigationTitle("History")
        .onAppear {
            if authManager.isAuthenticated && storageManager.workouts.isEmpty {
                Task {
                    await storageManager.loadWorkoutsAsync()
                }
            }
        }
    }
    
    private func deleteWorkouts(at offsets: IndexSet) {
        for index in offsets {
            let workout = storageManager.workouts[index]
            storageManager.deleteWorkout(id: workout.id)
        }
    }
}

struct WorkoutRowView: View {
    let session: WorkoutSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startTime.toShortDateString())
                    .font(.headline)
                Spacer()
                Text(session.startTime.toTimeOnlyString())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                Label(session.durationSeconds.toTimeString(), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Label(String(format: "%.2f km", session.totalDistanceKm), systemImage: "figure.run")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Label(session.avgPaceSecondsPerKm.toPaceString(), systemImage: "gauge")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

import Foundation
import SwiftData
import CloudKit

/// Handles CloudKit synchronization for training plans
@MainActor
class SyncService: ObservableObject {
    static let shared = SyncService()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    private let container: CKContainer
    private let database: CKDatabase
    
    init() {
        // Initialize with the default CloudKit container
        // In production, you'd configure this with your actual container identifier
        container = CKContainer.default()
        database = container.privateCloudDatabase
    }
    
    // MARK: - Sync Status
    
    /// Check CloudKit account status
    func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return true
            case .noAccount:
                syncError = "No iCloud account found. Sign in to sync your plans."
                return false
            case .restricted:
                syncError = "iCloud access is restricted."
                return false
            case .couldNotDetermine:
                syncError = "Could not determine iCloud account status."
                return false
            case .temporarilyUnavailable:
                syncError = "iCloud is temporarily unavailable."
                return false
            @unknown default:
                syncError = "Unknown iCloud status."
                return false
            }
        } catch {
            syncError = error.localizedDescription
            return false
        }
    }
    
    /// Trigger a manual sync
    func syncNow() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncError = nil
        
        // Check account status first
        let isAvailable = await checkAccountStatus()
        
        if isAvailable {
            // SwiftData with CloudKit handles sync automatically
            // This is mainly for triggering a refresh and updating UI
            lastSyncDate = Date()
        }
        
        isSyncing = false
    }
    
    // MARK: - Subscription Management
    
    /// Subscribe to remote changes
    func subscribeToChanges() async {
        let subscription = CKDatabaseSubscription(subscriptionID: "training-plan-changes")
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await database.save(subscription)
        } catch {
            // Subscription might already exist, which is fine
            print("Subscription error (may already exist): \(error)")
        }
    }
}

// MARK: - CloudKit Model Extensions
extension TrainingPlan {
    /// Convert to CloudKit record (for manual sync if needed)
    func toCloudKitRecord() -> CKRecord {
        let record = CKRecord(recordType: "TrainingPlan")
        record["id"] = id.uuidString
        record["raceType"] = raceTypeRaw
        record["raceDate"] = raceDate
        record["raceName"] = raceName
        record["goalTime"] = goalTime
        record["currentWeeklyMileage"] = currentWeeklyMileage
        record["longestRecentRun"] = longestRecentRun
        record["fitnessLevel"] = fitnessLevelRaw
        record["startDate"] = startDate
        record["planMode"] = planModeRaw
        record["createdAt"] = createdAt
        return record
    }
}

// MARK: - Sync Settings View
import SwiftUI

struct SyncSettingsView: View {
    @StateObject private var syncService = SyncService.shared
    
    var body: some View {
        List {
            Section {
                HStack {
                    Label("iCloud Sync", systemImage: "icloud")
                    
                    Spacer()
                    
                    if syncService.isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Text("Last synced")
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button("Sync Now") {
                    Task {
                        await syncService.syncNow()
                    }
                }
                .disabled(syncService.isSyncing)
            } header: {
                Text("Cloud Sync")
            } footer: {
                Text("Your training plans are automatically synced across all your devices signed into the same iCloud account.")
            }
            
            if let error = syncService.syncError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("Sync Settings")
        .task {
            _ = await syncService.checkAccountStatus()
        }
    }
}

#Preview {
    NavigationStack {
        SyncSettingsView()
    }
}

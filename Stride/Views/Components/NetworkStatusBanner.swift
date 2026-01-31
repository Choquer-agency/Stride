import SwiftUI

/// Banner view that shows network/database connection status
struct NetworkStatusBanner: View {
    @ObservedObject var storageManager: StorageManager
    
    var body: some View {
        if !NeonClient.shared.isConfigured {
            notConfiguredBanner
        } else if let error = storageManager.lastError {
            errorBanner(error: error)
        } else if storageManager.isLoading {
            loadingBanner
        }
    }
    
    private var notConfiguredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud Storage Not Configured")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Go to Settings → Cloud Database to connect")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            NavigationLink(destination: NeonSettingsView()) {
                Text("Setup")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func errorBanner(error: NeonError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Error")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    await storageManager.loadWorkoutsAsync()
                }
            }) {
                Text("Retry")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var loadingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            
            Text("Syncing with cloud...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

/// Overlay view for showing loading state
struct LoadingOverlay: View {
    let isLoading: Bool
    var message: String = "Loading..."
    
    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color(.systemGray3).opacity(0.9))
                .cornerRadius(16)
            }
        }
    }
}

/// Empty state view when no data and not connected
struct CloudNotConfiguredEmptyState: View {
    var title: String = "No Data"
    var message: String = "Connect to Neon cloud database to sync your data."
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            NavigationLink(destination: NeonSettingsView()) {
                Label("Configure Cloud Database", systemImage: "gear")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Connection required wrapper view
struct RequiresCloudConnection<Content: View>: View {
    @ObservedObject var storageManager: StorageManager
    let content: () -> Content
    
    var body: some View {
        if NeonClient.shared.isConfigured {
            content()
        } else {
            CloudNotConfiguredEmptyState()
        }
    }
}

#Preview("Not Configured") {
    NetworkStatusBanner(storageManager: StorageManager())
}

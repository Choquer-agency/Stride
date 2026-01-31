import SwiftUI

/// Banner view that shows network/database connection status
struct NetworkStatusBanner: View {
    @ObservedObject var storageManager: StorageManager
    @ObservedObject var authManager = AuthManager.shared
    
    var body: some View {
        if !authManager.isAuthenticated {
            notAuthenticatedBanner
        } else if let error = storageManager.lastError {
            errorBanner(error: error)
        } else if storageManager.isLoading {
            loadingBanner
        }
    }
    
    private var notAuthenticatedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Not Signed In")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Sign in to sync your data to the cloud")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func errorBanner(error: APIError) -> some View {
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

/// Empty state view when not authenticated
struct NotAuthenticatedEmptyState: View {
    var title: String = "Sign In Required"
    var message: String = "Sign in with Apple to sync your data across devices."
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Connection required wrapper view
struct RequiresAuthentication<Content: View>: View {
    @ObservedObject var authManager = AuthManager.shared
    let content: () -> Content
    
    var body: some View {
        if authManager.isAuthenticated {
            content()
        } else {
            NotAuthenticatedEmptyState()
        }
    }
}

#Preview("Not Authenticated") {
    NetworkStatusBanner(storageManager: StorageManager())
}

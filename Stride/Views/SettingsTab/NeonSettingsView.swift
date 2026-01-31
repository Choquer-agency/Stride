import SwiftUI

/// Settings view for cloud database connection status
struct NeonSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager = AuthManager.shared
    
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Status indicator
                statusSection
                
                // Action buttons
                actionButtonsSection
                
                // Info section
                infoSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Cloud Database")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
            
            Text("Cloud Storage")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your workouts, training plans, and goals are stored securely in the cloud.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    private var statusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(authManager.isAuthenticated ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(authManager.isAuthenticated ? "Connected" : "Not Connected")
                    .font(.headline)
                
                if authManager.isAuthenticated {
                    Text("Your data is syncing to the cloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Sign in with Apple to enable cloud storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if authManager.isAuthenticated {
                // Test connection button
                Button(action: testConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        } else {
                            Image(systemName: "bolt.circle")
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .foregroundColor(.cyan)
                    .cornerRadius(12)
                }
                .disabled(isTesting)
                
                // Sign out button
                Button(action: { authManager.signOut() }) {
                    HStack {
                        Image(systemName: "arrow.right.square")
                        Text("Sign Out")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                }
            } else {
                // Sign in button
                Button(action: { authManager.signInWithApple() }) {
                    HStack {
                        Image(systemName: "applelogo")
                        Text("Sign in with Apple")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            // Test result message
            if let result = testResult {
                HStack {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connection successful!")
                            .foregroundColor(.green)
                    case .failure(let message):
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .foregroundColor(.red)
                    }
                }
                .font(.subheadline)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About Cloud Storage")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                infoRow(icon: "lock.shield", text: "Your data is encrypted and stored securely")
                infoRow(icon: "arrow.triangle.2.circlepath", text: "Syncs automatically across all your devices")
                infoRow(icon: "person.crop.circle.badge.checkmark", text: "Only you can access your data")
                infoRow(icon: "icloud", text: "Powered by Neon PostgreSQL")
            }
        }
        .padding(.top, 16)
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.cyan)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            let isHealthy = await APIClient.shared.healthCheck()
            await MainActor.run {
                testResult = isHealthy ? .success : .failure("Could not connect to server")
                isTesting = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        NeonSettingsView()
    }
}

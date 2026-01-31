import SwiftUI

/// Settings view for Neon database connection configuration
struct NeonSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var connectionString: String = ""
    @State private var isConfigured: Bool = false
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    @State private var showClearAlert: Bool = false
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    init() {
        _isConfigured = State(initialValue: NeonKeyManager.isConfigured)
        if let existing = NeonKeyManager.getMaskedConnectionString() {
            _connectionString = State(initialValue: existing)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Status indicator
                statusSection
                
                // Connection string input
                connectionInputSection
                
                // Action buttons
                actionButtonsSection
                
                // Help section
                helpSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Cloud Database")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear Connection", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearConnection()
            }
        } message: {
            Text("This will remove your Neon connection. Your data will remain in the cloud but the app won't be able to access it until you reconnect.")
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
            
            Text("Neon PostgreSQL")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Connect to Neon to store your workouts, training plans, and goals in the cloud.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    private var statusSection: some View {
        HStack(spacing: 12) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(isConfigured ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(isConfigured ? "Connected" : "Not Connected")
                    .font(.headline)
                
                if isConfigured {
                    Text("Your data is syncing to the cloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Add your connection string to enable cloud storage")
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
    
    private var connectionInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection String")
                .font(.headline)
            
            if isConfigured {
                // Show masked connection string
                HStack {
                    Text(NeonKeyManager.getMaskedConnectionString() ?? "****")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { showClearAlert = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                // Show input field
                TextField("postgresql://user:password@host/database", text: $connectionString)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("Paste your Neon connection string from console.neon.tech")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if !isConfigured {
                // Save button
                Button(action: saveConnection) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle")
                        }
                        Text(isTesting ? "Testing Connection..." : "Save & Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(connectionString.count > 30 ? Color.cyan : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(connectionString.count < 30 || isTesting)
            } else {
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
    
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to Get Your Connection String")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                helpStep(number: 1, text: "Go to console.neon.tech and sign in")
                helpStep(number: 2, text: "Create a project or select an existing one")
                helpStep(number: 3, text: "Click on your database branch")
                helpStep(number: 4, text: "Copy the connection string (starts with postgresql://)")
                helpStep(number: 5, text: "Paste it above and click Save & Connect")
            }
            
            // SQL schema notice
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Database Setup Required")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text("You'll need to run the SQL schema in your Neon console before using cloud storage. The schema file (neon_schema.sql) is included in the app project.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.top, 16)
    }
    
    private func helpStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 20, height: 20)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(10)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func saveConnection() {
        guard NeonKeyManager.validateConnectionString(connectionString) else {
            testResult = .failure("Invalid connection string format. Must be a Neon PostgreSQL URL.")
            return
        }
        
        isTesting = true
        testResult = nil
        
        Task {
            // Save to keychain
            let saved = NeonKeyManager.saveConnectionString(connectionString)
            
            if saved {
                // Test the connection
                do {
                    let success = try await NeonClient.shared.testConnection()
                    await MainActor.run {
                        if success {
                            isConfigured = true
                            testResult = .success
                            // Clear the raw connection string from state
                            connectionString = ""
                        } else {
                            NeonKeyManager.removeConnectionString()
                            testResult = .failure("Connection test failed. Check your credentials.")
                        }
                        isTesting = false
                    }
                } catch let error as NeonError {
                    await MainActor.run {
                        NeonKeyManager.removeConnectionString()
                        testResult = .failure(error.localizedDescription)
                        isTesting = false
                    }
                } catch {
                    await MainActor.run {
                        NeonKeyManager.removeConnectionString()
                        testResult = .failure("Connection failed: \(error.localizedDescription)")
                        isTesting = false
                    }
                }
            } else {
                await MainActor.run {
                    testResult = .failure("Failed to save connection string")
                    isTesting = false
                }
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let success = try await NeonClient.shared.testConnection()
                await MainActor.run {
                    testResult = success ? .success : .failure("Connection test failed")
                    isTesting = false
                }
            } catch let error as NeonError {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure("Error: \(error.localizedDescription)")
                    isTesting = false
                }
            }
        }
    }
    
    private func clearConnection() {
        NeonKeyManager.removeConnectionString()
        isConfigured = false
        connectionString = ""
        testResult = nil
    }
}

#Preview {
    NavigationStack {
        NeonSettingsView()
    }
}

import SwiftUI

/// Settings view for managing AI Coach (ChatGPT API) configuration
struct AICoachSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isKeyValid: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var showingDeleteConfirmation: Bool = false
    @State private var errorMessage: String?
    
    private var isConfigured: Bool {
        SecureKeyManager.isAPIKeyConfigured
    }
    
    private var maskedKey: String? {
        SecureKeyManager.getMaskedAPIKey()
    }
    
    var body: some View {
        List {
            // Status Section
            Section {
                HStack {
                    Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isConfigured ? .green : .red)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Coach Status")
                            .font(.headline)
                        
                        Text(isConfigured ? "Enabled - Using ChatGPT" : "Disabled - API Key Required")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                
                if let masked = maskedKey {
                    HStack {
                        Text("API Key:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(masked)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Current Status")
            }
            
            // Requirement Notice
            if !isConfigured {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key Required")
                                .font(.headline)
                            
                            Text("Training plans require an OpenAI API key. Add your key below to enable AI Coach.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Important")
                }
            }
            
            // Benefits Section
            Section {
                FeatureBullet(
                    icon: "brain",
                    title: "Intelligent Planning",
                    description: "ChatGPT creates progressive, personalized training plans that adapt to your fitness gaps"
                )
                
                FeatureBullet(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Progressive Pacing",
                    description: "Smart pace progressions to bridge the gap between your current fitness and race goals"
                )
                
                FeatureBullet(
                    icon: "sparkles",
                    title: "Race-Specific Training",
                    description: "Includes race pace practice, strides, and workout variety tailored to your distance"
                )
                
                FeatureBullet(
                    icon: "figure.strengthtraining.traditional",
                    title: "Smart Scheduling",
                    description: "Properly spaces strength workouts and avoids common planning mistakes"
                )
            } header: {
                Text("AI Coach Benefits")
            } footer: {
                Text("AI Coach uses GPT-4o to generate complete training plans. API key is stored securely in your device's keychain.")
            }
            
            // Configuration Section
            Section {
                if isConfigured {
                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remove API Key")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter your OpenAI API key from the OpenAI Platform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .onChange(of: apiKey) { oldValue, newValue in
                                isKeyValid = SecureKeyManager.validateAPIKey(newValue)
                                errorMessage = nil
                            }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        Button(action: saveAPIKey) {
                            HStack {
                                Image(systemName: "key.fill")
                                Text("Save API Key")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isKeyValid)
                        
                        Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                            HStack {
                                Image(systemName: "arrow.up.right.square")
                                Text("Get API Key from OpenAI")
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Configuration")
            } footer: {
                if !isConfigured {
                    Text("Sign up at platform.openai.com to get your API key. The key stays on your device and is never shared.")
                }
            }
            
            // Cost Information
            Section {
                HStack {
                    Text("Model:")
                    Spacer()
                    Text("GPT-4o")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Est. Cost per Plan:")
                    Spacer()
                    Text("$0.05 - $0.15")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Tokens per Plan:")
                    Spacer()
                    Text("~6,000 - 10,000")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Usage & Costs")
            } footer: {
                Text("Plans are generated once per goal. Weekly adaptations use rule-based logic (no API cost).")
            }
        }
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .alert("API Key Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your OpenAI API key has been securely saved. AI Coach is now enabled!")
        }
        .alert("Remove API Key?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                SecureKeyManager.removeAPIKey()
                apiKey = ""
                errorMessage = nil
            }
        } message: {
            Text("This will remove your API key and disable AI Coach. You will not be able to generate training plans until you add a new key.")
        }
    }
    
    private func saveAPIKey() {
        guard isKeyValid else {
            errorMessage = "Invalid API key format"
            return
        }
        
        if SecureKeyManager.updateAPIKey(apiKey) {
            showingSaveConfirmation = true
            apiKey = "" // Clear the field
        } else {
            errorMessage = "Failed to save API key. Please try again."
        }
    }
}

struct FeatureBullet: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AICoachSettingsView()
    }
}

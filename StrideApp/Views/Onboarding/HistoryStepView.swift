import SwiftUI

struct HistoryStepView: View {
    @Binding var data: OnboardingData
    @State private var yearsText: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR RUNNING BACKGROUND")
                        .font(.barlowCondensed(size: 28, weight: .bold))
                    
                    Text("Share your experience and any considerations")
                        .font(.inter(size: 14))
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 24) {
                    // Years Running
                    FormField(label: "Years of Running Experience", isRequired: true) {
                        HStack(spacing: 12) {
                            TextField("0", text: $yearsText)
                                .keyboardType(.numberPad)
                                .font(.inter(size: 15))
                                .padding()
                                .frame(width: 70)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onChange(of: yearsText) { _, newValue in
                                    data.yearsRunning = Int(newValue) ?? 0
                                }
                            
                            Text("years")
                                .foregroundStyle(.secondary)
                                .font(.inter(size: 14))
                            
                            Spacer()
                        }
                    }
                    
                    // Experience Level Visual
                    ExperienceLevelIndicator(years: data.yearsRunning)
                    
                    // Previous Injuries
                    FormField(label: "Previous Injuries or Limitations", isRequired: false) {
                        TextEditor(text: $data.previousInjuries)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                Group {
                                    if data.previousInjuries.isEmpty {
                                        Text("e.g., IT band issues in 2024 (fully recovered), prone to calf tightness")
                                            .font(.inter(size: 14))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                            .padding(.top, 16)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                    
                    // Previous Experience
                    FormField(label: "Previous Experience at Goal Distance", isRequired: false) {
                        TextEditor(text: $data.previousExperience)
                            .font(.inter(size: 15))
                            .autocorrectionDisabled()
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                Group {
                                    if data.previousExperience.isEmpty {
                                        Text("e.g., Completed one marathon in 4:15 two years ago")
                                            .font(.inter(size: 14))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                            .padding(.top, 16)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if data.yearsRunning > 0 {
                yearsText = "\(data.yearsRunning)"
            }
        }
    }
}

// MARK: - Experience Level Indicator
struct ExperienceLevelIndicator: View {
    let years: Int
    
    private var level: String {
        switch years {
        case 0: return "Just Starting"
        case 1...2: return "Building Foundation"
        case 3...5: return "Established Runner"
        case 6...10: return "Experienced"
        default: return "Veteran"
        }
    }
    
    private var icon: String {
        switch years {
        case 0: return "leaf"
        case 1...2: return "leaf.fill"
        case 3...5: return "figure.run"
        case 6...10: return "medal"
        default: return "star.fill"
        }
    }
    
    private var progress: Double {
        min(Double(years) / 10.0, 1.0)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.stridePrimary.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.stridePrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(level)
                    .font(.inter(size: 14, weight: .medium))
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemBackground))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(Color.stridePrimary)
                            .frame(width: geometry.size.width * progress, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HistoryStepView(data: .constant(OnboardingData()))
}

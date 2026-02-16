import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject private var authService: AuthService
    let user: UserResponse

    @State private var name: String = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var gender: String = ""
    @State private var heightCm: String = ""
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var showImagePicker = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 8)

                    // Title
                    VStack(spacing: 8) {
                        Text("SET UP YOUR PROFILE")
                            .font(.barlowCondensed(size: 28, weight: .bold))

                        Text("Help us personalize your training")
                            .font(.inter(size: 14))
                            .foregroundStyle(.secondary)
                    }

                    // Photo picker
                    Button { showImagePicker = true } label: {
                        ZStack {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 120, height: 120)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.title)
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            // Edit badge
                            Circle()
                                .fill(Color.stridePrimary)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 42, y: 42)
                        }
                    }

                    // Form fields
                    VStack(spacing: 20) {
                        // Name
                        profileField(title: "NAME") {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .font(.inter(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Date of birth
                        profileField(title: "DATE OF BIRTH") {
                            DatePicker(
                                "Date of Birth",
                                selection: $dateOfBirth,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .font(.inter(size: 16))
                            .tint(Color.stridePrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Gender
                        profileField(title: "GENDER") {
                            Menu {
                                Button("Male") { gender = "male" }
                                Button("Female") { gender = "female" }
                                Button("Non-binary") { gender = "non_binary" }
                                Button("Prefer not to say") { gender = "prefer_not_to_say" }
                            } label: {
                                HStack {
                                    Text(genderDisplayName)
                                        .foregroundStyle(gender.isEmpty ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.inter(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }

                        // Height
                        profileField(title: "HEIGHT (CM)") {
                            TextField("175", text: $heightCm)
                                .keyboardType(.numberPad)
                                .font(.inter(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 8)

                    // Complete Setup button
                    Button(action: completeSetup) {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Complete Setup")
                                    .font(.inter(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.stridePrimary)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 32)

                    // Skip
                    Button("Skip for now") {
                        skipSetup()
                    }
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)

                    Spacer().frame(height: 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            name = user.name ?? ""
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker { image in
                photoImage = image
                photoData = image.jpegData(compressionQuality: 0.7)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func profileField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.inter(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            content()
        }
    }

    private var genderDisplayName: String {
        switch gender {
        case "male": return "Male"
        case "female": return "Female"
        case "non_binary": return "Non-binary"
        case "prefer_not_to_say": return "Prefer not to say"
        default: return "Select gender"
        }
    }

    private func completeSetup() {
        isSaving = true
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var request = ProfileUpdateRequest()
        request.name = name.trimmingCharacters(in: .whitespaces)
        request.dateOfBirth = dateFormatter.string(from: dateOfBirth)
        if !gender.isEmpty { request.gender = gender }
        if let h = Double(heightCm), h > 0 { request.heightCm = h }
        if let data = photoData {
            request.profilePhotoBase64 = data.base64EncodedString()
        }

        Task {
            do {
                let updatedUser = try await authService.updateProfile(request)
                // Always transition to signedIn — user can edit profile later
                if case .needsProfile = authService.authState {
                    authService.authState = .signedIn(updatedUser)
                }
            } catch {
                authService.error = error.localizedDescription
                // Still let user through on error
                if case .needsProfile(let user) = authService.authState {
                    authService.authState = .signedIn(user)
                }
            }
            isSaving = false
        }
    }

    private func skipSetup() {
        // Mark profile as complete even without data so user can enter the app
        Task {
            var request = ProfileUpdateRequest()
            // Send name at minimum if provided
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if !trimmedName.isEmpty { request.name = trimmedName }
            do {
                _ = try await authService.updateProfile(request)
                // Force transition to signedIn even if profile isn't "complete"
                if case .needsProfile(let user) = authService.authState {
                    authService.authState = .signedIn(user)
                }
            } catch {
                // Even on error, let user through
                if case .needsProfile(let user) = authService.authState {
                    authService.authState = .signedIn(user)
                }
            }
        }
    }
}

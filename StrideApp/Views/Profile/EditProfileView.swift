import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dateOfBirth = Date()
    @State private var gender = ""
    @State private var heightCm = ""
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var existingPhoto: UIImage?
    @State private var showImagePicker = false
    @State private var isSaving = false
    @State private var hasLoadedDOB = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer().frame(height: 8)

                    // Photo picker
                    Button { showImagePicker = true } label: {
                        ZStack {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else if let existingPhoto {
                                Image(uiImage: existingPhoto)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 100, height: 100)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            Circle()
                                .fill(Color.stridePrimary)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .offset(x: 36, y: 36)
                        }
                    }

                    // Form fields
                    VStack(spacing: 20) {
                        editField(title: "NAME") {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .font(.inter(size: 16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        editField(title: "DATE OF BIRTH") {
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

                        editField(title: "GENDER") {
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

                        editField(title: "HEIGHT (CM)") {
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

                    Spacer().frame(height: 16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemBackground))
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .onAppear { loadCurrentData() }
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
    private func editField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.inter(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            content()
        }
    }

    private var currentUser: UserResponse? {
        switch authService.authState {
        case .signedIn(let user): return user
        case .needsProfile(let user): return user
        default: return nil
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

    private func loadCurrentData() {
        guard let user = currentUser else { return }
        name = user.name ?? ""
        gender = user.gender ?? ""
        if let h = user.heightCm { heightCm = "\(Int(h))" }
        if let dobString = user.dateOfBirth, !dobString.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dobString) {
                dateOfBirth = date
                hasLoadedDOB = true
            }
        }
        // Decode existing photo once
        if let base64 = user.profilePhotoBase64,
           !base64.isEmpty,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            existingPhoto = image
        }
    }

    private func save() {
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
                _ = try await authService.updateProfile(request)
                dismiss()
            } catch {
                authService.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    EditProfileView()
        .environmentObject(AuthService.shared)
}

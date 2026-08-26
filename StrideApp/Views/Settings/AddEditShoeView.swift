import SwiftUI
import PhotosUI

struct AddEditShoeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ShoesViewModel

    var shoe: Shoe?

    @State private var name: String = ""
    @State private var isDefault: Bool = false
    @State private var usage: ShoeUsage = .outdoor
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var showDeleteConfirm = false
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false

    private var isEditing: Bool { shoe != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Photo
                Section {
                    HStack {
                        Spacer()
                        Button {
                            showPhotoOptions = true
                        } label: {
                            if let photoImage {
                                Image(uiImage: photoImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else if let shoe, let data = shoe.photoData, let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemGray6))
                                        .frame(width: 80, height: 80)
                                    VStack(spacing: 4) {
                                        Image(systemName: "camera")
                                            .font(.system(size: 20))
                                            .foregroundColor(.secondary)
                                        Text("Add Photo")
                                            .font(.inter(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Details
                Section {
                    TextField("Shoe name", text: $name)
                        .font(.inter(size: 15))

                    Picker("Used for", selection: $usage) {
                        ForEach(ShoeUsage.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Set as Default", isOn: $isDefault)
                        .tint(Color.stridePrimary)
                }

                // Mileage (edit mode only)
                if let shoe {
                    Section {
                        HStack {
                            Text("Total Mileage")
                                .font(.inter(size: 15))
                            Spacer()
                            Text(String(format: "%.1f km", shoe.totalDistanceKm))
                                .font(.barlowCondensed(size: 18, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Delete (edit mode only)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Shoe")
                                    .font(.inter(size: 15, weight: .medium))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Shoe" : "Add Shoe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundColor(.stridePrimary)
                }
            }
            .onAppear {
                if let shoe {
                    name = shoe.name
                    isDefault = shoe.isDefault
                    usage = shoe.usage
                    // Load existing photo
                    if let data = shoe.photoData {
                        photoImage = UIImage(data: data)
                    }
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showPhotoOptions, titleVisibility: .visible) {
                Button("Take Photo") {
                    showCamera = true
                }
                Button("Choose from Library") {
                    showPhotoPicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraView { image in
                    photoImage = image
                    photoData = image.jpegData(compressionQuality: 0.8)
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        photoImage = img
                        photoData = img.jpegData(compressionQuality: 0.8)
                    }
                }
            }
            .alert("Delete Shoe", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let shoe {
                        viewModel.deleteShoe(shoe: shoe, context: modelContext)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this shoe. Run history will keep the shoe name.")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let shoe {
            shoe.usage = usage
            viewModel.updateShoe(shoe: shoe, name: trimmedName, isDefault: isDefault, photoData: photoData, context: modelContext)
        } else {
            viewModel.addShoe(name: trimmedName, isDefault: isDefault, photoData: photoData, usage: usage, context: modelContext)
        }
        dismiss()
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

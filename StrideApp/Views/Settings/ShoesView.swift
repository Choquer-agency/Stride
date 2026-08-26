import SwiftUI
import SwiftData

struct ShoesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Shoe> { $0.isRetired == false }, sort: \Shoe.name) private var shoes: [Shoe]
    @StateObject private var viewModel = ShoesViewModel()
    @State private var showAddSheet = false
    @State private var editingShoe: Shoe?

    var body: some View {
        List {
            if shoes.isEmpty && !viewModel.isLoading {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "shoe.2")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No shoes added yet")
                            .font(.inter(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Track mileage on your running shoes to know when it's time for a new pair.")
                            .font(.inter(size: 13))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }

            ForEach(shoes) { shoe in
                Button {
                    editingShoe = shoe
                } label: {
                    shoeRow(shoe)
                }
                .buttonStyle(PlainButtonStyle())
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteShoe(shoe: shoe, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Shoes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.stridePrimary)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditShoeView(viewModel: viewModel)
        }
        .sheet(item: $editingShoe) { shoe in
            AddEditShoeView(viewModel: viewModel, shoe: shoe)
        }
        .onAppear {
            viewModel.syncFromServer(context: modelContext)
        }
    }

    private func shoeRow(_ shoe: Shoe) -> some View {
        HStack(spacing: 12) {
            // Photo thumbnail
            ShoePhotoView(shoe: shoe, size: 40)

            // Name + mileage
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(shoe.name)
                        .font(.inter(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    if shoe.isDefault {
                        Text("DEFAULT")
                            .font(.inter(size: 9, weight: .bold))
                            .foregroundColor(.stridePrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.stridePrimary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(shoe.usage.displayName) · " + String(format: "%.0f / %.0f km", shoe.totalDistanceKm, shoe.effectiveMaxKm))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5)).frame(height: 5)
                            Capsule().fill(shoe.lifeFraction >= 1.0 ? Color.stridePrimary
                                           : shoe.lifeFraction >= 0.8 ? Color.orange : Color.green)
                                .frame(width: max(5, geo.size.width * min(shoe.lifeFraction, 1.0)), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                    .font(.barlowCondensed(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shoe Photo View (loads from photoData or URL)

struct ShoePhotoView: View {
    let shoe: Shoe
    let size: CGFloat

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let photoData = shoe.photoData, let img = UIImage(data: photoData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shoe.2")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color(.systemGray6)))
        .clipShape(Circle())
        .onAppear { loadFromURL() }
    }

    private func loadFromURL() {
        guard shoe.photoData == nil,
              let urlString = shoe.photoURL,
              let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    loadedImage = img
                    // Cache locally
                    shoe.photoData = data
                }
            } catch {}
        }
    }
}

extension Shoe: Identifiable {}

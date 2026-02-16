import SwiftUI
import SwiftData

struct ShoesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ShoesViewModel()
    @State private var showAddSheet = false
    @State private var editingShoe: Shoe?

    var body: some View {
        List {
            if viewModel.shoes.isEmpty && !viewModel.isLoading {
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

            ForEach(viewModel.shoes, id: \.id) { shoe in
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
            viewModel.loadShoes(context: modelContext)
            viewModel.syncFromServer(context: modelContext)
        }
    }

    private func shoeRow(_ shoe: Shoe) -> some View {
        HStack(spacing: 12) {
            // Photo thumbnail
            Group {
                if let photoData = shoe.photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "shoe.2")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .background(Circle().fill(Color(.systemGray6)))

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
                Text(String(format: "%.1f km", shoe.totalDistanceKm))
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

extension Shoe: Identifiable {}

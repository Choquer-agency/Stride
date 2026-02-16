import Foundation
import SwiftData
import SwiftUI

@MainActor
class ShoesViewModel: ObservableObject {
    @Published var shoes: [Shoe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadShoes(context: ModelContext) {
        let predicate = #Predicate<Shoe> { $0.isRetired == false }
        let descriptor = FetchDescriptor<Shoe>(predicate: predicate, sortBy: [SortDescriptor(\Shoe.name)])
        shoes = (try? context.fetch(descriptor)) ?? []
    }

    func syncFromServer(context: ModelContext) {
        guard AuthService.shared.currentToken != nil else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let remoteShoes = try await APIService.shared.fetchShoes(includeRetired: true)
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                // Build set of remote IDs
                var remoteIds = Set<UUID>()

                for remote in remoteShoes {
                    guard let uuid = UUID(uuidString: remote.id) else { continue }
                    remoteIds.insert(uuid)

                    // Upsert
                    let predicate = #Predicate<Shoe> { $0.id == uuid }
                    let descriptor = FetchDescriptor<Shoe>(predicate: predicate)
                    let existing = try? context.fetch(descriptor)

                    if let shoe = existing?.first {
                        shoe.name = remote.name
                        shoe.photoURL = remote.photoUrl
                        shoe.isDefault = remote.isDefault
                        shoe.totalDistanceKm = remote.totalDistanceKm
                        shoe.isRetired = remote.isRetired
                    } else {
                        let shoe = Shoe(
                            id: uuid,
                            name: remote.name,
                            photoURL: remote.photoUrl,
                            isDefault: remote.isDefault,
                            totalDistanceKm: remote.totalDistanceKm,
                            isRetired: remote.isRetired,
                            createdAt: dateFormatter.date(from: remote.createdAt) ?? Date()
                        )
                        context.insert(shoe)
                    }
                }

                try context.save()
                loadShoes(context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addShoe(name: String, isDefault: Bool, photoData: Data?, context: ModelContext) {
        Task {
            do {
                let response = try await APIService.shared.createShoe(name: name, isDefault: isDefault)
                guard let uuid = UUID(uuidString: response.id) else { return }

                if isDefault {
                    for shoe in shoes where shoe.isDefault {
                        shoe.isDefault = false
                    }
                }

                let shoe = Shoe(
                    id: uuid,
                    name: response.name,
                    isDefault: response.isDefault,
                    totalDistanceKm: response.totalDistanceKm,
                    isRetired: response.isRetired
                )
                context.insert(shoe)

                // Upload photo if provided
                if let photoData {
                    let photoResponse = try await APIService.shared.uploadShoePhoto(id: response.id, imageData: photoData)
                    shoe.photoURL = photoResponse.photoUrl
                    shoe.photoData = photoData
                }

                try context.save()
                loadShoes(context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateShoe(shoe: Shoe, name: String, isDefault: Bool, photoData: Data?, context: ModelContext) {
        Task {
            do {
                let nameChanged = shoe.name != name ? name : nil
                let defaultChanged = shoe.isDefault != isDefault ? isDefault : nil

                let response = try await APIService.shared.updateShoe(
                    id: shoe.id.uuidString,
                    name: nameChanged,
                    isDefault: defaultChanged
                )

                if isDefault {
                    for s in shoes where s.id != shoe.id && s.isDefault {
                        s.isDefault = false
                    }
                }

                shoe.name = response.name
                shoe.isDefault = response.isDefault

                if let photoData {
                    let photoResponse = try await APIService.shared.uploadShoePhoto(id: shoe.id.uuidString, imageData: photoData)
                    shoe.photoURL = photoResponse.photoUrl
                    shoe.photoData = photoData
                }

                try context.save()
                loadShoes(context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteShoe(shoe: Shoe, context: ModelContext) {
        Task {
            do {
                try await APIService.shared.deleteShoe(id: shoe.id.uuidString)
                context.delete(shoe)
                try context.save()
                loadShoes(context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setDefault(shoe: Shoe, context: ModelContext) {
        Task {
            do {
                _ = try await APIService.shared.updateShoe(id: shoe.id.uuidString, isDefault: true)
                for s in shoes {
                    s.isDefault = (s.id == shoe.id)
                }
                try context.save()
                loadShoes(context: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

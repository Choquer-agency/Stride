import Foundation
import SwiftData
import SwiftUI

@MainActor
class ShoesViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    func syncFromServer(context: ModelContext) {
        guard AuthService.shared.currentToken != nil else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let remoteShoes = try await APIService.shared.fetchShoes(includeRetired: true)
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                for remote in remoteShoes {
                    guard let uuid = UUID(uuidString: remote.id) else { continue }

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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addShoe(name: String, isDefault: Bool, photoData: Data?, usage: ShoeUsage = .outdoor, context: ModelContext) {
        Task {
            do {
                let response = try await APIService.shared.createShoe(name: name, isDefault: isDefault)
                guard let uuid = UUID(uuidString: response.id) else { return }

                if isDefault {
                    // Clear other defaults locally
                    let allPredicate = #Predicate<Shoe> { $0.isDefault == true }
                    let allDesc = FetchDescriptor<Shoe>(predicate: allPredicate)
                    let defaults = (try? context.fetch(allDesc)) ?? []
                    for s in defaults { s.isDefault = false }
                }

                // Create shoe with photoData immediately so @Query shows it with photo
                // (usage applied after init — new field with default)
                let shoe = Shoe(
                    id: uuid,
                    name: response.name,
                    photoData: photoData,
                    isDefault: response.isDefault,
                    totalDistanceKm: response.totalDistanceKm,
                    isRetired: response.isRetired
                )
                shoe.usage = usage
                context.insert(shoe)
                try context.save()

                // Upload photo to server in background
                if let photoData {
                    let photoResponse = try await APIService.shared.uploadShoePhoto(id: response.id, imageData: photoData)
                    shoe.photoURL = photoResponse.photoUrl
                    try context.save()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateShoe(shoe: Shoe, name: String, isDefault: Bool, photoData: Data?, context: ModelContext) {
        // Apply local changes immediately so @Query reflects them
        shoe.name = name
        if let photoData {
            shoe.photoData = photoData
        }
        if isDefault && !shoe.isDefault {
            let allPredicate = #Predicate<Shoe> { $0.isDefault == true }
            let allDesc = FetchDescriptor<Shoe>(predicate: allPredicate)
            let defaults = (try? context.fetch(allDesc)) ?? []
            for s in defaults { s.isDefault = false }
        }
        shoe.isDefault = isDefault
        try? context.save()

        // Sync to server in background
        Task {
            do {
                let nameChanged = shoe.name != name ? name : nil
                let defaultChanged = shoe.isDefault != isDefault ? isDefault : nil

                _ = try await APIService.shared.updateShoe(
                    id: shoe.id.uuidString,
                    name: nameChanged,
                    isDefault: defaultChanged
                )

                if let photoData {
                    let photoResponse = try await APIService.shared.uploadShoePhoto(id: shoe.id.uuidString, imageData: photoData)
                    shoe.photoURL = photoResponse.photoUrl
                    try context.save()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteShoe(shoe: Shoe, context: ModelContext) {
        context.delete(shoe)
        try? context.save()

        Task {
            do {
                try await APIService.shared.deleteShoe(id: shoe.id.uuidString)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setDefault(shoe: Shoe, context: ModelContext) {
        let allPredicate = #Predicate<Shoe> { $0.isDefault == true }
        let allDesc = FetchDescriptor<Shoe>(predicate: allPredicate)
        let defaults = (try? context.fetch(allDesc)) ?? []
        for s in defaults { s.isDefault = false }
        shoe.isDefault = true
        try? context.save()

        Task {
            do {
                _ = try await APIService.shared.updateShoe(id: shoe.id.uuidString, isDefault: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

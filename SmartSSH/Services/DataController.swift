//
//  DataController.swift
//  SSH Terminal
//
//  Core Data + iCloud sync
//

import Foundation
import CoreData

class DataController: ObservableObject {
    static let shared = DataController()
    
    let container: NSPersistentCloudKitContainer
    @Published var persistentStoreErrorMessage: String?
    
    init(inMemory: Bool = false, cloudSyncEnabled: Bool = true) {
        let modelLoadResult = Self.loadManagedObjectModel()
        container = NSPersistentCloudKitContainer(
            name: "SmartSSH",
            managedObjectModel: modelLoadResult.model
        )
        persistentStoreErrorMessage = modelLoadResult.errorMessage

        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }

            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

            if !cloudSyncEnabled {
                description.cloudKitContainerOptions = nil
            }
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.persistentStoreErrorMessage = error.localizedDescription
                }
                return
            }

            self.container.viewContext.automaticallyMergesChangesFromParent = true
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }

    private static func loadManagedObjectModel() -> (model: NSManagedObjectModel, errorMessage: String?) {
        let modelURLs = [
            Bundle.main.url(forResource: "SmartSSH", withExtension: "momd"),
            Bundle.main.url(forResource: "SmartSSH", withExtension: "mom")
        ].compactMap { $0 }

        for url in modelURLs {
            if let model = NSManagedObjectModel(contentsOf: url) {
                return (model, nil)
            }
        }

        if let model = NSManagedObjectModel.mergedModel(from: [Bundle.main]) {
            return (model, nil)
        }

        #if DEBUG
        fatalError("SmartSSH could not load its Core Data model from the app bundle. Please reinstall the app.")
        #else
        let errorMessage = "SmartSSH could not load its data model. Please reinstall the app."
        print("[DataController] CRITICAL: \(errorMessage)")
        return (NSManagedObjectModel(), errorMessage)
        #endif
    }
}

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
        container = NSPersistentCloudKitContainer(name: "SmartSSH")

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
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

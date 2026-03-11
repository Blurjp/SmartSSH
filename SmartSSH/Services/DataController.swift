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
                print("Core Data error: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}

//
//  Host.swift
//  SmartSSH
//
//  SSH Host model
//

import Foundation
import CoreData

@objc(Host)
public class Host: NSManagedObject, Identifiable {
    
}

extension Host {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Host> {
        return NSFetchRequest<Host>(entityName: "Host")
    }
    
    @NSManaged public var color: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var group: String?
    @NSManaged public var hostname: String?
    @NSManaged public var id: UUID?
    @NSManaged public var keyFingerprint: String?
    @NSManaged public var lastConnectedAt: Date?
    @NSManaged public var name: String?
    @NSManaged public var port: Int16
    @NSManaged public var snippets: [String]?
    @NSManaged public var status: String?
    @NSManaged public var tags: [String]?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var username: String?
    @NSManaged public var useKeyAuth: Bool
    
    // Computed properties
    var wrappedName: String {
        name ?? "Unknown Host"
    }
    
    var wrappedHostname: String {
        hostname ?? ""
    }
    
    var wrappedUsername: String {
        username ?? ""
    }
    
    var displayInfo: String {
        "\(wrappedUsername)@\(wrappedHostname):\(port)"
    }
    
    var statusColor: String {
        switch status {
        case "connected": return "green"
        case "connecting": return "yellow"
        case "error": return "red"
        default: return "gray"
        }
    }
    
    // Password is stored securely in Keychain, not Core Data
    var password: String? {
        get {
            guard let hostId = id else { return nil }
            return KeychainService.shared.getPassword(for: hostId)
        }
        set {
            guard let hostId = id else { return }
            if let newPassword = newValue, !newPassword.isEmpty {
                try? KeychainService.shared.savePassword(newPassword, for: hostId)
            } else {
                try? KeychainService.shared.deletePassword(for: hostId)
            }
        }
    }
    
    var hasPassword: Bool {
        guard let hostId = id else { return false }
        return KeychainService.shared.hasPassword(for: hostId)
    }
    
    // Factory method
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        hostname: String,
        port: Int16 = 22,
        username: String,
        password: String? = nil,
        keyFingerprint: String? = nil,
        group: String? = nil,
        tags: [String]? = nil,
        useKeyAuth: Bool = false
    ) -> Host {
        let host = Host(context: context)
        host.id = UUID()
        host.name = name
        host.hostname = hostname
        host.port = port
        host.username = username
        host.keyFingerprint = keyFingerprint
        host.group = group
        host.tags = tags
        host.useKeyAuth = useKeyAuth
        host.createdAt = Date()
        host.updatedAt = Date()
        host.lastConnectedAt = nil
        host.status = "disconnected"
        host.color = "blue"
        host.snippets = []
        
        // Save password to Keychain (secure storage)
        if let password = password, !password.isEmpty {
            try? KeychainService.shared.savePassword(password, for: host.id!)
        }
        
        return host
    }
    
    // Delete password from Keychain when host is deleted
    func deletePassword() {
        guard let hostId = id else { return }
        try? KeychainService.shared.deletePassword(for: hostId)
    }
}

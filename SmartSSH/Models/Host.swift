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
    enum ProxyType: String, Codable, CaseIterable, Identifiable {
        case http
        case socks5

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .http:
                return "HTTP"
            case .socks5:
                return "SOCKS5"
            }
        }
    }

    struct ProxyConfiguration: Codable, Equatable {
        var type: ProxyType
        var host: String
        var port: Int
        var username: String?
        var password: String?

        var displayName: String {
            type.displayName
        }

        var isValid: Bool {
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (1...65535).contains(port)
        }

        var requiresAuth: Bool {
            username != nil && !username!.isEmpty
        }

        var authSummary: String {
            guard requiresAuth else { return "No auth" }
            return "Auth: \(username!)"
        }
    }

    struct RoutingOptions: Codable, Equatable {
        var jumpHostID: UUID?
        var proxy: ProxyConfiguration?

        var hasRouting: Bool {
            jumpHostID != nil || proxy != nil
        }
    }

    struct PortForward: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var name: String
        var localPort: Int
        var remoteHost: String
        var remotePort: Int
        var isEnabled: Bool

        var isValid: Bool {
            (1...65535).contains(localPort) &&
            !remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (1...65535).contains(remotePort)
        }

        var summary: String {
            "\(localPort) -> \(remoteHost):\(remotePort)"
        }

        // Connection statistics
        var bytesReceived: Int64 = 0
        var bytesSent: Int64 = 0
        var connectionCount: Int = 0
        var lastConnectedAt: Date?
    }

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
    @NSManaged public var portForwardsData: String?
    @NSManaged public var routingOptionsData: String?
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
                do {
                    try KeychainService.shared.savePassword(newPassword, for: hostId)
                } catch {
                    print("Failed to save password for host \(wrappedName): \(error.localizedDescription)")
                }
            } else {
                do {
                    try KeychainService.shared.deletePassword(for: hostId)
                } catch {
                    print("Failed to delete password for host \(wrappedName): \(error.localizedDescription)")
                }
            }
        }
    }
    
    var hasPassword: Bool {
        guard let hostId = id else { return false }
        return KeychainService.shared.hasPassword(for: hostId)
    }

    var portForwards: [PortForward] {
        get {
            decodeJSON([PortForward].self, from: portForwardsData) ?? []
        }
        set {
            portForwardsData = encodeJSON(newValue)
        }
    }

    var routingOptions: RoutingOptions? {
        get {
            decodeJSON(RoutingOptions.self, from: routingOptionsData)
        }
        set {
            guard let newValue else {
                routingOptionsData = nil
                return
            }
            routingOptionsData = encodeJSON(newValue)
        }
    }
    
    // Factory method
    static func create(
        in context: NSManagedObjectContext,
        id: UUID? = nil,
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
        configure(
            host,
            id: id,
            name: name,
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            keyFingerprint: keyFingerprint,
            group: group,
            tags: tags,
            useKeyAuth: useKeyAuth
        )
        return host
    }

    static func createTransient(
        using context: NSManagedObjectContext,
        id: UUID? = nil,
        name: String,
        hostname: String,
        port: Int16 = 22,
        username: String,
        password: String? = nil,
        keyFingerprint: String? = nil,
        group: String? = nil,
        tags: [String]? = nil,
        useKeyAuth: Bool = false
    ) -> Host? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Host", in: context) else {
            return nil
        }

        let host = Host(entity: entity, insertInto: nil)
        configure(
            host,
            id: id,
            name: name,
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            keyFingerprint: keyFingerprint,
            group: group,
            tags: tags,
            useKeyAuth: useKeyAuth
        )
        return host
    }

    private static func configure(
        _ host: Host,
        id: UUID?,
        name: String,
        hostname: String,
        port: Int16,
        username: String,
        password: String?,
        keyFingerprint: String?,
        group: String?,
        tags: [String]?,
        useKeyAuth: Bool
    ) {
        host.id = id ?? UUID()
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
        host.portForwardsData = nil
        host.routingOptionsData = nil

        if let password = password,
           !password.isEmpty,
           let hostID = host.id {
            try? KeychainService.shared.savePassword(password, for: hostID)
        }
    }
    
    // Delete password from Keychain when host is deleted
    func deletePassword() {
        guard let hostId = id else { return }
        try? KeychainService.shared.deletePassword(for: hostId)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from value: String?) -> T? {
        guard let value,
              let data = value.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

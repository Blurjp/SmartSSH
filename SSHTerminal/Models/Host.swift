//
//  Host.swift
//  SSH Terminal
//
//  SSH Host model
//

import Foundation
import CoreData

extension Host {
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
    
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        hostname: String,
        port: Int16 = 22,
        username: String,
        password: String? = nil,
        keyFingerprint: String? = nil,
        group: String? = nil,
        tags: [String]? = nil
    ) -> Host {
        let host = Host(context: context)
        host.id = UUID()
        host.name = name
        host.hostname = hostname
        host.port = port
        host.username = username
        host.password = password
        host.keyFingerprint = keyFingerprint
        host.group = group
        host.tags = tags
        host.createdAt = Date()
        host.updatedAt = Date()
        host.lastConnectedAt = nil
        host.status = "disconnected"
        host.color = "blue"
        host.snippets = []
        return host
    }
}

//
//  QuickActions.swift
//  SSH Terminal
//
//  Quick action utilities
//

import SwiftUI

struct QuickAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let command: String
}

struct QuickActionsView: View {
    let onSelect: (String) -> Void

    static let availableActions: [QuickAction] = [
        QuickAction(icon: "folder", title: "List Files", subtitle: "ls -la", command: "ls -la"),
        QuickAction(icon: "location", title: "Current Directory", subtitle: "pwd", command: "pwd"),
        QuickAction(icon: "person", title: "Who Am I", subtitle: "whoami", command: "whoami"),
        QuickAction(icon: "externaldrive", title: "Disk Usage", subtitle: "df -h", command: "df -h"),
        QuickAction(icon: "memorychip", title: "Memory Info", subtitle: "free -h", command: "free -h"),
        QuickAction(icon: "network", title: "Network Info", subtitle: "ifconfig", command: "ifconfig"),
        QuickAction(icon: "doc.text", title: "System Logs", subtitle: "tail -f /var/log/syslog", command: "tail -f /var/log/syslog"),
        QuickAction(icon: "arrow.trianglehead.clockwise", title: "Restart Service", subtitle: "systemctl restart", command: "systemctl restart "),
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.availableActions) { action in
                    QuickActionButton(action: action) {
                        onSelect(action.command)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
}

struct QuickActionButton: View {
    let action: QuickAction
    let actionHandler: () -> Void
    
    var body: some View {
        Button {
            actionHandler()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(spacing: 2) {
                    Text(action.title)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(action.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 80, height: 80)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Connection String Parser

struct ConnectionStringParser {
    static func parse(_ string: String) -> (username: String, hostname: String, port: Int)? {
        // Parse formats like:
        // user@hostname
        // user@hostname:port
        // ssh user@hostname
        // ssh user@hostname -p port
        
        let cleanString = string
            .replacingOccurrences(of: "ssh ", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Split by @
        let parts = cleanString.split(separator: "@")
        guard parts.count == 2 else { return nil }
        
        let username = String(parts[0])
        let hostPart = String(parts[1])
        
        // Check for port
        if hostPart.contains(":") {
            let hostParts = hostPart.split(separator: ":")
            guard hostParts.count == 2,
                  let port = Int(hostParts[1]) else { return nil }
            return (username, String(hostParts[0]), port)
        }
        
        // Check for -p flag
        if let portRange = hostPart.range(of: "-p "),
           let port = Int(hostPart[portRange.upperBound...].split(separator: " ").first ?? "") {
            let hostname = String(hostPart[..<portRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            return (username, hostname, port)
        }
        
        return (username, hostPart, 22)
    }
}

// MARK: - Keyboard Shortcuts

enum KeyboardShortcut: String, CaseIterable {
    case ctrlC = "Ctrl+C"
    case ctrlD = "Ctrl+D"
    case ctrlL = "Ctrl+L"
    case ctrlZ = "Ctrl+Z"
    case tab = "Tab"
    
    var keyCode: String {
        switch self {
        case .ctrlC: return "\u{03}"
        case .ctrlD: return "\u{04}"
        case .ctrlL: return "\u{0C}"
        case .ctrlZ: return "\u{1A}"
        case .tab: return "\t"
        }
    }
    
    var description: String {
        switch self {
        case .ctrlC: return "Interrupt current command"
        case .ctrlD: return "Exit current shell"
        case .ctrlL: return "Clear screen"
        case .ctrlZ: return "Suspend current process"
        case .tab: return "Auto-complete"
        }
    }
}

// MARK: - Preview

#Preview {
    QuickActionsView { command in
        print("Selected: \(command)")
    }
}

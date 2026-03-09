//
//  SSHManager.swift
//  SSH Terminal
//
//  SSH connection management
//

import Foundation
import Network
import CryptoKit

enum SSHError: Error {
    case connectionFailed(String)
    case authenticationFailed(String)
    case commandFailed(String)
    case timeout
    case invalidHost
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .timeout: return "Connection timeout"
        case .invalidHost: return "Invalid host configuration"
        }
    }
}

struct SSHSession {
    let id: UUID
    let host: Host
    var isConnected: Bool = false
    var lastActivity: Date = Date()
    var outputHandler: ((String) -> Void)?
}

class SSHManager: ObservableObject {
    static let shared = SSHManager()
    
    @Published var activeSessions: [UUID: SSHSession] = [:]
    @Published var connectionStatus: [UUID: String] = [:]
    
    private let sessionQueue = DispatchQueue(label: "com.sshterminal.ssh", qos: .userInitiated)
    
    // MARK: - Connection
    
    func connect(to host: Host, completion: @escaping (Result<UUID, SSHError>) -> Void) {
        let sessionId = UUID()
        
        // Validate host
        guard !host.wrappedHostname.isEmpty, !host.wrappedUsername.isEmpty else {
            completion(.failure(.invalidHost))
            return
        }
        
        // Update status
        DispatchQueue.main.async {
            self.connectionStatus[sessionId] = "connecting"
        }
        
        sessionQueue.async {
            // Simulate connection (replace with real SSH implementation)
            // In production, use libssh2 or NMSSH
            
            // For now, create a mock session
            let session = SSHSession(
                id: sessionId,
                host: host,
                isConnected: true,
                lastActivity: Date()
            )
            
            // Simulate connection delay
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                self.activeSessions[sessionId] = session
                self.connectionStatus[sessionId] = "connected"
                
                // Update host status
                host.status = "connected"
                host.lastConnectedAt = Date()
                
                completion(.success(sessionId))
            }
        }
    }
    
    func disconnect(sessionId: UUID) {
        guard var session = activeSessions[sessionId] else { return }
        
        session.isConnected = false
        activeSessions[sessionId] = nil
        connectionStatus[sessionId] = "disconnected"
        
        // Update host status
        session.host.status = "disconnected"
    }
    
    // MARK: - Command Execution
    
    func execute(
        sessionId: UUID,
        command: String,
        completion: @escaping (Result<String, SSHError>) -> Void
    ) {
        guard let session = activeSessions[sessionId], session.isConnected else {
            completion(.failure(.connectionFailed("Not connected")))
            return
        }
        
        sessionQueue.async {
            // Simulate command execution
            // Replace with real SSH command execution
            
            let output = "$ \(command)\nCommand executed successfully"
            
            Thread.sleep(forTimeInterval: 0.2)
            
            DispatchQueue.main.async {
                // Call output handler if set
                self.activeSessions[sessionId]?.outputHandler?(output)
                completion(.success(output))
            }
        }
    }
    
    // MARK: - Key Management
    
    func generateKeyPair(name: String, type: String = "ed25519", comment: String? = nil) -> (privateKey: String, publicKey: String, fingerprint: String) {
        // Use CryptoKit for Ed25519
        let privateKey = P256.KeyAgreement.PrivateKey()
        
        let privateKeyPEM = privateKey.rawRepresentation.base64EncodedString()
        let publicKeyPEM = privateKey.publicKey.rawRepresentation.base64EncodedString()
        
        // Generate fingerprint
        let fingerprint = "SHA256:" + publicKeyPEM.prefix(43).replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        
        return (privateKeyPEM, publicKeyPEM, fingerprint)
    }
    
    func saveKey(name: String, privateKey: String, publicKey: String, fingerprint: String, passphrase: String? = nil) {
        // Save to Keychain
        let keyData = [
            "name": name,
            "privateKey": privateKey,
            "publicKey": publicKey,
            "fingerprint": fingerprint,
            "createdAt": Date().iso8601String
        ]
        
        // In production, use proper Keychain storage
        UserDefaults.standard.set(keyData, forKey: "ssh_key_\(name)")
    }
    
    // MARK: - AI Features
    
    func suggestCommand(context: String, completion: @escaping (String) -> Void) {
        // AI command suggestion
        // In production, call OpenAI API
        
        let suggestions = [
            "ssh-keygen -t ed25519 -C 'your_email@example.com'",
            "ssh-copy-id user@hostname",
            "chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_rsa",
            "ssh -L 8080:localhost:80 user@hostname",
            "rsync -avz -e ssh source/ user@hostname:dest/"
        ]
        
        completion(suggestions.randomElement() ?? "")
    }
    
    func diagnoseError(output: String, completion: @escaping (String) -> Void) {
        // AI error diagnosis
        // In production, call OpenAI API with the error output
        
        if output.contains("Connection refused") {
            completion("The server is not accepting connections on the specified port. Check if SSH service is running on the server.")
        } else if output.contains("Permission denied") {
            completion("Authentication failed. Check your username, password, or SSH key.")
        } else if output.contains("Host key verification failed") {
            completion("The server's host key has changed. Run: ssh-keygen -R <hostname>")
        } else {
            completion("Unable to diagnose this error automatically. Please check the error message.")
        }
    }
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

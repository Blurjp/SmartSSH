//
//  SSHClient.swift
//  SSH Terminal
//
//  Real SSH connection implementation
//  Uses NMSSH library for actual SSH connections
//

import Foundation
import Network
import CryptoKit
import NMSSH

// MARK: - SSH Connection States

enum SSHConnectionState {
    case disconnected
    case connecting
    case connected
    case authenticating
    case error(String)
    
    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting, .authenticating: return "yellow"
        case .connected: return "green"
        case .error: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .connecting, .authenticating: return "antenna.radiowaves.left.and.right"
        case .connected: return "antenna.radiowaves.left.and.right"
        case .error: return "exclamationmark.triangle"
        }
    }
}

// MARK: - SSH Client

class SSHClient: ObservableObject {
    static let shared = SSHClient()

    private let unavailableMessage = "Real SSH transport is not configured in this build. Add a production SSH backend before release."
    
    // MARK: - Properties
    
    @Published var state: SSHConnectionState = .disconnected
    @Published var output: String = ""
    @Published var isConnected: Bool = false
    
    private var session: NMSSHSession?
    var host: Host?
    private var outputQueue = DispatchQueue(label: "com.smartssh.output")

    var activeSession: NMSSHSession? {
        guard let session, session.isConnected, session.isAuthorized else { return nil }
        return session
    }
    
    // MARK: - Connection
    
    func connect(
        to host: Host,
        timeout: TimeInterval = 30,
        completion: @escaping (Result<Void, SSHError>) -> Void
    ) {
        let hostname = host.wrappedHostname
        let username = host.wrappedUsername
        let password = host.password
        let keyName = host.keyFingerprint
        let publicKey = SSHManager.shared.loadSavedKeys().first(where: { $0.name == keyName })?.publicKey
        let privateKey: String?
        if let keyName {
            privateKey = SSHManager.shared.privateKey(named: keyName)
        } else {
            privateKey = nil
        }

        self.host = host
        
        DispatchQueue.main.async {
            self.state = .connecting
            self.output = ""
        }
        
        // Validate host configuration
        guard !hostname.isEmpty, !username.isEmpty else {
            DispatchQueue.main.async {
                self.state = .error("Invalid hostname")
            }
            completion(.failure(.invalidHost))
            return
        }

        disconnect()
        appendOutput("Connecting to \(hostname)...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let session = NMSSHSession(host: hostname, port: Int(host.port), andUsername: username)
            session.timeout = NSNumber(value: timeout)

            guard session.connect(), session.isConnected else {
                let message = session.lastError?.localizedDescription ?? "Unable to connect"
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                }
                completion(.failure(.connectionFailed(message)))
                return
            }

            DispatchQueue.main.async {
                self.state = .authenticating
            }
            self.appendOutput("Authenticating as \(username)...\n")

            let authorized: Bool
            if host.useKeyAuth {
                guard let publicKey, let privateKey else {
                    session.disconnect()
                    let message = "Missing SSH key material for \(keyName ?? "selected key")"
                    DispatchQueue.main.async {
                        self.state = .error(message)
                        self.isConnected = false
                    }
                    completion(.failure(.authenticationFailed(message)))
                    return
                }

                authorized = session.authenticateBy(inMemoryPublicKey: publicKey, privateKey: privateKey, andPassword: nil)
            } else if let password, !password.isEmpty {
                authorized = session.authenticate(byPassword: password)
            } else {
                session.disconnect()
                let message = "No authentication method configured"
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                }
                completion(.failure(.authenticationFailed(message)))
                return
            }

            guard authorized, session.isAuthorized else {
                let message = session.lastError?.localizedDescription ?? "Authentication failed"
                session.disconnect()
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                }
                completion(.failure(.authenticationFailed(message)))
                return
            }

            session.channel.requestPty = true

            DispatchQueue.main.async {
                self.session = session
                self.state = .connected
                self.isConnected = true
                self.appendOutput("Connected!\n\n")
                completion(.success(()))
            }
        }
    }
    
    func disconnect() {
        let hadSession = session != nil || isConnected

        // Cleanup session
        session?.disconnect()
        session = nil
        host = nil
        
        DispatchQueue.main.async {
            self.state = .disconnected
            self.isConnected = false
            if hadSession {
                self.output.append("\nDisconnected.\n")
            }
        }
    }
    
    // MARK: - Command Execution
    
    func execute(
        command: String,
        completion: @escaping (Result<String, SSHError>) -> Void
    ) {
        guard isConnected else {
            completion(.failure(.connectionFailed("Not connected")))
            return
        }

        guard let session = activeSession else {
            completion(.failure(.connectionFailed("Session unavailable")))
            return
        }

        appendOutput("$ \(command)\n")

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let response = session.channel.execute(command, error: &error, timeout: 30)

            if let error {
                let message = error.localizedDescription
                self.appendOutput("\(message)\n")
                completion(.failure(.commandFailed(message)))
                return
            }

            let output = response ?? ""
            if !output.isEmpty {
                self.appendOutput(output.hasSuffix("\n") ? output : output + "\n")
            }
            completion(.success(output))
        }
    }
    
    // MARK: - Output Handling
    
    func appendOutput(_ text: String) {
        DispatchQueue.main.async {
            self.output.append(text)
        }
    }
    
    func clearOutput() {
        DispatchQueue.main.async {
            self.output = ""
        }
    }
    
}

// MARK: - Real SSH Implementation (NMSSH)

/*
 In production, replace simulation with NMSSH:
 
 import NMSSH
 
 class RealSSHClient {
     var session: NMSSHSession?
     
     func connect(to host: Host) throws {
         session = NMSSHSession(host: host.hostname, port: Int(host.port))
         session?.connect()
         
         if host.keyFingerprint != nil {
             // Key-based authentication
             session?.authenticateWithPublicKey(
                 host.keyFingerprint,
                 privateKey: loadKey(name: host.keyFingerprint!),
                 password: nil
             )
         } else {
             // Password authentication
             session?.authenticateWithPassword(host.password)
         }
     }
     
     func execute(command: String) throws -> String {
         return session?.channel.execute(command) ?? ""
     }
     
     func disconnect() {
         session?.disconnect()
         session = nil
     }
 }
 */

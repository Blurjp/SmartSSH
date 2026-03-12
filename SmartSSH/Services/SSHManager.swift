//
//  SSHManager.swift
//  SSH Terminal
//
//  SSH connection management
//

import Foundation
import Network
import CryptoKit
import NMSSH
import Security

enum SSHError: Error {
    case connectionFailed(String)
    case authenticationFailed(String)
    case commandFailed(String)
    case timeout
    case invalidHost
    case featureUnavailable(String)
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .timeout: return "Connection timeout"
        case .invalidHost: return "Invalid host configuration"
        case .featureUnavailable(let msg): return msg
        }
    }
}

struct SavedSSHKey: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: String
    let fingerprint: String
    let publicKey: String
    let createdAt: Date

    init(name: String, type: String, fingerprint: String, publicKey: String, createdAt: Date) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedID = try? container.decode(UUID.self, forKey: .id) {
            id = decodedID
        } else {
            id = UUID()
        }
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct SSHSession {
    let id: UUID
    let host: Host
    let session: NMSSHSession
    var isConnected: Bool = false
    var lastActivity: Date = Date()
    var outputHandler: ((String) -> Void)?
}

class SSHManager: ObservableObject {
    static let shared = SSHManager()

    private let savedKeysDefaultsKey = "saved_ssh_keys"
    private let knownHostsDefaultsKey = "known_ssh_hosts"
    
    @Published var activeSessions: [UUID: SSHSession] = [:]
    @Published var connectionStatus: [UUID: String] = [:]
    
    private let sessionQueue = DispatchQueue(label: "com.sshterminal.ssh", qos: .userInitiated)
    
    // MARK: - Connection
    
    func connect(to host: Host, completion: @escaping (Result<UUID, SSHError>) -> Void) {
        let sessionId = UUID()
        let hostname = host.wrappedHostname
        let username = host.wrappedUsername
        let password = host.password
        let keyName = host.keyFingerprint
        let publicKey = loadSavedKeys().first(where: { $0.name == keyName })?.publicKey
        let savedPrivateKey: String?
        if let keyName {
            savedPrivateKey = privateKey(named: keyName)
        } else {
            savedPrivateKey = nil
        }
        
        // Validate host
        guard !hostname.isEmpty, !username.isEmpty else {
            completion(.failure(.invalidHost))
            return
        }
        
        // Update status
        DispatchQueue.main.async {
            self.connectionStatus[sessionId] = "connecting"
        }
        
        sessionQueue.async {
            let session = NMSSHSession(host: hostname, port: Int(host.port), andUsername: username)
            session.timeout = 30

            guard session.connect(), session.isConnected else {
                let message = session.lastError?.localizedDescription ?? "Unable to connect"
                DispatchQueue.main.async {
                    self.connectionStatus[sessionId] = "error"
                    completion(.failure(.connectionFailed(message)))
                }
                return
            }

            let authorized: Bool
            if host.useKeyAuth {
                guard let publicKey, let savedPrivateKey else {
                    session.disconnect()
                    DispatchQueue.main.async {
                        self.connectionStatus[sessionId] = "error"
                        completion(.failure(.authenticationFailed("Missing SSH key material")))
                    }
                    return
                }
                authorized = session.authenticateBy(inMemoryPublicKey: publicKey, privateKey: savedPrivateKey, andPassword: nil)
            } else if let password, !password.isEmpty {
                authorized = session.authenticate(byPassword: password)
            } else {
                session.disconnect()
                DispatchQueue.main.async {
                    self.connectionStatus[sessionId] = "error"
                    completion(.failure(.authenticationFailed("No authentication method configured")))
                }
                return
            }

            guard authorized, session.isAuthorized else {
                let message = session.lastError?.localizedDescription ?? "Authentication failed"
                session.disconnect()
                DispatchQueue.main.async {
                    self.connectionStatus[sessionId] = "error"
                    completion(.failure(.authenticationFailed(message)))
                }
                return
            }

            session.channel.requestPty = true

            let sshSession = SSHSession(
                id: sessionId,
                host: host,
                session: session,
                isConnected: true,
                lastActivity: Date()
            )

            DispatchQueue.main.async {
                self.activeSessions[sessionId] = sshSession
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
        
        session.session.disconnect()
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
            var error: NSError?
            let output = session.session.channel.execute(command, error: &error, timeout: 30) ?? ""

            if let error {
                DispatchQueue.main.async {
                    completion(.failure(.commandFailed(error.localizedDescription)))
                }
                return
            }
            
            DispatchQueue.main.async {
                // Call output handler if set
                self.activeSessions[sessionId]?.outputHandler?(output)
                completion(.success(output))
            }
        }
    }
    
    // MARK: - Key Management
    
    func generateKeyPair(
        name: String,
        type: String = "ed25519",
        comment: String? = nil,
        passphrase: String? = nil
    ) throws -> (privateKey: String, publicKey: String, fingerprint: String) {
        guard type == "ed25519" else {
            throw SSHError.featureUnavailable("Only ED25519 key generation is currently supported.")
        }

        if let passphrase, !passphrase.isEmpty {
            throw SSHError.featureUnavailable("Passphrase-protected key generation is not supported yet.")
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let seedData = privateKey.rawRepresentation
        let commentText = comment?.isEmpty == false ? comment! : name

        let algorithm = Data("ssh-ed25519".utf8)
        let publicKeyBlob = sshString(algorithm) + sshString(publicKeyData)
        let publicKeyLine = "ssh-ed25519 \(publicKeyBlob.base64EncodedString()) \(commentText)"

        let check = try randomCheckInt()
        let privatePayload = Data()
            .appendingUInt32(check)
            .appendingUInt32(check)
            .appendingSSHString(algorithm)
            .appendingSSHString(publicKeyData)
            .appendingSSHString(seedData + publicKeyData)
            .appendingSSHString(Data(commentText.utf8))
            .appendingOpenSSHPadding(blockSize: 8)

        let privateKeyBlob = Data("openssh-key-v1\0".utf8)
            .appendingSSHString(Data("none".utf8))
            .appendingSSHString(Data("none".utf8))
            .appendingSSHString(Data())
            .appendingUInt32(1)
            .appendingSSHString(publicKeyBlob)
            .appendingSSHString(privatePayload)

        let formattedPrivateKey = [
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            privateKeyBlob.base64EncodedString().wrapped(at: 70),
            "-----END OPENSSH PRIVATE KEY-----"
        ].joined(separator: "\n")

        let fingerprintHash = SHA256.hash(data: publicKeyBlob)
        let fingerprint = "SHA256:" + Data(fingerprintHash).base64EncodedString().replacingOccurrences(of: "=", with: "")

        return (formattedPrivateKey, publicKeyLine, fingerprint)
    }
    
    func saveKey(name: String, privateKey: String, publicKey: String, fingerprint: String, type: String = "ed25519", passphrase: String? = nil) throws {
        let createdAt = Date()

        try KeychainService.shared.saveString(privateKey, forAccount: privateKeyAccount(for: name))

        let metadata = SavedSSHKey(
            name: name,
            type: type.uppercased(),
            fingerprint: fingerprint,
            publicKey: publicKey,
            createdAt: createdAt
        )

        var keys = loadSavedKeys()
        keys.removeAll { $0.name == name }
        keys.append(metadata)
        persistSavedKeys(keys)
    }

    func loadSavedKeys() -> [SavedSSHKey] {
        guard let data = UserDefaults.standard.data(forKey: savedKeysDefaultsKey),
              let keys = try? JSONDecoder().decode([SavedSSHKey].self, from: data) else {
            return []
        }

        return keys.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteKey(named name: String) throws {
        try KeychainService.shared.deleteValue(forAccount: privateKeyAccount(for: name))

        var keys = loadSavedKeys()
        keys.removeAll { $0.name == name }
        persistSavedKeys(keys)
    }

    func privateKey(named name: String) -> String? {
        KeychainService.shared.getString(forAccount: privateKeyAccount(for: name))
    }

    func clearKnownHosts() {
        UserDefaults.standard.removeObject(forKey: knownHostsDefaultsKey)
    }

    func verifyHostFingerprint(_ fingerprint: String, hostname: String, port: Int) -> HostTrustDecision {
        let endpoint = knownHostEndpoint(hostname: hostname, port: port)
        var knownHosts = loadKnownHosts()

        if let existing = knownHosts[endpoint] {
            if existing.fingerprint == fingerprint {
                return .trustedKnownHost
            }

            return .rejectedMismatch(expected: existing.fingerprint, actual: fingerprint)
        }

        knownHosts[endpoint] = KnownHostRecord(
            hostname: hostname,
            port: port,
            fingerprint: fingerprint,
            firstSeenAt: Date()
        )
        persistKnownHosts(knownHosts)
        return .trustedFirstUse
    }
    
}

private extension SSHManager {
    struct KnownHostRecord: Codable {
        let hostname: String
        let port: Int
        let fingerprint: String
        let firstSeenAt: Date
    }

    func privateKeyAccount(for name: String) -> String {
        "ssh_private_key_\(name)"
    }

    func knownHostEndpoint(hostname: String, port: Int) -> String {
        "\(hostname.lowercased()):\(port)"
    }

    func persistSavedKeys(_ keys: [SavedSSHKey]) {
        guard let data = try? JSONEncoder().encode(keys) else { return }
        UserDefaults.standard.set(data, forKey: savedKeysDefaultsKey)
    }

    func loadKnownHosts() -> [String: KnownHostRecord] {
        guard let data = UserDefaults.standard.data(forKey: knownHostsDefaultsKey),
              let knownHosts = try? JSONDecoder().decode([String: KnownHostRecord].self, from: data) else {
            return [:]
        }

        return knownHosts
    }

    func persistKnownHosts(_ knownHosts: [String: KnownHostRecord]) {
        guard let data = try? JSONEncoder().encode(knownHosts) else { return }
        UserDefaults.standard.set(data, forKey: knownHostsDefaultsKey)
    }
}

enum HostTrustDecision {
    case trustedFirstUse
    case trustedKnownHost
    case rejectedMismatch(expected: String, actual: String)
}

private func sshString(_ data: Data) -> Data {
    Data().appendingSSHString(data)
}

private func randomCheckInt() throws -> UInt32 {
    var value: UInt32 = 0
    let status = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value)
    guard status == errSecSuccess else {
        throw SSHError.commandFailed("Unable to generate secure random data")
    }
    return value
}

private extension Data {
    func appendingUInt32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        var result = self
        Swift.withUnsafeBytes(of: &bigEndian) { result.append(contentsOf: $0) }
        return result
    }

    func appendingSSHString(_ value: Data) -> Data {
        var result = appendingUInt32(UInt32(value.count))
        result.append(value)
        return result
    }

    func appendingOpenSSHPadding(blockSize: Int) -> Data {
        let remainder = count % blockSize
        let paddingLength = remainder == 0 ? blockSize : (blockSize - remainder)
        var result = self
        for index in 1...paddingLength {
            result.append(UInt8(index))
        }
        return result
    }
}

private extension String {
    func wrapped(at width: Int) -> String {
        guard count > width else { return self }
        var lines: [String] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: width, limitedBy: endIndex) ?? endIndex
            lines.append(String(self[index..<nextIndex]))
            index = nextIndex
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

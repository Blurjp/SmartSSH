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

class SSHClient: NSObject, ObservableObject, NMSSHSessionDelegate {
    static let shared = SSHClient()

    // MARK: - Properties
    
    @Published var state: SSHConnectionState = .disconnected
    @Published var output: String = ""
    @Published var isConnected: Bool = false
    
    private var connectionTimeout: TimeInterval {
        TimeInterval(UserDefaults.standard.integer(forKey: "connectionTimeout"))
    }
    
    /// Serializes all reads/writes of `_session` and `host`.
    private let sessionLock = NSLock()
    private var _session: NMSSHSession?
    private var _host: Host?
    private var _hostVerificationFailureMessage: String?
    private let inactiveSessionErrorFragment = "absence of an active session"
    private let localNetworkGuidance = "Make sure your iPhone is on the same network and SmartSSH has Local Network access enabled in Settings."

    var host: Host? {
        sessionLock.withLock { _host }
    }

    /// Returns the active, authorized session if one exists.
    /// Safe to call from any thread.
    var activeSession: NMSSHSession? {
        sessionLock.withLock {
            guard let s = _session, s.isConnected, s.isAuthorized else { return nil }
            return s
        }
    }
    
    // MARK: - Connection
    
    func connect(
        to host: Host,
        timeout: TimeInterval? = nil,
        completion: @escaping (Result<Void, SSHError>) -> Void
    ) {
        let timeout = timeout ?? connectionTimeout
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

        print("[SSHClient] Connecting to \(hostname):\(host.port) as \(username)")
        
        disconnect()
        sessionLock.withLock {
            _host = host
            _hostVerificationFailureMessage = nil
        }

        DispatchQueue.main.async {
            self.state = .connecting
            self.output = ""
        }
        
        // Validate host configuration
        guard !hostname.isEmpty, !username.isEmpty else {
            DispatchQueue.main.async {
                self.state = .error("Invalid hostname")
            }
            print("[SSHClient] ERROR: Invalid hostname or username")
            completion(.failure(.invalidHost))
            return
        }

        appendOutput("Connecting to \(hostname):\(Int(host.port))...\n")
        print("[SSHClient] Starting TCP preflight check...")

        DispatchQueue.global(qos: .userInitiated).async {
            if let preflightError = self.tcpPreflightErrorMessage(
                hostname: hostname,
                port: Int(host.port),
                timeout: min(timeout, 5)
            ) {
                print("[SSHClient] TCP preflight failed: \(preflightError)")
                DispatchQueue.main.async {
                    self.state = .error(preflightError)
                    self.isConnected = false
                }
                completion(.failure(.connectionFailed(preflightError)))
                return
            }

            print("[SSHClient] TCP preflight OK, creating NMSSHSession...")
            let session = NMSSHSession(host: hostname, port: Int(host.port), andUsername: username)
            session.timeout = NSNumber(value: timeout)
            session.delegate = self
            if let sha1Hash = NMSSHSessionHash(rawValue: 1) {
                session.fingerprintHash = sha1Hash
            }

            guard session.connect(), session.isConnected else {
                print("[SSHClient] NMSSHSession.connect() failed")
                let message = self.connectionFailureMessage(
                    for: session,
                    hostname: hostname,
                    port: Int(host.port)
                )
                print("[SSHClient] Connection failed: \(message)")
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
            print("[SSHClient] TCP connected, authenticating...")
            self.appendOutput("Authenticating as \(username)...\n")

            let authorized: Bool
            if host.useKeyAuth {
                print("[SSHClient] Attempting key authentication with key: \(keyName ?? "none")")
                guard let publicKey, let privateKey else {
                    session.disconnect()
                    let message = "Missing SSH key material for \(keyName ?? "selected key")"
                    print("[SSHClient] ERROR: \(message)")
                    DispatchQueue.main.async {
                        self.state = .error(message)
                        self.isConnected = false
                    }
                    completion(.failure(.authenticationFailed(message)))
                    return
                }

                authorized = session.authenticateBy(inMemoryPublicKey: publicKey, privateKey: privateKey, andPassword: nil)
            } else if let password, !password.isEmpty {
                print("[SSHClient] Attempting password authentication")
                authorized = session.authenticate(byPassword: password)
            } else {
                session.disconnect()
                let message = "No authentication method configured"
                print("[SSHClient] ERROR: \(message)")
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                }
                completion(.failure(.authenticationFailed(message)))
                return
            }

            guard authorized, session.isAuthorized else {
                let message = session.lastError?.localizedDescription ?? "Authentication failed"
                print("[SSHClient] Authentication failed: \(message)")
                session.disconnect()
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                }
                completion(.failure(.authenticationFailed(message)))
                return
            }

            print("[SSHClient] Authentication successful!")
            session.channel.requestPty = true

            self.sessionLock.withLock { self._session = session }
            DispatchQueue.main.async {
                self.state = .connected
                self.isConnected = true
                self.appendOutput("Connected!\n\n")
                completion(.success(()))
            }
        }
    }
    
    func disconnect() {
        var hadSession = false
        let oldSession: NMSSHSession? = sessionLock.withLock {
            hadSession = _session != nil
            let s = _session
            _session = nil
            _host = nil
            _hostVerificationFailureMessage = nil
            return s
        }
        oldSession?.disconnect()

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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var error: NSError?
            let response = session.channel.execute(command, error: &error, timeout: NSNumber(value: self.connectionTimeout))

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

    func session(_ session: NMSSHSession, shouldConnectToHostWithFingerprint fingerprint: String) -> Bool {
        let decision = SSHManager.shared.verifyHostFingerprint(
            fingerprint,
            hostname: session.host,
            port: session.port.intValue
        )

        switch decision {
        case .trustedKnownHost:
            return true
        case .trustedFirstUse:
            appendOutput("Trusted new host fingerprint for \(session.host):\(session.port.intValue).\n")
            return true
        case .rejectedMismatch(let expected, let actual):
            sessionLock.withLock {
                _hostVerificationFailureMessage = "Host key verification failed for \(session.host):\(session.port.intValue). Expected \(expected), received \(actual)."
            }
            return false
        }
    }

    private func connectionFailureMessage(for session: NMSSHSession, hostname: String, port: Int) -> String {
        if let verificationMessage = sessionLock.withLock({ _hostVerificationFailureMessage }) {
            return verificationMessage
        }

        if let rawMessage = session.lastError?.localizedDescription,
           !rawMessage.localizedCaseInsensitiveContains(inactiveSessionErrorFragment) {
            let lowercased = rawMessage.lowercased()
            if lowercased.contains("failure establishing ssh session") || lowercased.contains("socket connection") && lowercased.contains("successful") {
                return "SSH handshake with \(hostname):\(port) failed. This usually means the server requires newer encryption algorithms than this client supports. Try adding 'KexAlgorithms +diffie-hellman-group14-sha1' to your server's sshd_config, or use a different SSH client."
            }
            return rawMessage
        }

        return "Unable to connect to \(hostname):\(port). Check the host, port, and network reachability."
    }

    private func tcpPreflightErrorMessage(hostname: String, port: Int, timeout: TimeInterval) -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return "Invalid SSH port \(port)."
        }

        let connection = NWConnection(host: NWEndpoint.Host(hostname), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "SmartSSH.TCPPreflight")
        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var result: String?
        var finished = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            resultLock.lock()
            defer { resultLock.unlock() }

            guard !finished else { return }

            switch state {
            case .ready:
                finished = true
                result = nil
                semaphore.signal()
            case .failed(let error):
                finished = true
                result = self?.preflightMessage(for: error, hostname: hostname, port: port)
                semaphore.signal()
            case .waiting(let error):
                finished = true
                result = self?.preflightMessage(for: error, hostname: hostname, port: port)
                semaphore.signal()
            case .cancelled:
                finished = true
                result = "Connection check was cancelled."
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)

        resultLock.lock()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut && !finished {
            finished = true
            result = "Timed out reaching \(hostname):\(port). \(localNetworkGuidance)"
        }
        resultLock.unlock()

        connection.cancel()
        return result
    }

    private func preflightMessage(for error: NWError, hostname: String, port: Int) -> String {
        switch error {
        case .dns:
            return "Unable to resolve \(hostname). Check the host name or IP address."
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return "\(hostname):\(port) is reachable, but SSH refused the connection. Check that sshd is running and listening on port \(port)."
            case .ETIMEDOUT:
                return "Timed out reaching \(hostname):\(port). \(localNetworkGuidance)"
            case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN:
                return "\(hostname):\(port) is unreachable from this device. \(localNetworkGuidance)"
            case .EACCES, .EPERM:
                return "Network access to \(hostname):\(port) was denied. Check Local Network permission for SmartSSH in Settings."
            default:
                return "Network check failed for \(hostname):\(port): \(code.rawValue)."
            }
        default:
            return "Unable to reach \(hostname):\(port). Check the host, port, and network connection."
        }
    }
}

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
import NMSSH_riden

// MARK: - SSH Connection States

enum SSHConnectionState: Equatable {
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

class SSHClient: NSObject, ObservableObject, NMSSHSessionDelegate, NMSSHChannelDelegate {
    static let shared = SSHClient()

    // MARK: - Properties
    
    @Published var state: SSHConnectionState = .disconnected
    @Published var output: String = ""
    @Published var isConnected: Bool = false
    @Published var isShellActive: Bool = false
    
    private var connectionTimeout: TimeInterval {
        let saved = UserDefaults.standard.integer(forKey: "connectionTimeout")
        return saved > 0 ? TimeInterval(saved) : 30.0
    }
    
    /// Serializes all reads/writes of `_session` and `host`.
    private let sessionLock = NSLock()
    private var _session: NMSSHSession?
    private var _host: Host?
    private var _hostVerificationFailureMessage: String?
    private let outputLock = NSLock()
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

            var authorized: Bool
            if host.useKeyAuth, let publicKey, let privateKey {
                print("[SSHClient] Attempting key authentication with key: \(keyName ?? "none")")
                authorized = session.authenticateBy(inMemoryPublicKey: publicKey, privateKey: privateKey, andPassword: nil)
            } else if host.useKeyAuth {
                // Key auth was requested but key material is missing - fall back to password
                let allKeys = SSHManager.shared.loadSavedKeys()
                print("[SSHClient] Key '\(keyName ?? "none")' not found (available: \(allKeys.map { $0.name })). Falling back to password auth.")
                self.appendOutput("⚠️ SSH key '\(keyName ?? "selected key")' not found. Trying password...\n")
                if let password, !password.isEmpty {
                    // Try keyboard-interactive first (many servers require this for password auth)
                    authorized = session.authenticateByKeyboardInteractive { request in
                        // Server is asking for password via keyboard-interactive
                        print("[SSHClient] Keyboard-interactive request: \(request)")
                        return password
                    }

                    // Fall back to regular password auth if keyboard-interactive fails
                    if !authorized {
                        print("[SSHClient] Keyboard-interactive failed, trying regular password auth")
                        authorized = session.authenticate(byPassword: password)
                    }
                } else {
                    session.disconnect()
                    let message = "SSH key '\(keyName ?? "selected key")' is missing and no password is configured. Re-add the key in the Keys tab or edit the host to use password auth."
                    print("[SSHClient] ERROR: \(message)")
                    DispatchQueue.main.async {
                        self.state = .error(message)
                        self.isConnected = false
                    }
                    completion(.failure(.authenticationFailed(message)))
                    return
                }
            } else if let password, !password.isEmpty {
                print("[SSHClient] Attempting password authentication")
                // Try keyboard-interactive first (many servers require this for password auth)
                authorized = session.authenticateByKeyboardInteractive { request in
                    // Server is asking for password via keyboard-interactive
                    print("[SSHClient] Keyboard-interactive request: \(request)")
                    return password
                }

                // Fall back to regular password auth if keyboard-interactive fails
                if !authorized {
                    print("[SSHClient] Keyboard-interactive failed, trying regular password auth")
                    authorized = session.authenticate(byPassword: password)
                }
            } else {
                session.disconnect()
                let message = "No authentication method configured. Add a password or SSH key to this host."
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
            session.channel.ptyTerminalType = .xterm
            session.channel.delegate = self

            do {
                try session.channel.startShell()
            } catch {
                let message = error.localizedDescription
                print("[SSHClient] Shell startup failed: \(message)")
                session.disconnect()
                DispatchQueue.main.async {
                    self.state = .error(message)
                    self.isConnected = false
                    self.isShellActive = false
                }
                completion(.failure(.connectionFailed(message)))
                return
            }

            _ = session.channel.requestSizeWidth(120, height: 32)

            self.sessionLock.withLock { self._session = session }
            DispatchQueue.main.async {
                self.state = .connected
                self.isConnected = true
                self.isShellActive = true
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
            self.isShellActive = false
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
        guard let session = activeSession else {
            completion(.failure(.connectionFailed("Not connected")))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.isShellActive {
                var error: NSError?
                let success = session.channel.write(command + "\n", error: &error, timeout: NSNumber(value: self.connectionTimeout))

                if let error {
                    let message = error.localizedDescription
                    self.appendOutput("\(message)\n")
                    completion(.failure(.commandFailed(message)))
                    return
                }

                guard success else {
                    let message = "Failed to write to remote shell"
                    self.appendOutput("\(message)\n")
                    completion(.failure(.commandFailed(message)))
                    return
                }

                completion(.success(command))
                return
            }

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

    func requestTerminalSize(width: Int, height: Int) {
        guard width > 0, height > 0, let session = activeSession, isShellActive else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = session.channel.requestSizeWidth(UInt(width), height: UInt(height))
        }
    }
    
    // MARK: - Output Handling

    // Performance optimization: Batch small updates
    private var outputUpdateTimer: DispatchWorkItem?
    private var pendingOutput: String = ""

    func appendOutput(_ text: String) {
        outputLock.withLock {
            pendingOutput.append(text)
        }

        outputUpdateTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let flushedOutput = self.outputLock.withLock { () -> String in
                let value = self.pendingOutput
                self.pendingOutput = ""
                return value
            }
            DispatchQueue.main.async {
                self.output.append(flushedOutput)
            }
        }

        outputUpdateTimer = workItem

        // Dispatch after a short delay (accumulates rapid updates)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
    
    func clearOutput() {
        DispatchQueue.main.async {
            self.output = ""
        }
    }

    func channel(_ channel: NMSSHChannel, didReadData message: String) {
        appendOutput(message)
    }

    func channel(_ channel: NMSSHChannel, didReadError error: String) {
        appendOutput(error)
    }

    func channelShellDidClose(_ channel: NMSSHChannel) {
        DispatchQueue.main.async {
            self.isShellActive = false
            if self.isConnected {
                self.appendOutput("\nRemote shell closed.\n")
            }
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

        connection.stateUpdateHandler = { [weak self] state in
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
            case .waiting:
                // Do NOT treat .waiting as failure - this is normal for local network
                // connections while iOS resolves local network permission.
                // Let it keep waiting until timeout.
                break
            case .cancelled:
                finished = true
                result = "Connection check was cancelled."
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)

        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        resultLock.lock()
        if timedOut && !finished {
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

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
import CoreFoundation

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
    @Published var activePortForwardPorts: [Int] = []

    private static let minimumKeepAliveInterval = 10

    private var connectionTimeout: TimeInterval {
        let saved = UserDefaults.standard.integer(forKey: "connectionTimeout")
        return saved > 0 ? TimeInterval(saved) : 30.0
    }

    private var keepAliveInterval: TimeInterval {
        TimeInterval(Self.sanitizedKeepAliveInterval(UserDefaults.standard.integer(forKey: "keepAliveInterval")))
    }
    
    /// Serializes all reads/writes of `_session` and `host`.
    private let sessionLock = NSLock()
    private var _session: NMSSHSession?
    private var _host: Host?
    private var _hostVerificationFailureMessage: String?
    private let outputLock = NSLock()
    private let inactiveSessionErrorFragment = "absence of an active session"
    private let localNetworkGuidance = "Make sure your iPhone is on the same network and SmartSSH has Local Network access enabled in Settings."
    private var keepAliveTimer: DispatchSourceTimer?
    private let portForwardLock = NSLock()
    private var portForwardRuntimes: [UUID: PortForwardRuntime] = [:]
    private var lastRequestedTerminalSize: (width: Int, height: Int)?

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

    static func sanitizedKeepAliveInterval(_ value: Int) -> Int {
        max(value, minimumKeepAliveInterval)
    }

    static func enabledPortForwards(from forwards: [Host.PortForward]) -> [Host.PortForward] {
        forwards
            .filter { $0.isEnabled && $0.isValid }
            .sorted { $0.localPort < $1.localPort }
    }

    static func portForwardStatusSummary(for forwards: [Host.PortForward]) -> String {
        enabledPortForwards(from: forwards)
            .map(\.localPort)
            .map(String.init)
            .joined(separator: ", ")
    }

    static func resolvedForwardDestination(for host: Host, forward: Host.PortForward) -> (host: String, port: Int) {
        let remoteHost = forward.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesJumpHost = host.routingOptions?.jumpHostID != nil
        let shouldRewriteLoopback = usesJumpHost && ["127.0.0.1", "localhost", "::1"].contains(remoteHost.lowercased())

        return (
            host: shouldRewriteLoopback ? host.wrappedHostname : remoteHost,
            port: forward.remotePort
        )
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
                self.appendConnectionPlan(for: host)
                self.startKeepAliveLoop()
                self.startPortForwards(for: host)
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
        stopKeepAliveLoop()
        stopPortForwards()

        DispatchQueue.main.async {
            self.state = .disconnected
            self.isConnected = false
            self.isShellActive = false
            self.activePortForwardPorts = []
            self.lastRequestedTerminalSize = nil  // Reset terminal size tracking
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

        // Debounce: Only send if size actually changed
        if let last = lastRequestedTerminalSize, last.width == width && last.height == height {
            return
        }
        lastRequestedTerminalSize = (width, height)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = session.channel.requestSizeWidth(UInt(width), height: UInt(height))
        }
    }
    
    // MARK: - Output Handling

    // Performance optimization: Batch small updates
    private var outputUpdateTimer: DispatchWorkItem?
    private var pendingOutput: String = ""
    private let maxPendingOutputSize = 100_000  // ~100KB limit to prevent memory issues

    func appendOutput(_ text: String) {
        outputLock.withLock {
            pendingOutput.append(text)

            // Prevent unbounded growth if main thread is blocked
            if pendingOutput.count > maxPendingOutputSize {
                // Flush immediately to avoid memory pressure
                let value = pendingOutput
                pendingOutput = ""
                DispatchQueue.main.async {
                    self.output.append(value)
                }
                return
            }
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

    func session(_ session: NMSSHSession, didDisconnectWithError error: Error) {
        stopKeepAliveLoop()

        let wasActiveSession = sessionLock.withLock { _session === session }
        guard wasActiveSession else { return }

        DispatchQueue.main.async {
            self.isConnected = false
            self.isShellActive = false
            self.activePortForwardPorts = []
            let message = error.localizedDescription.isEmpty ? "SSH session disconnected unexpectedly." : error.localizedDescription
            self.state = .error(message)
            self.appendOutput("\nSession disconnected: \(message)\n")
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

    private func appendConnectionPlan(for host: Host) {
        let forwards = Self.enabledPortForwards(from: host.portForwards)
        if !forwards.isEmpty {
            appendOutput("Saved local forwards:\n")
            for forward in forwards {
                appendOutput("  - \(forward.summary)\n")
            }
        }

        if let routing = host.routingOptions {
            if routing.jumpHostID != nil {
                appendOutput("Jump host is configured for this connection.\n")
            }

            if let proxy = routing.proxy {
                appendOutput("Proxy configured: \(proxy.type.displayName) \(proxy.host):\(proxy.port)\n")
            }
        }
    }

    private func startPortForwards(for host: Host) {
        stopPortForwards()

        let forwards = Self.enabledPortForwards(from: host.portForwards)
        guard !forwards.isEmpty else {
            DispatchQueue.main.async {
                self.activePortForwardPorts = []
            }
            return
        }

        var startedPorts: [Int] = []
        for forward in forwards {
            do {
                let runtime = try PortForwardRuntime(
                    host: host,
                    forward: forward,
                    outputHandler: { [weak self] message in
                        self?.appendOutput(message)
                    }
                )
                try runtime.start()
                portForwardLock.withLock {
                    portForwardRuntimes[forward.id] = runtime
                }
                startedPorts.append(forward.localPort)
            } catch {
                appendOutput("Failed to start local forward \(forward.summary): \(error.localizedDescription)\n")
            }
        }

        DispatchQueue.main.async {
            self.activePortForwardPorts = startedPorts.sorted()
        }

        if !startedPorts.isEmpty {
            appendOutput("Listening for local forwards on ports: \(startedPorts.sorted().map(String.init).joined(separator: ", "))\n")
        }
    }

    private func stopPortForwards() {
        let runtimes = portForwardLock.withLock { () -> [PortForwardRuntime] in
            let values = Array(portForwardRuntimes.values)
            portForwardRuntimes.removeAll()
            return values
        }

        for runtime in runtimes {
            runtime.stop()
        }
    }

    private func startKeepAliveLoop() {
        stopKeepAliveLoop()

        guard activeSession != nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + keepAliveInterval, repeating: keepAliveInterval)
        timer.setEventHandler { [weak self] in
            self?.performKeepAliveTick()
        }
        keepAliveTimer = timer
        timer.resume()
    }

    private func stopKeepAliveLoop() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
    }

    private func performKeepAliveTick() {
        guard let session = activeSession else {
            stopKeepAliveLoop()
            return
        }

        guard session.isConnected, session.isAuthorized else {
            stopKeepAliveLoop()
            DispatchQueue.main.async {
                self.state = .error("Connection lost")
                self.isConnected = false
                self.isShellActive = false
                self.appendOutput("\n⚠️ Connection lost. Please reconnect.\n")
            }
            return
        }

        guard isShellActive else { return }

        var error: NSError?
        _ = session.channel.write("", error: &error, timeout: NSNumber(value: connectionTimeout))

        if let error {
            stopKeepAliveLoop()
            DispatchQueue.main.async {
                self.state = .error("Keep-alive failed")
                self.isConnected = false
                self.isShellActive = false
                self.appendOutput("\n⚠️ Keep-alive failed: \(error.localizedDescription)\n")
            }
        }
    }
}

private final class PortForwardRuntime {
    private let host: Host
    private let forward: Host.PortForward
    private let outputHandler: (String) -> Void
    private let queue: DispatchQueue
    private let route: TunnelRoute
    private var listener: NWListener?
    private var activeConnections: [UUID: PortForwardConnection] = [:]
    private let activeConnectionsLock = NSLock()

    init(host: Host, forward: Host.PortForward, outputHandler: @escaping (String) -> Void) throws {
        self.host = host
        self.forward = forward
        self.outputHandler = outputHandler
        self.queue = DispatchQueue(label: "SmartSSH.PortForward.\(forward.localPort)")
        self.route = try TunnelRoute(host: host)
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(forward.localPort)))

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.outputHandler("Local forward ready: \(self.forward.summary)\n")
            case .failed(let error):
                self.outputHandler("Local forward failed on \(self.forward.localPort): \(error.localizedDescription)\n")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil

        let connections = activeConnectionsLock.withLock { () -> [PortForwardConnection] in
            let values = Array(activeConnections.values)
            activeConnections.removeAll()
            return values
        }

        for connection in connections {
            connection.stop()
        }
    }

    private func accept(connection: NWConnection) {
        let runtime = PortForwardConnection(
            host: host,
            route: route,
            forward: forward,
            connection: connection,
            outputHandler: outputHandler,
            onStop: { [weak self] id in
                _ = self?.activeConnectionsLock.withLock {
                    self?.activeConnections.removeValue(forKey: id)
                }
            }
        )

        activeConnectionsLock.withLock {
            activeConnections[runtime.id] = runtime
        }
        runtime.start()
    }
}

private final class PortForwardConnection {
    let id = UUID()

    private let host: Host
    private let route: TunnelRoute
    private let forward: Host.PortForward
    private let connection: NWConnection
    private let outputHandler: (String) -> Void
    private let onStop: (UUID) -> Void
    private let queue: DispatchQueue

    private var tunnelSession: LibSSH2TunnelSession?
    private var rawChannel: OpaquePointer?
    private var pollTimer: DispatchSourceTimer?
    private var isStopped = false

    init(
        host: Host,
        route: TunnelRoute,
        forward: Host.PortForward,
        connection: NWConnection,
        outputHandler: @escaping (String) -> Void,
        onStop: @escaping (UUID) -> Void
    ) {
        self.host = host
        self.route = route
        self.forward = forward
        self.connection = connection
        self.outputHandler = outputHandler
        self.onStop = onStop
        self.queue = DispatchQueue(label: "SmartSSH.PortForward.Connection.\(forward.localPort).\(UUID().uuidString)")
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.queue.async {
                    self.handleReadyConnection()
                }
            case .failed(let error):
                self.outputHandler("Forward client on \(self.forward.localPort) failed: \(error.localizedDescription)\n")
                self.stop()
            case .cancelled:
                self.stop()
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    func stop() {
        queue.async {
            guard !self.isStopped else { return }
            self.isStopped = true
            self.pollTimer?.cancel()
            self.pollTimer = nil

            if let rawChannel = self.rawChannel {
                libssh2_channel_close(rawChannel)
                libssh2_channel_free(rawChannel)
                self.rawChannel = nil
            }

            if let tunnelSession = self.tunnelSession {
                tunnelSession.close()
                self.tunnelSession = nil
            }

            self.connection.cancel()
            self.onStop(self.id)
        }
    }

    private func handleReadyConnection() {
        do {
            let tunnelSession = try LibSSH2TunnelSession(route: route)
            let destination = SSHClient.resolvedForwardDestination(for: host, forward: forward)
            let channel = try tunnelSession.openDirectTCPIPChannel(
                host: destination.host,
                port: destination.port,
                originPort: forward.localPort
            )

            self.tunnelSession = tunnelSession
            self.rawChannel = channel

            outputHandler("Forward active: localhost:\(forward.localPort) -> \(destination.host):\(destination.port)\n")
            startReadPolling()
            scheduleReceive()
        } catch {
            outputHandler("Forward setup failed for \(forward.summary): \(error.localizedDescription)\n")
            stop()
        }
    }

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.outputHandler("Forward local read failed on \(self.forward.localPort): \(error.localizedDescription)\n")
                self.stop()
                return
            }

            if let data, !data.isEmpty {
                self.queue.async {
                    self.writeToSSH(data: data)
                }
            }

            if isComplete {
                self.stop()
                return
            }

            self.scheduleReceive()
        }
    }

    private func startReadPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            self?.pumpSSHReads()
        }
        pollTimer = timer
        timer.resume()
    }

    private func writeToSSH(data: Data) {
        guard let rawChannel else { return }

        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let written = bytes.withUnsafeBufferPointer { buffer -> Int in
                let base = buffer.baseAddress!.advanced(by: offset)
                return Int(libssh2_channel_write_ex(rawChannel, 0, base, remaining))
            }

            if written == LIBSSH2_ERROR_EAGAIN {
                usleep(2_000)
                continue
            }

            if written <= 0 {
                self.outputHandler("Forward remote write failed on \(self.forward.localPort).\n")
                self.stop()
                return
            }

            offset += written
        }
    }

    private func pumpSSHReads() {
        var chunks: [Data] = []
        var shouldStop = false

        guard let rawChannel else { return }

        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let read = libssh2_channel_read_ex(rawChannel, 0, &buffer, buffer.count)
            if read > 0 {
                chunks.append(Data(buffer.prefix(Int(read))))
                continue
            }

            if read == 0 {
                if libssh2_channel_eof(rawChannel) == 1 {
                    shouldStop = true
                }
                break
            }

            if read == LIBSSH2_ERROR_EAGAIN {
                break
            }

            shouldStop = true
            break
        }

        for chunk in chunks {
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.outputHandler("Forward local write failed on \(self?.forward.localPort ?? 0): \(error.localizedDescription)\n")
                    self?.stop()
                }
            })
        }

        if shouldStop {
            stop()
        }
    }
}

private struct TunnelRoute {
    let targetHost: TunnelRouteHost
    let jumpHost: TunnelRouteHost?
    let proxy: Host.ProxyConfiguration?

    init(host: Host) throws {
        self.targetHost = TunnelRouteHost(host: host)
        self.proxy = host.routingOptions?.proxy

        if let jumpHostID = host.routingOptions?.jumpHostID,
           let jumpHost = try TunnelRoute.lookupHost(by: jumpHostID) {
            self.jumpHost = TunnelRouteHost(host: jumpHost)
        } else {
            self.jumpHost = nil
        }
    }

    private static func lookupHost(by id: UUID) throws -> Host? {
        let context = DataController.shared.container.viewContext
        var result: Host?
        var fetchError: Error?

        context.performAndWait {
            do {
                let request = Host.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                result = try context.fetch(request).first
            } catch {
                fetchError = error
            }
        }

        if let fetchError {
            throw fetchError
        }

        return result
    }
}

private struct TunnelRouteHost {
    let hostname: String
    let port: Int
    let username: String
    let password: String?
    let publicKey: String?
    let privateKey: String?
    let useKeyAuth: Bool

    init(host: Host) {
        self.hostname = host.wrappedHostname
        self.port = Int(host.port)
        self.username = host.wrappedUsername
        self.password = host.password
        self.useKeyAuth = host.useKeyAuth

        let keyName = host.keyFingerprint
        self.publicKey = SSHManager.shared.loadSavedKeys().first(where: { $0.name == keyName })?.publicKey
        self.privateKey = keyName.flatMap { SSHManager.shared.privateKey(named: $0) }
    }
}

private final class LibSSH2TunnelSession {
    private static let initializeLibSSH2: Void = {
        _ = libssh2_init(0)
    }()

    private let route: TunnelRoute
    private var socketFD: Int32 = -1
    private var session: OpaquePointer?

    init(route: TunnelRoute) throws {
        Self.initializeLibSSH2
        self.route = route
        try connectAndAuthenticate()
    }

    func openDirectTCPIPChannel(host: String, port: Int, originPort: Int) throws -> OpaquePointer {
        guard let session else {
            throw SSHError.connectionFailed("Tunnel session is not connected.")
        }

        libssh2_session_set_blocking(session, 0)

        guard let channel = libssh2_channel_direct_tcpip_ex(
            session,
            host,
            Int32(port),
            "127.0.0.1",
            Int32(originPort)
        ) else {
            throw SSHError.connectionFailed("Could not open direct TCP/IP channel to \(host):\(port).")
        }

        return channel
    }

    func close() {
        if let session {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "SmartSSH tunnel closing", "")
            libssh2_session_free(session)
            self.session = nil
        }

        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    deinit {
        close()
    }

    private func connectAndAuthenticate() throws {
        let endpoint = route.jumpHost ?? route.targetHost
        socketFD = try TunnelSocket.open(to: endpoint.hostname, port: endpoint.port, proxy: route.proxy)

        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            throw SSHError.connectionFailed("Could not initialize libssh2 session.")
        }

        if libssh2_session_handshake(session, socketFD) != 0 {
            libssh2_session_free(session)
            throw SSHError.connectionFailed("SSH handshake failed for forwarded connection.")
        }

        if endpoint.useKeyAuth, let publicKey = endpoint.publicKey, let privateKey = endpoint.privateKey {
            let result = libssh2_userauth_publickey_frommemory(
                session,
                endpoint.username,
                endpoint.username.utf8.count,
                publicKey,
                publicKey.utf8.count,
                privateKey,
                privateKey.utf8.count,
                nil
            )
            guard result == 0 else {
                libssh2_session_free(session)
                throw SSHError.authenticationFailed("SSH key authentication failed for forwarded connection.")
            }
        } else if let password = endpoint.password, !password.isEmpty {
            let result = libssh2_userauth_password_ex(
                session,
                endpoint.username,
                UInt32(endpoint.username.utf8.count),
                password,
                UInt32(password.utf8.count),
                nil
            )
            guard result == 0 else {
                libssh2_session_free(session)
                throw SSHError.authenticationFailed("Password authentication failed for forwarded connection.")
            }
        } else {
            libssh2_session_free(session)
            throw SSHError.authenticationFailed("Forwarded connection has no usable authentication method.")
        }

        self.session = session
    }
}

private enum TunnelSocket {
    static func open(to host: String, port: Int, proxy: Host.ProxyConfiguration?) throws -> Int32 {
        if let proxy {
            let socketFD = try connectSocket(host: proxy.host, port: proxy.port)
            do {
                switch proxy.type {
                case .http:
                    try performHTTPConnect(socketFD: socketFD, targetHost: host, targetPort: port)
                case .socks5:
                    try performSOCKS5Connect(socketFD: socketFD, targetHost: host, targetPort: port)
                }
                return socketFD
            } catch {
                Darwin.close(socketFD)
                throw error
            }
        }

        return try connectSocket(host: host, port: port)
    }

    private static func connectSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let service = String(port)
        let status = getaddrinfo(host, service, &hints, &result)
        guard status == 0, let result else {
            throw SSHError.connectionFailed("Unable to resolve \(host):\(port).")
        }
        defer { freeaddrinfo(result) }

        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let info = pointer {
            let socketFD = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketFD >= 0 {
                let connectResult = Darwin.connect(socketFD, info.pointee.ai_addr, info.pointee.ai_addrlen)
                if connectResult == 0 {
                    return socketFD
                }
                Darwin.close(socketFD)
            }
            pointer = info.pointee.ai_next
        }

        throw SSHError.connectionFailed("Could not connect to \(host):\(port).")
    }

    private static func performHTTPConnect(socketFD: Int32, targetHost: String, targetPort: Int) throws {
        let request = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\nHost: \(targetHost):\(targetPort)\r\n\r\n"
        try writeAll(socketFD: socketFD, data: Data(request.utf8))
        let response = try readUntil(socketFD: socketFD, terminator: Data("\r\n\r\n".utf8), maxLength: 4096)
        guard let text = String(data: response, encoding: .utf8),
              text.contains(" 200 ") else {
            throw SSHError.connectionFailed("HTTP proxy CONNECT failed.")
        }
    }

    private static func performSOCKS5Connect(socketFD: Int32, targetHost: String, targetPort: Int) throws {
        try writeAll(socketFD: socketFD, data: Data([0x05, 0x01, 0x00]))
        let methodReply = try readExact(socketFD: socketFD, count: 2)
        guard methodReply.count == 2, methodReply[1] == 0x00 else {
            throw SSHError.connectionFailed("SOCKS5 proxy requires unsupported authentication.")
        }

        var request = Data([0x05, 0x01, 0x00])
        if let ipv4 = IPv4Address(targetHost) {
            request.append(0x01)
            request.append(contentsOf: ipv4.rawValue)
        } else {
            let hostData = Data(targetHost.utf8)
            request.append(0x03)
            request.append(UInt8(hostData.count))
            request.append(hostData)
        }
        request.append(UInt8((targetPort >> 8) & 0xFF))
        request.append(UInt8(targetPort & 0xFF))

        try writeAll(socketFD: socketFD, data: request)

        let header = try readExact(socketFD: socketFD, count: 4)
        guard header.count == 4, header[1] == 0x00 else {
            throw SSHError.connectionFailed("SOCKS5 CONNECT failed.")
        }

        let atyp = header[3]
        switch atyp {
        case 0x01:
            _ = try readExact(socketFD: socketFD, count: 4 + 2)
        case 0x03:
            let length = Int(try readExact(socketFD: socketFD, count: 1)[0])
            _ = try readExact(socketFD: socketFD, count: length + 2)
        case 0x04:
            _ = try readExact(socketFD: socketFD, count: 16 + 2)
        default:
            throw SSHError.connectionFailed("SOCKS5 proxy returned an unknown address type.")
        }
    }

    private static func writeAll(socketFD: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.send(socketFD, baseAddress.advanced(by: offset), data.count - offset, 0)
                if written <= 0 {
                    throw SSHError.connectionFailed("Socket write failed.")
                }
                offset += written
            }
        }
    }

    private static func readExact(socketFD: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        let bytesRead = try data.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            var offset = 0
            while offset < count {
                let read = Darwin.recv(socketFD, baseAddress.advanced(by: offset), count - offset, 0)
                if read <= 0 {
                    throw SSHError.connectionFailed("Socket read failed.")
                }
                offset += read
            }
            return offset
        }
        return data.prefix(bytesRead)
    }

    private static func readUntil(socketFD: Int32, terminator: Data, maxLength: Int) throws -> Data {
        var buffer = Data()
        while buffer.count < maxLength {
            var byte: UInt8 = 0
            let read = Darwin.recv(socketFD, &byte, 1, 0)
            if read <= 0 {
                throw SSHError.connectionFailed("Socket read failed.")
            }
            buffer.append(byte)
            if buffer.suffix(terminator.count) == terminator {
                return buffer
            }
        }
        throw SSHError.connectionFailed("Socket read exceeded expected response length.")
    }
}

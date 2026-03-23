//
//  SessionStore.swift
//  SmartSSH
//
//  Tracks multiple concurrent SSH sessions and the currently selected session.
//

import Foundation
import Combine

final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [StoredSession] = []
    @Published var selectedSessionID: UUID?

    private var clientSubscriptions: [UUID: AnyCancellable] = [:]

    var selectedSession: StoredSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    func connect(
        to host: Host,
        completion: @escaping (Result<StoredSession, SSHError>) -> Void
    ) {
        let storedSession = StoredSession(host: host, client: SSHClient())

        DispatchQueue.main.async {
            host.status = "connecting"
            self.sessions.append(storedSession)
            self.selectedSessionID = storedSession.id
            self.observe(storedSession)
        }

        storedSession.client.connect(to: host) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    host.status = "connected"
                    host.lastConnectedAt = Date()
                    self.objectWillChange.send()
                    completion(.success(storedSession))
                case .failure(let error):
                    host.status = "error"
                    self.removeSession(withID: storedSession.id, syncHost: false)
                    completion(.failure(error))
                }
            }
        }
    }

    func select(sessionID: UUID) {
        selectedSessionID = sessionID
        objectWillChange.send()
    }

    func disconnectSelectedSession() {
        guard let selectedSession else { return }
        disconnect(sessionID: selectedSession.id)
    }

    func disconnect(sessionID: UUID) {
        guard let storedSession = sessions.first(where: { $0.id == sessionID }) else { return }
        storedSession.client.disconnect()
        removeSession(withID: sessionID, syncHost: true)
    }

    func status(for host: Host) -> String {
        let matching = sessions.filter { $0.host.objectID == host.objectID }
        guard !matching.isEmpty else { return "disconnected" }
        if matching.contains(where: { $0.client.isConnected }) { return "connected" }
        if matching.contains(where: { session in
            if case .connecting = session.client.state { return true }
            if case .authenticating = session.client.state { return true }
            return false
        }) {
            return "connecting"
        }
        if matching.contains(where: {
            if case .error = $0.client.state { return true }
            return false
        }) {
            return "error"
        }
        return "disconnected"
    }

    private func observe(_ storedSession: StoredSession) {
        clientSubscriptions[storedSession.id] = storedSession.client.objectWillChange.sink { [weak self, weak host = storedSession.host] _ in
            DispatchQueue.main.async {
                if let host {
                    self?.syncHostStatus(for: host)
                }
                self?.objectWillChange.send()
            }
        }
    }

    private func removeSession(withID sessionID: UUID, syncHost: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let host = sessions[index].host
        sessions.remove(at: index)
        clientSubscriptions[sessionID] = nil

        if selectedSessionID == sessionID {
            selectedSessionID = sessions.last?.id
        }

        if syncHost {
            syncHostStatus(for: host)
        }
        objectWillChange.send()
    }

    private func syncHostStatus(for host: Host) {
        host.status = status(for: host)
    }
}

final class StoredSession: Identifiable {
    let id = UUID()
    let host: Host
    let client: SSHClient

    init(host: Host, client: SSHClient) {
        self.host = host
        self.client = client
    }
}

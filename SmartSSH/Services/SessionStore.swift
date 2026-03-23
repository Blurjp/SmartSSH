//
//  SessionStore.swift
//  SmartSSH
//
//  Tracks multiple concurrent SSH sessions and the currently selected session.
//

import Foundation
import Combine
import CoreData

final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [StoredSession] = []
    @Published var selectedSessionID: UUID?
    @Published var splitSessionID: UUID?
    @Published var isSplitViewEnabled = false

    private var clientSubscriptions: [UUID: AnyCancellable] = [:]
    private let workspaceHostIDsKey = "workspace_open_host_ids"
    private let workspaceSelectedHostIDKey = "workspace_selected_host_id"
    private let workspaceSplitHostIDKey = "workspace_split_host_id"
    private let workspaceSplitEnabledKey = "workspace_split_enabled"
    private var isRestoringWorkspace = false

    var selectedSession: StoredSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    var splitSession: StoredSession? {
        guard let splitSessionID else { return nil }
        return sessions.first(where: { $0.id == splitSessionID })
    }

    func connect(
        to host: Host,
        completion: @escaping (Result<StoredSession, SSHError>) -> Void
    ) {
        if let existingSession = session(for: host) {
            DispatchQueue.main.async {
                self.selectedSessionID = existingSession.id
                self.persistWorkspace()
                completion(.success(existingSession))
            }
            return
        }

        let storedSession = StoredSession(host: host, client: SSHClient())

        DispatchQueue.main.async {
            host.status = "connecting"
            self.sessions.append(storedSession)
            self.selectedSessionID = storedSession.id
            if self.splitSessionID == self.selectedSessionID {
                self.splitSessionID = nil
            }
            self.observe(storedSession)
            self.persistWorkspace()
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
        if splitSessionID == sessionID {
            splitSessionID = nil
        }
        persistWorkspace()
        objectWillChange.send()
    }

    func setSplitSession(sessionID: UUID?) {
        guard let sessionID else {
            splitSessionID = nil
            isSplitViewEnabled = false
            persistWorkspace()
            objectWillChange.send()
            return
        }

        guard selectedSessionID != sessionID else {
            splitSessionID = nil
            isSplitViewEnabled = false
            persistWorkspace()
            objectWillChange.send()
            return
        }

        splitSessionID = sessionID
        isSplitViewEnabled = true
        persistWorkspace()
        objectWillChange.send()
    }

    func toggleSplitView() {
        guard sessions.count > 1 else {
            isSplitViewEnabled = false
            splitSessionID = nil
            persistWorkspace()
            objectWillChange.send()
            return
        }

        if isSplitViewEnabled {
            isSplitViewEnabled = false
            splitSessionID = nil
        } else {
            isSplitViewEnabled = true
            if splitSessionID == nil || splitSessionID == selectedSessionID {
                splitSessionID = sessions.first(where: { $0.id != selectedSessionID })?.id
            }
        }
        persistWorkspace()
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
        if splitSessionID == sessionID {
            splitSessionID = sessions.first(where: { $0.id != selectedSessionID })?.id
        }
        if sessions.count < 2 {
            splitSessionID = nil
            isSplitViewEnabled = false
        } else if isSplitViewEnabled && splitSessionID == nil {
            splitSessionID = sessions.first(where: { $0.id != selectedSessionID })?.id
        }

        if syncHost {
            syncHostStatus(for: host)
        }
        persistWorkspace()
        objectWillChange.send()
    }

    private func syncHostStatus(for host: Host) {
        host.status = status(for: host)
    }

    private func session(for host: Host) -> StoredSession? {
        sessions.first { $0.host.objectID == host.objectID }
    }

    func restoreWorkspace(in context: NSManagedObjectContext) {
        guard !isRestoringWorkspace, sessions.isEmpty else { return }

        let hostIDs = UserDefaults.standard.stringArray(forKey: workspaceHostIDsKey)?
            .compactMap(UUID.init(uuidString:))
            ?? []
        guard !hostIDs.isEmpty else { return }

        let selectedHostID = UserDefaults.standard.string(forKey: workspaceSelectedHostIDKey).flatMap(UUID.init(uuidString:))
        let splitHostID = UserDefaults.standard.string(forKey: workspaceSplitHostIDKey).flatMap(UUID.init(uuidString:))
        let shouldEnableSplit = UserDefaults.standard.bool(forKey: workspaceSplitEnabledKey)

        let request = Host.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", hostIDs)

        do {
            let hosts = try context.fetch(request)
            let hostMap = Dictionary(uniqueKeysWithValues: hosts.compactMap { host in
                host.id.map { ($0, host) }
            })

            isRestoringWorkspace = true
            restoreNextHost(
                from: hostIDs,
                hostMap: hostMap,
                index: 0,
                selectedHostID: selectedHostID,
                splitHostID: splitHostID,
                shouldEnableSplit: shouldEnableSplit
            )
        } catch {
            isRestoringWorkspace = false
            print("[SessionStore] Failed to restore workspace: \(error.localizedDescription)")
        }
    }

    private func restoreNextHost(
        from hostIDs: [UUID],
        hostMap: [UUID: Host],
        index: Int,
        selectedHostID: UUID?,
        splitHostID: UUID?,
        shouldEnableSplit: Bool
    ) {
        guard index < hostIDs.count else {
            finalizeWorkspaceRestore(selectedHostID: selectedHostID, splitHostID: splitHostID, shouldEnableSplit: shouldEnableSplit)
            return
        }

        let hostID = hostIDs[index]
        guard let host = hostMap[hostID] else {
            restoreNextHost(
                from: hostIDs,
                hostMap: hostMap,
                index: index + 1,
                selectedHostID: selectedHostID,
                splitHostID: splitHostID,
                shouldEnableSplit: shouldEnableSplit
            )
            return
        }

        connect(to: host) { _ in
            self.restoreNextHost(
                from: hostIDs,
                hostMap: hostMap,
                index: index + 1,
                selectedHostID: selectedHostID,
                splitHostID: splitHostID,
                shouldEnableSplit: shouldEnableSplit
            )
        }
    }

    private func finalizeWorkspaceRestore(
        selectedHostID: UUID?,
        splitHostID: UUID?,
        shouldEnableSplit: Bool
    ) {
        defer {
            isRestoringWorkspace = false
            persistWorkspace()
            objectWillChange.send()
        }

        if let selectedHostID,
           let selectedSession = sessions.first(where: { $0.host.id == selectedHostID }) {
            selectedSessionID = selectedSession.id
        } else {
            selectedSessionID = sessions.first?.id
        }

        if shouldEnableSplit,
           let splitHostID,
           let splitSession = sessions.first(where: { $0.host.id == splitHostID && $0.id != selectedSessionID }) {
            splitSessionID = splitSession.id
            isSplitViewEnabled = true
        } else {
            splitSessionID = nil
            isSplitViewEnabled = false
        }
    }

    private func persistWorkspace() {
        guard !isRestoringWorkspace else { return }

        let defaults = UserDefaults.standard
        defaults.set(
            sessions.compactMap { $0.host.id?.uuidString },
            forKey: workspaceHostIDsKey
        )
        defaults.set(
            selectedSession?.host.id?.uuidString,
            forKey: workspaceSelectedHostIDKey
        )
        defaults.set(
            splitSession?.host.id?.uuidString,
            forKey: workspaceSplitHostIDKey
        )
        defaults.set(isSplitViewEnabled, forKey: workspaceSplitEnabledKey)
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

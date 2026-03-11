//
//  SFTPClient.swift
//  SSH Terminal
//
//  SFTP file browser functionality
//

import Foundation
import NMSSH

// MARK: - SFTP File Model

struct SFTPFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date
    let permissions: String
    
    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log": return "doc.text"
        case "jpg", "jpeg", "png", "gif", "bmp": return "photo"
        case "mp4", "mov", "avi": return "video"
        case "mp3", "wav", "aac": return "music.note"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "java", "cpp": return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml": return "doc.badge.gearshape"
        default: return "doc"
        }
    }
    
    var iconColor: String {
        if isDirectory { return "blue" }
        
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif": return "green"
        case "mp4", "mov": return "red"
        case "mp3", "wav": return "pink"
        case "zip", "tar", "gz": return "orange"
        case "pdf": return "red"
        case "swift": return "orange"
        case "py": return "blue"
        case "js": return "yellow"
        default: return "gray"
        }
    }
    
    var formattedSize: String {
        if isDirectory { return "--" }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
}

// MARK: - SFTP Client

class SFTPClient: ObservableObject {
    static let shared = SFTPClient()

    private let unavailableMessage = "Connect to a host before starting an SFTP session."
    
    @Published var currentPath: String = "/"
    @Published var files: [SFTPFile] = []
    @Published var isLoading: Bool = false
    @Published var pathHistory: [String] = ["/"]
    @Published var historyIndex: Int = 0
    
    private var session: Any? // NMSSHSession in production
    
    // MARK: - Directory Operations
    
    func listDirectory(_ path: String, completion: @escaping (Result<[SFTPFile], SFTPError>) -> Void) {
        isLoading = true
        currentPath = path

        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                DispatchQueue.main.async {
                    self.files = []
                    self.isLoading = false
                    completion(.failure(.connectionFailed(self.unavailableMessage)))
                }
                return
            }

            guard let remoteFiles = sftp.contentsOfDirectory(atPath: path) else {
                let message = sftp.session.lastError?.localizedDescription ?? "Unable to list directory"
                DispatchQueue.main.async {
                    self.files = []
                    self.isLoading = false
                    completion(.failure(.operationFailed(message)))
                }
                return
            }

            let files = remoteFiles
                .filter { $0.filename != "." && $0.filename != ".." }
                .map { self.makeFile(from: $0, parentPath: path) }
                .sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

            DispatchQueue.main.async {
                self.files = files
                self.isLoading = false
                completion(.success(files))
            }
        }
    }
    
    func navigateUp() {
        let parentPath = (currentPath as NSString).deletingLastPathComponent
        if !parentPath.isEmpty {
            addToHistory(parentPath)
            listDirectory(parentPath) { _ in }
        }
    }
    
    func navigateTo(_ path: String) {
        addToHistory(path)
        listDirectory(path) { _ in }
    }
    
    func goBack() {
        if historyIndex > 0 {
            historyIndex -= 1
            let path = pathHistory[historyIndex]
            listDirectory(path) { _ in }
        }
    }
    
    func goForward() {
        if historyIndex < pathHistory.count - 1 {
            historyIndex += 1
            let path = pathHistory[historyIndex]
            listDirectory(path) { _ in }
        }
    }
    
    private func addToHistory(_ path: String) {
        // Remove forward history when navigating to new path
        if historyIndex < pathHistory.count - 1 {
            pathHistory = Array(pathHistory.prefix(historyIndex + 1))
        }
        pathHistory.append(path)
        historyIndex = pathHistory.count - 1
    }
    
    // MARK: - File Operations
    
    func downloadFile(_ file: SFTPFile, to localPath: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                completion(.failure(.connectionFailed(self.unavailableMessage)))
                return
            }

            let data = sftp.contents(atPath: file.path)
            guard let data else {
                let message = sftp.session.lastError?.localizedDescription ?? "Unable to download file"
                completion(.failure(.operationFailed(message)))
                return
            }

            do {
                try data.write(to: URL(fileURLWithPath: localPath), options: .atomic)
                completion(.success(()))
            } catch {
                completion(.failure(.operationFailed(error.localizedDescription)))
            }
        }
    }
    
    func uploadFile(_ localPath: String, to remotePath: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                completion(.failure(.connectionFailed(self.unavailableMessage)))
                return
            }

            let success = sftp.writeFile(atPath: localPath, toFileAtPath: remotePath)
            if success {
                completion(.success(()))
            } else {
                let message = sftp.session.lastError?.localizedDescription ?? "Unable to upload file"
                completion(.failure(.operationFailed(message)))
            }
        }
    }
    
    func deleteFile(_ file: SFTPFile, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                completion(.failure(.connectionFailed(self.unavailableMessage)))
                return
            }

            let success = file.isDirectory
                ? sftp.removeDirectory(atPath: file.path)
                : sftp.removeFile(atPath: file.path)

            DispatchQueue.main.async {
                if success {
                    self.files.removeAll { $0.path == file.path }
                    completion(.success(()))
                } else {
                    let message = sftp.session.lastError?.localizedDescription ?? "Unable to delete item"
                    completion(.failure(.operationFailed(message)))
                }
            }
        }
    }
    
    func createDirectory(name: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                completion(.failure(.connectionFailed(self.unavailableMessage)))
                return
            }

            let path = (self.currentPath as NSString).appendingPathComponent(name)
            let success = sftp.createDirectory(atPath: path)

            DispatchQueue.main.async {
                if success {
                    self.listDirectory(self.currentPath) { refreshResult in
                        switch refreshResult {
                        case .success:
                            completion(.success(()))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    let message = sftp.session.lastError?.localizedDescription ?? "Unable to create directory"
                    completion(.failure(.operationFailed(message)))
                }
            }
        }
    }
    
    func renameFile(_ file: SFTPFile, newName: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let sftp = self.connectedSFTP() else {
                completion(.failure(.connectionFailed(self.unavailableMessage)))
                return
            }

            let destination = ((file.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(newName)
            let success = sftp.moveItem(atPath: file.path, toPath: destination)

            DispatchQueue.main.async {
                if success {
                    self.listDirectory(self.currentPath) { refreshResult in
                        switch refreshResult {
                        case .success:
                            completion(.success(()))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    let message = sftp.session.lastError?.localizedDescription ?? "Unable to rename item"
                    completion(.failure(.operationFailed(message)))
                }
            }
        }
    }

    private func connectedSFTP() -> NMSFTP? {
        guard let session = SSHClient.shared.activeSession else { return nil }
        let sftp = session.sftp
        if sftp.isConnected { return sftp }
        return sftp.connect() ? sftp : nil
    }

    private func makeFile(from remoteFile: NMSFTPFile, parentPath: String) -> SFTPFile {
        let path = (parentPath as NSString).appendingPathComponent(remoteFile.filename)
        return SFTPFile(
            name: remoteFile.filename,
            path: path,
            isDirectory: remoteFile.isDirectory,
            size: remoteFile.fileSize?.int64Value ?? 0,
            modifiedDate: remoteFile.modificationDate ?? Date(),
            permissions: remoteFile.permissions ?? "----------"
        )
    }
}

// MARK: - SFTP Error

enum SFTPError: Error {
    case connectionFailed(String)
    case fileNotFound(String)
    case permissionDenied
    case operationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .permissionDenied: return "Permission denied"
        case .operationFailed(let msg): return "Operation failed: \(msg)"
        }
    }
}

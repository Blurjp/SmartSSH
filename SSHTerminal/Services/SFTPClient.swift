//
//  SFTPClient.swift
//  SSH Terminal
//
//  SFTP file browser functionality
//

import Foundation

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
        
        // Simulate SFTP listing (replace with real implementation)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let files = self.simulateListDirectory(path)
            
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
        // Simulate download
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }
    
    func uploadFile(_ localPath: String, to remotePath: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        // Simulate upload
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }
    
    func deleteFile(_ file: SFTPFile, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        // Simulate delete
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            DispatchQueue.main.async {
                if let index = self.files.firstIndex(where: { $0.id == file.id }) {
                    self.files.remove(at: index)
                }
                completion(.success(()))
            }
        }
    }
    
    func createDirectory(name: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        // Simulate create directory
        let newDir = SFTPFile(
            name: name,
            path: (currentPath as NSString).appendingPathComponent(name),
            isDirectory: true,
            size: 0,
            modifiedDate: Date(),
            permissions: "drwxr-xr-x"
        )
        
        DispatchQueue.main.async {
            self.files.append(newDir)
            completion(.success(()))
        }
    }
    
    func renameFile(_ file: SFTPFile, newName: String, completion: @escaping (Result<Void, SFTPError>) -> Void) {
        // Simulate rename
        DispatchQueue.main.async {
            if let index = self.files.firstIndex(where: { $0.id == file.id }) {
                let renamedFile = SFTPFile(
                    name: newName,
                    path: (file.path as NSString).deletingLastPathComponent + "/" + newName,
                    isDirectory: file.isDirectory,
                    size: file.size,
                    modifiedDate: Date(),
                    permissions: file.permissions
                )
                self.files[index] = renamedFile
            }
            completion(.success(()))
        }
    }
    
    // MARK: - Simulation
    
    private func simulateListDirectory(_ path: String) -> [SFTPFile] {
        // Generate realistic-looking files
        var files: [SFTPFile] = []
        
        let commonFiles = [
            ("README.md", false, 2048),
            ("config.yml", false, 512),
            ("src", true, 0),
            ("docs", true, 0),
            ("package.json", false, 1024),
            (".gitignore", false, 128),
            ("app.py", false, 4096),
            ("requirements.txt", false, 256),
            ("data", true, 0),
            ("logs", true, 0),
        ]
        
        for (name, isDir, size) in commonFiles {
            files.append(SFTPFile(
                name: name,
                path: (path as NSString).appendingPathComponent(name),
                isDirectory: isDir,
                size: Int64(size),
                modifiedDate: Date().addingTimeInterval(-Double.random(in: 0...86400 * 30)),
                permissions: isDir ? "drwxr-xr-x" : "-rw-r--r--"
            ))
        }
        
        return files.sorted { $0.name < $1.name }
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

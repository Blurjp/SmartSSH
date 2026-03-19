//
//  SFTPView.swift
//  SSH Terminal
//
//  SFTP file browser view
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct SFTPView: View {
    @ObservedObject private var sftpClient = SFTPClient.shared
    @State private var selectedFile: SFTPFile?
    @State private var showingFileActions = false
    @State private var showingCreateDirectory = false
    @State private var showingUploadSheet = false
    @State private var showingRenameSheet = false
    @State private var newDirectoryName = ""
    @State private var renamedFileName = ""
    @State private var searchText = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var filteredFiles: [SFTPFile] {
        if searchText.isEmpty {
            return sftpClient.files
        } else {
            return sftpClient.files.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Path breadcrumb
                pathBreadcrumb
                
                // File list
                fileList
                
                // Toolbar
                toolbar
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search files...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingCreateDirectory = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        
                        Button {
                            showingUploadSheet = true
                        } label: {
                            Label("Upload File", systemImage: "arrow.up.doc")
                        }
                        
                        Divider()
                        
                        Button {
                            refreshList()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCreateDirectory) {
                createDirectorySheet
            }
            .onChange(of: showingCreateDirectory) { _, isPresented in
                if !isPresented {
                    newDirectoryName = ""
                }
            }
            .sheet(isPresented: $showingRenameSheet) {
                renameFileSheet
            }
            .onChange(of: showingRenameSheet) { _, isPresented in
                if !isPresented {
                    renamedFileName = ""
                    selectedFile = nil
                }
            }
            .confirmationDialog("File Actions", isPresented: $showingFileActions, presenting: selectedFile) { file in
                fileActionsSheet(file: file)
            }
            .fileImporter(isPresented: $showingUploadSheet, allowedContentTypes: [.item]) { result in
                handleUploadSelection(result)
            }
            .alert("Files", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if sshConnected {
                    refreshList()
                }
            }
        }
    }

    private var sshConnected: Bool {
        SSHClient.shared.isConnected
    }
    
    // MARK: - View Components
    
    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pathComponents) { component in
                    Button {
                        sftpClient.navigateTo(component.path)
                    } label: {
                        HStack(spacing: 4) {
                            if component.name == "/" {
                                Image(systemName: "house.fill")
                            } else {
                                Text(component.name)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    if component.id != pathComponents.last?.id {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
    
    private var pathComponents: [BreadcrumbComponent] {
        let names = sftpClient.currentPath.split(separator: "/").map(String.init)
        var currentPath = "/"
        var components = [BreadcrumbComponent(name: "/", path: "/")]

        for name in names {
            currentPath = (currentPath as NSString).appendingPathComponent(name)
            components.append(BreadcrumbComponent(name: name, path: currentPath))
        }

        return components
    }
    
    private var fileList: some View {
        Group {
            if sftpClient.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !sshConnected {
                disconnectedStateView
            } else if filteredFiles.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredFiles) { file in
                        FileRowView(file: file)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleFileTap(file)
                            }
                            .onLongPressGesture {
                                selectedFile = file
                                showingFileActions = true
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(searchText.isEmpty ? "Empty Folder" : "No Files Found")
                .font(.headline)
            
            if searchText.isEmpty {
                Button {
                    showingCreateDirectory = true
                } label: {
                    Label("Create Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disconnectedStateView: some View {
        ContentUnavailableView {
            Label("No Active SFTP Session", systemImage: "folder")
        } description: {
            Text("Connect to a host in the Terminal tab before browsing files.")
        }
    }
    
    private var toolbar: some View {
        HStack(spacing: 20) {
            Button {
                sftpClient.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .disabled(sftpClient.historyIndex == 0)
            
            Button {
                sftpClient.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(sftpClient.historyIndex >= sftpClient.pathHistory.count - 1)
            
            Button {
                sftpClient.navigateUp()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.title3)
            }
            .disabled(sftpClient.currentPath == "/")
            
            Spacer()
            
            Button {
                refreshList()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var createDirectorySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder Name", text: $newDirectoryName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("New Folder")
                } footer: {
                    Text("Enter a name for the new folder.")
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCreateDirectory = false
                        newDirectoryName = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createDirectory()
                    }
                    .disabled(newDirectoryName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var renameFileSheet: some View {
        NavigationStack {
            Form {
                TextField("New Name", text: $renamedFileName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingRenameSheet = false
                        renamedFileName = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        renameSelectedFile()
                    }
                    .disabled(renamedFileName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    @ViewBuilder
    private func fileActionsSheet(file: SFTPFile) -> some View {
        Group {
            if file.isDirectory {
                Button {
                    sftpClient.navigateTo(file.path)
                    showingFileActions = false
                } label: {
                    Label("Open", systemImage: "folder")
                }
            } else {
                Button {
                    downloadFile(file)
                    showingFileActions = false
                } label: {
                    Label("Download", systemImage: "arrow.down.doc")
                }
            }
            
            Button {
                renamedFileName = file.name
                selectedFile = file
                showingRenameSheet = true
                showingFileActions = false
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Button {
                // Copy path
                UIPasteboard.general.string = file.path
                showingFileActions = false
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                deleteFile(file)
                showingFileActions = false
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleFileTap(_ file: SFTPFile) {
        if file.isDirectory {
            sftpClient.navigateTo(file.path)
        } else {
            selectedFile = file
            showingFileActions = true
        }
    }
    
    private func refreshList() {
        guard sshConnected else { return }
        sftpClient.listDirectory(sftpClient.currentPath) { _ in }
    }
    
    private func createDirectory() {
        guard !newDirectoryName.isEmpty else { return }
        
        sftpClient.createDirectory(name: newDirectoryName) { result in
            switch result {
            case .success:
                newDirectoryName = ""
                showingCreateDirectory = false
            case .failure(let error):
                showAlert(error.localizedDescription)
            }
        }
    }
    
    private func downloadFile(_ file: SFTPFile) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            showAlert("Unable to access Documents directory.")
            return
        }
        let destination = documentsDir.appendingPathComponent(file.name)

        sftpClient.downloadFile(file, to: destination.path) { result in
            switch result {
            case .success:
                showAlert("Downloaded \(file.name) to Files/Documents.")
            case .failure(let error):
                showAlert(error.localizedDescription)
            }
        }
    }
    
    private func deleteFile(_ file: SFTPFile) {
        sftpClient.deleteFile(file) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                showAlert(error.localizedDescription)
            }
        }
    }

    private func renameSelectedFile() {
        guard let file = selectedFile, !renamedFileName.isEmpty else { return }

        sftpClient.renameFile(file, newName: renamedFileName) { result in
            switch result {
            case .success:
                showingRenameSheet = false
                renamedFileName = ""
                selectedFile = nil
            case .failure(let error):
                showAlert(error.localizedDescription)
            }
        }
    }

    private func handleUploadSelection(_ result: Result<URL, Error>) {
        guard sshConnected else {
            showAlert("Connect to a host before uploading files.")
            return
        }

        switch result {
        case .success(let url):
            let accessGranted = url.startAccessingSecurityScopedResource()
            let remotePath = (sftpClient.currentPath as NSString).appendingPathComponent(url.lastPathComponent)
            let localUploadURL = uploadStagingURL(for: url)

            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                if FileManager.default.fileExists(atPath: localUploadURL.path) {
                    try FileManager.default.removeItem(at: localUploadURL)
                }
                try FileManager.default.copyItem(at: url, to: localUploadURL)
            } catch {
                showAlert(error.localizedDescription)
                return
            }

            sftpClient.uploadFile(localUploadURL.path, to: remotePath) { [localUploadURL] uploadResult in
                try? FileManager.default.removeItem(at: localUploadURL)
                switch uploadResult {
                case .success:
                    DispatchQueue.main.async {
                        self.refreshList()
                        self.showAlert("Uploaded \(url.lastPathComponent).")
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.showAlert(error.localizedDescription)
                    }
                }
            }
        case .failure(let error):
            showAlert(error.localizedDescription)
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }

    private func uploadStagingURL(for url: URL) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
    }
}

private struct BreadcrumbComponent: Identifiable, Hashable {
    let name: String
    let path: String

    var id: String { path }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: SFTPFile
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title2)
                .foregroundStyle(Color.appNamed(file.iconColor))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(file.formattedSize)
                    Text("•")
                    Text(file.formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    SFTPView()
}

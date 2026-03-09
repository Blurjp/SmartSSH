//
//  SFTPView.swift
//  SSH Terminal
//
//  SFTP file browser view
//

import SwiftUI

struct SFTPView: View {
    @StateObject private var sftpClient = SFTPClient.shared
    @State private var selectedFile: SFTPFile?
    @State private var showingFileActions = false
    @State private var showingCreateDirectory = false
    @State private var showingUploadSheet = false
    @State private var newDirectoryName = ""
    @State private var searchText = ""
    
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
            .confirmationDialog("File Actions", isPresented: $showingFileActions, presenting: selectedFile) { file in
                fileActionsSheet(file: file)
            }
        }
    }
    
    // MARK: - View Components
    
    private var pathBreadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pathComponents, id: \.self) { component in
                    Button {
                        navigateToPathComponent(component)
                    } label: {
                        HStack(spacing: 4) {
                            if component == "/" {
                                Image(systemName: "house.fill")
                            } else {
                                Text(component)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    if component != pathComponents.last {
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
    
    private var pathComponents: [String] {
        var components = sftpClient.currentPath.split(separator: "/").map(String.init)
        components.insert("/", at: 0)
        return components
    }
    
    private var fileList: some View {
        Group {
            if sftpClient.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .autocapitalization(.none)
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
                // Rename
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
    
    private func navigateToPathComponent(_ component: String) {
        if component == "/" {
            sftpClient.navigateTo("/")
            return
        }
        
        var path = ""
        for comp in pathComponents {
            if comp == "/" {
                path = "/"
            } else {
                path = (path as NSString).appendingPathComponent(comp)
            }
            if comp == component {
                break
            }
        }
        sftpClient.navigateTo(path)
    }
    
    private func refreshList() {
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
                print("Failed to create directory: \(error)")
            }
        }
    }
    
    private func downloadFile(_ file: SFTPFile) {
        // TODO: Implement download with progress
        print("Downloading: \(file.name)")
    }
    
    private func deleteFile(_ file: SFTPFile) {
        sftpClient.deleteFile(file) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                print("Failed to delete: \(error)")
            }
        }
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: SFTPFile
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title2)
                .foregroundStyle(Color(file.iconColor))
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

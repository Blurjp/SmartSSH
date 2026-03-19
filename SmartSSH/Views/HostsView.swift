//
//  HostsView.swift
//  SSH Terminal
//
//  Host management view with improved UX
//

import SwiftUI
import CoreData

#if canImport(UIKit)
import UIKit
#endif

struct HostsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var hosts: [Host] = []
    @State private var showingAddHost = false
    @State private var searchText = ""
    @State private var selectedHost: Host?
    @State private var showingConnectionAlert = false
    @State private var connectionMessage = ""
    @State private var fetchErrorMessage: String?
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var filteredHosts: [Host] {
        if searchText.isEmpty {
            return Array(hosts)
        } else {
            return hosts.filter { 
                $0.wrappedName.localizedCaseInsensitiveContains(searchText) ||
                $0.wrappedHostname.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var groupedHosts: [String: [Host]] {
        Dictionary(grouping: filteredHosts) { $0.group ?? "Uncategorized" }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if groupedHosts.isEmpty {
                    emptyStateView
                } else {
                    ForEach(groupedHosts.keys.sorted(), id: \.self) { group in
                        Section(header: sectionHeader(group)) {
                            ForEach(groupedHosts[group] ?? [], id: \.id) { host in
                                HostRowView(host: host)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        connect(to: host)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        deleteButton(for: host)
                                    }
                                    .swipeActions(edge: .leading) {
                                        connectButton(for: host)
                                        editButton(for: host)
                                    }
                                    .contextMenu {
                                        hostContextMenu(for: host)
                                    }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search hosts...")
            .navigationTitle("Hosts")
            .accessibilityIdentifier("hosts.screen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
            .task {
                loadHosts()
            }
            .sheet(isPresented: $showingAddHost, onDismiss: loadHosts) {
                AddHostView()
            }
            .sheet(item: $selectedHost, onDismiss: loadHosts) { host in
                AddHostView(hostToEdit: host)
            }
            .alert("Connection Status", isPresented: $showingConnectionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(connectionMessage)
            }
            .alert("Storage Error", isPresented: Binding(
                get: { fetchErrorMessage != nil },
                set: { if !$0 { fetchErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(fetchErrorMessage ?? "")
            }
        }
    }
    
    // MARK: - View Components
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Hosts Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("hosts.emptyTitle")
            
            Text("Add your first SSH server to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddHost = true
            } label: {
                Label("Add Host", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("hosts.addButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }
    
    private func sectionHeader(_ group: String) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(group)
                .font(.headline)
        }
    }
    
    private func deleteButton(for host: Host) -> some View {
        Button(role: .destructive) {
            deleteHost(host)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func connectButton(for host: Host) -> some View {
        Button {
            connect(to: host)
        } label: {
            Label("Connect", systemImage: "play.fill")
        }
        .tint(.green)
    }
    
    private func editButton(for host: Host) -> some View {
        Button {
            selectedHost = host
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.orange)
    }
    
    private func hostContextMenu(for host: Host) -> some View {
        Group {
            Button {
                connect(to: host)
            } label: {
                Label("Connect", systemImage: "play.fill")
            }
            
            Button {
                copyConnectionInfo(host)
            } label: {
                Label("Copy Connection String", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button {
                selectedHost = host
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                deleteHost(host)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var addButton: some View {
        Button {
            showingAddHost = true
        } label: {
            Label("Add Host", systemImage: "plus")
        }
        .accessibilityIdentifier("hosts.addButton")
    }
    
    // MARK: - Actions

    private func loadHosts() {
        guard let entity = NSEntityDescription.entity(forEntityName: "Host", in: viewContext) else {
            hosts = []
            fetchErrorMessage = "The Core Data model is missing the 'Host' entity in this build."
            return
        }

        let request = Host.fetchRequest()
        request.entity = entity
        request.sortDescriptors = [
            NSSortDescriptor(
                key: "name",
                ascending: true,
                selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
            )
        ]

        do {
            hosts = try viewContext.fetch(request)
            fetchErrorMessage = nil
        } catch {
            hosts = []
            fetchErrorMessage = error.localizedDescription
        }
    }
    
    private func connect(to host: Host) {
        // Update host status
        host.status = "connecting"
        
        SSHClient.shared.connect(to: host) { result in
            switch result {
            case .success:
                host.status = "connected"
                connectionMessage = "Connected to \(host.wrappedName)"
                showingConnectionAlert = true
                
            case .failure(let error):
                host.status = "error"
                connectionMessage = "Connection failed: \(error.localizedDescription)"
                showingConnectionAlert = true
            }
        }
    }
    
    private func deleteHost(_ host: Host) {
        withAnimation {
            host.deletePassword()
            viewContext.delete(host)
            do {
                try viewContext.save()
                hosts.removeAll { $0.objectID == host.objectID }
            } catch {
                showAlert("Failed to delete host: \(error.localizedDescription)")
            }
        }
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
    
    private func copyConnectionInfo(_ host: Host) {
        let info = "ssh \(host.wrappedUsername)@\(host.wrappedHostname) -p \(host.port)"
        UIPasteboard.general.string = info
    }
}

// MARK: - Host Row View

struct HostRowView: View {
    let host: Host
    @ObservedObject var sshClient = SSHClient.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon with animation
            ZStack {
                Circle()
                    .fill(Color.appNamed(host.statusColor).opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(Color.appNamed(host.color ?? "blue"))
            }
            
            // Host info
            VStack(alignment: .leading, spacing: 4) {
                Text(host.wrappedName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(host.displayInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status indicator
            VStack(alignment: .trailing, spacing: 4) {
                Circle()
                    .fill(Color.appNamed(host.statusColor))
                    .frame(width: 10, height: 10)
                    .animation(.easeInOut, value: host.status)
                
                if let lastConnected = host.lastConnectedAt {
                    Text(lastConnected, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private var statusIcon: String {
        switch host.status {
        case "connected": return "antenna.radiowaves.left.and.right"
        case "connecting": return "antenna.radiowaves.left.and.right"
        case "error": return "exclamationmark.triangle"
        default: return "server.rack"
        }
    }
}

// MARK: - Preview

#Preview {
    HostsView()
        .environment(\.managedObjectContext, DataController.shared.container.viewContext)
}

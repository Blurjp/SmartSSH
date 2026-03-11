//
//  SmartSSHApp.swift
//  SmartSSH
//
//  A modern, native iOS SSH client
//

import SwiftUI

@main
struct SmartSSHApp: App {
    @StateObject private var dataController: DataController
    
    var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let controller = isUITesting
            ? DataController(inMemory: true, cloudSyncEnabled: false)
            : DataController.shared
        _dataController = StateObject(wrappedValue: controller)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isUITesting {
                    UITestContentView()
                } else {
                    ContentView()
                }
            }
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(dataController)
                .tint(.blue)
        }
    }
}

private struct UITestContentView: View {
    var body: some View {
        TabView {
            UITestHostsView()
                .tabItem {
                    Label("Hosts", systemImage: "server.rack")
                }

            NavigationStack {
                Text("UITest Terminal")
                    .navigationTitle("Terminal")
            }
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            NavigationStack {
                Text("UITest Files")
                    .navigationTitle("Files")
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }

            NavigationStack {
                Text("UITest Keys")
                    .navigationTitle("Keys")
            }
            .tabItem {
                Label("Keys", systemImage: "key")
            }

            NavigationStack {
                Text("UITest Snippets")
                    .navigationTitle("Snippets")
            }
            .tabItem {
                Label("Snippets", systemImage: "text.badge.plus")
            }

            UITestSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

private struct UITestHostsView: View {
    @State private var showingAddHost = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "server.rack")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("No Hosts Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("hosts.emptyTitle")

                Text("Add your first SSH server to get started.")
                    .foregroundStyle(.secondary)

                Button {
                    showingAddHost = true
                } label: {
                    Label("Add Host", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("hosts.addButton")
            }
            .padding()
            .navigationTitle("Hosts")
            .accessibilityIdentifier("hosts.screen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddHost = true
                    } label: {
                        Label("Add Host", systemImage: "plus")
                    }
                    .accessibilityIdentifier("hosts.addButton")
                }
            }
            .sheet(isPresented: $showingAddHost) {
                UITestAddHostView()
            }
        }
    }
}

private struct UITestAddHostView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: .constant(""))
                    .accessibilityIdentifier("addHost.name")

                TextField("Hostname or IP", text: .constant(""))
                    .accessibilityIdentifier("addHost.hostname")

                TextField("Username", text: .constant(""))
                    .accessibilityIdentifier("addHost.username")

                SecureField("Password", text: .constant(""))
                    .accessibilityIdentifier("addHost.password")
            }
            .navigationTitle("Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct UITestSettingsView: View {
    @State private var showingSubscription = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Subscription") {
                        showingSubscription = true
                    }
                }

                Section("Terminal") {
                    Text("Font")
                }

                Section("Connection") {
                    Text("Timeout")
                }

                Section("Features") {
                    Text("Snippets")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSubscription) {
                NavigationStack {
                    Text("UITest Subscription")
                        .navigationTitle("Subscription")
                }
            }
        }
    }
}

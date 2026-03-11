//
//  SettingsView.swift
//  SSH Terminal
//
//  App settings with subscription
//

import SwiftUI
import CoreData

struct SettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("terminalFont") private var terminalFont = "Menlo"
    @AppStorage("terminalColorScheme") private var terminalColorScheme = "dark"
    @AppStorage("keepAliveInterval") private var keepAliveInterval = 30
    @AppStorage("connectionTimeout") private var connectionTimeout = 30
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingSubscription = false
    @State private var settingsMessage = ""
    @State private var showingSettingsMessage = false

    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                subscriptionSection
                
                // Terminal Section
                terminalSection
                
                // Connection Section
                connectionSection
                
                // General Section
                generalSection
                
                // About Section
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
            }
            .alert("Settings", isPresented: $showingSettingsMessage) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(settingsMessage)
            }
        }
    }
    
    // MARK: - Subscription Section
    
    private var subscriptionSection: some View {
        Section {
            Button {
                showingSubscription = true
            } label: {
                HStack {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subscription")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text(subscriptionManager.currentTier.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } footer: {
            Text("Upgrade to Pro for unlimited hosts, SFTP access, and synced workflows.")
        }
    }
    
    // MARK: - Terminal Section
    
    private var terminalSection: some View {
        Section("Terminal") {
            Picker("Font", selection: $terminalFont) {
                Text("Menlo").tag("Menlo")
                Text("Monaco").tag("Monaco")
                Text("Courier").tag("Courier")
                Text("SF Mono").tag("SF Mono")
            }
            
            VStack(alignment: .leading) {
                Text("Font Size: \(Int(terminalFontSize))")
                    .font(.subheadline)
                
                Slider(value: $terminalFontSize, in: 10...24, step: 1)
            }
            
            Picker("Color Scheme", selection: $terminalColorScheme) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
                Text("Solarized Dark").tag("solarized-dark")
                Text("Dracula").tag("dracula")
                Text("Monokai").tag("monokai")
            }
        }
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        Section("Connection") {
            VStack(alignment: .leading) {
                Text("Keep Alive: \(keepAliveInterval)s")
                    .font(.subheadline)
                
                Slider(value: Binding(
                    get: { Double(keepAliveInterval) },
                    set: { keepAliveInterval = Int($0) }
                ), in: 10...120, step: 10)
            }
            
            VStack(alignment: .leading) {
                Text("Timeout: \(connectionTimeout)s")
                    .font(.subheadline)
                
                Slider(value: Binding(
                    get: { Double(connectionTimeout) },
                    set: { connectionTimeout = Int($0) }
                ), in: 10...120, step: 10)
            }
        }
    }
    
    // MARK: - General Section
    
    private var generalSection: some View {
        Section("General") {
            Toggle("Haptic Feedback", isOn: $hapticFeedback)
            
            Button {
                exportData()
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
            
            Button {
                importData()
            } label: {
                Label("Import Data", systemImage: "square.and.arrow.down")
            }
            .disabled(!FileManager.default.fileExists(atPath: exportURL().path))
            
            Button(role: .destructive) {
                clearAllData()
            } label: {
                Label("Clear All Data", systemImage: "trash")
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                Label("About SmartSSH", systemImage: "info.circle")
            }
            
            Link(destination: URL(string: "https://github.com/Blurjp/SmartSSH")!) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            
            Link(destination: URL(string: "https://github.com/Blurjp/SmartSSH/issues")!) {
                Label("Support", systemImage: "questionmark.circle")
            }
        }
    }
    
    // MARK: - Actions
    
    private func exportData() {
        do {
            let payload = try makeExportPayload()
            let data = try JSONEncoder().encode(payload)
            try data.write(to: exportURL(), options: .atomic)
            settingsMessage = "Exported hosts and snippets to \(exportURL().lastPathComponent). SSH private keys stay in the Keychain and are not exported."
        } catch {
            settingsMessage = "Export failed: \(error.localizedDescription)"
        }

        showingSettingsMessage = true
    }
    
    private func importData() {
        do {
            let data = try Data(contentsOf: exportURL())
            let payload = try JSONDecoder().decode(SettingsExportPayload.self, from: data)
            try restore(from: payload)
            settingsMessage = "Imported app data from \(exportURL().lastPathComponent)."
        } catch {
            settingsMessage = "Import failed: \(error.localizedDescription)"
        }

        showingSettingsMessage = true
    }
    
    private func clearAllData() {
        do {
            try clearPersistedData()
            settingsMessage = "Cleared hosts, keys, and saved snippets."
        } catch {
            settingsMessage = "Clear failed: \(error.localizedDescription)"
        }

        showingSettingsMessage = true
    }

    private func exportURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("smartssh-export.json")
    }

    private func makeExportPayload() throws -> SettingsExportPayload {
        let request = Host.fetchRequest()
        let hosts = try viewContext.fetch(request).map { host in
            ExportHost(
                name: host.wrappedName,
                hostname: host.wrappedHostname,
                port: host.port,
                username: host.wrappedUsername,
                keyFingerprint: host.keyFingerprint,
                group: host.group,
                tags: host.tags,
                useKeyAuth: host.useKeyAuth
            )
        }

        let snippets = loadSavedSnippets()
        return SettingsExportPayload(hosts: hosts, snippets: snippets)
    }

    private func restore(from payload: SettingsExportPayload) throws {
        try clearPersistedData()

        for host in payload.hosts {
            _ = Host.create(
                in: viewContext,
                name: host.name,
                hostname: host.hostname,
                port: host.port,
                username: host.username,
                keyFingerprint: host.keyFingerprint,
                group: host.group,
                tags: host.tags,
                useKeyAuth: host.useKeyAuth
            )
        }

        try viewContext.save()

        if let snippetsData = try? JSONEncoder().encode(payload.snippets) {
            UserDefaults.standard.set(snippetsData, forKey: "saved_snippets")
        }

        settingsMessage = "Imported hosts and snippets. Re-import any SSH private keys manually on this device."
    }

    private func clearPersistedData() throws {
        let request = Host.fetchRequest()
        let hosts = try viewContext.fetch(request)
        for host in hosts {
            host.deletePassword()
            viewContext.delete(host)
        }
        try viewContext.save()

        for key in SSHManager.shared.loadSavedKeys() {
            SSHManager.shared.deleteKey(named: key.name)
        }

        SSHManager.shared.clearKnownHosts()

        UserDefaults.standard.removeObject(forKey: "saved_snippets")
    }

    private func loadSavedSnippets() -> [Snippet] {
        guard let data = UserDefaults.standard.data(forKey: "saved_snippets"),
              let snippets = try? JSONDecoder().decode([Snippet].self, from: data) else {
            return []
        }

        return snippets
    }
}

private struct SettingsExportPayload: Codable {
    let hosts: [ExportHost]
    let snippets: [Snippet]
}

private struct ExportHost: Codable {
    let name: String
    let hostname: String
    let port: Int16
    let username: String
    let keyFingerprint: String?
    let group: String?
    let tags: [String]?
    let useKeyAuth: Bool
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About View

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (Build \(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    // App Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)
                    
                    Text("SmartSSH")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            
            Section("Features") {
                FeatureRow(icon: "network", text: "SSH Connection")
                FeatureRow(icon: "folder", text: "SFTP Browser")
                FeatureRow(icon: "key", text: "Key Management")
                FeatureRow(icon: "text.badge.plus", text: "Code Snippets")
                FeatureRow(icon: "icloud", text: "iCloud Sync")
            }
            
            Section {
                VStack(spacing: 12) {
                    Text("Made with ❤️ for developers who want a better SSH experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("© 2026 SmartSSH. All rights reserved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}

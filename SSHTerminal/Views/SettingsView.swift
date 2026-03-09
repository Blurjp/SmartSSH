//
//  SettingsView.swift
//  SSH Terminal
//
//  App settings with subscription
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("terminalFont") private var terminalFont = "Menlo"
    @AppStorage("terminalColorScheme") private var terminalColorScheme = "dark"
    @AppStorage("keepAliveInterval") private var keepAliveInterval = 30
    @AppStorage("connectionTimeout") private var connectionTimeout = 30
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("aiEnabled") private var aiEnabled = true
    
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingSubscription = false
    
    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                subscriptionSection
                
                // Terminal Section
                terminalSection
                
                // Connection Section
                connectionSection
                
                // AI Section
                aiSection
                
                // General Section
                generalSection
                
                // About Section
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
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
            Text("Upgrade to Pro for unlimited hosts, AI features, and more.")
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
                
                Slider(value: Double($keepAliveInterval), in: 10...120, step: 10)
            }
            
            VStack(alignment: .leading) {
                Text("Timeout: \(connectionTimeout)s")
                    .font(.subheadline)
                
                Slider(value: Double($connectionTimeout), in: 10...120, step: 10)
            }
        }
    }
    
    // MARK: - AI Section
    
    private var aiSection: some View {
        Section("AI Features") {
            Toggle("Enable AI", isOn: $aiEnabled)
                .disabled(!subscriptionManager.hasAccess(to: .aiFeatures))
            
            if subscriptionManager.hasAccess(to: .aiFeatures) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Features Include:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    FeatureRow(icon: "sparkles", text: "Command Suggestions")
                    FeatureRow(icon: "wrench.and.screwdriver", text: "Error Diagnosis")
                    FeatureRow(icon: "book", text: "Command Explanations")
                    FeatureRow(icon: "text.badge.plus", text: "Snippet Generation")
                }
            } else {
                Button {
                    showingSubscription = true
                } label: {
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.gray)
                        
                        Text("Upgrade to Pro")
                            .font(.subheadline)
                    }
                }
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
                Label("About SSH Terminal", systemImage: "info.circle")
            }
            
            Link(destination: URL(string: "https://github.com/example/sshterminal")!) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            
            Link(destination: URL(string: "mailto:support@example.com")!) {
                Label("Support", systemImage: "envelope")
            }
            
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            
            Link(destination: URL(string: "https://example.com/terms")!) {
                Label("Terms of Service", systemImage: "doc.text")
            }
        }
    }
    
    // MARK: - Actions
    
    private func exportData() {
        // Export data logic
        print("Exporting data...")
    }
    
    private func importData() {
        // Import data logic
        print("Importing data...")
    }
    
    private func clearAllData() {
        // Clear data logic
        print("Clearing all data...")
    }
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
                    
                    Text("SSH Terminal")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0 (Build 1)")
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
                FeatureRow(icon: "sparkles", text: "AI Assistant")
            }
            
            Section {
                VStack(spacing: 12) {
                    Text("Made with ❤️ for developers who want a better SSH experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("© 2026 SSH Terminal. All rights reserved.")
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

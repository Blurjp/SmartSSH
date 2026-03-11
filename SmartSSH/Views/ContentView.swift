//
//  ContentView.swift
//  SSH Terminal
//
//  Main app view
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingSettings = false
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HostsView()
                .tabItem {
                    Label("Hosts", systemImage: "server.rack")
                }
                .tag(0)
            
            TerminalView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
                .tag(1)
            
            featureTab(
                SFTPView(),
                requiredFeature: .sftpBrowser,
                title: "Files",
                systemImage: "folder",
                tag: 2
            )
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
            
            KeysView()
                .tabItem {
                    Label("Keys", systemImage: "key")
                }
                .tag(3)
            
            featureTab(
                SnippetsView(),
                requiredFeature: .snippets,
                title: "Snippets",
                systemImage: "text.badge.plus",
                tag: 4
            )
                .tabItem {
                    Label("Snippets", systemImage: "text.badge.plus")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)
        }
        .tint(.blue)
    }

    @ViewBuilder
    private func featureTab<Content: View>(
        _ content: Content,
        requiredFeature: Feature,
        title: String,
        systemImage: String,
        tag: Int
    ) -> some View {
        if subscriptionManager.hasAccess(to: requiredFeature) {
            content.tag(tag)
        } else {
            LockedFeatureView(title: title, systemImage: systemImage)
                .tag(tag)
        }
    }
}

private struct LockedFeatureView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text("Upgrade to Pro to unlock this feature.")
            } actions: {
                NavigationLink("Open Subscription") {
                    SubscriptionView()
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
}

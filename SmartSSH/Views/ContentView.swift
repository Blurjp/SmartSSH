//
//  ContentView.swift
//  SSH Terminal
//
//  Main app view
//

import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab = 0
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var sessionStore = SessionStore.shared
    
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
                systemImage: "folder"
            )
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(2)
            
            KeysView()
                .tabItem {
                    Label("Keys", systemImage: "key")
                }
                .tag(3)
            
            featureTab(
                SnippetsView(),
                requiredFeature: .snippets,
                title: "Snippets",
                systemImage: "text.badge.plus"
            )
                .tabItem {
                    Label("Snippets", systemImage: "text.badge.plus")
                }
                .tag(4)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)
        }
        .tint(.blue)
        .task {
            sessionStore.restoreWorkspace(in: viewContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartSSHSelectTab)) { notification in
            guard let tab = notification.object as? Int else { return }
            selectedTab = tab
        }
    }

    @ViewBuilder
    private func featureTab<Content: View>(
        _ content: Content,
        requiredFeature: Feature,
        title: String,
        systemImage: String
    ) -> some View {
        if subscriptionManager.hasAccess(to: requiredFeature) {
            content
        } else {
            LockedFeatureView(title: title, systemImage: systemImage)
        }
    }
}

extension Notification.Name {
    static let smartSSHSelectTab = Notification.Name("smartSSHSelectTab")
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

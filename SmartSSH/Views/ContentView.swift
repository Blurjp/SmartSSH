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
            
            SFTPView()
                .tabItem {
                    Label("Files", systemImage: "folder")
                }
                .tag(2)
            
            KeysView()
                .tabItem {
                    Label("Keys", systemImage: "key")
                }
                .tag(3)
            
            SnippetsView()
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
    }
}

#Preview {
    ContentView()
}

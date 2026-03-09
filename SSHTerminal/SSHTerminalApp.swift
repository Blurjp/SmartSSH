//
//  SSHTerminalApp.swift
//  SSH Terminal
//
//  A modern, native iOS SSH client
//

import SwiftUI

@main
struct SSHTerminalApp: App {
    @StateObject private var dataController = DataController.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(dataController)
                .tint(.blue)
        }
    }
}

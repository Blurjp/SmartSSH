//
//  SmartSSHApp.swift
//  SmartSSH
//
//  A modern, native iOS SSH client
//

import SwiftUI

@main
struct SmartSSHApp: App {
    @StateObject private var dataController = DataController.shared
    
    var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environmentObject(dataController)
                .tint(.blue)
        }
    }
}

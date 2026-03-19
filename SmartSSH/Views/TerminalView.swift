//
//  TerminalView.swift
//  SSH Terminal
//
//  SSH Terminal view with improved UX
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TerminalView: View {
    @ObservedObject private var sshClient = SSHClient.shared
    @State private var commandInput = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @AppStorage("terminalFontSize") private var fontSize = 14.0
    @FocusState private var isInputFocused: Bool
    
    private let maxHistorySize = 100
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                if sshClient.isConnected {
                    statusBar
                }
                
                // Terminal output
                terminalOutput
                
                // Command input
                commandInputBar
            }
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarMenu
                }
            }
            .overlay {
                if !sshClient.isConnected {
                    disconnectedOverlay
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var statusBar: some View {
        HStack {
            Circle()
                .fill(Color.appNamed(sshClient.state.color))
                .frame(width: 8, height: 8)
            
            Text(connectionStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if let host = sshClient.host {
                Text(host.displayInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    private var connectionStatusText: String {
        switch sshClient.state {
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Welcome message
                    if sshClient.output.isEmpty {
                        welcomeMessage
                    } else {
                        Text(sshClient.output)
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.black)
            .onChange(of: sshClient.output) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
    
    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to SSH Terminal")
                .font(.system(size: fontSize + 2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.green)
            
            Text("Type a command and press Enter to execute.")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Text("\nQuick Commands:")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.yellow)
            
            ForEach(["ls -la", "pwd", "whoami", "df -h"], id: \.self) { cmd in
                Button {
                    commandInput = cmd
                    executeCommand()
                } label: {
                    Text("  \(cmd)")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(sshClient.isConnected ? .cyan : .gray)
                }
                .disabled(!sshClient.isConnected)
            }
        }
    }
    
    private var commandInputBar: some View {
        HStack(spacing: 8) {
            // Prompt
            Text("$")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.green)
                .fontWeight(.bold)
            
            // Input field
            TextField("Enter command...", text: $commandInput)
                .font(.system(size: fontSize, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($isInputFocused)
                .onSubmit {
                    executeCommand()
                }
                .onKeyPress(.upArrow) {
                    navigateHistory(direction: .up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateHistory(direction: .down)
                    return .handled
                }
            
            // Send button
            Button {
                executeCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(commandInput.isEmpty ? .gray : .green)
            }
            .disabled(commandInput.isEmpty)
        }
        .padding()
        .background(Color.black)
    }
    
    private var toolbarMenu: some View {
        Menu {
            // Font size controls
            Menu {
                Button("Smaller") {
                    fontSize = max(10, fontSize - 2)
                }
                Button("Larger") {
                    fontSize = min(24, fontSize + 2)
                }
                Divider()
                Button("Reset to Default") {
                    fontSize = 14
                }
            } label: {
                Label("Font Size", systemImage: "textformat.size")
            }
            
            Divider()
            
            // Clear output
            Button {
                sshClient.clearOutput()
            } label: {
                Label("Clear Output", systemImage: "trash")
            }
            
            // Export log
            Button {
                exportLog()
            } label: {
                Label("Export Log", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            // Disconnect
            if sshClient.isConnected {
                Button(role: .destructive) {
                    sshClient.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var disconnectedOverlay: some View {
        ContentUnavailableView {
            Label("No Active Session", systemImage: "terminal")
        } description: {
            Text("Connect to a host from the Hosts tab to start a terminal session.")
        } actions: {
            Button("Go to Hosts") {
                NotificationCenter.default.post(name: .smartSSHSelectTab, object: 0)
            }
            .buttonStyle(.borderedProminent)
        }
        .background(Color.black)
    }
    
    // MARK: - Actions
    
    private func executeCommand() {
        guard !commandInput.isEmpty else { return }
        
        let command = commandInput
        commandInput = ""
        
        commandHistory.insert(command, at: 0)
        if commandHistory.count > maxHistorySize {
            commandHistory = Array(commandHistory.prefix(maxHistorySize))
        }
        historyIndex = -1
        
        // Handle special commands
        if command.lowercased() == "clear" {
            sshClient.clearOutput()
            return
        }
        
        // Execute command
        sshClient.execute(command: command) { result in
            // Command execution complete
        }
    }
    
    private enum HistoryDirection {
        case up, down
    }
    
    private func navigateHistory(direction: HistoryDirection) {
        guard !commandHistory.isEmpty, historyIndex >= -1 else { return }
        
        switch direction {
        case .up:
            let nextIndex = historyIndex + 1
            if nextIndex < commandHistory.count {
                historyIndex = nextIndex
                commandInput = commandHistory[historyIndex]
            }
        case .down:
            if historyIndex > 0 {
                historyIndex -= 1
                commandInput = commandHistory[historyIndex]
            } else if historyIndex == 0 {
                historyIndex = -1
                commandInput = ""
            }
        }
    }
    
    private func exportLog() {
        let activityVC = UIActivityViewController(
            activityItems: [sshClient.output],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    TerminalView()
}

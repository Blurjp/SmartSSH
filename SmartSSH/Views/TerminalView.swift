//
//  TerminalView.swift
//  SSH Terminal
//
//  SSH Terminal view with inline input (UITextView-based)
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct TerminalView: View {
    @ObservedObject private var sshClient = SSHClient.shared
    @AppStorage("terminalFontSize") private var fontSize = 14.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if sshClient.isConnected {
                    statusBar
                }

                // Single unified terminal view with inline input
                TerminalTextView(
                    sshClient: sshClient,
                    fontSize: fontSize
                )
            }
            .background(Color.black)
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

            if sshClient.isConnected {
                Text(sshClient.isShellActive ? "Shell Live" : "Shell Starting")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sshClient.isShellActive ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .foregroundStyle(sshClient.isShellActive ? .green : .yellow)
                    .clipShape(Capsule())
            }

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

// MARK: - Terminal TextView (UIViewRepresentable)

struct TerminalTextView: UIViewRepresentable {
    @ObservedObject var sshClient: SSHClient
    let fontSize: Double

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.backgroundColor = .black
        textView.textColor = .green
        textView.isEditable = true
        textView.isSelectable = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.spellCheckingType = .no
        textView.keyboardDismissMode = .interactive
        textView.indicatorStyle = .white

        // Content inset for better visibility
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        textView.delegate = context.coordinator

        // Store reference
        context.coordinator.textView = textView

        // Initial content
        context.coordinator.updateInitialState()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Update font size if changed
        if CGFloat(fontSize) != textView.font?.pointSize {
            textView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        // Update output when it changes
        context.coordinator.checkForOutputUpdates()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sshClient: sshClient)
    }
}

// MARK: - Coordinator

class Coordinator: NSObject, UITextViewDelegate {
    var textView: UITextView?
    let sshClient: SSHClient

    // Track output state
    private var lastProcessedOutput: String = ""
    private var processedLength: Int = 0

    // Command history
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private let maxHistorySize = 100

    // Track prompt position
    private var promptRange: NSRange?

    // Initialize terminal size
    private var terminalWidth: Int = 80
    private var terminalHeight: Int = 24

    init(sshClient: SSHClient) {
        self.sshClient = sshClient
        super.init()

        // Observe output changes
        sshClient.objectWillChange.sink { [weak self] _ in
            self?.updateOutputIfNeeded()
        }.store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle Enter key - execute command
        if text == "\n" {
            executeCurrentCommand(textView)
            return false
        }

        // Prevent editing before the prompt (protect existing output)
        if let promptRange = promptRange {
            if range.location < promptRange.location {
                return false
            }
        }

        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        // Update prompt range as user types
        updatePromptRange()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Ensure cursor is at the end when editing begins
        if let text = textView.text, !text.isEmpty {
            textView.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
    }

    // MARK: - Command Execution

    private func executeCurrentCommand(_ textView: UITextView) {
        guard let promptRange = promptRange else { return }

        // Extract command text (everything after prompt)
        let fullText = textView.text ?? ""
        let startIndex = fullText.index(fullText.startIndex, offsetBy: promptRange.location + promptRange.length)
        let commandText = String(fullText[startIndex...]).trimmingCharacters(in: .newlines)

        // Clear empty commands or add to history
        if !commandText.isEmpty {
            // Add to history
            commandHistory.insert(commandText, at: 0)
            if commandHistory.count > maxHistorySize {
                commandHistory = Array(commandHistory.prefix(maxHistorySize))
            }
            historyIndex = -1

            // Execute command via SSH client
            sshClient.execute(command: commandText) { [weak self] result in
                // Command completed - output will be updated via observer
            }
        }

        // Reset history index
        historyIndex = -1

        // Update terminal size
        updateTerminalSize()
    }

    // MARK: - Output Management

    func checkForOutputUpdates() {
        updateOutputIfNeeded()
    }

    private func updateOutputIfNeeded() {
        guard let textView = textView else { return }

        let currentOutput = sshClient.output

        // Only update if output has changed
        if currentOutput != lastProcessedOutput {
            lastProcessedOutput = currentOutput

            // Calculate new content to append
            let newContent = String(currentOutput.dropFirst(processedLength))
            if !newContent.isEmpty {
                appendOutput(newContent)
                processedLength = currentOutput.count
            }
        }
    }

    private func appendOutput(_ text: String) {
        guard let textView = textView, !text.isEmpty else { return }

        // Save current selected range
        let wasEditing = textView.isFirstResponder
        let currentRange = textView.selectedRange

        // Append new text
        let currentText = textView.text ?? ""
        textView.text = currentText + text

        // Update prompt range
        updatePromptRange()

        // Auto-scroll to bottom if not manually scrolling
        if wasEditing || currentRange.location == currentText.utf16.count {
            scrollToBottom()
        }

        // Restore editing state
        if wasEditing {
            textView.becomeFirstResponder()
        }
    }

    private func updatePromptRange() {
        guard let textView = textView, let text = textView.text else { return }

        // Find the last prompt position (last "$ " or "# " in the text)
        let nsString = text as NSString
        let promptPatterns = ["$ ", "# ", "➜ "]

        var lastPromptLocation: Int?
        for pattern in promptPatterns {
            let range = nsString.range(of: pattern, options: .backwards)
            if range.location != NSNotFound {
                if lastPromptLocation == nil || range.location > lastPromptLocation! {
                    lastPromptLocation = range.location
                    promptRange = NSRange(location: range.location, length: pattern.count)
                }
            }
        }
    }

    private func scrollToBottom() {
        guard let textView = textView, let text = textView.text else { return }
        let bottomRange = NSRange(location: text.utf16.count, length: 0)
        textView.scrollRangeToVisible(bottomRange)
    }

    // MARK: - Initial State

    func updateInitialState() {
        guard let textView = textView else { return }

        lastProcessedOutput = sshClient.output
        processedLength = sshClient.output.count

        // Set initial text
        if !sshClient.output.isEmpty {
            textView.text = sshClient.output
        } else {
            // Show welcome message
            let welcome = """
            Welcome to SSH Terminal
            Type a command and press Enter to execute.

            Quick Commands:
              ls -la    - List files
              pwd       - Print working directory
              whoami    - Show current user
              df -h     - Disk usage

            """
            textView.text = welcome
            lastProcessedOutput = welcome
            processedLength = welcome.count
        }

        updatePromptRange()
        scrollToBottom()

        // Request keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak textView] in
            textView?.becomeFirstResponder()
        }
    }

    // MARK: - Terminal Size

    private func updateTerminalSize() {
        guard let textView = textView else { return }

        // Calculate terminal grid size
        let font = textView.font ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let charWidth = "x".size(withAttributes: [.font: font]).width
        let charHeight = font.lineHeight

        let bounds = textView.bounds.inset(by: textView.textContainerInset)
        let width = Int(max(40, bounds.width / charWidth))
        let height = Int(max(12, bounds.height / charHeight))

        terminalWidth = width
        terminalHeight = height

        // Notify SSH client of new size
        sshClient.requestTerminalSize(width: width, height: height)
    }
}

// MARK: - Combine import

import Combine

// MARK: - Preview

#Preview {
    TerminalView()
}

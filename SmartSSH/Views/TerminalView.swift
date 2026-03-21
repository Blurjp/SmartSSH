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

// MARK: - Custom Terminal TextView with Key Commands

class CustomTerminalTextView: UITextView {
    weak var coordinator: Coordinator?

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []

        let upArrow = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleArrowKey(_:)))
        upArrow.discoverabilityTitle = "Previous command"
        let downArrow = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleArrowKey(_:)))
        downArrow.discoverabilityTitle = "Next command"

        commands.append(upArrow)
        commands.append(downArrow)

        return commands
    }

    @objc func handleArrowKey(_ sender: UIKeyCommand) {
        coordinator?.handleArrowKey(sender)
    }
}

// MARK: - Terminal TextView (UIViewRepresentable)

struct TerminalTextView: UIViewRepresentable {
    @ObservedObject var sshClient: SSHClient
    let fontSize: Double

    func makeUIView(context: Context) -> CustomTerminalTextView {
        let textView = CustomTerminalTextView()
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
        textView.coordinator = context.coordinator

        // Store reference
        context.coordinator.textView = textView

        // Initial content
        context.coordinator.updateInitialState()

        return textView
    }

    func updateUIView(_ textView: CustomTerminalTextView, context: Context) {
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
    weak var textView: CustomTerminalTextView?
    let sshClient: SSHClient

    // Track output state
    private var lastProcessedOutput: String = ""
    private var processedLength: Int = 0

    // Command history
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var savedCurrentInput: String = ""
    private let maxHistorySize = 100

    // Track prompt position - use last known good position
    private var promptLocation: Int = 0
    private var promptLength: Int = 0

    // Initialize terminal size
    private var terminalWidth: Int = 80
    private var terminalHeight: Int = 24

    // Track if we're processing output to prevent recursive updates
    private var isUpdatingOutput: Bool = false

    init(sshClient: SSHClient) {
        self.sshClient = sshClient
        super.init()

        // Observe output changes - dispatch to main queue to avoid race conditions
        sshClient.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateOutputIfNeeded()
            }
        }.store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    deinit {
        cancellables.removeAll()
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Prevent recursive updates
        guard !isUpdatingOutput else { return false }

        // Handle Enter key - execute command
        if text == "\n" {
            executeCurrentCommand(textView)
            return false
        }

        // Prevent editing before the prompt (protect existing output)
        let promptStart = promptLocation
        if range.location < promptStart {
            return false
        }

        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        // Reset history index when user types
        historyIndex = -1
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Ensure cursor is at the end when editing begins
        if let text = textView.text, !text.isEmpty {
            textView.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }
    }

    // Handle keyboard events for command history
    func handleKeyCommand(_ keyCommand: UIKeyCommand) -> Bool {
        guard let textView = textView else { return false }

        if keyCommand.input == UIKeyCommand.inputUpArrow {
            navigateHistory(.up, in: textView)
            return true
        } else if keyCommand.input == UIKeyCommand.inputDownArrow {
            navigateHistory(.down, in: textView)
            return true
        }

        return false
    }

    // Objc selector for UIKeyCommand
    @objc func handleArrowKey(_ sender: UIKeyCommand) {
        guard let textView = textView else { return }

        if sender.input == UIKeyCommand.inputUpArrow {
            navigateHistory(.up, in: textView)
        } else if sender.input == UIKeyCommand.inputDownArrow {
            navigateHistory(.down, in: textView)
        }
    }

    // MARK: - Command Execution

    private func executeCurrentCommand(_ textView: UITextView) {
        let fullText = textView.text ?? ""

        // Extract command text (everything after prompt)
        let promptEndIndex = promptLocation + promptLength
        guard fullText.utf16.count >= promptEndIndex else { return }

        let startIndex = fullText.index(fullText.startIndex, offsetBy: promptEndIndex)
        let commandText = String(fullText[startIndex...]).trimmingCharacters(in: .newlines)

        // Add to history (skip empty and duplicates)
        if !commandText.isEmpty && commandHistory.first != commandText {
            commandHistory.insert(commandText, at: 0)
            if commandHistory.count > maxHistorySize {
                commandHistory.removeLast()
            }
        }

        // Reset history index
        historyIndex = -1
        savedCurrentInput = ""

        // Execute command via SSH client
        if !commandText.isEmpty {
            sshClient.execute(command: commandText) { [weak self] result in
                // Command completed - output will be updated via observer
                DispatchQueue.main.async {
                    self?.updateTerminalSize()
                }
            }
        }
    }

    // MARK: - Command History Navigation

    private enum HistoryDirection {
        case up, down
    }

    private func navigateHistory(_ direction: HistoryDirection, in textView: UITextView) {
        guard !commandHistory.isEmpty else { return }

        let fullText = textView.text ?? ""
        let promptEndIndex = promptLocation + promptLength

        // Save current input on first navigation
        if historyIndex == -1 {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: min(promptEndIndex, fullText.utf16.count))
            savedCurrentInput = String(fullText[startIndex...])
        }

        // Calculate new index
        let newIndex: Int
        switch direction {
        case .up:
            newIndex = min(historyIndex + 1, commandHistory.count - 1)
        case .down:
            newIndex = max(historyIndex - 1, -1)
        }

        // Skip if no change
        guard newIndex != historyIndex else { return }
        historyIndex = newIndex

        // Get the command to display
        let commandText: String
        if historyIndex == -1 {
            commandText = savedCurrentInput
        } else {
            commandText = commandHistory[historyIndex]
        }

        // Replace text after prompt
        let promptEnd = fullText.index(fullText.startIndex, offsetBy: promptEndIndex)
        let newText = String(fullText[..<promptEnd]) + commandText

        textView.text = newText

        // Move cursor to end
        textView.selectedRange = NSRange(location: newText.utf16.count, length: 0)
    }

    // MARK: - Output Management

    func checkForOutputUpdates() {
        updateOutputIfNeeded()
    }

    private func updateOutputIfNeeded() {
        guard let textView = textView, !isUpdatingOutput else { return }

        let currentOutput = sshClient.output

        // Only update if output has changed
        if currentOutput != lastProcessedOutput {
            isUpdatingOutput = true
            defer { isUpdatingOutput = false }

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
        let oldTextLength = textView.text?.utf16.count ?? 0

        // Append new text
        let currentText = textView.text ?? ""
        textView.text = currentText + text

        // Update prompt position - track the end of output
        detectAndUpdatePromptPosition()

        // Auto-scroll to bottom if cursor was at end
        let wasAtEnd = currentRange.location >= oldTextLength - 1
        if wasEditing || wasAtEnd {
            scrollToBottom()
            // Move cursor to end after output
            textView.selectedRange = NSRange(location: textView.text?.utf16.count ?? 0, length: 0)
        }

        // Restore editing state
        if wasEditing {
            textView.becomeFirstResponder()
        }
    }

    private func detectAndUpdatePromptPosition() {
        guard let textView = textView, let text = textView.text else { return }

        // The prompt position is at the end of the text
        // We track where the user can start typing
        let textLength = text.utf16.count

        // Look for common prompt patterns at the end of text
        let nsString = text as NSString

        // Common prompt endings: "$ ", "# ", "➜ ", "> "
        let promptPatterns = ["$ ", "# ", "➜ ", "> ", "% "]

        var foundPromptEnd = false
        for pattern in promptPatterns {
            // Check if text ends with this pattern or contains it near the end
            let searchRange = NSRange(location: max(0, textLength - 200), length: min(200, textLength))
            let range = nsString.range(of: pattern, options: [.backwards], range: searchRange)

            if range.location != NSNotFound {
                // Found a prompt - set typing position after it
                promptLocation = range.location
                promptLength = pattern.count
                foundPromptEnd = true
                break
            }
        }

        // Fallback: if no prompt found, allow typing at end
        if !foundPromptEnd {
            promptLocation = textLength
            promptLength = 0
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
            detectAndUpdatePromptPosition()
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
            // No prompt in welcome screen - allow typing at end
            promptLocation = welcome.utf16.count
            promptLength = 0
        }

        scrollToBottom()

        // Request keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.textView?.becomeFirstResponder()
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

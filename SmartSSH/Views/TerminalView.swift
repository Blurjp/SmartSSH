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
    @ObservedObject private var sessionStore = SessionStore.shared
    @AppStorage("terminalFontSize") private var fontSize = 14.0
    @AppStorage("terminalFont") private var fontName = "Menlo"
    @AppStorage("terminalColorScheme") private var colorScheme = "dark"
    @State private var savedSnippets: [Snippet] = []
    @State private var showingCommandLibrary = false

    private var theme: TerminalTheme {
        TerminalTheme(named: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !sessionStore.sessions.isEmpty {
                    sessionSwitcher
                }

                if let selectedSession = sessionStore.selectedSession {
                    ActiveTerminalSessionView(
                        storedSession: selectedSession,
                        fontSize: fontSize,
                        fontName: fontName,
                        theme: theme,
                        savedSnippets: savedSnippets,
                        showingCommandLibrary: $showingCommandLibrary,
                        onLoadSnippets: loadSavedSnippets
                    )
                    .id(selectedSession.id)
                } else {
                    Color.clear
                }
            }
            .background(theme.background)
            .navigationTitle("Terminal")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarMenu
                }
            }
            .onAppear(perform: loadSavedSnippets)
            .overlay {
                if sessionStore.selectedSession == nil {
                    disconnectedOverlay
                }
            }
            .sheet(isPresented: $showingCommandLibrary) {
                CommandLibraryView(
                    snippets: savedSnippets,
                    onRun: { command in
                        guard let sshClient = sessionStore.selectedSession?.client else { return }
                        runCommand(command, using: sshClient)
                    },
                    onInsert: { command in
                        guard let sshClient = sessionStore.selectedSession?.client else { return }
                        insertCommand(command, using: sshClient)
                    },
                    onRefresh: loadSavedSnippets
                )
            }
        }
    }

    private var sessionSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sessionStore.sessions) { storedSession in
                    SessionChipView(
                        storedSession: storedSession,
                        isSelected: storedSession.id == sessionStore.selectedSession?.id,
                        theme: theme,
                        onSelect: { sessionStore.select(sessionID: storedSession.id) },
                        onClose: { sessionStore.disconnect(sessionID: storedSession.id) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(theme.chromeBackground)
    }

    private var toolbarMenu: some View {
        Menu {
            Button {
                loadSavedSnippets()
                showingCommandLibrary = true
            } label: {
                Label("Command Library", systemImage: "square.grid.2x2")
            }

            Divider()

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

            if let sshClient = sessionStore.selectedSession?.client {
                Divider()

                Button {
                    sshClient.clearOutput()
                } label: {
                    Label("Clear Output", systemImage: "trash")
                }

                Button {
                    exportLog(output: sshClient.output)
                } label: {
                    Label("Export Log", systemImage: "square.and.arrow.up")
                }
            }

            if sessionStore.selectedSession != nil {
                Divider()

                Button(role: .destructive) {
                    sessionStore.disconnectSelectedSession()
                } label: {
                    Label("Close Session", systemImage: "xmark.circle")
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
            Text("Connect to hosts from the Hosts tab to open terminal sessions.")
        } actions: {
            Button("Go to Hosts") {
                NotificationCenter.default.post(name: .smartSSHSelectTab, object: 0)
            }
            .buttonStyle(.borderedProminent)
        }
        .background(theme.background)
    }

    private func exportLog(output: String) {
        let activityVC = UIActivityViewController(
            activityItems: [output],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }

    private func loadSavedSnippets() {
        guard let data = UserDefaults.standard.data(forKey: "saved_snippets"),
              let snippets = try? JSONDecoder().decode([Snippet].self, from: data) else {
            savedSnippets = []
            return
        }

        savedSnippets = snippets.sorted { lhs, rhs in
            let lhsDate = lhs.lastUsedAt ?? lhs.createdAt
            let rhsDate = rhs.lastUsedAt ?? rhs.createdAt
            return lhsDate > rhsDate
        }
    }

    private func runCommand(_ command: String, using sshClient: SSHClient) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sshClient.sendInput(command, addNewline: true) { result in
            if case .failure = result {
                sshClient.execute(command: command) { _ in }
            }
        }
    }

    private func insertCommand(_ command: String, using sshClient: SSHClient) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sshClient.sendInput(command) { result in
            if case .failure = result {
                UIPasteboard.general.string = command
            }
        }
    }
}

private struct ActiveTerminalSessionView: View {
    let storedSession: StoredSession
    let fontSize: Double
    let fontName: String
    let theme: TerminalTheme
    let savedSnippets: [Snippet]
    @Binding var showingCommandLibrary: Bool
    let onLoadSnippets: () -> Void

    @ObservedObject private var sshClient: SSHClient

    init(
        storedSession: StoredSession,
        fontSize: Double,
        fontName: String,
        theme: TerminalTheme,
        savedSnippets: [Snippet],
        showingCommandLibrary: Binding<Bool>,
        onLoadSnippets: @escaping () -> Void
    ) {
        self.storedSession = storedSession
        self.fontSize = fontSize
        self.fontName = fontName
        self.theme = theme
        self.savedSnippets = savedSnippets
        self._showingCommandLibrary = showingCommandLibrary
        self.onLoadSnippets = onLoadSnippets
        _sshClient = ObservedObject(wrappedValue: storedSession.client)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar

            TerminalTextView(
                sshClient: sshClient,
                fontSize: fontSize,
                fontName: fontName,
                theme: theme
            )

            if sshClient.isConnected {
                commandTray
            }
        }
    }

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

            if !sshClient.activePortForwardPorts.isEmpty {
                Text("Forwards \(sshClient.activePortForwardPorts.map(String.init).joined(separator: ", "))")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(storedSession.host.displayInfo)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(theme.chromeBackground)
    }

    private var commandTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                commandButton(title: "Library", subtitle: "Saved", systemImage: "square.grid.2x2") {
                    onLoadSnippets()
                    showingCommandLibrary = true
                }

                ForEach(QuickActionsView.availableActions) { action in
                    commandButton(
                        title: action.title,
                        subtitle: action.subtitle,
                        systemImage: action.icon
                    ) {
                        sshClient.sendInput(action.command, addNewline: true) { result in
                            if case .failure = result {
                                sshClient.execute(command: action.command) { _ in }
                            }
                        }
                    }
                }

                ForEach(savedSnippets.prefix(6)) { snippet in
                    commandButton(
                        title: snippet.name,
                        subtitle: snippet.command,
                        systemImage: "text.badge.plus"
                    ) {
                        sshClient.sendInput(snippet.command, addNewline: true) { result in
                            if case .failure = result {
                                sshClient.execute(command: snippet.command) { _ in }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(theme.chromeBackground)
    }

    private func commandButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(theme.accent)

                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)
            .padding(10)
            .background(theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
}

private struct SessionChipView: View {
    let storedSession: StoredSession
    let isSelected: Bool
    let theme: TerminalTheme
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var sshClient: SSHClient

    init(
        storedSession: StoredSession,
        isSelected: Bool,
        theme: TerminalTheme,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.storedSession = storedSession
        self.isSelected = isSelected
        self.theme = theme
        self.onSelect = onSelect
        self.onClose = onClose
        _sshClient = ObservedObject(wrappedValue: storedSession.client)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.appNamed(sshClient.state.color))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(storedSession.host.wrappedName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(storedSession.host.wrappedUsername)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? theme.panelBackground : theme.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(isSelected ? theme.background.opacity(0.35) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    let fontName: String
    let theme: TerminalTheme

    func makeUIView(context: Context) -> CustomTerminalTextView {
        let textView = CustomTerminalTextView()
        textView.font = resolvedFont()
        textView.backgroundColor = UIColor(theme.background)
        textView.textColor = UIColor(theme.text)
        textView.tintColor = UIColor(theme.accent)
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
        let updatedFont = resolvedFont()
        if textView.font?.fontName != updatedFont.fontName || textView.font?.pointSize != updatedFont.pointSize {
            textView.font = updatedFont
        }
        textView.backgroundColor = UIColor(theme.background)
        textView.textColor = UIColor(theme.text)
        textView.tintColor = UIColor(theme.accent)

        context.coordinator.checkForOutputUpdates()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sshClient: sshClient)
    }

    private func resolvedFont() -> UIFont {
        if let customFont = UIFont(name: fontName, size: fontSize) {
            return customFont
        }

        return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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

        // Use UTF-16 index to handle multi-byte characters correctly
        guard let startIndex = fullText.utf16.index(fullText.startIndex, offsetBy: promptEndIndex, limitedBy: fullText.endIndex) else { return }
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
            let safeIndex = min(promptEndIndex, fullText.utf16.count)
            if let startIndex = fullText.utf16.index(fullText.startIndex, offsetBy: safeIndex, limitedBy: fullText.endIndex) {
                savedCurrentInput = String(fullText[startIndex...])
            }
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

        // Replace text after prompt using UTF-16 safe indexing
        let safePromptEnd = min(promptEndIndex, fullText.utf16.count)
        guard let promptEnd = fullText.utf16.index(fullText.startIndex, offsetBy: safePromptEnd, limitedBy: fullText.endIndex) else { return }
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

    /// Strip ANSI escape codes from terminal output
    private static func stripANSIEscapeCodes(from text: String) -> String {
        // ANSI escape sequences start with ESC (0x1b = 27) followed by [
        // Common patterns:
        // - ESC[K : Erase to end of line
        // - ESC[?2004h : Enable bracketed paste mode
        // - ESC[?2004l : Disable bracketed paste mode
        // - ESC[<n>m : Set graphics mode (colors, bold, etc.)
        // - ESC[<n>A/B/C/D : Cursor movement
        // - ESC[<n>;<n>H : Cursor position
        // - ESC[?<n>h/l : Private mode set/reset

        var result = text
        // ESC character as Character
        let esc = Character(UnicodeScalar(27))

        // Match ESC followed by [ and any parameters ending with a letter or ? sequences
        let ansiPattern = "\\u001b\\[[0-9;?]*[a-zA-Z]"

        if let regex = try? NSRegularExpression(pattern: ansiPattern, options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Also strip bare ESC characters followed by [ that might be incomplete
        let escBracket = String(esc) + "["
        result = result.replacingOccurrences(of: escBracket, with: "")

        return result
    }

    private func appendOutput(_ text: String) {
        guard let textView = textView, !text.isEmpty else { return }

        // Filter out ANSI escape codes
        let filteredText = Self.stripANSIEscapeCodes(from: text)

        // Save current selected range
        let wasEditing = textView.isFirstResponder
        let currentRange = textView.selectedRange
        let oldTextLength = textView.text?.utf16.count ?? 0

        // Append filtered text
        let currentText = textView.text ?? ""
        textView.text = currentText + filteredText

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

private struct TerminalTheme {
    let background: Color
    let chromeBackground: Color
    let panelBackground: Color
    let text: Color
    let secondaryText: Color
    let accent: Color

    init(named name: String) {
        switch name {
        case "light":
            background = Color(red: 0.98, green: 0.98, blue: 0.97)
            chromeBackground = Color(red: 0.92, green: 0.93, blue: 0.91)
            panelBackground = Color.white
            text = Color.black
            secondaryText = Color.gray
            accent = Color.blue
        case "solarized-dark":
            background = Color(red: 0.0, green: 0.17, blue: 0.21)
            chromeBackground = Color(red: 0.03, green: 0.21, blue: 0.26)
            panelBackground = Color(red: 0.02, green: 0.24, blue: 0.29)
            text = Color(red: 0.51, green: 0.58, blue: 0.59)
            secondaryText = Color(red: 0.36, green: 0.47, blue: 0.5)
            accent = Color(red: 0.15, green: 0.55, blue: 0.82)
        case "dracula":
            background = Color(red: 0.11, green: 0.11, blue: 0.16)
            chromeBackground = Color(red: 0.16, green: 0.16, blue: 0.23)
            panelBackground = Color(red: 0.2, green: 0.2, blue: 0.29)
            text = Color(red: 0.97, green: 0.97, blue: 0.95)
            secondaryText = Color(red: 0.67, green: 0.65, blue: 0.75)
            accent = Color(red: 1.0, green: 0.47, blue: 0.78)
        case "monokai":
            background = Color(red: 0.15, green: 0.16, blue: 0.13)
            chromeBackground = Color(red: 0.19, green: 0.2, blue: 0.16)
            panelBackground = Color(red: 0.23, green: 0.24, blue: 0.2)
            text = Color(red: 0.97, green: 0.97, blue: 0.95)
            secondaryText = Color(red: 0.74, green: 0.72, blue: 0.64)
            accent = Color(red: 0.65, green: 0.89, blue: 0.18)
        default:
            background = .black
            chromeBackground = Color(red: 0.08, green: 0.08, blue: 0.08)
            panelBackground = Color(red: 0.13, green: 0.13, blue: 0.13)
            text = Color.green
            secondaryText = Color.white.opacity(0.65)
            accent = Color.blue
        }
    }
}

private struct CommandLibraryView: View {
    let snippets: [Snippet]
    let onRun: (String) -> Void
    let onInsert: (String) -> Void
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var feedbackMessage = ""

    private var quickActions: [QuickAction] {
        filter(QuickActionsView.availableActions) {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSnippets: [Snippet] {
        filter(snippets) {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !feedbackMessage.isEmpty {
                    Section {
                        Text(feedbackMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quick Commands") {
                    ForEach(quickActions) { action in
                        commandRow(
                            title: action.title,
                            command: action.command,
                            subtitle: action.subtitle,
                            tags: []
                        )
                    }
                }

                Section("Saved Snippets") {
                    if filteredSnippets.isEmpty {
                        Text("No saved snippets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredSnippets) { snippet in
                            commandRow(
                                title: snippet.name,
                                command: snippet.command,
                                subtitle: snippet.description,
                                tags: snippet.tags
                            )
                        }
                    }
                }
            }
            .navigationTitle("Command Library")
            .searchable(text: $searchText, prompt: "Search commands")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(title: String, command: String, subtitle: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .fontWeight(.semibold)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Run") {
                    onRun(command)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack {
                Button("Insert") {
                    onInsert(command)
                    feedbackMessage = "Inserted into the current shell."
                }
                .buttonStyle(.bordered)

                Button("Copy") {
                    UIPasteboard.general.string = command
                    feedbackMessage = "Copied to clipboard."
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func filter<T>(_ items: [T], using predicate: (T) -> Bool) -> [T] {
        guard !searchText.isEmpty else { return items }
        return items.filter(predicate)
    }
}

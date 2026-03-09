//
//  AIService.swift
//  SSH Terminal
//
//  AI-powered features (command suggestions, error diagnosis)
//

import Foundation

// MARK: - AI Service

class AIService: ObservableObject {
    static let shared = AIService()
    
    @Published var isEnabled: Bool = true
    @Published var isProcessing: Bool = false
    
    private let apiKey: String? = nil // Set your OpenAI API key here
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    // MARK: - Command Suggestions
    
    func suggestCommand(
        context: String,
        recentCommands: [String] = [],
        completion: @escaping (Result<[CommandSuggestion], AIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.disabled))
            return
        }
        
        isProcessing = true
        
        // Simulate AI suggestions (replace with real OpenAI API call)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let suggestions = self.generateSimulatedSuggestions(context: context, recentCommands: recentCommands)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(.success(suggestions))
            }
        }
    }
    
    // MARK: - Error Diagnosis
    
    func diagnoseError(
        errorOutput: String,
        command: String,
        completion: @escaping (Result<ErrorDiagnosis, AIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.disabled))
            return
        }
        
        isProcessing = true
        
        // Simulate error diagnosis
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let diagnosis = self.generateSimulatedDiagnosis(errorOutput: errorOutput, command: command)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(.success(diagnosis))
            }
        }
    }
    
    // MARK: - Command Explanation
    
    func explainCommand(
        _ command: String,
        completion: @escaping (Result<CommandExplanation, AIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.disabled))
            return
        }
        
        isProcessing = true
        
        // Simulate command explanation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let explanation = self.generateSimulatedExplanation(command: command)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(.success(explanation))
            }
        }
    }
    
    // MARK: - Snippet Generation
    
    func generateSnippet(
        description: String,
        completion: @escaping (Result<Snippet, AIError>) -> Void
    ) {
        guard isEnabled else {
            completion(.failure(.disabled))
            return
        }
        
        isProcessing = true
        
        // Simulate snippet generation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            let snippet = self.generateSimulatedSnippet(description: description)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(.success(snippet))
            }
        }
    }
    
    // MARK: - Simulation Methods
    
    private func generateSimulatedSuggestions(context: String, recentCommands: [String]) -> [CommandSuggestion] {
        let allSuggestions = [
            CommandSuggestion(
                command: "ls -la",
                description: "List all files with details",
                category: .fileManagement
            ),
            CommandSuggestion(
                command: "df -h",
                description: "Check disk space usage",
                category: .system
            ),
            CommandSuggestion(
                command: "top",
                description: "Show running processes",
                category: .monitoring
            ),
            CommandSuggestion(
                command: "grep -r 'pattern' .",
                description: "Search for pattern in files",
                category: .search
            ),
            CommandSuggestion(
                command: "systemctl status nginx",
                description: "Check nginx service status",
                category: .serviceManagement
            ),
            CommandSuggestion(
                command: "tail -f /var/log/syslog",
                description: "Follow system logs in real-time",
                category: .logs
            ),
            CommandSuggestion(
                command: "docker ps -a",
                description: "List all Docker containers",
                category: .docker
            ),
            CommandSuggestion(
                command: "git status",
                description: "Check git repository status",
                category: .git
            ),
        ]
        
        // Return 3-5 random suggestions
        return Array(allSuggestions.shuffled().prefix(5))
    }
    
    private func generateSimulatedDiagnosis(errorOutput: String, command: String) -> ErrorDiagnosis {
        let lowercased = errorOutput.lowercased()
        
        if lowercased.contains("permission denied") {
            return ErrorDiagnosis(
                problem: "Permission Denied",
                cause: "The current user doesn't have permission to access this file or directory.",
                solutions: [
                    "Run the command with sudo: `sudo \(command)`",
                    "Check file permissions: `ls -la`",
                    "Change ownership: `chown user:group filename`",
                ],
                severity: .warning
            )
        } else if lowercased.contains("command not found") {
            return ErrorDiagnosis(
                problem: "Command Not Found",
                cause: "The command '\(command)' is not installed or not in your PATH.",
                solutions: [
                    "Install the command: `apt install <package>` or `brew install <package>`",
                    "Check if the command exists: `which <command>`",
                    "Update your PATH environment variable",
                ],
                severity: .error
            )
        } else if lowercased.contains("connection refused") {
            return ErrorDiagnosis(
                problem: "Connection Refused",
                cause: "The target service is not running or the port is blocked.",
                solutions: [
                    "Check if the service is running: `systemctl status <service>`",
                    "Check if the port is open: `netstat -tulpn | grep <port>`",
                    "Check firewall rules: `ufw status`",
                ],
                severity: .error
            )
        } else if lowercased.contains("no such file or directory") {
            return ErrorDiagnosis(
                problem: "File Not Found",
                cause: "The specified file or directory doesn't exist.",
                solutions: [
                    "Check the current directory: `pwd`",
                    "List files: `ls -la`",
                    "Verify the path is correct",
                ],
                severity: .error
            )
        } else {
            return ErrorDiagnosis(
                problem: "Unknown Error",
                cause: "Unable to diagnose this error automatically.",
                solutions: [
                    "Check the error message for clues",
                    "Search online for the error",
                    "Check system logs: `journalctl -xe`",
                ],
                severity: .info
            )
        }
    }
    
    private func generateSimulatedExplanation(command: String) -> CommandExplanation {
        let parts = command.split(separator: " ")
        let mainCommand = String(parts.first ?? "")
        
        let explanations: [String: String] = [
            "ls": "Lists directory contents. Use `-l` for long format, `-a` to show hidden files.",
            "cd": "Changes the current directory. Use `cd ..` to go up one level.",
            "grep": "Searches for patterns in text. Use `-r` for recursive, `-i` for case-insensitive.",
            "find": "Searches for files in a directory hierarchy. Very powerful for locating files.",
            "cat": "Concatenates and displays file contents. Use with caution on large files.",
            "chmod": "Changes file permissions. Use numeric (755) or symbolic (u+x) notation.",
            "chown": "Changes file owner and group. Requires sudo for system files.",
            "ps": "Displays running processes. Use `aux` for detailed information.",
            "kill": "Terminates processes by PID. Use `-9` for force kill.",
            "tar": "Archives files. Use `-czf` to create gzip archives, `-xzf` to extract.",
        ]
        
        let description = explanations[mainCommand] ?? "Command not in database. This would be explained by AI in the full version."
        
        return CommandExplanation(
            command: command,
            mainCommand: mainCommand,
            description: description,
            flags: parts.dropFirst().map { String($0) },
            examples: [
                "Basic usage: \(mainCommand)",
                "With options: \(command)",
            ],
            risks: mainCommand == "rm" ? ["This command can permanently delete files!"] : []
        )
    }
    
    private func generateSimulatedSnippet(description: String) -> Snippet {
        let lowercased = description.lowercased()
        
        if lowercased.contains("backup") {
            return Snippet(
                name: "Backup Script",
                command: "tar -czf backup_$(date +%Y%m%d).tar.gz /path/to/backup",
                description: "Create a timestamped backup archive",
                tags: ["backup", "tar", "archive"],
                createdAt: Date(),
                useCount: 0
            )
        } else if lowercased.contains("log") || lowercased.contains("logs") {
            return Snippet(
                name: "View Logs",
                command: "tail -f /var/log/syslog | grep --color=auto -i error",
                description: "Follow logs and highlight errors",
                tags: ["logs", "monitoring", "debug"],
                createdAt: Date(),
                useCount: 0
            )
        } else if lowercased.contains("docker") {
            return Snippet(
                name: "Docker Cleanup",
                command: "docker system prune -af --volumes",
                description: "Clean up unused Docker resources",
                tags: ["docker", "cleanup"],
                createdAt: Date(),
                useCount: 0
            )
        } else {
            return Snippet(
                name: "Custom Command",
                command: "# AI-generated command for: \(description)",
                description: description,
                tags: ["ai-generated"],
                createdAt: Date(),
                useCount: 0
            )
        }
    }
}

// MARK: - Models

struct CommandSuggestion: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let category: CommandCategory
    
    var icon: String {
        category.icon
    }
}

enum CommandCategory: String, CaseIterable {
    case fileManagement = "Files"
    case system = "System"
    case monitoring = "Monitoring"
    case search = "Search"
    case serviceManagement = "Services"
    case logs = "Logs"
    case docker = "Docker"
    case git = "Git"
    case network = "Network"
    
    var icon: String {
        switch self {
        case .fileManagement: return "folder"
        case .system: return "gear"
        case .monitoring: return "chart.line.uptrend.xyaxis"
        case .search: return "magnifyingglass"
        case .serviceManagement: return "server.rack"
        case .logs: return "doc.text"
        case .docker: return "shippingbox"
        case .git: return "arrow.triangle.branch"
        case .network: return "network"
        }
    }
}

struct ErrorDiagnosis: Identifiable {
    let id = UUID()
    let problem: String
    let cause: String
    let solutions: [String]
    let severity: Severity
    
    var icon: String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
    
    var color: String {
        switch severity {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        }
    }
}

enum Severity {
    case info, warning, error
}

struct CommandExplanation: Identifiable {
    let id = UUID()
    let command: String
    let mainCommand: String
    let description: String
    let flags: [String]
    let examples: [String]
    let risks: [String]
}

struct AIError: Error {
    let message: String
    
    static let disabled = AIError(message: "AI features are disabled")
    static let noAPIKey = AIError(message: "OpenAI API key not configured")
    static let networkError = AIError(message: "Network request failed")
}

// MARK: - Real API Implementation (Template)

/*
 Replace simulation with real OpenAI API calls:
 
 func callOpenAI(prompt: String, completion: @escaping (Result<String, AIError>) -> Void) {
     guard let apiKey = apiKey else {
         completion(.failure(.noAPIKey))
         return
     }
     
     var request = URLRequest(url: URL(string: baseURL)!)
     request.httpMethod = "POST"
     request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
     request.setValue("application/json", forHTTPHeaderField: "Content-Type")
     
     let body: [String: Any] = [
         "model": "gpt-4",
         "messages": [
             ["role": "system", "content": "You are a helpful SSH/Linux expert."],
             ["role": "user", "content": prompt]
         ],
         "temperature": 0.7,
         "max_tokens": 500
     ]
     
     request.httpBody = try? JSONSerialization.data(withJSONObject: body)
     
     URLSession.shared.dataTask(with: request) { data, response, error in
         // Handle response
     }.resume()
 }
 */

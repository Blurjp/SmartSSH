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
    
    private let apiKey: String? = nil
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

        guard apiKey != nil else {
            completion(.failure(.noAPIKey))
            return
        }
        
        isProcessing = true
        isProcessing = false
        completion(.failure(.networkError))
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

        guard apiKey != nil else {
            completion(.failure(.noAPIKey))
            return
        }
        
        isProcessing = true
        isProcessing = false
        completion(.failure(.networkError))
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

        guard apiKey != nil else {
            completion(.failure(.noAPIKey))
            return
        }
        
        isProcessing = true
        isProcessing = false
        completion(.failure(.networkError))
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

        guard apiKey != nil else {
            completion(.failure(.noAPIKey))
            return
        }
        
        isProcessing = true
        isProcessing = false
        completion(.failure(.networkError))
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

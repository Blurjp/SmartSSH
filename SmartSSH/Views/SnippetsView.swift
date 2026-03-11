//
//  SnippetsView.swift
//  SSH Terminal
//
//  Command snippets management
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct Snippet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var command: String
    var description: String
    var tags: [String]
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int = 0
}

struct SnippetsView: View {
    private let snippetsDefaultsKey = "saved_snippets"

    @State private var snippets: [Snippet] = []
    @State private var searchText = ""
    @State private var showingAddSnippet = false
    @State private var showingAISuggestion = false
    
    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return snippets
        } else {
            return snippets.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.command.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            snippetsList
            .searchable(text: $searchText, prompt: "Search snippets...")
            .navigationTitle("Snippets")
            .toolbar { snippetsToolbar }
            .sheet(isPresented: $showingAddSnippet) {
                AddSnippetView { snippet in
                    snippets.append(snippet)
                }
            }
            .onAppear(perform: loadSnippets)
            .onChange(of: snippets) { _, newValue in
                saveSnippets(newValue)
            }
            .overlay {
                if snippets.isEmpty {
                    ContentUnavailableView(
                        "No Snippets",
                        systemImage: "text.badge.plus",
                        description: Text("Save frequently used commands as snippets for quick access.")
                    )
                }
            }
        }
    }

    private var snippetsList: some View {
        List {
            ForEach(filteredSnippets) { snippet in
                snippetRow(snippet)
            }
        }
    }

    private var snippetsToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    showingAddSnippet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }

                Button {
                    showingAISuggestion = true
                } label: {
                    Label("AI Generate", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }
    
    private func copySnippet(_ snippet: Snippet) {
        UIPasteboard.general.string = snippet.command
    }
    
    private func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    private func loadSnippets() {
        guard let data = UserDefaults.standard.data(forKey: snippetsDefaultsKey),
              let savedSnippets = try? JSONDecoder().decode([Snippet].self, from: data) else {
            return
        }

        snippets = savedSnippets
    }

    private func saveSnippets(_ snippets: [Snippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: snippetsDefaultsKey)
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        SnippetRowView(snippet: snippet)
            .onTapGesture {
                copySnippet(snippet)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteSnippet(snippet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    copySnippet(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(.blue)
            }
    }
}

struct SnippetRowView: View {
    let snippet: Snippet
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snippet.name)
                    .font(.headline)
                
                Spacer()
                
                Text("\(snippet.useCount) uses")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Text(snippet.command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            if !snippet.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(snippet.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddSnippetView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var command = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var showAIHelp = false
    
    let onAdd: (Snippet) -> Void
    
    var isValid: Bool {
        !name.isEmpty && !command.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Snippet Details") {
                    TextField("Name", text: $name)
                    
                    TextField("Command", text: $command, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...10)
                    
                    TextField("Description (optional)", text: $description)
                    
                    TextField("Tags (comma separated)", text: $tags)
                }
                
                Section {
                    Button {
                        showAIHelp = true
                    } label: {
                        Label("AI: Help me write this command", systemImage: "sparkles")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSnippet()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private func saveSnippet() {
        let tagList = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let snippet = Snippet(
            name: name,
            command: command,
            description: description,
            tags: tagList,
            createdAt: Date(),
            lastUsedAt: nil,
            useCount: 0
        )
        
        onAdd(snippet)
        dismiss()
    }
}

#Preview {
    SnippetsView()
}

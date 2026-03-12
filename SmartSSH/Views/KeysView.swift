//
//  KeysView.swift
//  SSH Terminal
//
//  SSH Key management
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct KeysView: View {
    @State private var keys: [SavedSSHKey] = []
    @State private var showingGenerateKey = false
    @State private var errorMessage = ""
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(keys) { key in
                    KeyRowView(key: key)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteKey(key)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                copyPublicKey(key)
                            } label: {
                                Label("Copy Public Key", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                }
            }
            .navigationTitle("SSH Keys")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingGenerateKey = true
                        } label: {
                            Label("Generate New Key", systemImage: "key.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingGenerateKey) {
                GenerateKeyView {
                    loadKeys()
                }
            }
            .alert("SSH Keys", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear(perform: loadKeys)
            .overlay {
                if keys.isEmpty {
                    ContentUnavailableView(
                        "No SSH Keys",
                        systemImage: "key",
                        description: Text("Generate or import an SSH key to get started.")
                    )
                }
            }
        }
    }
    
    private func deleteKey(_ key: SavedSSHKey) {
        do {
            try SSHManager.shared.deleteKey(named: key.name)
            loadKeys()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func copyPublicKey(_ key: SavedSSHKey) {
        UIPasteboard.general.string = key.publicKey
    }

    private func loadKeys() {
        keys = SSHManager.shared.loadSavedKeys()
    }
}

struct KeyRowView: View {
    let key: SavedSSHKey
    
    var body: some View {
        HStack {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(key.name)
                    .font(.headline)
                
                Text("\(key.type) • \(key.fingerprint)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(key.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct GenerateKeyView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var keyName = ""
    @State private var keyType = "ed25519"
    @State private var keyComment = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    
    let onGenerate: () -> Void
    
    let keyTypes = ["ed25519"]
    
    var isValid: Bool {
        !keyName.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Key Details") {
                    TextField("Key Name", text: $keyName)
                        .textContentType(.name)
                    
                    Picker("Key Type", selection: $keyType) {
                        ForEach(keyTypes, id: \.self) { type in
                            Text(type.uppercased()).tag(type)
                        }
                    }
                    
                    TextField("Comment (optional)", text: $keyComment)
                        .textContentType(.emailAddress)
                }
                Section("Encryption") {
                    Text("Generated keys are currently saved without a passphrase. Add passphrase support before distributing to untrusted devices.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Generate Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        generateKey()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Unable to Generate Key", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func generateKey() {
        do {
            let result = try SSHManager.shared.generateKeyPair(
                name: keyName,
                type: keyType,
                comment: keyComment.isEmpty ? nil : keyComment
            )
        
            try SSHManager.shared.saveKey(
                name: keyName,
                privateKey: result.privateKey,
                publicKey: result.publicKey,
                fingerprint: result.fingerprint,
                type: keyType
            )

            onGenerate()
            dismiss()
        } catch {
            errorMessage = (error as? SSHError)?.localizedDescription ?? error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    KeysView()
}

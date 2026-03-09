//
//  KeysView.swift
//  SSH Terminal
//
//  SSH Key management
//

import SwiftUI

struct SSHKey: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let fingerprint: String
    let createdAt: Date
    let publicKey: String
}

struct KeysView: View {
    @State private var keys: [SSHKey] = []
    @State private var showingGenerateKey = false
    @State private var showingImportKey = false
    
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
                        
                        Button {
                            showingImportKey = true
                        } label: {
                            Label("Import Key", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingGenerateKey) {
                GenerateKeyView { key in
                    keys.append(key)
                }
            }
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
    
    private func deleteKey(_ key: SSHKey) {
        keys.removeAll { $0.id == key.id }
        // TODO: Delete from Keychain
    }
    
    private func copyPublicKey(_ key: SSHKey) {
        UIPasteboard.general.string = key.publicKey
    }
}

struct KeyRowView: View {
    let key: SSHKey
    
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
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    
    let onGenerate: (SSHKey) -> Void
    
    let keyTypes = ["ed25519", "rsa", "ecdsa"]
    
    var isValid: Bool {
        !keyName.isEmpty && (passphrase.isEmpty || passphrase == confirmPassphrase)
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
                
                Section("Passphrase (optional)") {
                    SecureField("Passphrase", text: $passphrase)
                    SecureField("Confirm Passphrase", text: $confirmPassphrase)
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
        }
    }
    
    private func generateKey() {
        let result = SSHManager.shared.generateKeyPair(
            name: keyName,
            type: keyType,
            comment: keyComment.isEmpty ? nil : keyComment
        )
        
        let key = SSHKey(
            name: keyName,
            type: keyType.uppercased(),
            fingerprint: result.fingerprint,
            createdAt: Date(),
            publicKey: result.publicKey
        )
        
        // Save to Keychain
        SSHManager.shared.saveKey(
            name: keyName,
            privateKey: result.privateKey,
            publicKey: result.publicKey,
            fingerprint: result.fingerprint,
            passphrase: passphrase.isEmpty ? nil : passphrase
        )
        
        onGenerate(key)
        dismiss()
    }
}

#Preview {
    KeysView()
}

//
//  AddHostView.swift
//  SSH Terminal
//
//  Add/Edit host view with improved UX
//

import SwiftUI

struct AddHostView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var group = ""
    @State private var color = "blue"
    @State private var useKeyAuth = false
    @State private var selectedKey = ""
    
    @State private var isTesting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name, hostname, port, username, password
    }
    
    let colors = ["blue", "green", "orange", "purple", "red", "pink", "yellow", "gray"]
    
    var isValid: Bool {
        !name.isEmpty && !hostname.isEmpty && !username.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                authenticationSection
                organizationSection
                testConnectionSection
            }
            .formStyle(.grouped)
            .navigationTitle("Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHost()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showingSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Connection test successful!")
            }
        }
    }
    
    // MARK: - View Components
    
    private var basicInfoSection: some View {
        Section {
            // Name
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($focusedField, equals: .name)
                    .onAppear {
                        focusedField = .name
                    }
            }
            
            // Hostname
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                TextField("Hostname or IP", text: $hostname)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .hostname)
            }
            
            // Port
            HStack {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .port)
                
                Stepper("", value: Binding(
                    get: { Int(port) ?? 22 },
                    set: { port = String($0) }
                ), in: 1...65535)
                .labelsHidden()
            }
            
            // Username
            HStack {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
            }
        } header: {
            Text("Basic Info")
        }
    }
    
    private var authenticationSection: some View {
        Section {
            Toggle("Use SSH Key", isOn: $useKeyAuth)
                .toggleStyle(.switch)
            
            if useKeyAuth {
                Picker("SSH Key", selection: $selectedKey) {
                    Text("Select a key...").tag("")
                    Text("id_ed25519").tag("id_ed25519")
                    Text("id_rsa").tag("id_rsa")
                }
            } else {
                HStack {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                }
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text("SSH keys are more secure than passwords. Generate one in the Keys tab.")
                .font(.caption)
        }
    }
    
    private var organizationSection: some View {
        Section {
            // Group
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                
                TextField("Group (optional)", text: $group)
            }
            
            // Color
            Picker("Color", selection: $color) {
                ForEach(colors, id: \.self) { color in
                    HStack {
                        Circle()
                            .fill(Color(color))
                            .frame(width: 12, height: 12)
                        Text(color.capitalized)
                    }
                    .tag(color)
                }
            }
        } header: {
            Text("Organization")
        }
    }
    
    private var testConnectionSection: some View {
        Section {
            Button {
                testConnection()
            } label: {
                HStack {
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Testing...")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Test Connection")
                    }
                    Spacer()
                }
            }
            .disabled(!isValid || isTesting)
        } footer: {
            Text("Test your connection before saving to ensure everything works.")
                .font(.caption)
        }
    }
    
    // MARK: - Actions
    
    private func testConnection() {
        isTesting = true
        
        // Create temporary host for testing
        let tempHost = Host.create(
            in: viewContext,
            name: name,
            hostname: hostname,
            port: Int16(port) ?? 22,
            username: username,
            password: useKeyAuth ? nil : password,
            keyFingerprint: useKeyAuth ? selectedKey : nil
        )
        
        SSHClient.shared.connect(to: tempHost) { result in
            isTesting = false
            
            switch result {
            case .success:
                showingSuccess = true
                SSHClient.shared.disconnect()
                viewContext.delete(tempHost)
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
                viewContext.delete(tempHost)
            }
        }
    }
    
    private func saveHost() {
        let host = Host.create(
            in: viewContext,
            name: name,
            hostname: hostname,
            port: Int16(port) ?? 22,
            username: username,
            password: useKeyAuth ? nil : password,
            keyFingerprint: useKeyAuth ? selectedKey : nil,
            group: group.isEmpty ? nil : group
        )
        host.color = color
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Preview

#Preview {
    AddHostView()
}

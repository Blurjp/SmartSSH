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
    @State private var availableKeys: [SavedSSHKey] = []
    
    @FocusState private var focusedField: Field?

    let hostToEdit: Host?
    
    enum Field: Hashable {
        case name, hostname, port, username, password
    }
    
    let colors = ["blue", "green", "orange", "purple", "red", "pink", "yellow", "gray"]

    init(hostToEdit: Host? = nil) {
        self.hostToEdit = hostToEdit
    }
    
    private var isValid: Bool {
        !name.isEmpty && !hostname.isEmpty && !username.isEmpty && validPort != nil && (!useKeyAuth || !selectedKey.isEmpty)
    }
    
    private var validPort: Int16? {
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else { return nil }
        return Int16(portInt)
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
            .navigationTitle(hostToEdit == nil ? "Add Host" : "Edit Host")
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
            .onAppear {
                loadKeys()
                populateFormIfNeeded()
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
                    .accessibilityIdentifier("addHost.name")
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
                    .accessibilityIdentifier("addHost.hostname")
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
                    set: { newValue in port = String(newValue) }
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
                    .accessibilityIdentifier("addHost.username")
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
                    ForEach(availableKeys) { key in
                        Text(key.name).tag(key.name)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("addHost.password")
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
                            .fill(Color.appNamed(color))
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

        let portValue = validPort ?? 22
        guard let tempHost = Host.createTransient(
            using: viewContext,
            name: name,
            hostname: hostname,
            port: portValue,
            username: username,
            password: useKeyAuth ? nil : password,
            keyFingerprint: useKeyAuth ? selectedKey : nil,
            useKeyAuth: useKeyAuth
        ) else {
            isTesting = false
            errorMessage = "Unable to prepare a temporary host for connection testing."
            showingError = true
            return
        }

        SSHClient.shared.connect(to: tempHost) { result in
            isTesting = false
            
            switch result {
            case .success:
                showingSuccess = true
                SSHClient.shared.disconnect()
                tempHost.deletePassword()
                  
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
                tempHost.deletePassword()
            }
        }
    }
    
    private func saveHost() {
        let portValue = validPort ?? 22
        
        let host: Host
        if let existingHost = hostToEdit {
            host = existingHost
            host.name = name
            host.hostname = hostname
            host.port = portValue
            host.username = username
            host.keyFingerprint = useKeyAuth ? selectedKey : nil
            host.group = group.isEmpty ? nil : group
            host.useKeyAuth = useKeyAuth
            host.updatedAt = Date()

            if useKeyAuth {
                host.password = nil
            } else {
                host.password = password.isEmpty ? nil : password
            }
        } else {
            host = Host.create(
                in: viewContext,
                name: name,
                hostname: hostname,
                port: portValue,
                username: username,
                password: useKeyAuth ? nil : password,
                keyFingerprint: useKeyAuth ? selectedKey : nil,
                group: group.isEmpty ? nil : group
            )
        }

        host.color = color
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadKeys() {
        availableKeys = SSHManager.shared.loadSavedKeys()
        if !availableKeys.contains(where: { $0.name == selectedKey }) {
            selectedKey = ""
        }
    }

    private func populateFormIfNeeded() {
        guard let hostToEdit, name.isEmpty, hostname.isEmpty, username.isEmpty else { return }

        name = hostToEdit.wrappedName
        hostname = hostToEdit.wrappedHostname
        port = String(hostToEdit.port)
        username = hostToEdit.wrappedUsername
        password = hostToEdit.useKeyAuth ? "" : (hostToEdit.password ?? "")
        group = hostToEdit.group ?? ""
        color = hostToEdit.color ?? "blue"
        useKeyAuth = hostToEdit.useKeyAuth
        selectedKey = hostToEdit.keyFingerprint ?? ""
    }
}

// MARK: - Preview

#Preview {
    AddHostView()
}

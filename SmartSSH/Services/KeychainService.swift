//
//  KeychainService.swift
//  SmartSSH
//
//  Secure password storage using iOS Keychain
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.smartssh.app"
    
    private init() {}
    
    // MARK: - Save Password
    
    func savePassword(_ password: String, for hostId: UUID) throws {
        try saveString(password, forAccount: "password_\(hostId.uuidString)")
    }
    
    // MARK: - Get Password
    
    func getPassword(for hostId: UUID) -> String? {
        getString(forAccount: "password_\(hostId.uuidString)")
    }
    
    // MARK: - Delete Password
    
    func deletePassword(for hostId: UUID) throws {
        try deleteValue(forAccount: "password_\(hostId.uuidString)")
    }
    
    // MARK: - Check if Password Exists
    
    func hasPassword(for hostId: UUID) -> Bool {
        return getPassword(for: hostId) != nil
    }

    // MARK: - Generic Storage

    func saveString(_ value: String, forAccount account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try saveData(data, forAccount: account)
    }

    func getString(forAccount account: String) -> String? {
        guard let data = getData(forAccount: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveData(_ data: Data, forAccount account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let addQuery: [String: Any] = baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw KeychainError.unableToSave(status: addStatus)
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)

        guard updateStatus == errSecSuccess else {
            throw KeychainError.unableToSave(status: updateStatus)
        }
    }

    func getData(forAccount account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    func deleteValue(forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status: status)
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unableToSave(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case notFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .unableToSave(let status):
            return "Unable to save password to Keychain (\(status))"
        case .unableToDelete(let status):
            return "Unable to delete password from Keychain (\(status))"
        case .notFound:
            return "Password not found in Keychain"
        case .invalidData:
            return "Unable to encode data for Keychain storage"
        }
    }
}

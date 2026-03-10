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
        let key = "password_\(hostId.uuidString)"
        
        // First, delete any existing password
        try? deletePassword(for: hostId)
        
        let data = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    // MARK: - Get Password
    
    func getPassword(for hostId: UUID) -> String? {
        let key = "password_\(hostId.uuidString)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    // MARK: - Delete Password
    
    func deletePassword(for hostId: UUID) throws {
        let key = "password_\(hostId.uuidString)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
    
    // MARK: - Check if Password Exists
    
    func hasPassword(for hostId: UUID) -> Bool {
        return getPassword(for: hostId) != nil
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unableToSave
    case unableToDelete
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .unableToSave:
            return "Unable to save password to Keychain"
        case .unableToDelete:
            return "Unable to delete password from Keychain"
        case .notFound:
            return "Password not found in Keychain"
        }
    }
}

import Foundation
import Security

public enum KeychainError: Error {
    case itemNotFound
    case duplicateItem
    case invalidData
    case unexpectedStatus(OSStatus)
}

public actor KeychainManager {
    public static let shared = KeychainManager()
    
    private let service = "com.openterm.ssh"
    
    public init() {}
    
    public func savePassword(_ password: String, forHost host: String, port: UInt16, username: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let account = "\(username)@\(host):\(port)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try updatePassword(password, forHost: host, port: port, username: username)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func getPassword(forHost host: String, port: UInt16, username: String) throws -> String? {
        let account = "\(username)@\(host):\(port)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return password
    }
    
    public func updatePassword(_ password: String, forHost host: String, port: UInt16, username: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let account = "\(username)@\(host):\(port)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func deletePassword(forHost host: String, port: UInt16, username: String) throws {
        let account = "\(username)@\(host):\(port)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func savePassphrase(_ passphrase: String, forPrivateKeyPath path: String) throws {
        guard let data = passphrase.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let account = "key:\(path)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try updatePassphrase(passphrase, forPrivateKeyPath: path)
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func getPassphrase(forPrivateKeyPath path: String) throws -> String? {
        let account = "key:\(path)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data, let passphrase = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return passphrase
    }
    
    public func updatePassphrase(_ passphrase: String, forPrivateKeyPath path: String) throws {
        guard let data = passphrase.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let account = "key:\(path)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func deletePassphrase(forPrivateKeyPath path: String) throws {
        let account = "key:\(path)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
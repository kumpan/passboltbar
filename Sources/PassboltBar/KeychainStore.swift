import Foundation
import LocalAuthentication
import Security

/// Stores the private-key passphrase and the TOTP secret in the login keychain. Reads are gated
/// by Touch ID / device password; one approval covers all reads for 5 minutes.
@MainActor
enum KeychainStore {
    enum Item: String { case passphrase, totp }

    private static let reuse: TimeInterval = 300
    private static var authenticatedAt: Date?

    private static func query(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "PassboltBar",
         kSecAttrAccount as String: item.rawValue]
    }

    static func has(_ item: Item) -> Bool {
        var q = query(item)
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func save(_ value: String, as item: Item) throws {
        delete(item)
        var q = query(item)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CLIError(message: "Keychain save failed (\(status)).")
        }
        authenticatedAt = Date() // the user just typed it
    }

    /// Returns nil if nothing is stored. Throws if authentication is cancelled or fails.
    static func read(_ item: Item) async throws -> String? {
        guard has(item) else { return nil }
        if authenticatedAt.map({ Date().timeIntervalSince($0) > reuse }) ?? true {
            try await LAContext().evaluatePolicy(.deviceOwnerAuthentication,
                                                 localizedReason: "unlock your Passbolt credentials")
            authenticatedAt = Date()
        }
        var q = query(item)
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, var data = result as? Data else {
            return nil
        }
        defer { data.resetBytes(in: 0..<data.count) }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ item: Item) {
        SecItemDelete(query(item) as CFDictionary)
    }
}

import Foundation

/// Turns what the user pastes into a base32 TOTP secret. Accepts a raw base32 key, an
/// otpauth:// link, or a Google Authenticator export link (otpauth-migration://offline?data=…).
enum TOTPSecret {
    static func parse(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed), let scheme = comps.scheme?.lowercased() else {
            return trimmed.replacingOccurrences(of: " ", with: "")
        }
        let query = { (name: String) in comps.queryItems?.first { $0.name.lowercased() == name }?.value }
        switch scheme {
        case "otpauth":
            return query("secret") ?? ""
        case "otpauth-migration":
            guard let data = query("data").flatMap(base64Decode) else {
                throw CLIError(message: "Couldn't read the Google Authenticator export link.")
            }
            return try passboltSecret(fromMigration: data)
        default:
            return trimmed
        }
    }

    /// Base32 (RFC 4648), at least 16 chars (80 bits) – rules out typed 6-digit codes.
    static func isValid(_ s: String) -> Bool {
        let t = s.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return t.count >= 16 && t.allSatisfy { alphabet.contains($0) }
    }

    // MARK: - Google Authenticator migration payload

    struct Account { var secret = Data(), name = "", issuer = "" }

    /// Picks the Passbolt account from the export (or the only account, if there is just one).
    static func passboltSecret(fromMigration data: Data) throws -> String {
        let accounts = try decodeMigration(data)
        let passbolt = accounts.filter { ($0.issuer + " " + $0.name).lowercased().contains("passbolt") }
        guard let account = passbolt.count == 1 ? passbolt.first : (accounts.count == 1 ? accounts.first : nil) else {
            let names = accounts.map { $0.issuer.isEmpty ? $0.name : "\($0.issuer): \($0.name)" }
            throw CLIError(message: "Found \(accounts.count) accounts in the export (\(names.joined(separator: ", "))). "
                + "Export only the Passbolt account and try again.")
        }
        return base32Encode(account.secret)
    }

    /// Minimal protobuf reader for MigrationPayload { repeated OtpParameters otp_parameters = 1; … }
    /// where OtpParameters { bytes secret = 1; string name = 2; string issuer = 3; … }.
    static func decodeMigration(_ data: Data) throws -> [Account] {
        try fields(of: data).compactMap { field, value in
            guard field == 1, case .bytes(let raw) = value else { return nil }
            var account = Account()
            for (f, v) in try fields(of: raw) {
                guard case .bytes(let b) = v else { continue }
                switch f {
                case 1: account.secret = b
                case 2: account.name = String(decoding: b, as: UTF8.self)
                case 3: account.issuer = String(decoding: b, as: UTF8.self)
                default: break
                }
            }
            return account
        }
    }

    private enum Value { case varint(UInt64), bytes(Data) }

    private static func fields(of data: Data) throws -> [(Int, Value)] {
        let bytes = [UInt8](data)
        var i = 0, out: [(Int, Value)] = []
        func varint() throws -> UInt64 {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < bytes.count {
                let b = bytes[i]; i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { break }
            }
            throw CLIError(message: "Malformed Google Authenticator export.")
        }
        while i < bytes.count {
            let key = try varint()
            switch key & 7 {
            case 0: out.append((Int(key >> 3), .varint(try varint())))
            case 2:
                let len = Int(try varint())
                guard len >= 0, i + len <= bytes.count else { throw CLIError(message: "Malformed Google Authenticator export.") }
                out.append((Int(key >> 3), .bytes(Data(bytes[i..<i + len]))))
                i += len
            default: throw CLIError(message: "Malformed Google Authenticator export.")
            }
        }
        return out
    }

    // MARK: - Encoding helpers

    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func base32Encode(_ data: Data) -> String {
        var out = "", buffer = 0, bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return out
    }

    private static func base64Decode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: " ", with: "+") // a '+' that got turned into a space
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }
}

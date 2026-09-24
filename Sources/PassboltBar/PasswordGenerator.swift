import Foundation
import Security

enum PasswordGenerator {
    static let classes = [
        "abcdefghijklmnopqrstuvwxyz",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "0123456789",
        "!@#$%^&*()-_=+[]{};:,.?/~",
    ].map(Array.init)

    /// Random password containing at least one character from every class.
    static func generate(length: Int = 20) -> String {
        let all = classes.flatMap { $0 }
        while true {
            let pw = (0..<length).map { _ in all[randomIndex(below: all.count)] }
            if classes.allSatisfy({ c in pw.contains(where: c.contains) }) { return String(pw) }
        }
    }

    /// Uniform index in 0..<n (n <= 256) using rejection sampling to avoid modulo bias.
    static func randomIndex(below n: Int) -> Int {
        let limit = 256 - 256 % n
        var byte: UInt8 = 0
        repeat {
            precondition(SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess)
        } while Int(byte) >= limit
        return Int(byte) % n
    }
}

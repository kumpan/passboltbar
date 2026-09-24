import Foundation

struct Resource: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var username: String?
    var uri: String?
}

struct Credentials {
    let passphrase: String
    var totpSecret: String?
}

struct CLIError: LocalizedError {
    enum Kind { case other, wrongPassphrase, totpMissing, totpRejected }
    let message: String
    var kind = Kind.other
    var errorDescription: String? { message }
}

/// Thin wrapper around go-passbolt-cli. The app never does crypto or API calls itself.
struct PassboltCLI {
    static let timeout: TimeInterval = 15
    static let candidates = ["/opt/homebrew/bin/passbolt", "/usr/local/bin/passbolt"]

    static var detectedPath: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    let path: String

    func list(creds: Credentials) async throws -> [Resource] {
        // Always name the columns: with -j and no -c the CLI also decrypts and prints every password.
        let data = try await run(["list", "resource", "-c", "id", "-c", "name", "-c", "username", "-c", "uri", "-j"],
                                 creds: creds)
        return try Self.decodeList(data)
    }

    func password(id: String, creds: Credentials) async throws -> String {
        var data = try await run(["get", "resource", "--id", id, "-j"], creds: creds)
        defer { data.resetBytes(in: 0..<data.count) }
        return try Self.decodePassword(data)
    }

    func create(name: String, username: String, password: String, uri: String, description: String,
                creds: Credentials) async throws -> String {
        var args = ["create", "resource", "--name", name, "-j"]
        if !username.isEmpty { args += ["--username", username] }
        if !uri.isEmpty { args += ["--uri", uri] }
        if !description.isEmpty { args += ["--description", description] }
        // The CLI has no stdin option for the new secret, so it is passed as an argument and is
        // visible in `ps` to this user for the second or two the process runs.
        if !password.isEmpty { args += ["--password", password] }
        let data = try await run(args, creds: creds)
        return try JSONDecoder().decode([String: String].self, from: data)["id"] ?? ""
    }

    static func decodeList(_ data: Data) throws -> [Resource] {
        try JSONDecoder().decode([Resource].self, from: data)
    }

    static func decodePassword(_ data: Data) throws -> String {
        struct Secret: Decodable { let password: String? }
        return try JSONDecoder().decode(Secret.self, from: data).password ?? ""
    }

    /// Runs the CLI off the main thread. Secrets go only into the child's environment (read by the
    /// CLI's viper AutomaticEnv: USERPASSWORD, MFATOTPTOKEN), never into argv.
    func run(_ args: [String], creds: Credentials) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw CLIError(message: "passbolt CLI not found at \(path). Install it with: brew install passbolt/tap/go-passbolt-cli")
        }
        let path = self.path
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                // Minimal env on purpose: viper maps any env var onto config keys (e.g. DEBUG would log).
                p.environment = Self.environment(creds)
                // Password/TOTP prompts read stdin; /dev/null makes them fail fast instead of hanging.
                p.standardInput = FileHandle.nullDevice
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { return cont.resume(throwing: error) }

                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: killer)
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                killer.cancel()

                if p.terminationReason == .uncaughtSignal {
                    return cont.resume(throwing: CLIError(message: "passbolt CLI timed out after \(Int(Self.timeout))s."))
                }
                if p.terminationStatus != 0 {
                    return cont.resume(throwing: Self.error(from: String(decoding: errData, as: UTF8.self)))
                }
                cont.resume(returning: outData)
            }
        }
    }

    static func environment(_ creds: Credentials) -> [String: String] {
        var env = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "USERPASSWORD": creds.passphrase]
        if let totp = creds.totpSecret {
            // One quick retry covers a code that expires mid-request without exceeding our 15 s timeout.
            env.merge(["MFAMODE": "noninteractive-totp", "MFATOTPTOKEN": totp,
                       "MFARETRYS": "1", "MFADELAY": "3s"]) { $1 }
        }
        return env
    }

    static func error(from stderr: String) -> CLIError {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.contains("error in unlocking key") {
            return CLIError(message: "Wrong passphrase – the CLI could not unlock your private key.", kind: .wrongPassphrase)
        }
        if lower.contains("reading totp") {
            return CLIError(message: "Your account requires TOTP. Enter your TOTP secret.", kind: .totpMissing)
        }
        if lower.contains("totp") || lower.contains("mfa") {
            return CLIError(message: "TOTP login failed – check the stored TOTP secret.\n\nCLI said: \(text)", kind: .totpRejected)
        }
        return CLIError(message: text.isEmpty ? "passbolt CLI failed with no output." : text)
    }
}

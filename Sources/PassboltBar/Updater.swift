import AppKit
import Security

/// Checks GitHub releases and replaces the running app with a newer one, after verifying the
/// download is signed by Kumpan's Developer ID and notarized.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release { let version: String; let zip: URL }

    nonisolated static let latestURL = URL(string: "https://api.github.com/repos/kumpan/passboltbar/releases/latest")!
    /// Only code signed by Kumpan's Developer ID with our bundle id may replace this app.
    nonisolated static let signingRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "NH4M8452G6" and identifier "se.kumpan.passboltbar""#

    @Published var available: Release?
    @Published var status: String?
    @Published var isWorking = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Checks on launch and then daily; silent unless an update is found.
    func startAutomaticChecks() {
        Task {
            while true {
                await check(silent: true)
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func check(silent: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        if !silent { status = "Checking…" }
        do {
            var request = URLRequest(url: Self.latestURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            struct GHRelease: Decodable {
                struct Asset: Decodable { let name: String; let browser_download_url: URL }
                let tag_name: String
                let assets: [Asset]
            }
            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard Self.isVersion(version, newerThan: currentVersion),
                  let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
                available = nil
                if !silent { status = "PassboltBar \(currentVersion) is up to date." }
                return
            }
            available = Release(version: version, zip: asset.browser_download_url)
            status = nil
        } catch {
            if !silent { status = "Couldn't check for updates: \(error.localizedDescription)" }
        }
    }

    func install() async {
        guard let release = available else { return }
        let current = Bundle.main.bundleURL
        guard !current.path.contains("/AppTranslocation/") else {
            status = "Move PassboltBar to your Applications folder first, then install the update."
            return
        }
        isWorking = true
        defer { isWorking = false }
        status = "Downloading \(release.version)…"
        do {
            let (zip, _) = try await URLSession.shared.download(from: release.zip)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PassboltBar-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
            let newApp = dir.appendingPathComponent("PassboltBar.app")

            status = "Verifying signature…"
            try Self.verifySignature(of: newApp)
            try await Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path]) // notarized?

            // Swap the bundle after we quit, then relaunch. Paths go in as arguments, not into the script.
            let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; rm -rf "$2" && mv "$3" "$2" && open "$2""#
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            swap.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), current.path, newApp.path]
            try swap.run()
            NSApp.terminate(nil)
        } catch {
            status = "Update failed: \(error.localizedDescription)"
        }
    }

    nonisolated static func verifySignature(of app: URL) throws {
        var code: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(signingRequirement as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else {
            throw CLIError(message: "The download isn't signed by Kumpan – update rejected.")
        }
    }

    /// Numeric, component-wise comparison ("1.0.10" > "1.0.9").
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func run(_ tool: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { p in
                p.terminationStatus == 0
                    ? cont.resume()
                    : cont.resume(throwing: CLIError(message: "\((tool as NSString).lastPathComponent) failed (\(p.terminationStatus))."))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

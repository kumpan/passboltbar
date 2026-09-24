import SwiftUI

@main
struct PassboltBarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("PassboltBar", systemImage: "key.fill") {
            RootView().environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.register { HotKey.toggleMenuBarExtra() }
    }
}

enum Settings {
    static let cliPathKey = "cliPath", clearSecondsKey = "clearSeconds"
    static var cliPath: String {
        let custom = UserDefaults.standard.string(forKey: cliPathKey) ?? ""
        return custom.isEmpty ? (PassboltCLI.detectedPath ?? PassboltCLI.candidates[0]) : custom
    }
    static var clearSeconds: Int {
        let v = UserDefaults.standard.integer(forKey: clearSecondsKey)
        return v > 0 ? v : 30
    }
}

@MainActor
final class AppState: ObservableObject {
    enum Mode { case search, add, settings }

    @Published var mode = Mode.search
    @Published var resources: [Resource] = []
    @Published var isBusy = false
    /// Which secret the user must enter before anything else works.
    @Published var prompt: KeychainStore.Item?
    @Published var error: String?
    @Published var toast: String?
    private var loadedAt: Date?

    private var cli: PassboltCLI { PassboltCLI(path: Settings.cliPath) }

    /// Loads the list if forced or the cache is older than 5 minutes.
    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        if let list = await withCredentials({ try await self.cli.list(creds: $0) }) {
            resources = list.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
            loadedAt = Date()
        }
    }

    func copyPassword(_ r: Resource) async {
        guard let pw = await withCredentials({ try await self.cli.password(id: r.id, creds: $0) }) else { return }
        let seconds = Settings.clearSeconds
        Clipboard.copy(pw, secret: true, clearAfter: seconds)
        flash("Copied – clears in \(seconds)s")
    }

    func copyUsername(_ r: Resource) {
        guard let u = r.username, !u.isEmpty else { return flash("No username") }
        Clipboard.copy(u, secret: false, clearAfter: 0)
        flash("Username copied")
    }

    func create(name: String, username: String, password: String, uri: String, description: String) async -> Bool {
        let id = await withCredentials {
            try await self.cli.create(name: name, username: username, password: password, uri: uri,
                                      description: description, creds: $0)
        }
        guard id != nil else { return false }
        flash("Created “\(name)”")
        mode = .search
        await refresh(force: true)
        return true
    }

    func save(_ value: String, as item: KeychainStore.Item) async {
        do {
            let v = item == .totp ? try TOTPSecret.parse(value) : value
            if item == .totp, !TOTPSecret.isValid(v) {
                error = v.allSatisfy(\.isNumber)
                    ? "That looks like a 6-digit code. PassboltBar needs the secret behind it – see the README section “MFA (TOTP)”."
                    : "That isn't a valid TOTP secret. Paste the Google Authenticator export link or the base32 key."
                return
            }
            try KeychainStore.save(v, as: item)
            prompt = nil
            error = nil
            await refresh(force: true)
        } catch { self.error = error.localizedDescription }
    }

    func forget(_ item: KeychainStore.Item) {
        KeychainStore.delete(item)
        if item == .passphrase { prompt = .passphrase }
        flash(item == .totp ? "TOTP secret removed" : "Passphrase removed")
    }

    /// Reads the credentials (Touch ID gated) and runs `body`, surfacing any error in the UI.
    private func withCredentials<T>(_ body: @escaping (Credentials) async throws -> T) async -> T? {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            guard let passphrase = try await KeychainStore.read(.passphrase) else {
                prompt = .passphrase
                return nil
            }
            return try await body(Credentials(passphrase: passphrase, totpSecret: try await KeychainStore.read(.totp)))
        } catch let e as CLIError {
            switch e.kind {
            case .wrongPassphrase: KeychainStore.delete(.passphrase); prompt = .passphrase
            case .totpMissing, .totpRejected: prompt = .totp
            case .other: break
            }
            // The TOTP prompt explains itself; other errors need the message.
            if e.kind != .totpMissing { error = e.message }
        } catch {
            self.error = error.localizedDescription
        }
        return nil
    }

    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }
}

/// MenuBarExtra draws its window with the old ~10 pt corners. Clip it to the larger, concentric
/// radius used by macOS 26+ menu bar panels (inner controls use radius = 26 - their 8 pt inset).
let panelCornerRadius: CGFloat = 26

@MainActor private func roundCorners(of window: NSWindow) {
    guard #available(macOS 26, *), let frame = window.contentView?.superview else { return }
    frame.wantsLayer = true
    frame.layer?.cornerRadius = panelCornerRadius
    frame.layer?.cornerCurve = .continuous
    frame.layer?.masksToBounds = true
    window.invalidateShadow()
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            switch state.mode {
            case .search: SearchView()
            case .add: AddView()
            case .settings: SettingsView()
            }
            StatusBar()
        }
        .frame(width: 400, height: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if let w = n.object as? NSWindow, w.className.contains("MenuBarExtraWindow") { roundCorners(of: w) }
            Task { await state.refresh() }
        }
    }
}


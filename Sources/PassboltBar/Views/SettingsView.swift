import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(Settings.cliPathKey) private var cliPath = ""
    @AppStorage(Settings.clearSecondsKey) private var clearSeconds = 30
    @State private var keychainVersion = 0 // bumps to re-read Keychain status after Forget

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings")
            Form {
                Section {
                    TextField("CLI path", text: $cliPath, prompt: Text(PassboltCLI.detectedPath ?? "not found"))
                    LabeledContent("Status") {
                        let ok = FileManager.default.isExecutableFile(atPath: Settings.cliPath)
                        Label(ok ? "Found" : "Not found", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ok ? .green : .red)
                    }
                } header: {
                    Text("Passbolt CLI")
                } footer: {
                    Text("Leave empty to auto-detect.").foregroundStyle(.secondary)
                }

                Section("Clipboard") {
                    Picker("Clear copied passwords after", selection: $clearSeconds) {
                        ForEach([10, 15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                }

                Section("Keychain") {
                    credentialRow("Passphrase", .passphrase)
                    credentialRow("TOTP secret", .totp)
                }
                .id(keychainVersion)

                Section {
                    LabeledContent("Open PassboltBar") { Text("⌃⌥P").monospaced() }
                    Button("Quit PassboltBar", role: .destructive) { NSApp.terminate(nil) }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func credentialRow(_ title: String, _ item: KeychainStore.Item) -> some View {
        LabeledContent(title) {
            if KeychainStore.has(item) {
                Button("Forget", role: .destructive) {
                    state.forget(item)
                    keychainVersion += 1
                }
            } else {
                Text("Not stored").foregroundStyle(.secondary)
            }
        }
    }
}

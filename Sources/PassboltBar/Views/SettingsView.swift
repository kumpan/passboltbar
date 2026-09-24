import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater
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
                    LabeledContent("Version", value: updater.currentVersion)
                    if let release = updater.available {
                        LabeledContent("Version \(release.version) is available") {
                            Button("Install and Relaunch") { Task { await updater.install() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(updater.isWorking)
                        }
                    } else {
                        LabeledContent("Updates") {
                            Button("Check for Updates") { Task { await updater.check() } }
                                .disabled(updater.isWorking)
                        }
                    }
                } header: {
                    Text("Updates")
                } footer: {
                    if let status = updater.status { Text(status).foregroundStyle(.secondary) }
                }

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

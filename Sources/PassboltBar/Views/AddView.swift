import SwiftUI

struct AddView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""
    @State private var uri = ""
    @State private var description = ""
    @State private var showPassword = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !state.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "New Password")
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Required"))
                    TextField("Username", text: $username, prompt: Text("Optional"))
                    LabeledContent("Password") {
                        HStack(spacing: 2) {
                            Group {
                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Optional")).monospaced()
                                } else {
                                    SecureField("", text: $password, prompt: Text("Optional"))
                                }
                            }
                            .multilineTextAlignment(.trailing)
                            IconButton(systemName: showPassword ? "eye.slash" : "eye", help: "Show password") {
                                showPassword.toggle()
                            }
                            IconButton(systemName: "wand.and.stars", help: "Generate 20-character password") {
                                password = PasswordGenerator.generate()
                                showPassword = true
                            }
                        }
                    }
                    TextField("URL", text: $uri, prompt: Text("https://"))
                }
                Section("Description") {
                    TextField("", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...5)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel") { state.mode = .search }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    if state.isBusy { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onDisappear { password = "" }
    }

    private func save() {
        Task {
            if await state.create(name: name.trimmingCharacters(in: .whitespaces), username: username,
                                  password: password, uri: uri, description: description) {
                password = ""
            }
        }
    }
}

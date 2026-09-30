import SwiftUI

/// New item, or edits `editing`. Editing sends only the fields that changed; an empty password keeps the old one.
struct AddView: View {
    @EnvironmentObject var state: AppState
    private let editing: Resource?
    private let original: (username: String, uris: [String], description: String)
    @State private var name: String
    @State private var username: String
    @State private var password = ""
    @State private var uri: String
    @State private var description: String
    @State private var showPassword = false

    init(editing: Resource? = nil, fields: [ResourceField] = []) {
        func values(_ label: String) -> [String] { fields.filter { !$0.custom && $0.label == label }.map(\.value) }
        let original = (username: values("Username").first ?? "", uris: values("URL"),
                        description: values("Description").first ?? "")
        self.editing = editing
        self.original = original
        _name = State(initialValue: editing?.name ?? "")
        _username = State(initialValue: original.username)
        _uri = State(initialValue: original.uris.first ?? "")
        _description = State(initialValue: original.description)
    }

    private var passwordPrompt: Text { Text(editing == nil ? "Optional" : "Unchanged") }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !state.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: editing == nil ? "New Password" : "Edit Password")
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Required"))
                    TextField("Username", text: $username, prompt: Text("Optional"))
                    LabeledContent("Password") {
                        HStack(spacing: 2) {
                            Group {
                                if showPassword {
                                    TextField("", text: $password, prompt: passwordPrompt).monospaced()
                                } else {
                                    SecureField("", text: $password, prompt: passwordPrompt)
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
        let name = name.trimmingCharacters(in: .whitespaces)
        Task {
            let saved: Bool
            if let editing {
                func changed<T: Equatable>(_ new: T, _ old: T) -> T? { new == old ? nil : new }
                // The form shows the first URL; any others are kept.
                let uris = (uri.isEmpty ? [] : [uri]) + original.uris.dropFirst()
                saved = await state.update(editing, name: changed(name, editing.name ?? ""),
                                           username: changed(username, original.username), password: password,
                                           uris: changed(uris, original.uris),
                                           description: changed(description, original.description))
            } else {
                saved = await state.create(name: name, username: username, password: password, uri: uri,
                                           description: description)
            }
            if saved { password = "" }
        }
    }
}

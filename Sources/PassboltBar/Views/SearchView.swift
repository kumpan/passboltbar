import SwiftUI

/// Substring match on name, username and URI, plus fuzzy (in-order letters) match on name.
/// Ranked: name prefix, name substring, username/URI substring, fuzzy name.
func filterResources(_ items: [Resource], query: String) -> [Resource] {
    let q = normalize(query.trimmingCharacters(in: .whitespaces))
    guard !q.isEmpty else { return items }
    func rank(_ r: Resource) -> Int? {
        let name = normalize(r.name ?? "")
        if name.hasPrefix(q) { return 0 }
        if name.contains(q) { return 1 }
        if [r.username, r.uri].contains(where: { normalize($0 ?? "").contains(q) }) { return 2 }
        if isSubsequence(q, of: name) { return 3 }
        return nil
    }
    let ranked = items.compactMap { r in rank(r).map { (r, $0) } }
    return (0...3).flatMap { level in ranked.filter { $0.1 == level }.map(\.0) }
}

private func normalize(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
    var it = needle.makeIterator()
    var next = it.next()
    for c in haystack where c == next { next = it.next() }
    return next == nil
}

struct SearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selection = 0
    @State private var monitor: Any?
    @FocusState private var searchFocused: Bool

    private var results: [Resource] { filterResources(state.resources, query: query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let item = state.prompt {
                SecretPrompt(item: item).id(item)
            } else if state.isBusy && state.resources.isEmpty {
                ProgressView("Loading passwords…").controlSize(.small).frame(maxHeight: .infinity)
            } else if results.isEmpty {
                Group {
                    if state.resources.isEmpty {
                        ContentUnavailableView("No Passwords", systemImage: "key.slash",
                                               description: Text("Nothing loaded yet. Try refreshing."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                resultList
            }
        }
        .onChange(of: query) { selection = 0 }
        .onAppear {
            searchFocused = state.prompt == nil
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKey)
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if state.prompt == nil { searchFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search passwords", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .disabled(state.prompt != nil)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassBackground(cornerRadius: 18)

            HStack(spacing: 0) {
                IconButton(systemName: "arrow.clockwise", help: "Refresh") { Task { await state.refresh(force: true) } }
                IconButton(systemName: "plus", help: "Add password") { state.mode = .add }
                IconButton(systemName: "gearshape", help: "Settings") { state.mode = .settings }
            }
            .padding(.horizontal, 4)
            .frame(height: 36)
            .glassBackground(cornerRadius: 18)
        }
        .padding(8)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, r in
                        ResourceRow(resource: r, selected: index == selection)
                            .id(index)
                            .onTapGesture { selection = index }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: selection) { proxy.scrollTo(selection) }
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if state.prompt != nil { return event }
        let list = results
        switch event.keyCode {
        case 125: selection = min(selection + 1, max(list.count - 1, 0))  // down
        case 126: selection = max(selection - 1, 0)                        // up
        case 36, 76:                                                        // return, enter
            guard list.indices.contains(selection) else { return nil }
            let r = list[selection]
            if event.modifierFlags.contains(.command) { state.copyUsername(r) }
            else { Task { await state.copyPassword(r) } }
        default: return event
        }
        return nil
    }
}

struct ResourceRow: View {
    @EnvironmentObject var state: AppState
    let resource: Resource
    let selected: Bool
    @State private var hovering = false

    private var subtitle: String {
        if let u = resource.username, !u.isEmpty { return u }
        if let uri = resource.uri, !uri.isEmpty { return URL(string: uri)?.host() ?? uri }
        return "—"
    }

    var body: some View {
        HStack(spacing: 10) {
            Monogram(name: resource.name ?? "?")
            VStack(alignment: .leading, spacing: 1) {
                Text(resource.name ?? "(no name)").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if selected || hovering {
                HStack(spacing: 0) {
                    IconButton(systemName: "person", help: "Copy username (⌘↩)") { state.copyUsername(resource) }
                    IconButton(systemName: "key", help: "Copy password (↩)") { Task { await state.copyPassword(resource) } }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct SecretPrompt: View {
    @EnvironmentObject var state: AppState
    let item: KeychainStore.Item
    @State private var value = ""
    @State private var scanning = false
    @State private var showPaste = false
    @FocusState private var focused: Bool

    private var showField: Bool { item == .passphrase || showPaste }

    var body: some View {
        Group {
            if scanning {
                QRScanView(onCode: { code in
                    scanning = false
                    Task { await state.save(code, as: .totp) }
                }, onCancel: { scanning = false })
            } else {
                form
            }
        }
        .padding(.horizontal, scanning ? 16 : 36)
        .frame(maxHeight: .infinity)
    }

    private var form: some View {
        VStack(spacing: 14) {
            Image(systemName: item == .passphrase ? "lock.shield" : "qrcode.viewfinder")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text(item == .passphrase ? "Unlock Passbolt" : "Two-factor authentication")
                    .font(.system(size: 15, weight: .semibold))
                Text(item == .passphrase
                     ? "Enter your private-key passphrase."
                     : "Your account uses an authenticator app. Scan its export QR code once so PassboltBar can sign in for you.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if item == .totp {
                Button { scanning = true } label: {
                    Label("Scan with Camera", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if !showPaste {
                    Button("Paste a setup key instead") { showPaste = true; focused = true }
                        .buttonStyle(.link).font(.system(size: 12))
                }
            }
            if showField {
                SecureField(item == .passphrase ? "Passphrase" : "Setup key or otpauth:// link", text: $value)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1))
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true } // whole box is clickable, not just the text line
                Button(action: save) { Text("Save to Keychain").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(item == .passphrase ? .accentColor : .secondary)
                    .controlSize(.large)
                    .disabled(value.isEmpty)
            }
            Label("Stored in your Keychain, protected by Touch ID", systemImage: "touchid")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { if showField { DispatchQueue.main.async { focused = true } } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if showField { DispatchQueue.main.async { focused = true } }
        }
    }

    private func save() {
        guard !value.isEmpty else { return }
        let v = value
        value = ""
        Task { await state.save(v, as: item) }
    }
}

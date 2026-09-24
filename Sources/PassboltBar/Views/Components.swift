import SwiftUI

/// Small borderless icon button with a hover highlight.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Header for sub-screens: back button + title.
struct ScreenHeader: View {
    @EnvironmentObject var state: AppState
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "chevron.left", help: "Back") { state.mode = .search }
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// Rounded-square monogram, coloured deterministically from the name.
struct Monogram: View {
    let name: String
    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .mint, .cyan]

    var body: some View {
        let color = Self.palette[name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % Self.palette.count]
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.gradient)
            .frame(width: 30, height: 30)
            .overlay(Text(name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white))
    }
}

extension View {
    /// Liquid Glass on macOS 26+, a subtle fill before that.
    @ViewBuilder func glassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Error banner + status line at the bottom of every screen.
struct StatusBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: Updater

    var body: some View {
        VStack(spacing: 0) {
            if let error = state.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11.5))
                        .textSelection(.enabled)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(systemName: "xmark", help: "Dismiss") { state.error = nil }
                        .frame(width: 20, height: 20)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider().opacity(0.5)
            HStack(spacing: 6) {
                if let toast = state.toast {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(toast)
                } else if state.isBusy {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                } else {
                    Text(state.resources.isEmpty ? "" : "\(state.resources.count) items")
                }
                Spacer()
                if let release = updater.available {
                    Button { state.mode = .settings } label: {
                        Label("Update \(release.version)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                } else {
                    Text("⌃⌥P").monospaced()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 28)
        }
        .animation(.snappy, value: state.error)
        .animation(.snappy, value: state.toast)
    }
}

import SwiftUI

/// All fields of one item, fetched on demand. ↑/↓ select, ↩ copies, ← or esc goes back.
struct DetailView: View {
    @EnvironmentObject var state: AppState
    let resource: Resource
    let fields: [ResourceField]
    let back: () -> Void
    @State private var selection = 0
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: resource.name ?? "(no name)", back: back)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { index, f in
                            FieldRow(field: f, selected: index == selection)
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
        .onAppear { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKey) }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: selection = min(selection + 1, max(fields.count - 1, 0))  // down
        case 126: selection = max(selection - 1, 0)                          // up
        case 36, 76: if fields.indices.contains(selection) { state.copy(fields[selection]) }  // return, enter
        case 123, 53: back()                                                  // left, esc
        default: return event
        }
        return nil
    }
}

struct FieldRow: View {
    @EnvironmentObject var state: AppState
    let field: ResourceField
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(field.label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(field.secret ? "••••••••" : field.value).font(.system(size: 13)).lineLimit(3)
            }
            Spacer(minLength: 4)
            if selected || hovering {
                IconButton(systemName: "doc.on.doc", help: "Copy (↩)") { state.copy(field) }
            }
        }
        .rowStyle(selected: selected, hovering: $hovering)
    }
}

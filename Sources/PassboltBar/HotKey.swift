import AppKit
import Carbon

enum HotKey {
    private static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    /// Registers Ctrl+Option+P globally.
    static func register(_ action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5042_4152), id: 1) // 'PBAR'
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    /// MenuBarExtra has no public API to open it. On macOS 27 its status button has no action, and
    /// presentation runs through private "expanded interface session" SPI (same trick as the
    /// MenuBarExtraAccess project). Guarded by responds(to:), so it degrades to a no-op if Apple changes it.
    static func toggleMenuBarExtra() {
        NSApp.activate(ignoringOtherApps: true)
        let statusItemSel = NSSelectorFromString("statusItem")
        let begin = NSSelectorFromString("_beginExpandedInterfaceSession:")
        let session = NSSelectorFromString("expandedInterfaceSession")
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") && window.responds(to: statusItemSel) {
            guard let item = window.perform(statusItemSel)?.takeUnretainedValue() as? NSStatusItem else { continue }
            if item.responds(to: begin), item.responds(to: session), let imp = item.method(for: begin) {
                if let active = item.perform(session)?.takeUnretainedValue() as? NSObject {
                    active.perform(NSSelectorFromString("cancel"))
                } else {
                    typealias Begin = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
                    unsafeBitCast(imp, to: Begin.self)(item, begin, .greatestFiniteMagnitude)
                }
            } else {
                item.button?.performClick(nil) // macOS 14–26
            }
            return
        }
    }
}

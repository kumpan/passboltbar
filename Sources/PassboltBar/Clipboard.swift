import AppKit

enum Clipboard {
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Secrets are marked concealed/transient (clipboard managers skip them) and cleared after
    /// `clearAfter` seconds, unless something else was copied in the meantime.
    static func copy(_ string: String, secret: Bool, clearAfter seconds: Int) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard secret else { pb.setString(string, forType: .string); return }
        pb.declareTypes([.string, concealed, transient], owner: nil)
        pb.setString(string, forType: .string)
        pb.setData(Data(), forType: concealed)
        pb.setData(Data(), forType: transient)
        let ours = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            if pb.changeCount == ours { pb.clearContents() }
        }
    }
}

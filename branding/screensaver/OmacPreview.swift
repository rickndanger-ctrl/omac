import AppKit

final class PreviewController: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 700)
        let size = NSSize(width: min(1100, screen.width - 80), height: min(700, screen.height - 100))
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "OMAC Screensaver Preview"
        window.isReleasedWhenClosed = false
        let scene = CommandLine.arguments.firstIndex(of: "--scene").flatMap { index in
            index + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[index + 1]) : nil
        }
        let initialPhase = Double(max(0, min(3, scene ?? 0))) * 8.0
        window.contentView = OmacRendererView(frame: NSRect(origin: .zero, size: size), initialPhase: initialPhase)
        window.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let text=event.charactersIgnoringModifiers,let scene=Int(text),(1...4).contains(scene) {
                (self?.window.contentView as? OmacRendererView)?.selectScene(scene-1);return nil
            }
            if event.keyCode == 53 { NSApp.terminate(nil); return nil }
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

@main
struct OmacPreviewMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

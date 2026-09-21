import AppKit

/// A manually launched, ordinary AppKit overlay. It is intentionally not a
/// ScreenSaverView and never changes idle, sleep, lock, or authentication state.
final class OmacIdleOverlayController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private weak var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        previousApp = NSWorkspace.shared.frontmostApplication
        let screens = NSScreen.screens
        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame)
            window.delegate = self
            window.contentView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                                      dismiss: { [weak self] in self?.dismissAll() })
            window.contentView?.layoutSubtreeIfNeeded()
            window.level = NSWindow.Level.normal
            window.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces,
                                         NSWindow.CollectionBehavior.fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismissAll()
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowWillClose(_ notification: Notification) { dismissAll() }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private func dismissAll() {
        guard !windows.isEmpty else { return }
        let current = windows
        windows.removeAll()
        current.forEach { $0.orderOut(nil) }
        NSApp.terminate(nil)
    }
}

final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
    }

    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayContentView: NSView {
    private let dismiss: () -> Void
    private let renderer: OmacRendererView
    private let button = NSButton(title: "Return to desktop", target: nil, action: nil)

    init(frame: NSRect, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
        renderer = OmacRendererView(frame: frame)
        super.init(frame: frame)
        wantsLayer = true
        renderer.wantsLayer = true
        renderer.layer?.zPosition = 0
        renderer.autoresizingMask = [.width, .height]
        addSubview(renderer)
        button.target = self
        button.action = #selector(returnToDesktop)
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.isBordered = true
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.frame = NSRect(x: 0, y: 0, width: 150, height: 34)
        button.autoresizingMask = [.minXMargin, .maxYMargin]
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.zPosition = 10
        addSubview(button, positioned: .above, relativeTo: renderer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        renderer.frame = bounds
        button.frame = NSRect(x: max(16, bounds.width - 182), y: 28, width: 150, height: 34)
    }

    @objc private func returnToDesktop() { dismiss() }

    override func mouseDown(with event: NSEvent) {
        dismiss()
    }
}

@main
struct OmacIdleOverlayMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = OmacIdleOverlayController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

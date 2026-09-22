import AppKit

/// A click-through desktop background host. It is deliberately separate from
/// ScreenSaverView and never changes idle, sleep, lock, or authentication state.
final class OmacWallpaperController: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sessionActive = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        installObservers()
        rebuildWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installObservers() {
        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append((appCenter, appCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false; self?.setAnimating(false)
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true; self?.setAnimating(true)
        }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.setAnimating(false) }))
        observers.append((workspaceCenter, workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.setAnimating(self.sessionActive)
        }))
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        for screen in NSScreen.screens {
            let window = OmacWallpaperWindow(contentRect: screen.frame)
            let renderer = OmacRendererView(frame: NSRect(origin: .zero, size: screen.frame.size))
            renderer.autoresizingMask = [.width, .height]
            window.contentView = renderer
            // One level above the desktop window, still below desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.ignoresMouseEvents = true
            window.orderBack(nil)
            windows.append(window)
        }
        setAnimating(sessionActive)
    }

    private func setAnimating(_ active: Bool) {
        windows.compactMap { $0.contentView as? OmacRendererView }.forEach {
            active ? $0.startAnimating() : $0.stopAnimating()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }
}

final class OmacWallpaperWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
    }

    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main
struct OmacWallpaperMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = OmacWallpaperController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

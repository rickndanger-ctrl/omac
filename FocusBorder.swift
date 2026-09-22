import AppKit
import ApplicationServices

struct FocusBorderGeometry {
    static func appKitFrame(axFrame: CGRect, primaryScreenTop: CGFloat, outset: CGFloat) -> CGRect {
        CGRect(x: axFrame.minX - outset,
               y: primaryScreenTop - axFrame.maxY - outset,
               width: axFrame.width + (outset * 2),
               height: axFrame.height + (outset * 2))
    }
}

private final class FocusBorderView: NSView {
    let accent = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.12, alpha: 1.0)
    private let edgeInset: CGFloat = 4

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        // The panel extends four points beyond the AX frame, so this centerline
        // lands exactly on the real window edge instead of hovering outside it.
        let rect = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        accent.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 4
        path.stroke()
        accent.withAlphaComponent(0.90).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Event-driven, click-through outline for the frontmost application's focused AX window.
/// It never requests Accessibility permission; callers can decide how to explain a missing grant.
final class FocusBorderController {
    private static let excludedBundleIdentifiers: Set<String> = [
        // Screen Sharing is an input tunnel, not part of the local tile world.
        // Outlining its parked offscreen viewer leaves a stray yellow rectangle
        // and can make the return to the local workspace feel like it is still
        // selected.
        "com.apple.ScreenSharing"
    ]
    private let stateDirectory: URL
    private let panel: NSPanel
    private let borderView = FocusBorderView(frame: .zero)
    private var workspaceTokens: [NSObjectProtocol] = []
    private var appObserver: AXObserver?
    private var windowObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private(set) var isEngaged = false
    private(set) var isEnabled = true

    init(stateDirectory: URL) {
        self.stateDirectory = stateDirectory
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        panel.contentView = borderView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            self?.observeFrontmostApplication()
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderOut(nil)
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            self?.observeFrontmostApplication()
        })
    }

    deinit {
        stopObserving()
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func setEngaged(_ engaged: Bool) {
        isEngaged = engaged
        if engaged && isEnabled { observeFrontmostApplication() }
        else { stopObserving(); panel.orderOut(nil) }
    }

    /// Suitable for an optional menu checkbox; the preference persists in Omac's state directory.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        let marker = stateDirectory.appendingPathComponent("focus-border.disabled")
        if enabled { try? FileManager.default.removeItem(at: marker) }
        else { FileManager.default.createFile(atPath: marker.path, contents: Data()) }
        setEngaged(isEngaged)
    }

    func loadEnabledPreference() {
        isEnabled = !FileManager.default.fileExists(atPath:
            stateDirectory.appendingPathComponent("focus-border.disabled").path)
    }

    private func stopObserving() {
        if let appObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(appObserver), .commonModes)
        }
        if let windowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
        }
        appObserver = nil
        windowObserver = nil
        observedPID = nil
        observedWindow = nil
    }

    private func observeFrontmostApplication() {
        followFocusedApplication(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    /// AeroSpace can focus a tile while macOS still calls another app frontmost.
    /// Prefer that exact tiled app so the outline follows Omac's keyboard focus.
    func followFocusedApplication(pid: pid_t?) {
        guard isEngaged, isEnabled, let pid,
              let app = NSRunningApplication(processIdentifier: pid),
              pid != ProcessInfo.processInfo.processIdentifier,
              !Self.excludedBundleIdentifiers.contains(app.bundleIdentifier ?? "") else {
            panel.orderOut(nil); return
        }
        if observedPID == pid, observedWindow != nil { observeFocusedWindow(); return }
        stopObserving()
        observedPID = pid
        let application = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusBorderAXCallback, &observer) == .success,
              let observer else { panel.orderOut(nil); return }
        appObserver = observer
        AXObserverAddNotification(observer, application, kAXFocusedWindowChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observeFocusedWindow(in: application)
    }

    fileprivate func observeFocusedWindow(in application: AXUIElement? = nil) {
        guard isEngaged, isEnabled else { panel.orderOut(nil); return }
        if let windowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
            self.windowObserver = nil
        }
        let appElement: AXUIElement
        if let application { appElement = application }
        else if let app = NSWorkspace.shared.frontmostApplication {
            appElement = AXUIElementCreateApplication(app.processIdentifier)
        } else { panel.orderOut(nil); return }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            panel.orderOut(nil); return
        }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        observedWindow = window

        if let pid = observedPID {
            var observer: AXObserver?
            if AXObserverCreate(pid, focusBorderAXCallback, &observer) == .success, let observer {
                windowObserver = observer
                for notification in [kAXMovedNotification, kAXResizedNotification,
                                     kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification] {
                    AXObserverAddNotification(observer, window, notification as CFString,
                                              Unmanaged.passUnretained(self).toOpaque())
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
        updateFrame()
    }

    fileprivate func handleAXNotification(_ notification: CFString) {
        if notification as String == kAXFocusedWindowChangedNotification {
            observeFocusedWindow()
        } else if notification as String == kAXUIElementDestroyedNotification ||
                    notification as String == kAXWindowMiniaturizedNotification {
            panel.orderOut(nil)
        } else {
            updateFrame()
        }
    }

    private func updateFrame() {
        guard let window = observedWindow,
              let frame = Self.frame(of: window),
              let primaryTop = NSScreen.screens.first?.frame.maxY else {
            panel.orderOut(nil); return
        }
        panel.setFrame(FocusBorderGeometry.appKitFrame(axFrame: frame, primaryScreenTop: primaryTop, outset: 4),
                       display: true)
        panel.orderFrontRegardless()
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let p = positionValue, let s = sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

}

private func focusBorderAXCallback(_ observer: AXObserver,
                                   _ element: AXUIElement,
                                   _ notification: CFString,
                                   _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let controller = Unmanaged<FocusBorderController>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { controller.handleAXNotification(notification) }
}

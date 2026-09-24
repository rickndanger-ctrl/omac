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

/// Which Accessibility notification reached the controller, stripped of AX types so the
/// response rules below can be read (and reasoned about) without a live observer.
enum FocusBorderEvent: Equatable {
    case focusedWindowChanged, mainWindowChanged, windowCreated
    case moved, resized, destroyed, miniaturized
    case other

    init(_ notification: String) {
        switch notification {
        case kAXFocusedWindowChangedNotification: self = .focusedWindowChanged
        case kAXMainWindowChangedNotification: self = .mainWindowChanged
        case kAXWindowCreatedNotification: self = .windowCreated
        case kAXMovedNotification: self = .moved
        case kAXResizedNotification: self = .resized
        case kAXUIElementDestroyedNotification: self = .destroyed
        case kAXWindowMiniaturizedNotification: self = .miniaturized
        default: self = .other
        }
    }
}

enum FocusBorderResponse: Equatable {
    /// A callback from an observer that has already been replaced. Rapid Command-W closes
    /// deliver the old window's "destroyed" after the new window is already outlined;
    /// acting on it hid the live outline. Stale callbacks are dropped, never acted on.
    case ignore
    /// Re-read the frontmost application's focused window and outline it.
    case resync
    /// The outlined window is gone or hidden: hide now, then re-read the focused window
    /// because the application may not announce its replacement focus.
    case hideThenResync
    case updateFrame
}

/// Pure response rules. `fromCurrentObserver` is false when the callback came from an
/// observer this controller has since torn down; `matchesObservedWindow` is false when a
/// window-level callback names a different element than the one currently outlined.
struct FocusBorderEventPolicy {
    static func response(to event: FocusBorderEvent,
                         fromCurrentObserver: Bool,
                         matchesObservedWindow: Bool) -> FocusBorderResponse {
        guard fromCurrentObserver else { return .ignore }
        switch event {
        case .focusedWindowChanged, .mainWindowChanged, .windowCreated:
            return .resync
        case .destroyed, .miniaturized:
            return matchesObservedWindow ? .hideThenResync : .ignore
        case .moved, .resized:
            return matchesObservedWindow ? .updateFrame : .ignore
        case .other:
            return .ignore
        }
    }

    /// Bounded retry schedule (seconds) used when the focused window cannot be read yet.
    /// During a burst of closes the application briefly reports no focused window, or the
    /// dying one; a handful of short retries covers that transition without polling.
    static let resyncDelays: [TimeInterval] = [0.05, 0.15, 0.4, 0.9]
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
    private let stateDirectory: URL
    private let panel: NSPanel
    private let borderView = FocusBorderView(frame: .zero)
    private var workspaceTokens: [NSObjectProtocol] = []
    private var appObserver: AXObserver?
    private var windowObserver: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedWindow: AXUIElement?
    private var pendingResyncs: [DispatchWorkItem] = []
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
            self?.cancelPendingResyncs()
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

    private func cancelPendingResyncs() {
        pendingResyncs.forEach { $0.cancel() }
        pendingResyncs.removeAll()
    }

    private func stopWindowObserver() {
        if let windowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
        }
        windowObserver = nil
        observedWindow = nil
    }

    private func stopObserving() {
        cancelPendingResyncs()
        stopWindowObserver()
        if let appObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(appObserver), .commonModes)
        }
        appObserver = nil
        observedApplication = nil
    }

    private func observeFrontmostApplication() {
        guard isEngaged, isEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            stopObserving(); panel.orderOut(nil); return
        }

        stopObserving()
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var observer: AXObserver?
        guard AXObserverCreate(app.processIdentifier, focusBorderAXCallback, &observer) == .success,
              let observer else { panel.orderOut(nil); return }
        appObserver = observer
        observedApplication = application
        // Focus changes are the primary signal. Main-window and window-created changes cover
        // applications that replace a closed window without announcing a new focused window.
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                             kAXWindowCreatedNotification] {
            AXObserverAddNotification(observer, application, notification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        resyncFocusedWindow()
    }

    /// Outline the application's current focused window. If the application is mid-transition
    /// (a window just closed and the next one is not yet focused), retry on a short bounded
    /// schedule instead of giving up until the next notification.
    private func resyncFocusedWindow(attempt: Int = 0) {
        cancelPendingResyncs()
        guard isEngaged, isEnabled else { panel.orderOut(nil); return }
        if outlineFocusedWindow() { return }
        panel.orderOut(nil)
        guard attempt < FocusBorderEventPolicy.resyncDelays.count, observedApplication != nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.resyncFocusedWindow(attempt: attempt + 1) }
        pendingResyncs.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusBorderEventPolicy.resyncDelays[attempt],
                                      execute: work)
    }

    /// Returns true when a live focused window with a usable frame is now outlined.
    private func outlineFocusedWindow() -> Bool {
        guard let appElement = observedApplication else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        guard let frame = Self.frame(of: window) else { return false }

        // Observe the window through its own process, not whichever app is frontmost now.
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return false }

        stopWindowObserver()
        observedWindow = window
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
        show(frame: frame)
        return true
    }

    fileprivate func handleAXNotification(_ notification: CFString,
                                          from observer: AXObserver,
                                          element: AXUIElement) {
        let fromCurrent = isCurrent(observer)
        let matches = observedWindow.map { CFEqual($0, element) } ?? false
        switch FocusBorderEventPolicy.response(to: FocusBorderEvent(notification as String),
                                               fromCurrentObserver: fromCurrent,
                                               matchesObservedWindow: matches) {
        case .ignore:
            return
        case .resync:
            resyncFocusedWindow()
        case .hideThenResync:
            stopWindowObserver()
            panel.orderOut(nil)
            resyncFocusedWindow()
        case .updateFrame:
            updateFrame()
        }
    }

    private func isCurrent(_ observer: AXObserver) -> Bool {
        if let appObserver, CFEqual(appObserver, observer) { return true }
        if let windowObserver, CFEqual(windowObserver, observer) { return true }
        return false
    }

    private func updateFrame() {
        guard let window = observedWindow, let frame = Self.frame(of: window) else {
            panel.orderOut(nil); return
        }
        show(frame: frame)
    }

    private func show(frame: CGRect) {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { panel.orderOut(nil); return }
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
    // Delivery is asynchronous, so by the time this runs the observer may have been replaced.
    // The controller checks that before acting; see FocusBorderEventPolicy.
    DispatchQueue.main.async { controller.handleAXNotification(notification, from: observer, element: element) }
}

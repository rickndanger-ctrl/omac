import Cocoa
import ScreenCaptureKit

// Isolated capture acceptance app. Not loaded by the daily Omac launcher.
@main
struct PreviewLabMain {
    static func main() {
        let app = NSApplication.shared
        let delegate: NSObject & NSApplicationDelegate = CommandLine.arguments.contains("--test-pattern") ? PreviewPatternDelegate() : PreviewLabDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class PreviewLabDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let message = NSTextField(wrappingLabelWithString: "Live previews need Screen Recording permission. Nothing is captured until you choose a window and press Preview.")
    private let chooser = NSPopUpButton()
    private var targets: [SCWindow] = []
    private var tile: OmacPreviewTileController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 560,height: 250), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.title = "Omac Tile Lab — isolated preview test"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24,left: 24,bottom: 24,right: 24)
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(NSButton(title: "Allow Screen Recording…", target: self, action: #selector(permission)))
        stack.addArrangedSubview(NSButton(title: "Load available windows", target: self, action: #selector(loadWindows)))
        stack.addArrangedSubview(chooser)
        stack.addArrangedSubview(NSButton(title: "Preview selected window", target: self, action: #selector(preview)))
        window.contentView = stack
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func permission() {
        _ = CGRequestScreenCaptureAccess()
        message.stringValue = "Grant access to Omac Tile Lab in macOS Settings, then load available windows. macOS may require reopening this test app."
    }
    @objc private func loadWindows() {
        guard CGPreflightScreenCaptureAccess() else {
            message.stringValue = "Screen Recording is not authorized. No capture started."
            return
        }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly: false)
                targets = content.windows.filter { $0.owningApplication?.processID != getpid() && $0.windowLayer == 0 && !($0.title ?? "").isEmpty }
                chooser.removeAllItems()
                chooser.addItems(withTitles: targets.map { ($0.owningApplication?.applicationName ?? "App") + " — " + ($0.title ?? "Window") })
                message.stringValue = "Choose one window. Its image stays local; audio is disabled."
            } catch { message.stringValue = "Could not list windows. Check Screen Recording access and reopen this test app." }
        }
    }
    @objc private func preview() {
        guard CGPreflightScreenCaptureAccess(), targets.indices.contains(chooser.indexOfSelectedItem) else { return }
        let target = targets[chooser.indexOfSelectedItem]
        tile?.stop()
        let controller = OmacPreviewTileController(targetWindowID: target.windowID, onActivate: {
            if let pid = target.owningApplication?.processID { NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
        }, onFailure: { [weak self] _ in
            DispatchQueue.main.async { self?.message.stringValue = "Preview stopped or the source window is unavailable." }
        })
        tile = controller
        Task { @MainActor in
            do { try await controller.start(); message.stringValue = "Preview active. Close the preview to stop capture." }
            catch { message.stringValue = "Preview did not start. No window layout was changed." }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { tile?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Deterministic capture source: contains no user content and changes once/second.
final class PreviewPatternDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect:NSRect(x:100,y:100,width:640,height:400),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title = "Omac Capture Test Pattern"
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString:"Frame 0")
        label.font = .monospacedSystemFont(ofSize:44,weight:.bold)
        label.alignment = .center
        label.frame = NSRect(x:20,y:150,width:600,height:70)
        label.autoresizingMask = [.width,.minYMargin,.maxYMargin]
        let content = NSView(frame:NSRect(x:0,y:0,width:640,height:400))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemPurple.cgColor
        content.addSubview(label);window.contentView = content
        var count = 0
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { _ in
            count += 1; label.stringValue = "Frame \(count)"
            content.layer?.backgroundColor = (count%2 == 0 ? NSColor.systemPurple : NSColor.systemTeal).cgColor
        }
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {timer?.invalidate()}
}

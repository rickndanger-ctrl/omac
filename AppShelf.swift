import Cocoa
import ApplicationServices

/// A retained, user-selected app window. The shelf never launches or closes apps.
public final class AppShelf {
    public struct Entry {
        public let windowID: CGWindowID
        public let appPID: pid_t
        public let bundleIdentifier: String?
        public let appName: String
        public let windowTitle: String
        public let icon: NSImage?
        public let initialFrame: CGRect
        public let initialWorkspace: String
    }

    public enum ShelfError: Error {
        case unavailable(String)
        case stale
        case unsupportedWindow
        case notShelved
        case geometry
    }

    private final class Record {
        let entry: Entry
        let appKey: String
        let element: AXUIElement
        let initialLayout: String
        var full = false
        init(_ entry: Entry, initialLayout: String, appKey: String, element: AXUIElement) { self.entry = entry; self.initialLayout = initialLayout; self.appKey = appKey; self.element = element }
    }

    private var records: [CGWindowID: Record] = [:]
    private var appRecords: [String: CGWindowID] = [:]
    public var entries: [Entry] { records.values.map(\.entry).sorted { $0.windowID < $1.windowID } }

    @discardableResult
    public func addFocusedWindow() throws -> Entry {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["list-windows", "--focused", "--format", "%{window-id} %{app-pid} %{app-name} %{window-title} %{workspace} %{window-layout}", "--json"])
        guard result.0 == 0, let rows = (try? JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [[String: Any]]),
              let row = rows.first,
              let id = row["window-id"] as? Int, let pid = row["app-pid"] as? Int,
              let name = row["app-name"] as? String, let title = row["window-title"] as? String,
              let workspace = row["workspace"] as? String, let layout = row["window-layout"] as? String else {
        throw ShelfError.unavailable("Focused window inventory is unavailable")
    }
    guard let app = NSRunningApplication(processIdentifier: pid_t(pid)),
          app.bundleIdentifier != "com.mitchellh.ghostty" else { throw ShelfError.unsupportedWindow }
    let appKey = app.bundleIdentifier ?? "pid:\(pid)"
    if let existing = appRecords[appKey], let record = records[existing] { return record.entry }
    let target = try resolve(id: CGWindowID(id), pid: pid_t(pid))
    try validateStandardWindow(target.element)
    let entry = Entry(windowID: CGWindowID(id), appPID: pid_t(pid), bundleIdentifier: app.bundleIdentifier, appName: name,
                      windowTitle: title, icon: app.icon, initialFrame: target.frame,
                      initialWorkspace: workspace)
    do {
        try setLayout(entry.windowID, "floating")
        let frame = centeredFrame(in: target.visibleFrame, full: false, minimum: minimumSize(of: target.element))
        try setFrame(target.element, frame)
        try verify(id: entry.windowID, pid: entry.appPID, expected: frame)
    } catch {
        try? setFrame(target.element, target.frame)
        try? setLayout(entry.windowID, layout)
        throw error
    }
    records[entry.windowID] = Record(entry, initialLayout: layout, appKey: appKey, element: target.element)
    appRecords[appKey] = entry.windowID
    return entry
    }

    public func tuckAll() throws {
        var failures: [Error] = []
        for record in records.values {
            do {
                guard AXUIElementSetAttributeValue(record.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else { throw ShelfError.geometry }
            } catch { failures.append(error) }
        }
        if let failure = failures.first { throw ShelfError.unavailable("Could not tuck shelf window: \(failure)") }
    }

    public func summon(windowID: CGWindowID, onWorkspace workspace: String) throws {
        guard let record = records[windowID] else { throw ShelfError.notShelved }
        try setMinimized(record.element, false)
        let target = try resolve(record.entry)
        try moveToWorkspace(windowID, workspace)
        try setLayout(windowID, "floating")
        let visible = NSScreen.main?.visibleFrame ?? target.visibleFrame
        let frame = centeredFrame(in: visible, full: record.full, minimum: minimumSize(of: target.element))
        try setFrame(target.element, frame)
        try verify(id: record.entry.windowID, pid: record.entry.appPID, expected: frame)
        try focus(windowID)
    }

    public func toggleCenteredFull(windowID: CGWindowID) throws {
        guard let record = records[windowID] else { throw ShelfError.notShelved }
        try setMinimized(record.element, false)
        let target = try resolve(record.entry)
        record.full.toggle()
        let frame = centeredFrame(in: target.visibleFrame, full: record.full, minimum: minimumSize(of: target.element))
        do {
            try setFrame(target.element, frame)
            try verify(id: record.entry.windowID, pid: record.entry.appPID, expected: frame)
        } catch {
            record.full.toggle()
            throw error
        }
    }

    public func releaseAll() throws {
        var failures: [Error] = []
        for record in records.values {
            do {
                try setMinimized(record.element, false)
                let target = try resolve(record.entry)
                try moveToWorkspace(record.entry.windowID, record.entry.initialWorkspace)
                try setFrame(target.element, record.entry.initialFrame)
                try verify(id: record.entry.windowID, pid: record.entry.appPID, expected: record.entry.initialFrame)
                try setLayout(record.entry.windowID, record.initialLayout)
            } catch { failures.append(error) }
        }
        if let failure = failures.first { throw ShelfError.unavailable("Could not release shelf window: \(failure)") }
        records.removeAll(); appRecords.removeAll()
    }

    private func resolve(_ entry: Entry) throws -> NativeWindowTarget { try resolve(id: entry.windowID, pid: entry.appPID) }
    private func resolve(id: CGWindowID, pid: pid_t) throws -> NativeWindowTarget {
        do { return try NativeWindowTarget.resolve(id: id, pid: pid) }
        catch { throw ShelfError.stale }
    }
    private func validateStandardWindow(_ element: AXUIElement) throws {
        var role: CFTypeRef?, subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              (role as? String) == kAXWindowRole,
              AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
              let value = subrole as? String,
              value == kAXStandardWindowSubrole else { throw ShelfError.unsupportedWindow }
    }
    private func setMinimized(_ element: AXUIElement, _ value: Bool) throws {
        guard AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value ? kCFBooleanTrue : kCFBooleanFalse) == .success else { throw ShelfError.geometry }
    }
    private func minimumSize(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXMinSize" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else { return nil }
        return size.width > 0 && size.height > 0 ? size : nil
    }
    private func setFrame(_ element: AXUIElement, _ frame: CGRect) throws {
        var point = frame.origin, size = frame.size
        guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, p) == .success,
              AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, s) == .success else { throw ShelfError.geometry }
    }
    private func centeredFrame(in visible: CGRect, full: Bool, minimum: CGSize? = nil) -> CGRect {
        let margin: CGFloat = 8
        let area = visible.insetBy(dx: margin, dy: margin)
        let fraction: CGFloat = full ? 1 : 0.70
        let base = CGSize(width: area.width * fraction, height: area.height * fraction)
        let size = CGSize(width: min(area.width, max(base.width, minimum?.width ?? 0)),
                          height: min(area.height, max(base.height, minimum?.height ?? 0)))
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }
    private func verify(id: CGWindowID, pid: pid_t, expected: CGRect) throws {
        let actual = try resolve(id: id, pid: pid).frame
        guard abs(actual.minX - expected.minX) < 2, abs(actual.minY - expected.minY) < 2,
              abs(actual.width - expected.width) < 2, abs(actual.height - expected.height) < 2 else { throw ShelfError.geometry }
    }
    private func setLayout(_ id: CGWindowID, _ layout: String) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["layout", "--window-id", String(id), layout])
        guard result.0 == 0 else { throw ShelfError.unavailable(result.1) }
    }
    private func moveToWorkspace(_ id: CGWindowID, _ workspace: String) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["move-node-to-workspace", "--window-id", String(id), workspace])
        guard result.0 == 0 else { throw ShelfError.unavailable(result.1) }
    }
    private func focus(_ id: CGWindowID) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["focus", "--window-id", String(id)])
        guard result.0 == 0 else { throw ShelfError.unavailable(result.1) }
    }
}

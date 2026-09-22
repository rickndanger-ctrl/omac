import Cocoa
import ApplicationServices

/// A retained, user-selected app window. The shelf never launches or closes apps.
public final class AppShelf {
    public struct Entry {
        public let windowID: CGWindowID
        public let appPID: pid_t
        public let launchDate: Date
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
        let launchDate: Date
        let initialLayout: String
        var full = false
        init(_ entry: Entry, initialLayout: String, appKey: String, element: AXUIElement) { self.entry = entry; self.initialLayout = initialLayout; self.appKey = appKey; self.element = element; self.launchDate = entry.launchDate }
    }

    private var records: [CGWindowID: Record] = [:]
    private var appRecords: [String: CGWindowID] = [:]
    private let checkpointURL: URL?
    public var entries: [Entry] { pruneStaleRecords(); return records.values.map(\.entry).sorted { $0.windowID < $1.windowID } }

    public init(checkpointURL: URL? = nil) {
        self.checkpointURL = checkpointURL
        loadCheckpoint()
    }

    @discardableResult
    public func addFocusedWindow() throws -> Entry {
        pruneStaleRecords()
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["list-windows", "--focused", "--format", "%{window-id} %{app-pid} %{app-name} %{window-title} %{workspace} %{window-layout}", "--json"])
        guard result.0 == 0, let rows = (try? JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [[String: Any]]),
              let row = rows.first,
              let id = row["window-id"] as? Int, let pid = row["app-pid"] as? Int,
              let name = row["app-name"] as? String, let title = row["window-title"] as? String,
              let workspace = row["workspace"] as? String, let layout = row["window-layout"] as? String else {
        throw ShelfError.unavailable("Focused window inventory is unavailable")
    }
    guard let app = NSRunningApplication(processIdentifier: pid_t(pid)), !isTerminal(app) else { throw ShelfError.unsupportedWindow }
    let appKey = app.bundleIdentifier ?? "pid:\(pid)"
    if let existing = appRecords[appKey], let record = records[existing] {
        guard sameProcess(record.launchDate, app) else { throw ShelfError.stale }
        return record.entry
    }
    let target = try resolve(id: CGWindowID(id), pid: pid_t(pid))
    try validateStandardWindow(target.element)
    guard let launchDate = processLaunchDate(app) else { throw ShelfError.stale }
    let entry = Entry(windowID: CGWindowID(id), appPID: pid_t(pid), launchDate: launchDate, bundleIdentifier: app.bundleIdentifier, appName: name,
                      windowTitle: title, icon: app.icon, initialFrame: target.frame,
                      initialWorkspace: workspace)
    do {
        try setLayout(entry.windowID, "floating")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

    } catch {
        try? setFrame(target.element, target.frame)
        try? setLayout(entry.windowID, layout)
        throw error
    }
    records[entry.windowID] = Record(entry, initialLayout: layout, appKey: appKey, element: target.element)
    appRecords[appKey] = entry.windowID
    saveCheckpoint()
    return entry
    }

    public func tuckAll() throws {
        pruneStaleRecords()
        var failures: [Error] = []
        for record in records.values {
            let prepared = process(python ?? "/missing/python3", [root + "/control.py", "prepare-mixed-tuck", "--window-id", String(record.entry.windowID), "--app-pid", String(record.entry.appPID)])
            if prepared.0 != 0 { failures.append(ShelfError.unavailable(prepared.1)) }
        }
        if let failure = failures.first { throw ShelfError.unavailable("Could not prepare shelf windows: \(failure)") }
        for record in records.values {
            do {
                try validateRecord(record)
                guard AXUIElementSetAttributeValue(record.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else { throw ShelfError.geometry }
            } catch { failures.append(error) }
        }
        if let failure = failures.first { throw ShelfError.unavailable("Could not tuck shelf window: \(failure)") }
        saveCheckpoint()
    }

    public func summon(windowID: CGWindowID, onWorkspace workspace: String) throws {
        guard let record = records[windowID] else { throw ShelfError.notShelved }
        try validateRecord(record)
        try setMinimized(record.element, false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        do {
            try moveToWorkspace(windowID, workspace)
            try verifyWorkspace(windowID, workspace)
            try setLayout(windowID, "floating")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
            try focus(windowID)
            saveCheckpoint()
        } catch {
            var rollbackErrors: [String] = []
            do { try moveToWorkspace(windowID, record.entry.initialWorkspace) } catch { rollbackErrors.append("workspace: \(error)") }
            do {
                let target = try resolve(record.entry)
                try setFrame(target.element, record.entry.initialFrame)
                try setLayout(windowID, record.initialLayout)
            } catch { rollbackErrors.append("frame/layout: \(error)") }
            let suffix = rollbackErrors.isEmpty ? "" : " Rollback errors: \(rollbackErrors.joined(separator: "; "))"
            throw ShelfError.unavailable("Could not summon shelf window: \(error).\(suffix)")
        }
    }

    public func toggleCenteredFull(windowID: CGWindowID) throws {
        guard let record = records[windowID] else { throw ShelfError.notShelved }
        try validateRecord(record)
        try setMinimized(record.element, false)
        let target = try resolve(record.entry)
        record.full.toggle()
        let frame = centeredFrame(in: target.visibleFrame, full: record.full, minimum: minimumSize(of: target.element))
        do {
            try setFrame(target.element, frame)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
            try setPosition(target.element, frame.origin)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
            try verify(id: record.entry.windowID, pid: record.entry.appPID, expected: frame)
        } catch {
            record.full.toggle()
            saveCheckpoint()
            throw error
        }
    }

    public func releaseAll() throws {
        pruneStaleRecords()
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
        saveCheckpoint()
    }

    private struct Checkpoint: Codable {
        let windowID: CGWindowID; let appPID: pid_t; let launchDate: Date
        let bundleIdentifier: String?; let appName: String; let windowTitle: String
        let frame: [Double]; let workspace: String; let layout: String; let full: Bool
    }
    private func isTerminal(_ app: NSRunningApplication) -> Bool {
        ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "com.github.wez.wezterm", "org.alacritty"].contains(app.bundleIdentifier ?? "")
    }
    private func processLaunchDate(_ app:NSRunningApplication)->Date? {
        var info=proc_bsdinfo()
        let count=proc_pidinfo(app.processIdentifier,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size))
        guard count==MemoryLayout<proc_bsdinfo>.size else{return nil}
        return Date(timeIntervalSince1970:Double(info.pbi_start_tvsec)+Double(info.pbi_start_tvusec)/1_000_000)
    }
    private func sameProcess(_ date: Date, _ app: NSRunningApplication) -> Bool {
        guard let launch = processLaunchDate(app) else { return false }
        return abs(launch.timeIntervalSince(date)) < 0.01
    }
    private func validateRecord(_ record:Record) throws {
        guard let app=NSRunningApplication(processIdentifier:record.entry.appPID),sameProcess(record.launchDate,app) else {throw ShelfError.stale}
        let element=try resolveAXElement(id:record.entry.windowID,pid:record.entry.appPID)
        var minimized:CFTypeRef?
        _=AXUIElementCopyAttributeValue(element,kAXMinimizedAttribute as CFString,&minimized)
        if (minimized as? Bool) != true {try validateStandardWindow(element)}
    }
    private func pruneStaleRecords() {
        var changed = false
        for (id, record) in records {
            guard let app = NSRunningApplication(processIdentifier: record.entry.appPID) else {
                records.removeValue(forKey: id); appRecords.removeValue(forKey: record.appKey); changed = true; continue
            }
            var missing=false
            do {_ = try resolveAXElement(id:id,pid:record.entry.appPID)} catch ShelfError.stale {missing=true} catch {}
            if !sameProcess(record.launchDate, app) || missing {
                records.removeValue(forKey: id); appRecords.removeValue(forKey: record.appKey); changed = true
            }
        }
        if changed { saveCheckpoint() }
    }
    private func loadCheckpoint() {
        guard let checkpointURL, let data = try? Data(contentsOf: checkpointURL),
              let saved = try? JSONDecoder().decode([Checkpoint].self, from: data) else { return }
        for item in saved {
            guard item.frame.count == 4,
                  let app = NSRunningApplication(processIdentifier: item.appPID), sameProcess(item.launchDate, app), !isTerminal(app),
                  let element = try? resolveAXElement(id: item.windowID, pid: item.appPID) else { continue }
            var minimized:CFTypeRef?
            _=AXUIElementCopyAttributeValue(element,kAXMinimizedAttribute as CFString,&minimized)
            if (minimized as? Bool) != true {do {try validateStandardWindow(element)} catch {continue}}
            let entry = Entry(windowID: item.windowID, appPID: item.appPID, launchDate: item.launchDate,
                              bundleIdentifier: item.bundleIdentifier, appName: item.appName,
                              windowTitle: item.windowTitle, icon: app.icon,
                              initialFrame: CGRect(x: item.frame[0], y: item.frame[1], width: item.frame[2], height: item.frame[3]),
                              initialWorkspace: item.workspace)
            let key = app.bundleIdentifier ?? "pid:\(item.appPID)"
            let record = Record(entry, initialLayout: item.layout, appKey: key, element: element)
            record.full = item.full; records[item.windowID] = record; appRecords[key] = item.windowID
        }
    }
    private func saveCheckpoint() {
        guard let checkpointURL else { return }
        let saved = records.values.map { record in
            Checkpoint(windowID: record.entry.windowID, appPID: record.entry.appPID, launchDate: record.launchDate,
                       bundleIdentifier: record.entry.bundleIdentifier, appName: record.entry.appName,
                       windowTitle: record.entry.windowTitle,
                       frame: [record.entry.initialFrame.minX, record.entry.initialFrame.minY, record.entry.initialFrame.width, record.entry.initialFrame.height],
                       workspace: record.entry.initialWorkspace, layout: record.initialLayout, full: record.full)
        }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        do {
            try FileManager.default.createDirectory(at: checkpointURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temp = checkpointURL.appendingPathExtension("tmp")
            try data.write(to: temp, options: .atomic); _ = try FileManager.default.replaceItemAt(checkpointURL, withItemAt: temp)
        } catch {
            try? data.write(to: checkpointURL, options: .atomic)
        }
    }
    private func resolve(_ entry: Entry) throws -> NativeWindowTarget {
        guard let app = NSRunningApplication(processIdentifier: entry.appPID), sameProcess(entry.launchDate, app) else { throw ShelfError.stale }
        let target = try resolve(id: entry.windowID, pid: entry.appPID)
        try validateStandardWindow(target.element)
        return target
    }
    private func resolveAXElement(id: CGWindowID, pid: pid_t) throws -> AXUIElement {
        guard AXIsProcessTrusted(), let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { throw ShelfError.unavailable("Accessibility window identity is unavailable") }
        let getID = unsafeBitCast(symbol, to: AXWindowIDFunction.self)
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw ShelfError.unavailable("App window inventory is temporarily unavailable") }
        let matches = windows.filter { window in
            var candidate: CGWindowID = 0
            return getID(window, &candidate) == .success && candidate == id
        }
        guard matches.count == 1 else { throw ShelfError.stale }
        return matches[0]
    }
    private func resolve(id: CGWindowID, pid: pid_t) throws -> NativeWindowTarget {
        do { return try NativeWindowTarget.resolve(id: id, pid: pid) }
        catch NativeTargetError.permission { throw ShelfError.unavailable("Accessibility permission is unavailable") }
        catch NativeTargetError.unavailable { throw ShelfError.unavailable("Window identity API is unavailable") }
        catch NativeTargetError.ambiguous { throw ShelfError.unavailable("Window identity is ambiguous") }
        catch NativeTargetError.geometry { throw ShelfError.unavailable("Window geometry is unavailable") }
        catch NativeTargetError.missing { throw ShelfError.stale }
        catch { throw ShelfError.unavailable("Window resolution failed") }
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
    private func setPosition(_ element: AXUIElement, _ origin: CGPoint) throws {
        var point=origin
        guard let value=AXValueCreate(.cgPoint,&point), AXUIElementSetAttributeValue(element,kAXPositionAttribute as CFString,value) == .success else {throw ShelfError.geometry}
    }
    private func setFrame(_ element: AXUIElement, _ frame: CGRect) throws {
        var size=frame.size
        guard let value=AXValueCreate(.cgSize,&size), AXUIElementSetAttributeValue(element,kAXSizeAttribute as CFString,value) == .success else {throw ShelfError.geometry}
        RunLoop.current.run(until:Date(timeIntervalSinceNow:0.4))
        try setPosition(element,frame.origin)
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
        let deadline=Date(timeIntervalSinceNow:1.5)
        var actual=CGRect.zero
        repeat {
            actual = try resolve(id:id,pid:pid).frame
            if abs(actual.minX-expected.minX)<2 && abs(actual.minY-expected.minY)<2 && abs(actual.width-expected.width)<2 && abs(actual.height-expected.height)<2 {return}
            let target = try resolve(id:id,pid:pid)
            try setFrame(target.element, expected)
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.15))
        } while Date()<deadline
        throw ShelfError.unavailable("Requested frame \(expected), received \(actual)")
    }

    private func setLayout(_ id: CGWindowID, _ layout: String) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["layout", "--window-id", String(id), layout])
        guard result.0 == 0 else { throw ShelfError.unavailable(result.1) }
    }
    private func moveToWorkspace(_ id: CGWindowID, _ workspace: String) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let deadline=Date(timeIntervalSinceNow:2)
        var result:(Int32,String)=(1, "Window restore timed out")
        repeat {
            result=process(aerospace,["move-node-to-workspace","--window-id",String(id),workspace])
            if result.0 == 0 {return}
            guard result.1.contains("doesn't belong to any monitor") else {throw ShelfError.unavailable(result.1)}
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
        } while Date()<deadline
        throw ShelfError.unavailable(result.1)
    }
    private func focus(_ id: CGWindowID) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["focus", "--window-id", String(id)])
        guard result.0 == 0 else { throw ShelfError.unavailable(result.1) }
    }
    private func verifyWorkspace(_ id: CGWindowID, _ workspace: String) throws {
        guard let aerospace else { throw ShelfError.unavailable("AeroSpace is unavailable") }
        let result = process(aerospace, ["list-windows", "--all", "--format", "%{window-id} %{workspace}", "--json"])
        let rows = (try? JSONSerialization.jsonObject(with: Data(result.1.utf8))) as? [[String: Any]]
        let actual = rows?.first { ($0["window-id"] as? Int).map(CGWindowID.init) == id }?["workspace"] as? String
        guard result.0 == 0, actual == workspace else {
            throw ShelfError.unavailable("Window did not reach requested workspace")
        }
    }
}

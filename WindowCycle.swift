import AppKit
import ApplicationServices

enum WindowCycleDirection { case next, previous }

struct WindowCycleCandidate: Equatable {
    let windowID: CGWindowID
    let appPID: pid_t
    let workspace: String
    let layout: String

    static func decode(_ row: [String: Any]) -> WindowCycleCandidate? {
        guard let rawID = row["window-id"] as? Int,
              let rawPID = row["app-pid"] as? Int,
              let workspace = row["workspace"] as? String,
              let layout = row["window-layout"] as? String,
              rawID > 0, let pid = pid_t(exactly: rawPID) else { return nil }
        return WindowCycleCandidate(windowID: CGWindowID(rawID), appPID: pid,
                                    workspace: workspace, layout: layout)
    }
}

struct WindowCycleSelector {
    static let excludedLayouts = Set(["macos_native_window_of_hidden_app", "macos_fullscreen"])

    static func eligible(_ rows: [[String: Any]], workspace: String,
                         helperPID: pid_t) -> [WindowCycleCandidate] {
        rows.compactMap(WindowCycleCandidate.decode).filter {
            $0.workspace == workspace && $0.appPID != helperPID &&
            !excludedLayouts.contains($0.layout)
        }
    }

    static func choose(_ candidates: [WindowCycleCandidate], focusedID: CGWindowID?,
                       direction: WindowCycleDirection) -> WindowCycleCandidate? {
        guard !candidates.isEmpty else { return nil }
        guard let focusedID, let index = candidates.firstIndex(where: { $0.windowID == focusedID }) else {
            return direction == .next ? candidates.first : candidates.last
        }
        let delta = direction == .next ? 1 : -1
        return candidates[(index + delta + candidates.count) % candidates.count]
    }
}

private typealias CycleAXWindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowCycleError: Error {
    case unavailable(String)
    case stale
}

/// Explicit, event-free current-page cycling. Call only from a user-invoked hotkey action.
final class CurrentPageWindowCycler {
    typealias ProcessResult = (status: Int32, output: String)
    typealias Runner = (_ executable: String, _ arguments: [String]) -> ProcessResult

    private let aerospace: String
    private let helperPID: pid_t
    private let run: Runner

    static func inventoryArguments(workspace: String) -> [String] {
        ["list-windows", "--workspace", workspace, "--format",
         "%{window-id} %{app-pid} %{workspace} %{window-layout}", "--json"]
    }

    init(aerospace: String, helperPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         runner: @escaping Runner = CurrentPageWindowCycler.runProcess) {
        self.aerospace = aerospace
        self.helperPID = helperPID
        self.run = runner
    }

    func cycle(_ direction: WindowCycleDirection) throws {
        let page = run(aerospace, ["list-workspaces", "--focused"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["1", "2", "3", "4", "5"].contains(page) else {
            throw WindowCycleError.unavailable("The focused workspace is not an Omac page")
        }

        let inventory = run(aerospace, Self.inventoryArguments(workspace: page))
        guard inventory.status == 0,
              let data = inventory.output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WindowCycleError.unavailable("Current-page window inventory is unavailable")
        }
        let candidates = WindowCycleSelector.eligible(rows, workspace: page, helperPID: helperPID).filter {
            (try? exactStandardAXWindow(id: $0.windowID, pid: $0.appPID)) != nil
        }
        let focusResult = run(aerospace, ["list-windows", "--focused", "--format", "%{window-id}"])
        let focusedID = CGWindowID(focusResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let chosen = WindowCycleSelector.choose(candidates, focusedID: focusedID,
                                                       direction: direction) else {
            throw WindowCycleError.unavailable("This page has no eligible application windows")
        }

        // Re-read before mutation so a closed or moved window cannot become an accidental target.
        let fresh = run(aerospace, Self.inventoryArguments(workspace: page))
        guard fresh.status == 0,
              let freshData = fresh.output.data(using: .utf8),
              let freshRows = try? JSONSerialization.jsonObject(with: freshData) as? [[String: Any]],
              WindowCycleSelector.eligible(freshRows, workspace: page, helperPID: helperPID)
                .contains(chosen) else { throw WindowCycleError.stale }

        let window = try exactStandardAXWindow(id: chosen.windowID, pid: chosen.appPID)
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                               kCFBooleanFalse) == .success else {
                throw WindowCycleError.unavailable("The selected window could not be restored")
            }
        }

        let application = AXUIElementCreateApplication(chosen.appPID)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: chosen.appPID)?.activate(options: [])
        // End with the exact current-page AeroSpace identity so app activation cannot
        // leave keyboard focus on another window owned by the same application.
        let focus = run(aerospace, ["focus", "--window-id", String(chosen.windowID)])
        guard focus.status == 0 else {
            throw WindowCycleError.unavailable("AeroSpace could not focus the selected window")
        }
    }

    private func exactStandardAXWindow(id: CGWindowID, pid: pid_t) throws -> AXUIElement {
        guard AXIsProcessTrusted(),
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            throw WindowCycleError.unavailable("Accessibility window identity is unavailable")
        }
        let getID = unsafeBitCast(symbol, to: CycleAXWindowIDFunction.self)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw WindowCycleError.stale }
        let matches = windows.filter { element in
            var candidate: CGWindowID = 0
            return getID(element, &candidate) == .success && candidate == id
        }
        guard matches.count == 1 else { throw WindowCycleError.stale }
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(matches[0], kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXWindowRole,
              AXUIElementCopyAttributeValue(matches[0], kAXSubroleAttribute as CFString, &subrole) == .success,
              subrole as? String == kAXStandardWindowSubrole else {
            throw WindowCycleError.unavailable("The target is not a standard application window")
        }
        return matches[0]
    }

    static func runProcess(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch { return (1, String(describing: error)) }
        task.waitUntilExit()
        return (task.terminationStatus,
                String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }
}

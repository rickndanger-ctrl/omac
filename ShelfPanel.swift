import Cocoa

struct ShelfChoice {
    let windowID: CGWindowID
    let appName: String
    let windowTitle: String
    let icon: NSImage?
}

// A nonactivating palette keeps the destination workspace and app focus stable.
final class ShelfPanel: NSPanel {
    private var choices: [ShelfChoice] = []
    private var selected = 0
    private var rows: [NSButton] = []
    var onChoose: ((CGWindowID) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0,y: 0,width: 440,height: 200), styleMask: [.titled,.nonactivatingPanel], backing: .buffered, defer: false)
        title = "Omac Apps"
        level = .floating
        collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        isReleasedWhenClosed = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9)
    }
    func present(_ entries: [ShelfChoice]) {
        choices = entries; selected = 0; rows = []
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16,left: 16,bottom: 16,right: 16)
        stack.addArrangedSubview(NSTextField(labelWithString: "Arrow keys to choose · Return to open · Escape to dismiss"))
        if entries.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No apps tucked away yet.")) }
        for (index,entry) in entries.enumerated() {
            let button = NSButton(title: entry.appName, target: self, action: #selector(chooseRow(_:)))
            button.tag = index; button.image = entry.icon?.copy() as? NSImage
            button.image?.size = NSSize(width: 24,height: 24)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.setAccessibilityLabel(button.title)
            stack.addArrangedSubview(button); rows.append(button)
        }
        contentView = stack
        setContentSize(NSSize(width: 480,height: max(100, 60 + entries.count * 38)))
        center(); makeKeyAndOrderFront(nil); highlight()
    }
    private func highlight() {
        for (index,row) in rows.enumerated() { row.state = index == selected ? .on : .off }
        if rows.indices.contains(selected) { makeFirstResponder(rows[selected]) }
    }
    @objc private func chooseRow(_ sender: NSButton) { selected = sender.tag; choose() }
    private func choose() {
        guard choices.indices.contains(selected) else { return }
        let id = choices[selected].windowID; orderOut(nil); onChoose?(id)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: orderOut(nil)
        case 36,76: choose()
        case 123,126: if !choices.isEmpty {selected = (selected + choices.count - 1) % choices.count; highlight()}
        case 124,125,48: if !choices.isEmpty {selected = (selected + 1) % choices.count; highlight()}
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

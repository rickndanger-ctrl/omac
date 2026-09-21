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
        super.init(contentRect: NSRect(x: 0,y: 0,width: 440,height: 200), styleMask: [.titled,.fullSizeContentView,.nonactivatingPanel], backing: .buffered, defer: false)
        title = "Omac Apps"
        level = .floating
        collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        isReleasedWhenClosed = false
        titleVisibility = .hidden; titlebarAppearsTransparent = true
        isOpaque = false; hasShadow = true
        appearance = NSAppearance(named:.darkAqua)
        backgroundColor = NSColor(calibratedRed:21/255,green:26/255,blue:33/255,alpha:0.85)
    }
    func present(_ entries: [ShelfChoice]) {
        choices = entries; selected = 0; rows = []
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16,left: 16,bottom: 16,right: 16)
        let titleLabel=NSTextField(labelWithString:"Omac Apps")
        titleLabel.font = .systemFont(ofSize:18,weight:.semibold)
        titleLabel.textColor = NSColor(white:0.93,alpha:1)
        stack.addArrangedSubview(titleLabel)
        let hint=NSTextField(labelWithString:"Arrows to choose  ·  Return to open  ·  Esc to dismiss")
        hint.font = .systemFont(ofSize:11);hint.textColor = NSColor(white:0.7,alpha:1)
        stack.addArrangedSubview(hint)
        if entries.isEmpty { stack.addArrangedSubview(NSTextField(labelWithString: "No apps tucked away yet.")) }
        for (index,entry) in entries.enumerated() {
            let button = NSButton(title: entry.appName, target: self, action: #selector(chooseRow(_:)))
            button.tag = index; button.image = entry.icon?.copy() as? NSImage
            button.image?.size = NSSize(width: 24,height: 24)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded;button.isBordered=false
            button.alignment = .left;button.font = .systemFont(ofSize:14,weight:.medium)
            button.contentTintColor=NSColor(white:0.93,alpha:1)
            button.focusRingType = .none;button.wantsLayer=true;button.layer?.cornerRadius=7
            button.widthAnchor.constraint(equalToConstant:448).isActive=true
            button.heightAnchor.constraint(equalToConstant:36).isActive=true
            button.setAccessibilityLabel(button.title)
            stack.addArrangedSubview(button); rows.append(button)
        }
        contentView = stack
        setContentSize(NSSize(width: 480,height: max(130, 86 + entries.count * 44)))
        center(); makeKeyAndOrderFront(nil); highlight()
    }
    private func highlight() {
        for (index,row) in rows.enumerated() {
            row.state = index == selected ? .on : .off
            row.layer?.backgroundColor=NSColor(white:1,alpha:index == selected ? 0.12:0).cgColor
        }
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

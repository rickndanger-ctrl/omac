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

// Scan only application roots, never bundle internals or user documents.
func omacInstalledApplications() -> [(name:String,bundleID:String,url:URL)] {
 var found:[String:(name:String,bundleID:String,url:URL)]=[:]
 let roots=["/Applications",NSHomeDirectory()+"/Applications","/System/Applications","/System/Library/CoreServices/Applications"]
 for root in roots {
  guard let walker=FileManager.default.enumerator(at:URL(fileURLWithPath:root),includingPropertiesForKeys:nil,options:[.skipsHiddenFiles,.skipsPackageDescendants]) else {continue}
  for case let url as URL in walker where url.pathExtension.lowercased()=="app" {
   walker.skipDescendants()
   guard let bundle=Bundle(url:url),let id=bundle.bundleIdentifier,found[id]==nil,
    id != "com.richard.agentcontrolcenter",
    (bundle.object(forInfoDictionaryKey:"LSUIElement") as? NSNumber)?.boolValue != true,
    (bundle.object(forInfoDictionaryKey:"LSBackgroundOnly") as? NSNumber)?.boolValue != true else {continue}
   let name=(bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey:"CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
   found[id]=(name,id,url)
  }
 }
 if let finder=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.finder") {found["com.apple.finder"]=("Finder","com.apple.finder",finder)}
 return found.values.sorted {$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
}

// A themed replacement for NSMenu popups. It deliberately consumes NSMenu as its
// model so callers keep their existing targets, actions, icons, state, and enabled
// rules instead of maintaining a second menu representation.
struct OmacMenuSearchResult {
    let item: NSMenuItem
    let label: String
}

struct OmacMenuSearch {
    static func results(in menu: NSMenu, query: String) -> [OmacMenuSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var found: [OmacMenuSearchResult] = []
        collect(menu: menu, ancestors: [], query: needle, into: &found)
        return found
    }

    private static func collect(menu: NSMenu, ancestors: [String], query: String,
                                into found: inout [OmacMenuSearchResult]) {
        for item in menu.items where !item.isHidden && !item.isSeparatorItem {
            // A disabled parent makes its entire branch unavailable in NSMenu as well.
            guard item.isEnabled else { continue }
            let path = ancestors + [item.title]
            if let submenu = item.submenu {
                collect(menu: submenu, ancestors: path, query: query, into: &found)
            } else if item.action != nil {
                let searchable = path.joined(separator: " ")
                if searchable.localizedCaseInsensitiveContains(query) {
                    let context = ancestors.isEmpty ? "" : "  —  " + ancestors.joined(separator: " › ")
                    found.append(OmacMenuSearchResult(item: item, label: item.title + context))
                }
            }
        }
    }
}

final class OmacMenuPanel: NSPanel, NSSearchFieldDelegate {
    private struct Level {
        let menu: NSMenu
        let title: String
    }

    private let panelWidth: CGFloat = 310
    private let rowHeight: CGFloat = 34
    private let chromeHeight: CGFloat = 82
    private var levels: [Level] = []
    private var visibleItems: [NSMenuItem] = []
    private var selectableRows: [Int] = []
    private var rowButtons: [Int: NSButton] = [:]
    private var rowLabels: [String] = []
    private var selectedPosition = 0
    private var didNotifyClose = false
    private var query = ""
    private var presentationAnchor: NSRect?
    private let searchField = NSSearchField()
    private var resultsStack: NSStackView?
    private weak var resultsScroll: NSScrollView?

    /// Called once whenever a presented panel is dismissed or an action is chosen.
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        appearance = NSAppearance(named: .darkAqua)
    }

    func present(menu: NSMenu, anchor: NSRect? = nil) {
        levels = [Level(menu: menu, title: menu.title)]
        didNotifyClose = false
        query = ""
        presentationAnchor = anchor
        rebuild(anchor: anchor)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        notifyClose()
    }

    private func rebuild(anchor: NSRect? = nil) {
        guard let current = levels.last else { return }
        updateVisibleItems(current: current)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(
            calibratedRed: 21.0 / 255.0,
            green: 26.0 / 255.0,
            blue: 33.0 / 255.0,
            alpha: 0.85
        ).cgColor
        root.layer?.cornerRadius = 11
        root.layer?.masksToBounds = true

        let header = makeHeader(title: current.title)
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 7, right: 7)
        resultsStack = stack
        populateRows(in: stack)

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: panelWidth)
        ])

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = document
        resultsScroll = scroll
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: chromeHeight),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        contentView = root
        resizeForResults(stack: stack, scroll: scroll, anchor: anchor ?? presentationAnchor)
    }

    private func updateVisibleItems(current: Level) {
        let searchResults = query.isEmpty ? [] : OmacMenuSearch.results(in: levels[0].menu, query: query)
        if query.isEmpty {
            visibleItems = current.menu.items.filter { !$0.isHidden }
            rowLabels = visibleItems.map(\.title)
        } else {
            visibleItems = searchResults.map(\.item)
            rowLabels = searchResults.map(\.label)
        }
        selectableRows = visibleItems.indices.filter {
            let item = visibleItems[$0]
            return !item.isSeparatorItem && item.isEnabled && (query.isEmpty ? (item.submenu != nil || item.action != nil) : item.action != nil)
        }
        selectedPosition = selectableRows.isEmpty ? 0 : min(selectedPosition, selectableRows.count - 1)
    }

    private func populateRows(in stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowButtons.removeAll()

        for (index, item) in visibleItems.enumerated() {
            if item.isSeparatorItem {
                let separator = NSBox()
                separator.boxType = .separator
                separator.alphaValue = 0.35
                separator.heightAnchor.constraint(equalToConstant: 7).isActive = true
                stack.addArrangedSubview(separator)
                continue
            }

            let button = makeRow(for: item, title: rowLabels[index], index: index)
            stack.addArrangedSubview(button)
            rowButtons[index] = button
        }

        if visibleItems.isEmpty {
            let empty = NSTextField(labelWithString: "No menu items")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = NSColor(white: 0.68, alpha: 1)
            empty.alignment = .center
            empty.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            stack.addArrangedSubview(empty)
        }
    }

    private func resizeForResults(stack: NSStackView, scroll: NSScrollView, anchor: NSRect?) {
        stack.layoutSubtreeIfNeeded()
        let desiredRowsHeight = stack.fittingSize.height
        let screen = screenFor(anchor: anchor)
        let maximumHeight = min(640, max(150, screen.visibleFrame.height - 32))
        let height = min(maximumHeight, chromeHeight + desiredRowsHeight)
        setContentSize(NSSize(width: panelWidth, height: height))
        position(on: screen, anchor: anchor ?? presentationAnchor)
        highlightSelected(scrollView: scroll)
    }

    private func refreshSearchResults() {
        guard let current = levels.last, let stack = resultsStack, let scroll = resultsScroll else { return }
        updateVisibleItems(current: current)
        populateRows(in: stack)
        resizeForResults(stack: stack, scroll: scroll, anchor: presentationAnchor)
    }

    private func makeHeader(title: String) -> NSView {
        let view = NSView()
        let label = NSTextField(labelWithString: title.isEmpty ? "Omac" : title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = NSColor(white: 0.94, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search apps and controls"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        if searchField.stringValue != query { searchField.stringValue = query }
        searchField.focusRingType = .none
        view.addSubview(searchField)

        if levels.count > 1 {
            let back = NSButton(title: "‹", target: self, action: #selector(goBack))
            back.translatesAutoresizingMaskIntoConstraints = false
            back.isBordered = false
            back.font = .systemFont(ofSize: 25, weight: .regular)
            back.contentTintColor = NSColor(white: 0.92, alpha: 1)
            back.focusRingType = .none
            back.setAccessibilityLabel("Back")
            view.addSubview(back)
            NSLayoutConstraint.activate([
                back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9),
                back.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                back.widthAnchor.constraint(equalToConstant: 28),
                label.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 3)
            ])
        } else {
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15).isActive = true
        }

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 9),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
            searchField.heightAnchor.constraint(equalToConstant: 25)
        ])
        return view
    }

    private func makeRow(for item: NSMenuItem, title: String, index: Int) -> NSButton {
        let stateMark: String
        switch item.state {
        case .on: stateMark = "✓  "
        case .mixed: stateMark = "–  "
        default: stateMark = "    "
        }
        let submenuMark = item.submenu == nil ? "" : "   ›"
        let button = NSButton(title: stateMark + title + submenuMark, target: self, action: #selector(chooseRow(_:)))
        button.tag = index
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        button.widthAnchor.constraint(equalToConstant: panelWidth - 14).isActive = true
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.alignment = .left
        button.font = item.title == "" ? .systemFont(ofSize: 13) : .systemFont(ofSize: 13.5, weight: .medium)
        button.contentTintColor = item.isEnabled ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.55, alpha: 1)
        button.isEnabled = item.isEnabled
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.imagePosition = .imageLeading
        if let image = item.image?.copy() as? NSImage {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }
        button.setAccessibilityLabel(item.title)
        return button
    }

    private func screenFor(anchor: NSRect?) -> NSScreen {
        if let anchor,
           let matching = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) {
            return matching
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func position(on screen: NSScreen, anchor: NSRect?) {
        guard let anchor else {
            center()
            return
        }
        let visible = screen.visibleFrame
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - frame.height - 6)
        if origin.y < visible.minY { origin.y = anchor.maxY + 6 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }

    private func highlightSelected(scrollView: NSScrollView? = nil) {
        for (index, button) in rowButtons {
            let highlighted = selectableRows.indices.contains(selectedPosition) && selectableRows[selectedPosition] == index
            button.layer?.backgroundColor = NSColor(white: 1, alpha: highlighted ? 0.11 : 0).cgColor
        }
        guard selectableRows.indices.contains(selectedPosition),
              let button = rowButtons[selectableRows[selectedPosition]] else { return }
        button.scrollToVisible(button.bounds)
        scrollView?.reflectScrolledClipView(scrollView!.contentView)
    }

    @objc private func chooseRow(_ sender: NSButton) {
        guard let position = selectableRows.firstIndex(of: sender.tag) else { return }
        selectedPosition = position
        activateSelection()
    }

    private func activateSelection() {
        guard selectableRows.indices.contains(selectedPosition) else { return }
        let item = visibleItems[selectableRows[selectedPosition]]
        if let submenu = item.submenu {
            levels.append(Level(menu: submenu, title: item.title))
            selectedPosition = 0
            query = ""
            rebuild(anchor: presentationAnchor)
            makeFirstResponder(searchField)
            return
        }
        guard let action = item.action else { return }
        let target = item.target
        dismiss()
        NSApp.sendAction(action, to: target, from: item)
    }

    @objc private func goBack() {
        guard levels.count > 1 else { return }
        levels.removeLast()
        selectedPosition = 0
        query = ""
        rebuild(anchor: presentationAnchor)
        makeFirstResponder(searchField)
    }

    private func moveSelection(by offset: Int) {
        guard !selectableRows.isEmpty else { return }
        selectedPosition = (selectedPosition + offset + selectableRows.count) % selectableRows.count
        highlightSelected()
    }

    private func notifyClose() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        onClose?()
    }

    func controlTextDidChange(_ notification: Notification) {
        query = searchField.stringValue
        selectedPosition = 0
        refreshSearchResults()
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1); return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1); return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(); return true
        default:
            return false
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: dismiss()
        case 36, 76: activateSelection()
        case 123, 51: if query.isEmpty { goBack() } else { super.keyDown(with: event) }
        case 124:
            guard selectableRows.indices.contains(selectedPosition) else { return }
            let item = visibleItems[selectableRows[selectedPosition]]
            if item.submenu != nil { activateSelection() }
        case 125, 48: moveSelection(by: 1)
        case 126: moveSelection(by: -1)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}

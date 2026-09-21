import AppKit

/// Shared renderer for the Omac screensaver and its standalone preview.
/// The artwork is original: a compact OMAC wordmark with terminal-like drift.
final class OmacRendererView: NSView {
    private var timer: Timer?
    private var phase: Double = 0
    private var lastTick = Date()
    private let reduceMotion: Bool
    private let glyphs = Array("0123456789abcdef[]{}<>/\\|+=*#")
    private var stream: [String] = []

    private let logo = [
        "  ████       ███      ██████    ██████ ",
        " ██████    ███████   ████████  ████████",
        "██    ██  █████████  ██    ██  ██    ██",
        "██    ██  ██ ███ ██  ██    ██  ██     █",
        "██    ██  ██ ███ ██  ██    ██  ██      ",
        "██    ██  ██ ███ ██  ████████  ██      ",
        "██    ██  ██ ███ ██  ████████  ██     █",
        "██    ██  ██ ███ ██  ██    ██  ██    ██",
        " ██████   ██ ███ ██  ██    ██  ████████",
        "  ████    ██  █  ██  ██    ██   ██████ "
    ]

    override var isFlipped: Bool { true }

    init(frame frameRect: NSRect, reduceMotion: Bool? = nil) {
        self.reduceMotion = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init(frame: frameRect)
        wantsLayer = true
        rebuildStream()
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && !reduceMotion { startAnimating() } else { stopAnimating() }
    }

    deinit { stopAnimating() }

    func startAnimating() {
        guard !reduceMotion, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: reduceMotion ? 1.0 : (1.0 / 12.0), repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        let now = Date()
        let delta = min(now.timeIntervalSince(lastTick), 0.2)
        lastTick = now
        phase += delta * (reduceMotion ? 0.08 : 0.65)
        if !reduceMotion && Int(phase * 10) % 7 == 0 { rebuildStream() }
        needsDisplay = true
    }

    private func rebuildStream() {
        let width = max(28, Int(bounds.width / 8))
        stream = (0..<9).map { row in
            (0..<width).map { column in
                let phaseOffset: Int = Int(phase * 13)
                let rowOffset: Int = row * 17
                let columnOffset: Int = column * 11
                let index: Int = (rowOffset + columnOffset + phaseOffset) % glyphs.count
                return String(glyphs[index])
            }.joined()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        context.setFillColor(NSColor(calibratedWhite: 0.025, alpha: 1).cgColor)
        context.fill(bounds)

        let side = min(bounds.width, bounds.height)
        let maxLogoCharacters = CGFloat(44)
        let widthLimitedSize = bounds.width / (maxLogoCharacters * 0.62)
        let fontSize = max(3, min(34, side / 20, widthLimitedSize))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let smallFont = NSFont.monospacedSystemFont(ofSize: max(9, fontSize * 0.38), weight: .regular)
        let logoWidth = logo.map { $0.size(withAttributes: [.font: font]).width }.max() ?? 0
        let lineHeight = fontSize * 1.08
        let logoHeight = CGFloat(logo.count) * lineHeight
        let origin = CGPoint(x: (bounds.width - logoWidth) / 2, y: (bounds.height - logoHeight) / 2 - fontSize * 0.4)

        for (index, line) in stream.enumerated() {
            let y = 18 + CGFloat(index) * (smallFont.pointSize + 8)
            let alpha = 0.08 + CGFloat((index % 3)) * 0.025
            (line as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: [
                .font: smallFont,
                .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.72, blue: 0.34, alpha: alpha)
            ])
        }

        let cycle = reduceMotion ? 1.0 : phase.truncatingRemainder(dividingBy: 12.0) / 12.0
        for (index, line) in logo.enumerated() {
            let wobble = reduceMotion ? 0 : sin(phase + Double(index) * 0.7) * 1.2
            let color = NSColor(calibratedRed: 0.60, green: 0.85, blue: 0.40, alpha: 0.94)
            let reveal: Double
            if reduceMotion || cycle >= 0.17 && cycle < 0.67 { reveal = 1 }
            else if cycle < 0.17 { reveal = cycle / 0.17 }
            else { reveal = max(0, 1 - (cycle - 0.67) / 0.33) }
            let assembled = line.enumerated().map { column, character in
                let cell = Double((index * 53 + column * 29) % 97) / 97.0
                return cell <= reveal ? String(character) : " "
            }.joined()
            (assembled as NSString).draw(at: CGPoint(x: origin.x + CGFloat(wobble), y: origin.y + CGFloat(index) * lineHeight), withAttributes: [
                .font: font,
                .foregroundColor: color
            ])
        }

    }
}

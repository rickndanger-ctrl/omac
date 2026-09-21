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

    init(frame frameRect: NSRect, reduceMotion: Bool? = nil, initialPhase: Double = 0) {
        self.reduceMotion = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.phase = initialPhase
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

    func selectScene(_ scene: Int) {
        phase = Double(max(0,min(3,scene))) * 8 + 2
        lastTick = Date(); needsDisplay = true
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        let now = Date()
        let delta = min(now.timeIntervalSince(lastTick), 0.2)
        lastTick = now
        phase += delta * (reduceMotion ? 0.08 : 1.0)
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

        // Four eight-second scenes: matrix, spectrum, lightning, and particle assembly.
        // Each is deterministic so the saver stays calm and cheap to render.
        let effect = reduceMotion ? 0 : Int(phase / 8.0) % 4
        let effectProgress = reduceMotion ? 0.0 : phase.truncatingRemainder(dividingBy: 8.0) / 8.0

        for (index, line) in stream.enumerated() {
            let y = 18 + CGFloat(index) * (smallFont.pointSize + 8)
            let alpha = effect == 0 ? 0.14 + CGFloat((index % 3)) * 0.035 : 0.045 + CGFloat((index % 2)) * 0.018
            (line as NSString).draw(at: CGPoint(x: 24, y: y), withAttributes: [
                .font: smallFont,
                .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.72, blue: 0.34, alpha: alpha)
            ])
        }

        if effect == 1 {
            let scanY = bounds.height * CGFloat(effectProgress)
            context.setFillColor(NSColor(calibratedRed: 0.15, green: 0.85, blue: 0.95, alpha: 0.22).cgColor)
            context.fill(CGRect(x: 0, y: scanY, width: bounds.width, height: max(1, fontSize * 0.08)))
        } else if effect == 2 {
            let cursor = "▌"
            (cursor as NSString).draw(at: CGPoint(x: origin.x + logoWidth + 8, y: origin.y + logoHeight - lineHeight), withAttributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.60, green: 0.85, blue: 0.40, alpha: effectProgress < 0.5 ? 0.8 : 0.15)
            ])
            context.saveGState()
            context.setShadow(offset: .zero, blur: 14, color: NSColor.cyan.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(max(1, fontSize * 0.055))
            context.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.85, blue: 1, alpha: 0.75).cgColor)
            for bolt in 0..<3 {
                let path = CGMutablePath()
                let travel = CGFloat(effectProgress) * logoWidth
                let x = origin.x + CGFloat(bolt + 1) * logoWidth / 4 + travel * (bolt == 1 ? -0.35 : 0.18)
                path.move(to: CGPoint(x: x - 24, y: origin.y - 12))
                path.addLine(to: CGPoint(x: x - 8, y: origin.y + logoHeight * 0.35))
                path.addLine(to: CGPoint(x: x + 5, y: origin.y + logoHeight * 0.32))
                path.addLine(to: CGPoint(x: x - 4, y: origin.y + logoHeight + 10))
                context.addPath(path)
                context.strokePath()
            }
            let sparkX = origin.x + logoWidth * CGFloat(effectProgress)
            let sparkY = origin.y + logoHeight * (0.25 + 0.5 * CGFloat(sin(effectProgress * .pi)))
            context.setFillColor(NSColor(calibratedRed: 1, green: 0.55, blue: 0.08, alpha: 0.95).cgColor)
            context.fillEllipse(in: CGRect(x: sparkX - fontSize * 0.16, y: sparkY - fontSize * 0.16, width: fontSize * 0.32, height: fontSize * 0.32))
            context.restoreGState()
        } else if effect == 3 {
            context.setFillColor(NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.12, alpha: 0.55).cgColor)
            for particle in 0..<28 {
                let seed = CGFloat((particle * 37) % 101) / 100
                let x = bounds.midX + (seed - 0.5) * bounds.width * (0.3 + effectProgress * 1.3)
                let y = bounds.midY + CGFloat(sin(Double(particle) * 2.7 + phase)) * bounds.height * 0.35
                context.fillEllipse(in: CGRect(x: x, y: y, width: max(1, fontSize * 0.12), height: max(1, fontSize * 0.12)))
            }
        }

        let cycle = reduceMotion ? 0.5 : effectProgress
        for (index, line) in logo.enumerated() {
            let wobble = reduceMotion ? 0 : sin(phase + Double(index) * 0.7) * (effect == 3 ? 2.8 : 1.2)
            let baseHue = effect == 0 ? 0.27 : effect == 1 ? 0.76 : effect == 2 ? 0.56 : 0.10
            let reveal: Double
            if reduceMotion || cycle >= 0.12 && cycle < 0.88 { reveal = 1 }
            else if cycle < 0.12 { reveal = cycle / 0.12 }
            else { reveal = max(0, 1 - (cycle - 0.88) / 0.12) }
            let assembled = line.enumerated().map { column, character in
                let cell = Double((index * 53 + column * 29) % 97) / 97.0
                return cell <= reveal ? String(character) : " "
            }.joined()
            let cellWidth = "█".size(withAttributes: [.font: font]).width
            for (column, character) in assembled.enumerated() where character != " " {
                let hue = effect == 0 ? 0.27 : effect == 2 ? 0.54 + Double(column) * 0.001 : (baseHue + Double(column) * 0.018 + phase * 0.025).truncatingRemainder(dividingBy: 1)
                let light = effect == 2 ? max(0, 1 - abs(Double(column) / 40 - effectProgress) * 12) : 0
                let color = NSColor(hue: CGFloat(hue), saturation: CGFloat(0.78 * (1-light)), brightness: 0.98, alpha: 0.96)
                let glyph = String(character) as NSString
                let x = origin.x + CGFloat(column) * cellWidth + CGFloat(wobble)
                let scatter = effect == 3 ? pow(abs(effectProgress - 0.5) * 2, 3) : 0
                let dx = CGFloat(sin(Double(column * 13 + index * 7))) * bounds.width * 0.3 * scatter
                let dy = CGFloat(cos(Double(column * 7 + index * 11))) * bounds.height * 0.3 * scatter
                glyph.draw(at: CGPoint(x: x + dx, y: origin.y + CGFloat(index) * lineHeight + dy), withAttributes: [.font: font, .foregroundColor: color])
            }
            if effect == 3 && index % 3 == 0 {
                let ghost = String(assembled.dropFirst(min(2, assembled.count)))
                (ghost as NSString).draw(at: CGPoint(x: origin.x - 2, y: origin.y + CGFloat(index) * lineHeight), withAttributes: [
                    .font: font,
                    .foregroundColor: NSColor(calibratedRed: 0.48, green: 0.72, blue: 0.34, alpha: 0.20)
                ])
            }
        }

    }
}

import AppKit

/// Four restrained scenes rendered locally; no network or API calls.
final class OmacRendererView: NSView {
    private var timer: Timer?
    private var phase: Double
    private var lastTick = Date()
    private let reduceMotion: Bool
    private var cells: [CGPoint] = []
    private var maskSize = CGSize(width: 1, height: 1)
    private lazy var emblem: NSImage? = {
        let bundle = Bundle(for: OmacRendererView.self)
        guard let url = bundle.url(forResource: "Omac", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    override var isFlipped: Bool { true }

    init(frame: NSRect, reduceMotion: Bool? = nil, initialPhase: Double = 0) {
        self.reduceMotion = reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        phase = initialPhase
        super.init(frame: frame)
        makeWordmark()
    }
    required init?(coder: NSCoder) { nil }
    deinit { stopAnimating() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { startAnimating() } else { stopAnimating() }
    }
    func startAnimating() {
        guard !reduceMotion, timer == nil else { return }
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date(); self.phase += min(0.15, now.timeIntervalSince(self.lastTick))
            self.lastTick = now; self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stopAnimating() { timer?.invalidate(); timer = nil }
    func selectScene(_ scene: Int) {
        phase = Double(max(0,min(3,scene))) * 8 + 2
        lastTick = Date(); needsDisplay = true
    }

    private func makeWordmark() {
        // Sample a real letter silhouette into fine micro-strokes. Preserve counters,
        // curved edges and spacing instead of enlarging a ten-row block alphabet.
        let font = NSFont(name: "AvenirNext-DemiBold", size: 120) ?? .systemFont(ofSize: 120, weight: .semibold)
        let text = NSAttributedString(string: "OMAC", attributes: [.font:font,.foregroundColor:NSColor.white,.kern:12])
        let size = text.size(); maskSize = size
        let image = NSImage(size:size)
        image.lockFocus(); NSColor.clear.setFill(); NSRect(origin:.zero,size:size).fill()
        text.draw(at:.zero); image.unlockFocus()
        guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data) else {return}
        let sx=CGFloat(bitmap.pixelsWide)/size.width, sy=CGFloat(bitmap.pixelsHigh)/size.height
        for y in stride(from:0,to:Int(size.height),by:2) {
            for x in stride(from:0,to:Int(size.width),by:2) {
                if let color=bitmap.colorAt(x:min(bitmap.pixelsWide-1,Int(CGFloat(x)*sx)),y:min(bitmap.pixelsHigh-1,Int(CGFloat(y)*sy))),color.alphaComponent > 0.55 {
                    cells.append(CGPoint(x:x,y:y))
                }
            }
        }
    }
    override func draw(_ rect: NSRect) {
        guard let ctx=NSGraphicsContext.current?.cgContext else {return}
        NSColor(calibratedRed:0.008,green:0.014,blue:0.019,alpha:1).setFill(); bounds.fill()
        let scene=reduceMotion ? 2 : Int(phase/8)%4
        let t=reduceMotion ? 0.5 : phase.truncatingRemainder(dividingBy:8)/8
        let fade=reduceMotion ? 1 : min(1,min(t/0.1,(1-t)/0.1))
        if scene == 3,let image=emblem {
            let side=min(bounds.width*0.34,bounds.height*0.60)
            image.draw(in:NSRect(x:bounds.midX-side/2,y:bounds.midY-side/2,width:side,height:side),from:.zero,operation:.sourceOver,fraction:fade,respectFlipped:true,hints:nil)
            return
        }
        let scale=min(bounds.width*0.43/maskSize.width,bounds.height*0.22/maskSize.height)
        let origin=CGPoint(x:bounds.midX-maskSize.width*scale/2,y:bounds.midY-maskSize.height*scale/2)
        let width=maskSize.width*scale, height=maskSize.height*scale
        let beam=origin.x+width*CGFloat(t)
        let accent=scene == 1 ? NSColor(calibratedRed:0.96,green:0.70,blue:0.36,alpha:1) : NSColor(calibratedRed:0.46,green:0.79,blue:0.88,alpha:1)
        for (i,cell) in cells.enumerated() {
            let x=origin.x+cell.x*scale, y=origin.y+cell.y*scale
            let highlight=max(0,1-abs(x-beam)/max(1,width*0.045))
            let brightness=scene == 2 ? 0.36+0.64*highlight : 0.63+0.37*highlight
            let c=accent.blended(withFraction:highlight*0.85,of:.white) ?? accent
            c.withAlphaComponent(fade*brightness).setFill()
            let drift=scene == 0 ? pow(abs(t-0.5)*2,5)*sin(Double(i)*1.7)*18 : 0
            // Tiny horizontal facets form crisp, finely detailed letter edges.
            NSRect(x:x+drift,y:y,width:max(0.65,scale*1.7),height:max(0.55,scale*1.2)).fill()
        }
        guard !reduceMotion else {return}
        ctx.saveGState()
        ctx.setShadow(offset:.zero,blur:9,color:accent.withAlphaComponent(0.65*fade).cgColor)
        if scene == 2 {
            // Moving branched arcs skim the lettering; no full-screen flashes.
            for branch in 0..<3 {
                let path=CGMutablePath()
                let startX=origin.x+width*CGFloat(branch)/2
                path.move(to:CGPoint(x:startX,y:origin.y-height*0.55))
                for step in 1...18 {
                    let f=CGFloat(step)/18
                    let x=startX+(beam-startX)*f+CGFloat(sin(Double(step)*2.1+phase*3+Double(branch)))*7*sin(f * .pi)
                    let y=origin.y-height*0.55+height*1.35*f
                    path.addLine(to:CGPoint(x:x,y:y))
                }
                ctx.addPath(path);ctx.setLineWidth(0.65)
                ctx.setStrokeColor(accent.withAlphaComponent(fade*0.65).cgColor);ctx.strokePath()
            }
        }
        if scene == 1 || scene == 2 {
            let sparkY=origin.y+height*(0.35+0.2*sin(phase))
            for i in 0..<32 {
                let f=CGFloat(i)/32
                let px=beam-f*width*0.18
                let py=sparkY+sin(CGFloat(i)*2.4+phase)*f*height*0.65
                accent.withAlphaComponent((1-f)*fade*0.75).setFill()
                NSRect(x:px,y:py,width:1.1,height:1.1).fill()
            }
            NSColor.white.withAlphaComponent(fade).setFill()
            NSRect(x:beam,y:sparkY,width:2,height:2).fill()
        }
        ctx.restoreGState()
    }
}

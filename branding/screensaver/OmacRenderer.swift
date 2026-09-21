import AppKit

/// Four cinematic scenes rendered locally; no network or API calls.
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
        // Use the supplied logo's actual letter silhouettes as the particle map.
        // The original asset stays untouched; sample only its OMAC wordmark region.
        guard let image=emblem,let data=image.tiffRepresentation,
              let bitmap=NSBitmapImageRep(data:data) else { return }
        let left=Int(Double(bitmap.pixelsWide)*0.239)
        let top=Int(Double(bitmap.pixelsHigh)*0.608)
        let right=Int(Double(bitmap.pixelsWide)*0.760)
        let bottom=Int(Double(bitmap.pixelsHigh)*0.752)
        maskSize=CGSize(width:right-left,height:bottom-top)
        for y in stride(from:top,to:bottom,by:2) {
            for x in stride(from:left,to:right,by:2) {
                guard let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else {continue}
                if color.greenComponent > 0.48 && color.greenComponent > color.blueComponent*1.2 {
                    cells.append(CGPoint(x:x-left,y:y-top))
                }
            }
        }
        cells.sort { a,b in
            if a.x != b.x { return a.x < b.x }
            return Int(a.x/2)%2 == 0 ? a.y < b.y : a.y > b.y
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
        let scale=1.2*min(bounds.width*0.43/maskSize.width,bounds.height*0.22/maskSize.height)
        let origin=CGPoint(x:bounds.midX-maskSize.width*scale/2,y:bounds.midY-maskSize.height*scale/2)
        let width=maskSize.width*scale, height=maskSize.height*scale
        let etchProgress=max(0,min(1,(t-0.06)/0.72))
        let etchIndex=min(max(0,cells.count-1),Int(etchProgress*Double(cells.count)))
        let tipCell=cells.isEmpty ? CGPoint.zero : cells[etchIndex]
        let tip=CGPoint(x:origin.x+tipCell.x*scale,y:origin.y+tipCell.y*scale)
        let beam=scene == 1 ? tip.x : origin.x+width*CGFloat(t)
        let accent=scene == 1 ? NSColor(calibratedRed:1,green:0.10,blue:0.055,alpha:1) : NSColor(calibratedRed:0.46,green:0.79,blue:0.88,alpha:1)
        for (i,cell) in cells.enumerated() {
            let x=origin.x+cell.x*scale, y=origin.y+cell.y*scale
            let highlight=scene == 1 ? max(0,1-hypot(x-tip.x,y-tip.y)/18) : max(0,1-abs(x-beam)/max(1,width*0.045))
            if scene == 1 && i > etchIndex { continue }
            let brightness=scene == 2 ? 0.68+0.32*highlight : 0.78+0.22*highlight
            let c=accent.blended(withFraction:highlight*0.85,of:.white) ?? accent
            c.withAlphaComponent(fade*brightness).setFill()
            let drift=scene == 0 ? pow(abs(t-0.5)*2,5)*sin(Double(i)*1.7)*72 : 0
            // Tiny horizontal facets form crisp, finely detailed letter edges.
            NSRect(x:x+drift,y:y,width:max(0.65,scale*1.7),height:max(0.55,scale*1.2)).fill()
        }
        guard !reduceMotion else {return}
        ctx.saveGState()
        ctx.setShadow(offset:.zero,blur:27,color:accent.withAlphaComponent(0.95*fade).cgColor)
        if scene == 2 {
            // Moving branched arcs skim the lettering; no full-screen flashes.
            for branch in 0..<9 {
                let path=CGMutablePath()
                let startX=origin.x+width*CGFloat(branch)/8
                path.move(to:CGPoint(x:startX,y:origin.y-height*1.5))
                for step in 1...18 {
                    let f=CGFloat(step)/18
                    let x=startX+(beam-startX)*f+CGFloat(sin(Double(step)*2.1+phase*3+Double(branch)))*24*sin(f * .pi)
                    let y=origin.y-height*1.5+height*2.35*f
                    path.addLine(to:CGPoint(x:x,y:y))
                }
                ctx.addPath(path);ctx.setLineWidth(2.0)
                ctx.setStrokeColor(accent.withAlphaComponent(fade*0.85).cgColor);ctx.strokePath()
                ctx.addPath(path);ctx.setLineWidth(0.65)
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(fade*0.9).cgColor);ctx.strokePath()
                // Smaller forks split off the main arc near the wordmark.
                let fork=CGMutablePath()
                fork.move(to:CGPoint(x:beam,y:origin.y+height*0.65))
                fork.addLine(to:CGPoint(x:beam+CGFloat(branch-4)*14,y:origin.y+height*0.95))
                fork.addLine(to:CGPoint(x:beam+CGFloat(branch-4)*27,y:origin.y+height*1.45))
                ctx.addPath(fork);ctx.setLineWidth(0.8)
                ctx.setStrokeColor(accent.withAlphaComponent(fade*0.55).cgColor);ctx.strokePath()
            }
        }
        if scene == 1 && etchProgress > 0 && etchProgress < 1 {
            // A white-hot red laser follows the actual letter pixels as they appear.
            let ray=CGMutablePath()
            ray.move(to:CGPoint(x:bounds.midX-width*0.65,y:max(12,origin.y-height*1.3)))
            ray.addLine(to:tip)
            ctx.addPath(ray);ctx.setLineWidth(3)
            ctx.setStrokeColor(accent.withAlphaComponent(fade*0.8).cgColor);ctx.strokePath()
            ctx.addPath(ray);ctx.setLineWidth(0.7)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(fade).cgColor);ctx.strokePath()
            // Deterministic ballistic showers: all-direction launch, trailing streaks,
            // orange embers and gravity, without per-frame particle allocation.
            ctx.setShadow(offset:.zero,blur:6,color:NSColor.red.withAlphaComponent(0.8).cgColor)
            for particle in 0..<180 {
                let seed=Double(particle)
                let age=(phase*1.5+seed*0.6180339).truncatingRemainder(dividingBy:1)
                let angle=seed*2.3999632
                let speed=70+Double(particle%23)*12
                let vx=cos(angle)*speed, vy=sin(angle)*speed
                let px=tip.x+vx*age, py=tip.y+vy*age+130*age*age
                let trail=0.016+Double(particle%5)*0.007
                let path=CGMutablePath();path.move(to:CGPoint(x:px,y:py))
                path.addLine(to:CGPoint(x:px-vx*trail,y:py-(vy+260*age)*trail))
                ctx.addPath(path);ctx.setLineWidth(particle%7 == 0 ? 1.8:0.8)
                ctx.setStrokeColor(NSColor(calibratedRed:1,green:0.25+0.65*(1-age),blue:0.08+0.5*pow(1-age,4),alpha:fade*pow(1-age,1.6)).cgColor)
                ctx.strokePath()
            }
            ctx.setShadow(offset:.zero,blur:22,color:NSColor.red.cgColor)
            NSColor.white.withAlphaComponent(fade).setFill()
            NSBezierPath(ovalIn:NSRect(x:tip.x-3,y:tip.y-3,width:6,height:6)).fill()
        }
        if scene == 2 {
            let sparkY=origin.y+height*(0.35+0.2*sin(phase))
            for i in 0..<96 {
                let f=CGFloat(i)/96
                let px=beam-f*width*0.54
                let py=sparkY+sin(CGFloat(i)*2.4+phase)*f*height*1.95
                accent.withAlphaComponent((1-f)*fade*0.75).setFill()
                NSRect(x:px,y:py,width:1.8,height:1.8).fill()
            }
            NSColor.white.withAlphaComponent(fade).setFill()
            NSRect(x:beam,y:sparkY,width:4,height:4).fill()
        }
        ctx.restoreGState()
    }
}

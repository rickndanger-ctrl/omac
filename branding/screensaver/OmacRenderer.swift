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
    private lazy var wallpapers: [NSImage] = ["emerald-glass", "storm-forge", "crimson-etch"].compactMap {
        guard let url = Bundle(for: OmacRendererView.self).url(forResource: $0, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
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
        let scene=reduceMotion ? 0 : Int(phase/8)%4
        let t=reduceMotion ? 0.5 : phase.truncatingRemainder(dividingBy:8)/8
        if wallpapers.count == 3 {
            drawWallpaper(in: bounds, scene: reduceMotion ? 0 : Int(phase/8)%3, progress: t)
            if !reduceMotion { drawAmbientParticles(in: bounds, progress: t); drawSceneEnergy(scene:Int(phase/8)%3,progress:t) }
            return
        }
        let fade=reduceMotion ? 1 : min(1,min(t/0.1,(1-t)/0.1))
        if scene == 3,let image=emblem {
            if !reduceMotion {
                ctx.saveGState()
                ctx.setShadow(offset:.zero,blur:14,color:NSColor.systemGreen.withAlphaComponent(0.5).cgColor)
                for i in 0..<100 {
                    let a=Double(i)*2.399963
                    let life=(phase*0.35+Double(i)*0.031).truncatingRemainder(dividingBy:1)
                    let radius=min(bounds.width,bounds.height)*(0.12+life*0.4)
                    let x=bounds.midX+cos(a+phase*0.12)*radius
                    let y=bounds.midY+sin(a+phase*0.12)*radius
                    let color=i%3 == 0 ? NSColor.systemTeal : NSColor.systemGreen
                    color.withAlphaComponent(fade*(1-life)*0.8).setFill()
                    NSBezierPath(ovalIn:NSRect(x:x,y:y,width:2,height:2)).fill()
                }
                ctx.restoreGState()
            }
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
            let palette=scene == 0 ? NSColor(calibratedRed:0.28+0.5*Double(cell.x/maskSize.width),green:0.78,blue:0.94,alpha:1) : accent
            let c=palette.blended(withFraction:highlight*0.85,of:.white) ?? palette
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
                let boltColor=branch%3 == 0 ? NSColor(calibratedRed:0.72,green:0.45,blue:1,alpha:1) : accent
                ctx.setShadow(offset:.zero,blur:27,color:boltColor.withAlphaComponent(0.85*fade).cgColor)
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
                ctx.setStrokeColor(boltColor.withAlphaComponent(fade*0.85).cgColor);ctx.strokePath()
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
        if scene == 0 {
            for i in 0..<96 {
                let age=(phase*0.65+Double(i)*0.618).truncatingRemainder(dividingBy:1)
                let angle=Double(i)*2.399963
                let radius=40+age*width*0.7
                let x=bounds.midX+cos(angle)*radius,y=bounds.midY+sin(angle)*radius*0.55
                let path=CGMutablePath();path.move(to:CGPoint(x:x,y:y))
                path.addLine(to:CGPoint(x:x-cos(angle)*12,y:y-sin(angle)*8))
                ctx.addPath(path);ctx.setLineWidth(1)
                ctx.setStrokeColor((i%2 == 0 ? NSColor.systemTeal:NSColor.systemPurple).withAlphaComponent(fade*(1-age)*0.8).cgColor)
                ctx.strokePath()
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

    private func drawWallpaper(in bounds: NSRect, scene: Int, progress: Double) {
        guard wallpapers.count == 3 else { return }
        let first = scene % 3
        let second = (first + 1) % 3
        let blend = reduceMotion ? CGFloat(0) : CGFloat(max(0,min(1,(progress-0.78)/0.22)))
        for (image, alpha) in [(wallpapers[first], CGFloat(1)), (wallpapers[second], blend)] where alpha > 0.01 {
            let source = NSRect(origin: .zero, size: image.size)
            let scale = max(bounds.width / source.width, bounds.height / source.height) * 1.015
            let size = NSSize(width: source.width * scale, height: source.height * scale)
            let drift = reduceMotion ? CGFloat(0) : CGFloat(sin(phase * 0.15) * 5)
            let destination = NSRect(x: bounds.midX - size.width / 2 + drift, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: destination, from: source, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    private func drawSceneEnergy(scene:Int,progress:Double) {
        guard let ctx=NSGraphicsContext.current?.cgContext else {return}
        ctx.saveGState();defer {ctx.restoreGState()}
        let fade=CGFloat(min(1,min(progress/0.08,(1-progress)/0.22)))
        let w=bounds.width,h=bounds.height
        if scene == 0 {
            // A soft traveling emerald highlight, with no flash or opaque veil.
            let x=w*(0.39+0.22*(sin(phase*0.65)+1)/2)
            ctx.setShadow(offset:.zero,blur:24,color:NSColor.green.withAlphaComponent(0.35*fade).cgColor)
            NSColor.green.withAlphaComponent(0.12*fade).setStroke()
            let p=NSBezierPath();p.move(to:NSPoint(x:x,y:h*0.39));p.line(to:NSPoint(x:x-8,y:h*0.58));p.lineWidth=1;p.stroke()
        } else if scene == 1 {
            // Branching arcs evolve continuously; their glow breathes rather than strobing.
            let pulse=CGFloat(0.35+0.25*sin(phase*2)) * fade
            for branch in 0..<5 {
                let color=branch%2==0 ? NSColor.cyan:NSColor.systemPurple
                ctx.setShadow(offset:.zero,blur:12,color:color.withAlphaComponent(pulse).cgColor)
                color.withAlphaComponent(pulse).setStroke()
                let p=NSBezierPath()
                for step in 0...18 {
                    let t=Double(step)/18,side=branch%2==0 ? -1.0:1.0
                    let x=w*(0.5+side*t*0.28)+sin(Double(step)*2.7+phase*3+Double(branch))*8*t
                    let y=h*(0.36+Double(branch)*0.065-t*0.22)+cos(Double(step)*1.9+phase*2)*9*t
                    if step==0 {p.move(to:NSPoint(x:x,y:y))} else {p.line(to:NSPoint(x:x,y:y))}
                }
                p.lineWidth=1;p.stroke()
            }
        } else {
            let tip=NSPoint(x:w*(0.36+0.28*(sin(phase*0.6)+1)/2),y:h*0.69)
            ctx.setShadow(offset:.zero,blur:13,color:NSColor.red.cgColor)
            NSColor.red.withAlphaComponent(0.7*fade).setStroke()
            let beam=NSBezierPath();beam.move(to:NSPoint(x:w*0.84,y:0));beam.line(to:tip);beam.lineWidth=1.3;beam.stroke()
            for i in 0..<70 {
                let age=(phase*1.2+Double(i)*0.071).truncatingRemainder(dividingBy:1)
                let angle=Double(i)*2.39996,speed=40+Double(i%13)*9
                let x=tip.x+cos(angle)*speed*age,y=tip.y+sin(angle)*speed*age+70*age*age
                NSColor(calibratedRed:1,green:0.25+Double(i%4)*0.13,blue:0.05,alpha:(1-age)*Double(fade)).setStroke()
                let p=NSBezierPath();p.move(to:NSPoint(x:x,y:y));p.line(to:NSPoint(x:x-cos(angle)*7,y:y-sin(angle)*7));p.lineWidth=1;p.stroke()
            }
        }
    }

    private func drawAmbientParticles(in bounds: NSRect, progress: Double) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setShadow(offset: .zero, blur: 7, color: NSColor.systemTeal.withAlphaComponent(0.25).cgColor)
        for index in 0..<42 {
            let seed = Double(index) * 2.399963
            let life = (phase * 0.12 + Double(index) * 0.071).truncatingRemainder(dividingBy: 1)
            let radius = min(bounds.width, bounds.height) * (0.18 + life * 0.38)
            let point = CGPoint(x: bounds.midX + cos(seed + phase * 0.08) * radius,
                               y: bounds.midY + sin(seed + phase * 0.08) * radius * 0.58)
            let color = index % 3 == 0 ? NSColor.systemPurple : NSColor.systemTeal
            color.withAlphaComponent((1 - life) * 0.26).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x, y: point.y, width: 1.5, height: 1.5)).fill()
        }
        context?.restoreGState()
    }
}

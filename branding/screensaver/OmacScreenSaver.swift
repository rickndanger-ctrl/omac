import AppKit
import ScreenSaver

@objc(OmacScreenSaverView)
final class OmacScreenSaverView: ScreenSaverView {
    private var renderer: OmacRendererView!

    override init?(frame frameRect: NSRect, isPreview: Bool) {
        super.init(frame: frameRect, isPreview: isPreview)
        animationTimeInterval = 1.0 / 12.0
        renderer = OmacRendererView(frame: bounds)
        renderer.autoresizingMask = [.width, .height]
        addSubview(renderer)
    }

    required init?(coder: NSCoder) { return nil }

    override func startAnimation() { super.startAnimation(); renderer.startAnimating() }
    override func stopAnimation() { renderer.stopAnimating(); super.stopAnimation() }
    override func draw(_ rect: NSRect) { renderer.frame = bounds }
}

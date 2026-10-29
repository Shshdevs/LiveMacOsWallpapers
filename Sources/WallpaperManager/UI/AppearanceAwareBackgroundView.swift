import AppKit

final class AppearanceAwareBackgroundView: NSView {
    var fillColor: NSColor {
        didSet { updateBackground() }
    }

    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    init(fillColor: NSColor, cornerRadius: CGFloat = 0) {
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        updateBackground()
        layer?.cornerRadius = cornerRadius
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        updateBackground()
        layer?.cornerRadius = cornerRadius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = self?.fillColor.cgColor
        }
    }
}

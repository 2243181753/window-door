import AppKit

struct TileState: Equatable {
    var on = false
    var enabled = true
    var help: String = ""
}

@MainActor final class TileButton: NSButton {
    let name: String
    private let icon: NSImage
    private let callback: () -> Void
    private let provider: () -> TileState
    private let secondary: Bool
    private var rendered: TileState?
    private var names = false
    private var renderedIcon: NSImage?
    var expand: (() -> Void)?
    var leadingDivider = false
    private(set) var refreshCount = 0

    init(name: String, icon: NSImage, secondary: Bool = false,
         state: @escaping () -> TileState, action: @escaping () -> Void) {
        self.name = name; self.icon = icon; self.secondary = secondary
        provider = state; callback = action
        super.init(frame: .zero)
        target = self; self.action = #selector(pressed)
        isBordered = false; focusRingType = .default
        setButtonType(.momentaryPushIn)
        imageScaling = .scaleProportionallyDown
        font = .systemFont(ofSize: secondary ? 10 : 12, weight: .medium)
        setAccessibilityLabel(name)
        translatesAutoresizingMaskIntoConstraints = false
        refresh(names: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func rightMouseDown(with event: NSEvent) {
        if let expand { expand() } else { super.rightMouseDown(with: event) }
    }
    func duplicate() -> TileButton {
        TileButton(name: name, icon: icon, secondary: secondary, state: provider, action: callback)
    }
    @objc private func pressed() { callback(); refresh(names: names) }
    func refresh(names: Bool) {
        let value = provider()
        guard rendered != value || self.names != names else { return }
        rendered = value; self.names = names; refreshCount += 1
        title = names ? name : ""
        if names {
            attributedTitle = NSAttributedString(string: name, attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 12),
                .foregroundColor: value.enabled ? (value.on ? NSColor.black : .labelColor) : .tertiaryLabelColor])
        }
        image = names ? nil : icon
        imagePosition = names ? .noImage : .imageOnly
        isEnabled = value.enabled
        contentTintColor = value.enabled ? (value.on ? .black : .labelColor) : .tertiaryLabelColor
        let source = icon.copy() as! NSImage; source.isTemplate = false
        let tint = contentTintColor ?? .labelColor
        renderedIcon = NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect)
            tint.setFill(); rect.fill(using: .sourceIn)
            return true
        }
        toolTip = name + (value.help.isEmpty ? "" : " · " + value.help)
        setAccessibilityHelp(value.help)
        setAccessibilityValue(value.on ? "开启" : "关闭")
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let value = rendered ?? TileState()
        (value.on ? NSColor.white : NSColor.quaternaryLabelColor.withAlphaComponent(0.12)).setFill()
        bounds.fill()
        if !value.enabled { NSColor.windowBackgroundColor.withAlphaComponent(0.5).setFill(); bounds.fill() }
        if secondary {
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let line = NSBezierPath(); line.move(to: CGPoint(x: 0, y: bounds.maxY - 0.5)); line.line(to: CGPoint(x: bounds.maxX, y: bounds.maxY - 0.5)); line.lineWidth = 0.5; line.stroke()
        }
        if leadingDivider {
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let line = NSBezierPath(); line.move(to: CGPoint(x: 0.5, y: 0)); line.line(to: CGPoint(x: 0.5, y: bounds.maxY)); line.lineWidth = 0.5; line.stroke()
        }
        if names {
            let label = attributedTitle
            let size = label.size()
            label.draw(in: CGRect(x: max(3, (bounds.width-size.width)/2), y: (bounds.height-size.height)/2,
                                  width: bounds.width-6, height: size.height))
        } else if let renderedIcon {
            let limit: CGFloat = secondary ? 15 : 28
            let ratio = min(limit / max(1, renderedIcon.size.width), limit / max(1, renderedIcon.size.height))
            let size = CGSize(width: renderedIcon.size.width * ratio, height: renderedIcon.size.height * ratio)
            renderedIcon.draw(in: CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height))
        }
        if isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.08).setFill(); bounds.fill()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            ring.lineWidth = 2; ring.stroke()
        }

    }
}

@MainActor final class SettingsTile: NSView {
    let main: TileButton
    let children: [TileButton]
    private var arrow: NSButton?
    private var hoverArea: NSTrackingArea?
    private var arrowOn: Bool?
    func configureExpansion(left: Bool, action: @escaping () -> Void) {
        main.expand = action
        let button = NSButton(title: left ? "<" : ">", target: self, action: #selector(expandPressed))
        button.isBordered = false; button.font = .systemFont(ofSize: 13, weight: .regular)
        button.setAccessibilityLabel("展开" + main.name); button.toolTip = "展开设置，也可右键点击"
        button.translatesAutoresizingMaskIntoConstraints = false; addSubview(button)
        NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3), button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 2), button.widthAnchor.constraint(equalToConstant: 24), button.heightAnchor.constraint(equalToConstant: 24)])
        button.isHidden = true; arrow = button
    }
    @objc private func expandPressed() { main.expand?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { arrow?.isHidden = false }
    override func mouseExited(with event: NSEvent) { arrow?.isHidden = true }
    init(main: TileButton, children: [TileButton] = []) {
        self.main = main; self.children = children
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.cornerRadius = 13; layer?.masksToBounds = true
        layer?.borderWidth = 0.5; layer?.borderColor = NSColor.separatorColor.cgColor
        addSubview(main)
        NSLayoutConstraint.activate([main.leadingAnchor.constraint(equalTo: leadingAnchor), main.trailingAnchor.constraint(equalTo: trailingAnchor), main.topAnchor.constraint(equalTo: topAnchor)])
        if children.isEmpty { main.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true }
        else {
            let footer = NSStackView(views: children); footer.spacing = 0; footer.distribution = .fillEqually
            footer.translatesAutoresizingMaskIntoConstraints = false; addSubview(footer)
            for (index, child) in children.enumerated() {
                child.leadingDivider = index > 0
                child.heightAnchor.constraint(equalTo: footer.heightAnchor).isActive = true
            }
            NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo: leadingAnchor), footer.trailingAnchor.constraint(equalTo: trailingAnchor), footer.bottomAnchor.constraint(equalTo: bottomAnchor), footer.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1.0/3), main.bottomAnchor.constraint(equalTo: footer.topAnchor)])
        }
        heightAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh(names: Bool) {
        main.refresh(names: names); children.forEach { $0.refresh(names: names) }
        let on = main.accessibilityValue() as? String == "开启"
        if let arrow, arrowOn != on {
            arrowOn = on
            arrow.attributedTitle = NSAttributedString(string: arrow.title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: on ? NSColor.black : NSColor.labelColor])
        }
    }
}

@MainActor final class GridDetailsView: NSView { override var isFlipped: Bool { true } }


@MainActor final class MinimalSliderCell: NSSliderCell {
    private var trackCenterY: CGFloat = 0
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        trackCenterY = rect.midY
        NSColor.white.withAlphaComponent(isEnabled ? 0.38 : 0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2), xRadius: 1, yRadius: 1).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobRect.midX - 5, y: trackCenterY - 5, width: 10, height: 10)).fill()
    }
}

@MainActor final class CardActionButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        (isEnabled ? NSColor.white.withAlphaComponent(isHighlighted ? 0.8 : 1) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 6, yRadius: 6).fill()
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: isEnabled ? NSColor.black : NSColor.secondaryLabelColor])
        let size = text.size()
        let extra: CGFloat = image == nil ? 0 : 22
        let x = max(3, (bounds.width - size.width - extra)/2)
        if let image { image.draw(in: NSRect(x: x, y: (bounds.height-16)/2, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.25) }
        text.draw(in: NSRect(x: x + extra, y: (bounds.height - size.height)/2, width: bounds.width - 6, height: size.height))
    }
}


@MainActor final class OpacityPreviewSlider: NSSlider {
    var onTracking: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onTracking?(true)
        defer { onTracking?(false) }
        super.mouseDown(with: event)
    }
}

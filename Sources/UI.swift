import AppKit

// MARK: - Quinde Studio UI tokens (Design logic/UI-SYSTEM.md)

enum Q {
    static let blue = NSColor(srgbRed: 16 / 255, green: 48 / 255, blue: 1, alpha: 1) // #1030ff
    // spacing (Fibonacci)
    static let s1: CGFloat = 8, s2: CGFloat = 13, s3: CGFloat = 21, s4: CGFloat = 34, s6: CGFloat = 89
    // type (√φ steps)
    static let tCaption: CGFloat = 13, tBody: CGFloat = 16, tH2: CGFloat = 26
    // shape
    static let panelRadius: CGFloat = 21, fieldRadius: CGFloat = 13
    static let hairline: CGFloat = 1, line: CGFloat = 2
    static let minTarget: CGFloat = 44

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

/// Borderless windows refuse key status by default; ours need it to receive typing.
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Pill button

/// Solid for the one main action of a view, outline for the rest. Hover or press swaps fill and outline.
final class PillButton: NSButton {
    private let label: String
    private let solid: Bool
    private let ink: NSColor
    private let paper: NSColor
    private var hovered = false { didSet { refresh() } }

    init(_ label: String, solid: Bool, ink: NSColor, paper: NSColor, target: AnyObject, action: Selector) {
        self.label = label
        self.solid = solid
        self.ink = ink
        self.paper = paper
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.borderWidth = Q.line
        layer?.borderColor = ink.cgColor
        layer?.cornerRadius = Q.minTarget / 2
        heightAnchor.constraint(equalToConstant: Q.minTarget).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool { didSet { refresh() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private func refresh() {
        let filled = solid != (hovered || isHighlighted)
        layer?.backgroundColor = filled ? ink.cgColor : NSColor.clear.cgColor
        attributedTitle = NSAttributedString(string: label, attributes: [
            .font: Q.font(Q.tBody, bold: true),
            .foregroundColor: filled ? paper : ink,
        ])
    }
}

// MARK: - Panel

/// A floating panel in the UI system: a paper field with a hairline edge, 21 pt radius and no
/// shadow. Subclasses lay out their content in `build()`, which `rebuild()` runs again on change.
class Panel: NSObject {
    static let contentWidth: CGFloat = 377

    let window = BorderlessWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    let stack = NSStackView()
    let ink: NSColor
    let paper: NSColor

    override init() {
        // A field is white paper with blue ink; in dark mode it turns blue with white ink.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ink = dark ? .white : Q.blue
        paper = dark ? Q.blue : .white
        super.init()

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: Q.s4, left: Q.s4, bottom: Q.s4, right: Q.s4)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = paper.cgColor
        stack.layer?.cornerRadius = Q.panelRadius
        stack.layer?.borderWidth = Q.hairline
        stack.layer?.borderColor = ink.cgColor

        window.contentView = stack
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "LockShield"

        rebuild()
        window.center()
    }

    func build() {}

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    /// Lays the content out again and resizes the window around its centre.
    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        build()
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(stack.fittingSize)
        if window.isVisible {
            window.setFrameOrigin(NSPoint(x: center.x - window.frame.width / 2, y: center.y - window.frame.height / 2))
        }
    }

    // MARK: Content helpers

    func add(_ view: NSView, gapAfter: CGFloat) {
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(gapAfter, after: view)
    }

    func icon() -> NSImageView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: Q.s6).isActive = true
        icon.heightAnchor.constraint(equalToConstant: Q.s6).isActive = true
        icon.setAccessibilityElement(false) // decorative
        return icon
    }

    func text(_ string: String, size: CGFloat, bold: Bool = false, width: CGFloat = Panel.contentWidth) -> NSTextField {
        let paragraph = NSMutableParagraphStyle()
        // Headings sit tight, body text breathes at the golden ratio.
        let lineHeight = (size * (bold ? 1.2 : 1.618)).rounded()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = NSAttributedString(string: string, attributes: [
            .font: Q.font(size, bold: bold),
            .foregroundColor: bold ? ink : ink.withAlphaComponent(0.84),
            .kern: bold ? -0.03 * size : 0,
            .paragraphStyle: paragraph,
        ])
        label.isSelectable = false
        label.preferredMaxLayoutWidth = width
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    func button(_ label: String, solid: Bool, key: String = "", action: Selector,
                width: CGFloat = Panel.contentWidth) -> PillButton {
        let button = PillButton(label, solid: solid, ink: ink, paper: paper, target: self, action: action)
        button.keyEquivalent = key
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        return button
    }

    /// A text field in the system's form style: 2 pt ink line, 44 pt high, 13 pt radius.
    func field(_ textField: NSTextField, placeholder: String) -> NSView {
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = Q.font(Q.tBody)
        textField.textColor = ink
        textField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: Q.font(Q.tBody), .foregroundColor: ink.withAlphaComponent(0.5),
        ])
        textField.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.borderWidth = Q.line
        box.layer?.borderColor = ink.cgColor
        box.layer?.cornerRadius = Q.fieldRadius
        box.addSubview(textField)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: Q.minTarget),
            box.widthAnchor.constraint(equalToConstant: Panel.contentWidth),
            textField.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: Q.s2),
            textField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -Q.s2),
            textField.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    /// Caption above a control.
    func caption(_ string: String, width: CGFloat = Panel.contentWidth) -> NSTextField {
        text(string, size: Q.tCaption, width: width)
    }

    /// Two or more views side by side across the content width.
    func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Q.s3
        row.widthAnchor.constraint(equalToConstant: Panel.contentWidth).isActive = true
        return row
    }
}

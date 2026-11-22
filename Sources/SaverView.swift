import AppKit

/// The lock screen: a background colour and a clock that moves now and then (avoids burn-in).
/// Reads its look from `Settings` and follows changes live, so it also serves as the preview.
final class SaverView: NSView {
    private let clock = NSTextField(labelWithString: "")
    private let formatter = DateFormatter()
    /// Shrinks the clock for the settings preview; 1 on a real screen.
    private let scale: CGFloat
    private var timers: [Timer] = []
    private var velocity = CGPoint(x: 55, y: 34) // points per second, bounce only
    private var observer: NSObjectProtocol?

    init(frame: NSRect, scale: CGFloat = 1) {
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
        formatter.dateFormat = "HH:mm"
        addSubview(clock)
        observer = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) {
            [weak self] _ in self?.apply()
        }
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        timers.forEach { $0.invalidate() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        clock.setFrameOrigin(clamped(clock.frame.origin))
    }

    /// Applies the current settings and restarts the animation.
    private func apply() {
        let settings = Settings.shared
        layer?.backgroundColor = settings.backgroundColor.cgColor
        clock.font = settings.font(size: settings.fontSize * scale)
        clock.textColor = settings.textColor
        clock.alphaValue = 1
        tick()

        timers.forEach { $0.invalidate() }
        timers = []
        guard window != nil else { return }

        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() })
        switch settings.animation {
        case .drift:
            clock.setFrameOrigin(randomOrigin())
            timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.drift() })
        case .fade:
            clock.setFrameOrigin(randomOrigin())
            timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.fade() })
        case .bounce:
            clock.setFrameOrigin(randomOrigin())
            timers.append(Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.bounce() })
        case .none:
            clock.setFrameOrigin(centredOrigin())
        }
    }

    private func tick() {
        clock.stringValue = formatter.string(from: Date())
        clock.sizeToFit()
        if Settings.shared.animation == .none { clock.setFrameOrigin(centredOrigin()) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func drift() {
        guard !reduceMotion else { clock.setFrameOrigin(randomOrigin()); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 4
            clock.animator().setFrameOrigin(randomOrigin())
        }
    }

    private func fade() {
        guard !reduceMotion else { clock.setFrameOrigin(randomOrigin()); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 1
            clock.animator().alphaValue = 0
        }, completionHandler: { [self] in
            clock.setFrameOrigin(randomOrigin())
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1
                clock.animator().alphaValue = 1
            }
        })
    }

    private func bounce() {
        // Reduce Motion: no continuous movement, behave like Drift instead.
        if reduceMotion {
            if Int(Date().timeIntervalSince1970 * 30) % 900 == 0 { clock.setFrameOrigin(randomOrigin()) }
            return
        }
        var origin = clock.frame.origin
        origin.x += velocity.x * scale / 30
        origin.y += velocity.y * scale / 30
        let limit = clamped(origin)
        if origin.x != limit.x { velocity.x = -velocity.x }
        if origin.y != limit.y { velocity.y = -velocity.y }
        clock.setFrameOrigin(limit)
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, 0), max(bounds.width - clock.frame.width, 0)),
                y: min(max(point.y, 0), max(bounds.height - clock.frame.height, 0)))
    }

    private func randomOrigin() -> NSPoint {
        let maxX = max(bounds.width - clock.frame.width, 0)
        let maxY = max(bounds.height - clock.frame.height, 0)
        return NSPoint(x: .random(in: 0...maxX), y: .random(in: 0...maxY))
    }

    private func centredOrigin() -> NSPoint {
        NSPoint(x: (bounds.width - clock.frame.width) / 2, y: (bounds.height - clock.frame.height) / 2)
    }
}

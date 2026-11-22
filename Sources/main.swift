import AppKit
import ApplicationServices

// MARK: - Configuration

// Settings are read from the app's defaults, so they can be changed without rebuilding:
//   defaults write com.chcorral.lockshield unlockPassword -string "yourword"
//   defaults write com.chcorral.lockshield holdKey -string "c"
//   defaults write com.chcorral.lockshield holdSeconds -float 10
let settings = UserDefaults.standard

/// Typed blind anywhere on the lock screen to unlock. Case-insensitive.
/// Nothing on screen shows that typing is expected or received.
let unlockPassword: String = {
    let configured = settings.string(forKey: "unlockPassword") ?? ""
    return configured.isEmpty ? "unlock" : configured
}()

/// Holding this key down without letting go for this long also unlocks.
let holdToUnlockKey: String = {
    let configured = settings.string(forKey: "holdKey")?.lowercased() ?? ""
    return configured.count == 1 ? configured : "c"
}()
let holdToUnlockSeconds: TimeInterval = settings.object(forKey: "holdSeconds") == nil ? 10 : settings.double(forKey: "holdSeconds")

// MARK: - Password matching

/// Remembers the last few typed characters and reports when they spell the password.
struct PasswordMatcher {
    private let password: [Character]
    private var recent: [Character] = []

    init(password: String) {
        self.password = Array(password.lowercased())
    }

    mutating func feed(_ text: String) -> Bool {
        for character in text.lowercased() {
            recent.append(character)
            if recent.count > password.count { recent.removeFirst() }
            if recent == password { return true }
        }
        return false
    }
}

// MARK: - Lock screen UI

/// Borderless windows refuse key status by default; ours need it to receive typing.
final class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Black screen with a dim clock that drifts to a new spot now and then (avoids burn-in).
final class SaverView: NSView {
    private let clock = NSTextField(labelWithString: "")
    private let formatter = DateFormatter()
    private var tickTimer: Timer?
    private var driftTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        formatter.dateFormat = "HH:mm"
        clock.font = .monospacedDigitSystemFont(ofSize: 96, weight: .ultraLight)
        clock.textColor = NSColor(white: 1, alpha: 0.28)
        addSubview(clock)
        tick()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        tickTimer?.invalidate()
        driftTimer?.invalidate()
        guard window != nil else { return }
        clock.setFrameOrigin(randomOrigin())
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        driftTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.drift() }
    }

    private func tick() {
        clock.stringValue = formatter.string(from: Date())
        clock.sizeToFit()
    }

    private func drift() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 4
            clock.animator().setFrameOrigin(randomOrigin())
        }
    }

    private func randomOrigin() -> NSPoint {
        let maxX = max(bounds.width - clock.frame.width, 0)
        let maxY = max(bounds.height - clock.frame.height, 0)
        return NSPoint(x: .random(in: 0...maxX), y: .random(in: 0...maxY))
    }
}

// MARK: - Quinde Studio UI tokens (Design logic/UI-SYSTEM.md)

enum Q {
    static let blue = NSColor(srgbRed: 16 / 255, green: 48 / 255, blue: 1, alpha: 1) // #1030ff
    // spacing (Fibonacci)
    static let s1: CGFloat = 8, s2: CGFloat = 13, s3: CGFloat = 21, s4: CGFloat = 34, s6: CGFloat = 89
    // type (√φ steps)
    static let tCaption: CGFloat = 13, tBody: CGFloat = 16, tH2: CGFloat = 26
    // shape
    static let panelRadius: CGFloat = 21
    static let hairline: CGFloat = 1, line: CGFloat = 2
    static let minTarget: CGFloat = 44

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

/// Pill button: solid for the one main action of a view, outline for the rest.
/// Hover or press swaps fill and outline.
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

// MARK: - Permission prompt

/// Shown instead of the lock when the Accessibility permission is missing.
/// It notices by itself when the permission arrives, so the app never needs reopening.
final class PermissionPrompt: NSObject {
    enum State: String {
        case permission, ready
    }

    private static let contentWidth: CGFloat = 377

    private let window = BorderlessWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    private let stack = NSStackView()
    private let ink: NSColor
    private let paper: NSColor
    private let onLock: () -> Void
    private var state: State
    private var pollTimer: Timer?

    /// - Parameter polls: false keeps the given state on screen (used by `--preview-prompt`).
    init(state: State, polls: Bool = true, onLock: @escaping () -> Void) {
        self.state = state
        self.onLock = onLock
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

        if polls {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkPermission()
            }
        }
    }

    var windowNumber: Int { window.windowNumber }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func checkPermission() {
        guard state == .permission, AXIsProcessTrusted() else { return }
        state = .ready
        rebuild()
        show()
    }

    // MARK: Content

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: Q.s6).isActive = true
        icon.heightAnchor.constraint(equalToConstant: Q.s6).isActive = true
        icon.setAccessibilityElement(false) // decorative
        add(icon, gapAfter: Q.s3)

        switch state {
        case .permission:
            add(text("Allow LockShield to block input", size: Q.tH2, bold: true), gapAfter: Q.s2)
            add(text("""
                To stop every key and click, switch LockShield on under Privacy & Security › \
                Accessibility. This window notices when you do.
                """, size: Q.tBody), gapAfter: Q.s3)
            add(button("Open settings", solid: true, key: "\r", action: #selector(openSettings)), gapAfter: Q.s2)
            add(button("Lock anyway", solid: false, action: #selector(lockNow)), gapAfter: Q.s2)
            add(button("Quit", solid: false, key: "\u{1b}", action: #selector(quit)), gapAfter: Q.s3)
            add(text("""
                Lock anyway still covers the screen and stops app switching, but some system \
                shortcuts and media keys keep working.
                """, size: Q.tCaption), gapAfter: 0)
        case .ready:
            add(text("Ready to lock", size: Q.tH2, bold: true), gapAfter: Q.s2)
            add(text("""
                The screen goes dark and every key and click is blocked. To unlock, type your \
                password. Nothing on screen will ask for it.
                """, size: Q.tBody), gapAfter: Q.s3)
            add(button("Lock now", solid: true, key: "\r", action: #selector(lockNow)), gapAfter: Q.s2)
            add(button("Quit", solid: false, key: "\u{1b}", action: #selector(quit)), gapAfter: 0)
        }

        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setContentSize(stack.fittingSize)
        if window.isVisible {
            window.setFrameOrigin(NSPoint(x: center.x - window.frame.width / 2, y: center.y - window.frame.height / 2))
        }
    }

    private func add(_ view: NSView, gapAfter: CGFloat) {
        stack.addArrangedSubview(view)
        stack.setCustomSpacing(gapAfter, after: view)
    }

    private func text(_ string: String, size: CGFloat, bold: Bool = false) -> NSTextField {
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
        label.preferredMaxLayoutWidth = Self.contentWidth
        label.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return label
    }

    private func button(_ label: String, solid: Bool, key: String = "", action: Selector) -> PillButton {
        let button = PillButton(label, solid: solid, ink: ink, paper: paper, target: self, action: action)
        button.keyEquivalent = key
        button.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return button
    }

    // MARK: Actions

    @objc private func openSettings() {
        // Lists the app under Accessibility so it only needs switching on.
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func lockNow() {
        pollTimer?.invalidate()
        window.orderOut(nil)
        onLock()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var matcher = PasswordMatcher(password: unlockPassword)
    private var eventTap: CFMachPort?
    private var prompt: PermissionPrompt?
    private var locked = false

    /// Key code of the hold-to-unlock key while it is down, and the timer that unlocks when it fires.
    private var heldKeyCode: UInt16?
    private var holdTimer: Timer?
    private var holdDuration = holdToUnlockSeconds

    /// `--self-test` locks for a moment, types the password itself and exits. Used to verify a build.
    /// `--self-test=hold` unlocks by holding the key instead (with a shortened hold).
    private let selfTest = CommandLine.arguments.contains { $0.hasPrefix("--self-test") }
    private let selfTestHold = CommandLine.arguments.contains("--self-test=hold")

    /// `--preview-prompt=permission` or `=ready` shows that state of the permission prompt.
    private let promptPreview = CommandLine.arguments
        .first { $0.hasPrefix("--preview-prompt=") }
        .flatMap { PermissionPrompt.State(rawValue: String($0.split(separator: "=")[1])) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let promptPreview {
            showPrompt(promptPreview, polls: false)
            print("PREVIEW: window=\(prompt?.windowNumber ?? 0)")
            fflush(stdout)
        } else if selfTest || AXIsProcessTrusted() {
            lock()
            if selfTest { runSelfTest() }
        } else {
            showPrompt(.permission)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        locked ? .terminateCancel : .terminateNow
    }

    private func showPrompt(_ state: PermissionPrompt.State, polls: Bool = true) {
        prompt = PermissionPrompt(state: state, polls: polls) { [weak self] in
            self?.prompt = nil
            self?.lock()
        }
        prompt?.show()
    }

    // MARK: Locking

    private func lock() {
        locked = true
        rebuildWindows()
        NSApp.activate(ignoringOtherApps: true)

        // Kiosk mode: no Dock, menu bar, Cmd-Tab, Mission Control, Force Quit, logout or hide.
        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar, .disableAppleMenu, .disableProcessSwitching,
            .disableForceQuit, .disableSessionTermination, .disableHideApplication,
        ]

        // Freeze and hide the pointer for every mouse and trackpad.
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()

        installEventTap()

        // Fallback for when the event tap is unavailable: events that reach the app are
        // read for the password and then dropped.
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if event.type == .keyDown {
                self?.keyDown(event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode)
            } else if event.type == .keyUp {
                self?.keyUp(keyCode: event.keyCode)
            }
            return nil
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(lostFocus),
                           name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = BorderlessWindow(contentRect: screen.frame, styleMask: .borderless,
                                          backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.contentView = SaverView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func screensChanged() {
        guard locked else { return }
        rebuildWindows()
    }

    @objc private func lostFocus() {
        guard locked else { return }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }

    // MARK: Input blocking

    /// Session-wide tap that sees every input event (built-in, USB and Bluetooth devices
    /// alike) before any app or system shortcut does. Requires Accessibility permission.
    private func installEventTap() {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            return delegate.intercept(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: ~CGEventMask(0),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
    }

    private func intercept(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard locked else { return Unmanaged.passUnretained(event) }

        // The system switches a tap off if it is ever slow; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown {
            var length = 0
            var units = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length,
                                           unicodeString: &units)
            keyDown(String(utf16CodeUnits: units, count: length), keyCode: keyCode)
        } else if type == .keyUp {
            keyUp(keyCode: keyCode)
        }
        return nil // swallow everything
    }

    // MARK: Unlocking

    private func keyDown(_ text: String, keyCode: UInt16) {
        guard locked else { return }
        if matcher.feed(text) {
            unlock()
            return
        }
        // A held key repeats; only its first press starts the countdown.
        if text.lowercased() == holdToUnlockKey, heldKeyCode == nil {
            heldKeyCode = keyCode
            holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
                self?.unlock()
            }
        }
    }

    private func keyUp(keyCode: UInt16) {
        guard keyCode == heldKeyCode else { return }
        heldKeyCode = nil
        holdTimer?.invalidate()
    }

    private func unlock() {
        guard locked else { return }
        locked = false
        holdTimer?.invalidate()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        NSApp.presentationOptions = []
        if selfTest { print("SELF-TEST: unlocked") }
        NSApp.terminate(nil)
    }

    // MARK: Self-test

    private func runSelfTest() {
        print("SELF-TEST: windows=\(windows.count) accessibility=\(AXIsProcessTrusted()) eventTap=\(eventTap != nil) passwordLength=\(unlockPassword.count) holdKey=\(holdToUnlockKey)")
        let cKey: UInt16 = 8
        func type(_ text: String) {
            for character in text {
                keyDown(String(character), keyCode: 0)
                keyUp(keyCode: 0)
            }
        }
        holdDuration = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            type(String(unlockPassword.dropLast()) + "!")
            print("SELF-TEST: still locked after wrong input=\(locked)")
            // A short press of the hold key must not unlock.
            keyDown(holdToUnlockKey, keyCode: cKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [self] in
            keyUp(keyCode: cKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            print("SELF-TEST: still locked after short press=\(locked)")
            if selfTestHold {
                keyDown(holdToUnlockKey, keyCode: cKey)
                keyDown(holdToUnlockKey, keyCode: cKey) // key repeat
                print("SELF-TEST: holding key for \(holdDuration)s")
            } else {
                type("xx" + unlockPassword.uppercased())
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

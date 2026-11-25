import AppKit
import ApplicationServices

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var matcher = PasswordMatcher(password: "")
    private var eventTap: CFMachPort?
    private var startPanel: StartPanel?
    private var settingsPanel: SettingsPanel?
    private var locked = false

    /// Key code of the hold-to-unlock key while it is down, and the timer that unlocks when it fires.
    private var heldKeyCode: UInt16?
    private var holdTimer: Timer?
    private var holdDuration: TimeInterval = 10

    /// Same for the left mouse button: the timer runs while it is down. 0 means off.
    private var mouseHoldTimer: Timer?
    private var mouseHoldDuration: TimeInterval = 3

    /// `--self-test` locks for a moment, types the password itself and exits. Used to verify a build.
    /// `--self-test=hold` unlocks by holding the key instead, `--self-test=mouse` by holding the
    /// mouse button (both with a shortened hold).
    private let selfTest = CommandLine.arguments.contains { $0.hasPrefix("--self-test") }
    private let selfTestHold = CommandLine.arguments.contains("--self-test=hold")
    private let selfTestMouse = CommandLine.arguments.contains("--self-test=mouse")

    /// `--preview=permission`, `=ready` or `=settings` shows that window and keeps it there.
    private let preview = CommandLine.arguments
        .first { $0.hasPrefix("--preview=") }
        .map { String($0.dropFirst("--preview=".count)) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        if let preview {
            var panel: Panel?
            if preview.hasPrefix("settings") {
                openSettings()
                if preview == "settings-editing" { settingsPanel?.previewEditing() }
                panel = settingsPanel
            } else if let state = StartPanel.State(rawValue: preview) {
                showStart(state, polls: false)
                panel = startPanel
            }
            print("PREVIEW: window=\(panel?.window.windowNumber ?? 0)")
            fflush(stdout)
        } else if selfTest {
            lock()
            runSelfTest()
        } else {
            showStart(AXIsProcessTrusted() ? .ready : .permission)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        locked ? .terminateCancel : .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !locked && !flag { showStart(AXIsProcessTrusted() ? .ready : .permission) }
        return false
    }

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About LockShield", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LockShield", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "LockShield", action: nil, keyEquivalent: "").submenu = appMenu

        // Standard editing shortcuts, so they work in the password fields.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        NSApp.mainMenu = main
    }

    // MARK: Windows

    private func showStart(_ state: StartPanel.State, polls: Bool = true) {
        if startPanel == nil || startPanel?.state != state {
            startPanel = StartPanel(state: state, polls: polls, onLock: { [weak self] in
                self?.lock()
            }, onSettings: { [weak self] in
                self?.openSettings()
            })
        }
        startPanel?.show()
    }

    @objc private func openSettings() {
        guard !locked else { return }
        if settingsPanel == nil { settingsPanel = SettingsPanel() }
        settingsPanel?.show()
    }

    // MARK: Locking

    private func lock() {
        locked = true
        matcher = PasswordMatcher(password: Settings.shared.password)
        holdDuration = selfTest ? 1 : Settings.shared.holdSeconds
        mouseHoldDuration = selfTest ? 1 : Settings.shared.mouseHoldSeconds
        settingsPanel?.hide()
        NSColorPanel.shared.orderOut(nil)

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

        if eventTap == nil { installEventTap() }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }

        if localMonitor == nil {
            // Fallback for when the event tap is unavailable: events that reach the app are
            // read for the password and then dropped.
            let mask: NSEvent.EventTypeMask = [
                .keyDown, .keyUp, .flagsChanged, .scrollWheel,
                .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                .otherMouseDown, .otherMouseUp,
            ]
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self, locked else { return event }
                switch event.type {
                case .keyDown: keyDown(event.charactersIgnoringModifiers ?? "", keyCode: event.keyCode)
                case .keyUp: keyUp(keyCode: event.keyCode)
                case .leftMouseDown: mouseDown()
                case .leftMouseUp: mouseUp()
                default: break
                }
                return nil
            }

            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(screensChanged),
                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
            center.addObserver(self, selector: #selector(lostFocus),
                               name: NSApplication.didResignActiveNotification, object: nil)
        }
    }

    private var localMonitor: Any?

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
        eventTap = tap
    }

    private func intercept(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard locked else { return Unmanaged.passUnretained(event) }

        // The system switches a tap off if it is ever slow; switch it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
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
        } else if type == .leftMouseDown {
            mouseDown()
        } else if type == .leftMouseUp {
            mouseUp()
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
        if text.lowercased() == Settings.shared.holdKey, heldKeyCode == nil {
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

    /// The mouse-button hold is the way out when the keyboard is dead. A click or a drag is
    /// shorter than the hold time, so neither unlocks.
    private func mouseDown() {
        guard locked, mouseHoldDuration > 0, mouseHoldTimer == nil else { return }
        mouseHoldTimer = Timer.scheduledTimer(withTimeInterval: mouseHoldDuration, repeats: false) { [weak self] _ in
            self?.unlock()
        }
    }

    private func mouseUp() {
        mouseHoldTimer?.invalidate()
        mouseHoldTimer = nil
    }

    private func unlock() {
        guard locked else { return }
        locked = false
        holdTimer?.invalidate()
        heldKeyCode = nil
        mouseUp()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
        NSApp.presentationOptions = []
        windows.forEach { $0.orderOut(nil) }
        windows = []

        if selfTest {
            print("SELF-TEST: unlocked")
            NSApp.terminate(nil)
        } else {
            showStart(.ready)
        }
    }

    // MARK: Self-test

    private func runSelfTest() {
        let password = Settings.shared.password
        let holdKey = Settings.shared.holdKey
        print("SELF-TEST: windows=\(windows.count) accessibility=\(AXIsProcessTrusted()) eventTap=\(eventTap != nil) passwordLength=\(password.count) holdKey=\(holdKey) mouseHold=\(Settings.shared.mouseHoldSeconds)s")
        let holdKeyCode: UInt16 = 8
        func type(_ text: String) {
            for character in text {
                keyDown(String(character), keyCode: 0)
                keyUp(keyCode: 0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            type(String(password.dropLast()) + "!")
            print("SELF-TEST: still locked after wrong input=\(locked)")
            // A short press of the hold key, and a click, must not unlock.
            keyDown(holdKey, keyCode: holdKeyCode)
            mouseDown()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [self] in
            keyUp(keyCode: holdKeyCode)
            mouseUp()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            print("SELF-TEST: still locked after short press and click=\(locked)")
            if selfTestHold {
                keyDown(holdKey, keyCode: holdKeyCode)
                keyDown(holdKey, keyCode: holdKeyCode) // key repeat
                print("SELF-TEST: holding key for \(holdDuration)s")
            } else if selfTestMouse {
                mouseDown()
                print("SELF-TEST: holding mouse button for \(mouseHoldDuration)s")
            } else {
                type("xx" + password.uppercased())
            }
        }
    }
}

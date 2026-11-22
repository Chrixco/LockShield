import AppKit
import ApplicationServices

/// The window the app opens with. It asks for the Accessibility permission when that is
/// missing (and notices by itself when it arrives), otherwise it offers to lock.
final class StartPanel: Panel {
    enum State: String {
        case permission, ready
    }

    private(set) var state: State
    private let onLock: () -> Void
    private let onSettings: () -> Void
    private var pollTimer: Timer?

    /// - Parameter polls: false keeps the given state on screen (used by `--preview`).
    init(state: State, polls: Bool = true, onLock: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.state = state
        self.onLock = onLock
        self.onSettings = onSettings
        super.init()
        if polls {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkPermission()
            }
        }
    }

    override func build() {
        add(icon(), gapAfter: Q.s3)
        switch state {
        case .permission:
            add(text("Allow LockShield to block input", size: Q.tH2, bold: true), gapAfter: Q.s2)
            add(text("""
                To stop every key and click, switch LockShield on under Privacy & Security › \
                Accessibility. This window notices when you do.
                """, size: Q.tBody), gapAfter: Q.s3)
            add(button("Open settings", solid: true, key: "\r", action: #selector(openSystemSettings)), gapAfter: Q.s2)
            add(button("Lock anyway", solid: false, action: #selector(lock)), gapAfter: Q.s2)
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
            add(button("Lock now", solid: true, key: "\r", action: #selector(lock)), gapAfter: Q.s2)
            add(button("Settings", solid: false, action: #selector(settings)), gapAfter: Q.s2)
            add(button("Quit", solid: false, key: "\u{1b}", action: #selector(quit)), gapAfter: 0)
        }
    }

    private func checkPermission() {
        guard state == .permission, AXIsProcessTrusted() else { return }
        state = .ready
        rebuild()
        show()
    }

    // MARK: Actions

    @objc private func openSystemSettings() {
        // Lists the app under Accessibility so it only needs switching on.
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func lock() {
        hide()
        onLock()
    }

    @objc private func settings() {
        onSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

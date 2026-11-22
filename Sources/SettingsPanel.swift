import AppKit
import LocalAuthentication

/// Settings window. Changes apply at once and are kept in the app's defaults.
/// Changing the unlock password first asks for the Mac's own password or Touch ID.
final class SettingsPanel: Panel {
    private enum PasswordSection {
        case closed, editing, message(String)
    }

    private let settings = Settings.shared
    private var passwordSection = PasswordSection.closed
    private let newPassword = NSSecureTextField()
    private let repeatPassword = NSSecureTextField()
    private let holdKeyField = NSTextField()
    private var holdSlider: NSSlider?
    private let holdValue = NSTextField(labelWithString: "")
    private let sizeValue = NSTextField(labelWithString: "")
    private var preview: SaverView?

    override init() {
        super.init()
        NSColorPanel.shared.showsAlpha = true
    }

    /// Shows the unlock fields without authenticating (used by `--preview=settings-editing`).
    func previewEditing() {
        passwordSection = .editing
        rebuild()
    }

    override func build() {
        add(text("Settings", size: Q.tH2, bold: true), gapAfter: Q.s3)

        // Unlocking: password, hold key and hold time, behind the Mac's own authentication.
        add(caption("Unlocking"), gapAfter: Q.s1)
        switch passwordSection {
        case .closed:
            add(text("""
                Type the password blind on the lock screen, or hold the \(settings.holdKey.uppercased()) key \
                for \(Int(settings.holdSeconds)) seconds. Changing these asks for your Mac password.
                """, size: Q.tBody), gapAfter: Q.s2)
            add(button("Change unlock settings", solid: false, action: #selector(authenticate)), gapAfter: Q.s4)
        case .editing:
            add(field(newPassword, placeholder: "New password (leave empty to keep)"), gapAfter: Q.s2)
            add(field(repeatPassword, placeholder: "Repeat it"), gapAfter: Q.s3)
            add(caption("Hold key (one letter)"), gapAfter: Q.s1)
            holdKeyField.stringValue = settings.holdKey
            add(field(holdKeyField, placeholder: "c"), gapAfter: Q.s3)
            add(caption("Hold time"), gapAfter: Q.s1)
            let slider = NSSlider(value: settings.holdSeconds, minValue: 3, maxValue: 60, target: self,
                                  action: #selector(holdTimeChanged))
            slider.isContinuous = true
            holdSlider = slider
            holdValue.font = Q.font(Q.tCaption)
            holdValue.textColor = ink.withAlphaComponent(0.84)
            holdValue.alignment = .right
            holdValue.widthAnchor.constraint(equalToConstant: Q.s6 / 2).isActive = true
            holdValue.stringValue = "\(Int(settings.holdSeconds)) s"
            add(row([slider, holdValue]), gapAfter: Q.s3)
            add(row([
                button("Save", solid: true, key: "\r", action: #selector(saveUnlockSettings), width: (Panel.contentWidth - Q.s3) / 2),
                button("Cancel", solid: false, key: "\u{1b}", action: #selector(cancelUnlockSettings), width: (Panel.contentWidth - Q.s3) / 2),
            ]), gapAfter: 0)
            return // the lock-screen settings come back after Save or Cancel; both together exceed a laptop screen
        case .message(let message):
            add(text(message, size: Q.tBody), gapAfter: Q.s2)
            add(button("Change unlock settings", solid: false, action: #selector(authenticate)), gapAfter: Q.s4)
        }

        // Lock screen
        add(caption("Font"), gapAfter: Q.s1)
        add(fontPopup(), gapAfter: Q.s3)

        add(caption("Size"), gapAfter: Q.s1)
        let slider = NSSlider(value: settings.fontSize, minValue: 24, maxValue: 240, target: self,
                              action: #selector(sizeChanged))
        slider.isContinuous = true
        sizeValue.font = Q.font(Q.tCaption)
        sizeValue.textColor = ink.withAlphaComponent(0.84)
        sizeValue.alignment = .right
        sizeValue.widthAnchor.constraint(equalToConstant: Q.s6 / 2).isActive = true
        updateSizeValue()
        add(row([slider, sizeValue]), gapAfter: Q.s3)

        let textWell = colorWell(settings.textColor, action: #selector(textColorChanged))
        let backgroundWell = colorWell(settings.backgroundColor, action: #selector(backgroundColorChanged))
        let half = (Panel.contentWidth - Q.s3) / 2
        add(row([caption("Text colour", width: half), caption("Background", width: half)]), gapAfter: Q.s1)
        add(row([textWell, backgroundWell]), gapAfter: Q.s3)

        add(caption("Animation"), gapAfter: Q.s1)
        add(animationPopup(), gapAfter: Q.s3)

        add(caption("Preview"), gapAfter: Q.s1)
        add(previewView(), gapAfter: Q.s4)

        add(button("Done", solid: true, key: "\u{1b}", action: #selector(done)), gapAfter: 0)
    }

    // MARK: Controls

    private func fontPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItem(withTitle: "System")
        popup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        popup.selectItem(withTitle: settings.fontFamily.isEmpty ? "System" : settings.fontFamily)
        popup.target = self
        popup.action = #selector(fontChanged)
        popup.widthAnchor.constraint(equalToConstant: Panel.contentWidth).isActive = true
        return popup
    }

    private func animationPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: Settings.Animation.allCases.map(\.label))
        popup.selectItem(withTitle: settings.animation.label)
        popup.target = self
        popup.action = #selector(animationChanged)
        popup.widthAnchor.constraint(equalToConstant: Panel.contentWidth).isActive = true
        return popup
    }

    private func colorWell(_ color: NSColor, action: Selector) -> NSColorWell {
        let well = NSColorWell()
        well.color = color
        well.target = self
        well.action = action
        well.widthAnchor.constraint(equalToConstant: (Panel.contentWidth - Q.s3) / 2).isActive = true
        well.heightAnchor.constraint(equalToConstant: Q.minTarget).isActive = true
        return well
    }

    /// The lock screen at the size of a hero frame (1.618 : 1), clock scaled to match.
    private func previewView() -> NSView {
        let width = Panel.contentWidth
        let height = (width / 1.618).rounded()
        let scale = width / (NSScreen.main?.frame.width ?? 1512)
        let view = SaverView(frame: NSRect(x: 0, y: 0, width: width, height: height), scale: scale)
        view.layer?.cornerRadius = Q.panelRadius
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = Q.hairline
        view.layer?.borderColor = ink.withAlphaComponent(0.25).cgColor
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        preview = view
        return view
    }

    private func updateSizeValue() {
        sizeValue.stringValue = "\(Int(settings.fontSize)) pt"
    }

    // MARK: Actions

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        settings.fontFamily = sender.indexOfSelectedItem == 0 ? "" : (sender.titleOfSelectedItem ?? "")
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        settings.fontSize = CGFloat(sender.doubleValue.rounded())
        updateSizeValue()
    }

    @objc private func textColorChanged(_ sender: NSColorWell) {
        settings.textColor = sender.color
    }

    @objc private func backgroundColorChanged(_ sender: NSColorWell) {
        settings.backgroundColor = sender.color
    }

    @objc private func animationChanged(_ sender: NSPopUpButton) {
        settings.animation = Settings.Animation.allCases[sender.indexOfSelectedItem]
    }

    @objc private func done() {
        NSColorPanel.shared.orderOut(nil)
        hide()
    }

    // MARK: Password

    /// Asks macOS to confirm the user (Touch ID or the account password) before the fields appear.
    @objc private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            passwordSection = .message("Your Mac cannot confirm who you are right now, so the password stays as it is.")
            rebuild()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "change the unlock password") {
            [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.newPassword.stringValue = ""
                self.repeatPassword.stringValue = ""
                self.passwordSection = success ? .editing : .closed
                self.rebuild()
                if success { self.window.makeFirstResponder(self.newPassword) }
            }
        }
    }

    @objc private func holdTimeChanged(_ sender: NSSlider) {
        holdValue.stringValue = "\(Int(sender.doubleValue.rounded())) s"
    }

    @objc private func saveUnlockSettings() {
        let password = newPassword.stringValue
        let key = holdKeyField.stringValue.lowercased()
        guard key.count == 1, key.first?.isLetter == true || key.first?.isNumber == true else {
            passwordSection = .message("The hold key must be a single letter or digit.")
            return rebuild()
        }
        if !password.isEmpty {
            guard password.count >= 4 else {
                passwordSection = .message("Use at least 4 characters for the password.")
                return rebuild()
            }
            guard password == repeatPassword.stringValue else {
                passwordSection = .message("The two password entries differ. Try again.")
                return rebuild()
            }
            settings.password = password
        }
        settings.holdKey = key
        settings.holdSeconds = (holdSlider?.doubleValue ?? settings.holdSeconds).rounded()
        passwordSection = .message(password.isEmpty ? "Unlock settings saved." : "Password and unlock settings saved.")
        rebuild()
    }

    @objc private func cancelUnlockSettings() {
        passwordSection = .closed
        rebuild()
    }
}

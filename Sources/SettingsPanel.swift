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
    private let sizeValue = NSTextField(labelWithString: "")
    private var preview: SaverView?

    override init() {
        super.init()
        NSColorPanel.shared.showsAlpha = true
    }

    override func build() {
        add(text("Settings", size: Q.tH2, bold: true), gapAfter: Q.s3)

        // Password
        add(caption("Unlock password"), gapAfter: Q.s1)
        switch passwordSection {
        case .closed:
            add(text("Typed blind on the lock screen. Changing it asks for your Mac password.", size: Q.tBody),
                gapAfter: Q.s2)
            add(button("Change password", solid: false, action: #selector(authenticate)), gapAfter: Q.s4)
        case .editing:
            add(field(newPassword, placeholder: "New password"), gapAfter: Q.s2)
            add(field(repeatPassword, placeholder: "Repeat it"), gapAfter: Q.s2)
            add(row([
                button("Save", solid: true, key: "\r", action: #selector(savePassword), width: (Panel.contentWidth - Q.s3) / 2),
                button("Cancel", solid: false, action: #selector(cancelPassword), width: (Panel.contentWidth - Q.s3) / 2),
            ]), gapAfter: Q.s4)
        case .message(let message):
            add(text(message, size: Q.tBody), gapAfter: Q.s2)
            add(button("Change password", solid: false, action: #selector(authenticate)), gapAfter: Q.s4)
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

    @objc private func savePassword() {
        let password = newPassword.stringValue
        guard password.count >= 4 else {
            passwordSection = .message("Use at least 4 characters.")
            return rebuild()
        }
        guard password == repeatPassword.stringValue else {
            passwordSection = .message("The two entries differ. Try again.")
            return rebuild()
        }
        settings.password = password
        passwordSection = .message("Password changed.")
        rebuild()
    }

    @objc private func cancelPassword() {
        passwordSection = .closed
        rebuild()
    }
}

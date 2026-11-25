import AppKit

/// Everything the user can change. Stored in the app's defaults, so
/// `defaults write com.chcorral.lockshield <key> ...` works as well as the Settings window.
final class Settings {
    static let shared = Settings()

    /// Posted after any change; the lock screen and the settings preview re-read the values.
    static let changed = Notification.Name("LockShieldSettingsChanged")

    enum Animation: String, CaseIterable {
        case drift, fade, bounce, none

        var label: String {
            switch self {
            case .drift: return "Drift"
            case .fade: return "Fade"
            case .bounce: return "Bounce"
            case .none: return "None"
            }
        }
    }

    private let defaults = UserDefaults.standard

    private init() {}

    /// Typed blind on the lock screen to unlock. Case-insensitive.
    var password: String {
        get {
            let value = defaults.string(forKey: "unlockPassword") ?? ""
            return value.isEmpty ? "unlock" : value
        }
        set { set(newValue, forKey: "unlockPassword") }
    }

    /// Holding this key down without letting go for `holdSeconds` also unlocks.
    var holdKey: String {
        get {
            let value = (defaults.string(forKey: "holdKey") ?? "").lowercased()
            return value.count == 1 ? value : "c"
        }
        set { set(newValue, forKey: "holdKey") }
    }

    var holdSeconds: TimeInterval {
        get { defaults.object(forKey: "holdSeconds") == nil ? 10 : defaults.double(forKey: "holdSeconds") }
        set { set(newValue, forKey: "holdSeconds") }
    }

    /// Holding the left mouse (or trackpad) button down this long also unlocks, for when the
    /// keyboard is dead. 0 switches it off.
    var mouseHoldSeconds: TimeInterval {
        get { defaults.object(forKey: "mouseHoldSeconds") == nil ? 3 : defaults.double(forKey: "mouseHoldSeconds") }
        set { set(newValue, forKey: "mouseHoldSeconds") }
    }

    /// Font family of the clock; empty means the system font.
    var fontFamily: String {
        get { defaults.string(forKey: "fontFamily") ?? "" }
        set { set(newValue, forKey: "fontFamily") }
    }

    var fontSize: CGFloat {
        get {
            let value = defaults.double(forKey: "fontSize")
            return value > 0 ? value : 96
        }
        set { set(Double(newValue), forKey: "fontSize") }
    }

    var backgroundColor: NSColor {
        get { color(forKey: "backgroundColor") ?? .black }
        set { set(newValue.hexString, forKey: "backgroundColor") }
    }

    var textColor: NSColor {
        get { color(forKey: "textColor") ?? NSColor(white: 1, alpha: 0.28) }
        set { set(newValue.hexString, forKey: "textColor") }
    }

    var animation: Animation {
        get { Animation(rawValue: defaults.string(forKey: "animation") ?? "") ?? .drift }
        set { set(newValue.rawValue, forKey: "animation") }
    }

    func font(size: CGFloat) -> NSFont {
        if !fontFamily.isEmpty,
           let font = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size) {
            return font
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .ultraLight)
    }

    private func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Settings.changed, object: self)
    }

    private func color(forKey key: String) -> NSColor? {
        defaults.string(forKey: key).flatMap(NSColor.init(hexString:))
    }
}

extension NSColor {
    /// `#rrggbbaa` in sRGB.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
        return String(format: "#%02x%02x%02x%02x", channel(color.redComponent), channel(color.greenComponent),
                      channel(color.blueComponent), channel(color.alphaComponent))
    }

    /// Reads `#rrggbb` or `#rrggbbaa`.
    convenience init?(hexString: String) {
        var digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        if digits.count == 6 { digits += "ff" }
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 24) & 0xff) / 255, green: CGFloat((value >> 16) & 0xff) / 255,
                  blue: CGFloat((value >> 8) & 0xff) / 255, alpha: CGFloat(value & 0xff) / 255)
    }
}

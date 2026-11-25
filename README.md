# LockShield

A small macOS app that makes your Mac ignore every keyboard, mouse and trackpad until you type a hidden password. For cleaning the keyboard, leaving a toddler or a cat near the desk, or showing something on screen that nobody should be able to touch.

While it runs:

- every display is covered in black with a dim clock that drifts to avoid burn-in,
- the pointer is hidden and frozen,
- all keyboard, mouse and trackpad input is swallowed, including Bluetooth devices,
- the Dock, menu bar, Cmd-Tab, Mission Control, Force Quit and logout are disabled.

Nothing on screen asks for a password. To unlock, type it blind, anywhere, or hold the `c` key for ten seconds. If the keyboard is dead, hold the left mouse or trackpad button for three seconds.

## Install

Requires macOS 12 or later and Xcode (for `swiftc`).

```sh
git clone https://github.com/chrixco/LockShield.git
cd LockShield
./build.sh
cp -R build/LockShield.app /Applications/
```

On first launch LockShield asks for the Accessibility permission. Click **Open settings**, switch LockShield on under *Privacy & Security › Accessibility*, and the window changes to **Ready to lock** by itself. Without the permission you can still choose **Lock anyway**: the screen is covered and app switching is disabled, but some system shortcuts and media keys get through.

From then on the app opens on **Ready to lock**: press Return (or **Lock now**) to lock. After unlocking it returns to that window.

## Settings

Open **Settings** from the start window or with ⌘, in the menu bar.

- **Unlocking.** The password (default `unlock`; change it before you rely on the app), the hold-to-unlock key (one letter or digit, default `c`) and its hold time (3–60 s, default 10), and the mouse-button hold time (0–30 s, default 3; 0 switches it off). Changing any of them asks for your Mac password or Touch ID first. Typing on the lock screen is case-insensitive, so Caps Lock doesn't matter, and after a typo you just type the word again.
- **Lock screen.** Font, size, text colour, background colour and the clock's animation (drift, fade, bounce or none), with a live preview. Reduce Motion in macOS turns the movement into plain jumps.

Everything is stored in the app's defaults, so it can also be set from the terminal (a very long `holdSeconds` disables the hold):

```sh
defaults write com.chcorral.lockshield unlockPassword -string "yourword"
defaults write com.chcorral.lockshield holdKey -string "c"
defaults write com.chcorral.lockshield holdSeconds -float 10
defaults write com.chcorral.lockshield mouseHoldSeconds -float 3   # 0 = off
defaults write com.chcorral.lockshield fontFamily -string "Avenir Next"
defaults write com.chcorral.lockshield fontSize -float 96
defaults write com.chcorral.lockshield textColor -string "#ffffff48"
defaults write com.chcorral.lockshield backgroundColor -string "#000000"
defaults write com.chcorral.lockshield animation -string drift   # drift, fade, bounce, none
```

## If you are locked out

- Keyboard dead? Hold the left mouse or trackpad button for three seconds, or plug in any other keyboard: LockShield reads them all.
- Hold the power button to force the Mac off. No app can block that.
- From another machine: `ssh you@your-mac killall LockShield`.
- Pressing the power button or Touch ID briefly brings up the normal macOS lock screen, which also works as usual.

## What it is not

LockShield stops casual interaction. It is not a security boundary and not a replacement for the macOS lock screen: anyone who knows the password, holds `c` for ten seconds or holds the mouse button for three, gets in, and the password is stored in plain text in the app's preferences (the Mac-password check in Settings guards the window, not the preference file).

## Build and test

```sh
./build.sh                                   # builds build/LockShield.app
build/LockShield.app/Contents/MacOS/LockShield --self-test        # locks for ~3 s, unlocks with the password
build/LockShield.app/Contents/MacOS/LockShield --self-test=hold   # same, unlocks by holding the key
build/LockShield.app/Contents/MacOS/LockShield --self-test=mouse  # same, unlocks by holding the mouse button
build/LockShield.app/Contents/MacOS/LockShield --preview=permission   # shows a window: permission, ready or settings
```

`build.sh` signs with an Apple Development certificate when one is in the keychain, so macOS keeps the Accessibility permission across rebuilds. With an ad-hoc signature the permission has to be granted again after each build.

## How it works

- `NSApplication.presentationOptions` kiosk mode hides the Dock and menu bar and disables process switching, Force Quit and session termination.
- A session-wide `CGEventTap` sees every input event before any app or system shortcut does and swallows it, reading key presses for the password. This is what needs the Accessibility permission.
- A local event monitor is the fallback when the tap is unavailable.
- `CGAssociateMouseAndMouseCursorPosition(0)` freezes the pointer.

The icon and the first-run window follow the Quinde Studio design system; `Icon/make_icon.swift` draws the mark on a Fibonacci lattice and regenerates `AppIcon.icns`.

## License

MIT, see [LICENSE](LICENSE).

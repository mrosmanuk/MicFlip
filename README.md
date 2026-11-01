# MicFlip

**Flip your mic on or off instantly**

MicFlip is a lightweight, cross-platform tray/menu-bar utility for toggling your
microphone with a global hotkey. It mutes at the **OS level**, so it works no
matter which app is in focus, whether Google Meet, Teams, Zoom, or anything
else. No more hunting for the mute button

Built with [Tauri](https://tauri.app), a tiny Rust core with per-OS audio
backends and a web UI. One codebase, three platforms

## Platforms

| Platform | Mute backend | Status |
|---|---|---|
| **macOS** 11+ | CoreAudio (volume to 0 + mute flag) | Working and tested |
| **Windows** 10+ | WASAPI `IAudioEndpointVolume` | Implemented, needs testing on Windows |
| **Linux** | PulseAudio / PipeWire via `pactl` | Implemented, needs testing on Linux |

## Features

- **Global hotkey** to toggle mute from anywhere (default ⌘/Ctrl + Shift + M), re-bindable in Settings
- **OS-level mute** that silences the input device itself, so every app gets true silence
- **Vibrant tray badge**, a red **LIVE** when the mic is on, grayed out when muted
- **Notification toggles** for sound, the on-screen HUD, and device-switch popups, each independently switchable
- **Device-switch hotkeys** that jump straight to a chosen input or output device
- **Fast input device switching** and **per-device input volume**
- **Buy me a beer 🍺**, an optional donation link in Settings and the About panel

## Build and run

You need [Rust](https://rustup.rs) and the
[Tauri CLI](https://tauri.app) (`cargo install tauri-cli --version "^2"`).
Linux also needs the system deps listed in
[`.github/workflows/release.yml`](.github/workflows/release.yml)

```bash
cargo tauri dev      # run in development
cargo tauri build    # produce a release bundle/installer for the current OS
```

The macOS bundle lands at
`src-tauri/target/release/bundle/macos/MicFlip.app`

### macOS signing (dev)

So macOS privacy grants survive rebuilds, sign with a stable self-signed
identity once

```bash
reference/macos-swift/setup-signing.sh   # creates a "MicFlip Dev" identity
codesign --force --deep --sign "MicFlip Dev" \
  src-tauri/target/release/bundle/macos/MicFlip.app
```

## Releases (all platforms)

Pushing a tag like `v1.0.0` triggers
[`.github/workflows/release.yml`](.github/workflows/release.yml), which builds
macOS (Intel + Apple Silicon), Windows, and Linux on GitHub's runners and
attaches the installers to a draft GitHub Release

> The macOS build is signed with a local self-signed cert, so downloaders hit
> Gatekeeper ("unidentified developer") and need to right-click then Open. For a
> public release, sign with a Developer ID certificate and notarize

## Project layout

```
src-tauri/            Rust core + Tauri app
  src/main.rs         Tray, global shortcut, commands, settings
  src/audio/          Cross-platform mic control
    mod.rs            Shared mute strategy (volume-zero + mute flag)
    macos.rs          CoreAudio (raw FFI)
    windows.rs        WASAPI
    linux.rs          pactl
ui/                   Web UI (vanilla HTML/CSS/JS, no bundler)
reference/macos-swift/  Original native-Swift macOS prototype (kept as reference)
```

## License

MicFlip is free software released under the **MIT License**, see [LICENSE](LICENSE)

© 2026 Maksim Rosmanuk

## Support, buy me a beer 🍺

MicFlip is free. If it's saved you from an awkward hot-mic moment, you can chip
in at **[paypal.me/rosmanuk](https://paypal.me/rosmanuk)**

# Blabla

On-device speech transcription as a macOS Menu Bar app. Press a hotkey, speak, and your words are instantly inserted into any text field — without anything leaving your device.

## Requirements

- macOS 26+

## Installation

1. Download `Blabla.zip` from the [latest release](../../releases/latest)
2. Unzip and move `Blabla.app` to your `/Applications` folder
3. Open the app

**Note:** Because Blabla is not notarized, macOS will block it on first launch. To allow it:

- Go to **System Settings → Privacy & Security**
- Scroll down and click **"Open Anyway"** next to the Blabla entry

You only need to do this once.

## Usage

- **Push-to-talk:** Hold `Fn` while speaking — text is inserted when you release
- **Toggle mode:** Press `Fn` once to start, press again to stop and insert
- Configure the hotkey and behavior from the menu bar icon

---

## For Developers

### Requirements

- macOS 26+
- Xcode with Swift 6.2 toolchain

### Getting started

```bash
git clone <repo-url>
cd Blabla
make open
```

### Make commands

| Command | Description |
|---|---|
| `make build` | Build the app (debug) via `swift build` |
| `make run` | Run directly (debug build, no `.app` bundle) |
| `make open` | Open the project in Xcode via `Package.swift` |
| `make clean` | Clean build artifacts |

### Releases

Releases are built automatically via GitHub Actions when a tag is pushed:

```bash
git tag v1.0.5
git push origin v1.0.5
```

This builds an unsigned `.app`, zips it, and attaches it to the GitHub release.

### Project structure

```
Blabla/
├── Sources/Blabla/
│   ├── App/          # App entry point & state
│   ├── Models/       # Data models
│   ├── Services/     # Business logic / transcription services
│   ├── Views/        # SwiftUI views
│   └── YapSources/   # Transcription engine (see credits)
├── Package.swift
└── Makefile
```

### Credits

The transcription engine (`TranscriptionEngine`, `OutputFormat`, `AttributedString+Extensions`) is based on [yap](https://github.com/finnvoor/yap) by [Finn Voorhees](https://github.com/finnvoor).

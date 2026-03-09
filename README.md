# Blabla

On-device speech transcription as a macOS Menu Bar app.

## Requirements

- macOS 26+
- Xcode with Swift 6.2 toolchain

## Getting started

```bash
git clone <repo-url>
cd Blabla
make open
```

## Make commands

| Command | Description |
|---|---|
| `make build` | Build the app (debug) via `swift build` |
| `make run` | Run directly (debug build, no `.app` bundle) |
| `make open` | Open the project in Xcode via `Package.swift` |
| `make clean` | Clean build artifacts |

## Project structure

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

## Credits

The transcription engine (`TranscriptionEngine`, `OutputFormat`, `AttributedString+Extensions`) is based on [yap](https://github.com/finnvoor/yap) by [Finn Voorhees](https://github.com/finnvoor).

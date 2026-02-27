# YapMenuBar

On-device speech transcription as a macOS Menu Bar app.

The core transcription engine is pulled directly from the [yap](https://github.com/finnvoor/yap) git submodule via symlinks — no forking, no copying.

## Requirements

- macOS 26+
- Xcode with Swift 6.2 toolchain

## Getting started

```bash
git clone <repo-url>
cd YapMenuBar
make setup
make open
```

## Make commands

| Command | Description |
|---|---|
| `make setup` | First-time setup after `git clone` — initializes submodules |
| `make build` | Build the app (debug) via `swift build` |
| `make run` | Run directly (debug build, no `.app` bundle) |
| `make open` | Open the project in Xcode via `Package.swift` |
| `make update-yap` | Pull latest changes from the yap upstream repo |
| `make clean` | Clean build artifacts |

## Project structure

```
YapMenuBar/
├── Sources/YapMenuBar/
│   ├── App/          # App entry point
│   ├── Models/       # Data models
│   ├── Services/     # Business logic / transcription services
│   ├── Views/        # SwiftUI views
│   └── YapSources/   # Symlinks into the yap submodule
├── yap/              # Git submodule (finnvoor/yap)
├── Package.swift
└── Makefile
```

## Updating yap

The transcription core (`TranscriptionEngine`, `OutputFormat`, `AttributedString+Extensions`) lives in the `yap` submodule. To pull upstream changes:

```bash
make update-yap
make build
```

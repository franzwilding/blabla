# YapMenuBar — common development tasks

.PHONY: build run update-yap open clean

## Build the app (debug)
build:
	swift build

## Run directly (debug build, no .app bundle)
run:
	swift run YapMenuBar

## Pull latest changes from the yap upstream repo
update-yap:
	git submodule update --remote yap
	@echo "yap updated. Run 'make build' to recompile."

## Open the project in Xcode (via Package.swift)
open:
	open Package.swift

## Clean build artifacts
clean:
	swift package clean

## First-time setup after git clone
setup:
	git submodule update --init --recursive
	@echo "Submodules initialized. Run 'make open' to open in Xcode."

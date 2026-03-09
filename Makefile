# Blabla — common development tasks

.PHONY: build run open clean test

## Build the app (debug)
build:
	swift build

## Run directly (debug build, no .app bundle)
run:
	swift run Blabla

## Open the project in Xcode (via Package.swift)
open:
	open Package.swift

## Run tests
test:
	swift test

## Clean build artifacts
clean:
	swift package clean

import AppKit
import Combine
import SwiftUI

/// A floating, click-through overlay at the top of the screen that shows
/// the live transcription text scrolling from right to left.
@MainActor
final class LiveTextOverlayController {

    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    func attach(to appState: AppState) {
        cancellable = appState.$liveText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self?.hideOverlay()
                } else {
                    self?.showOverlay(text: text)
                }
            }
    }

    private func showOverlay(text: String) {
        guard let screen = NSScreen.main else { return }

        if window == nil {
            let w = NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.level = .statusBar
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window = w
        }

        guard let window else { return }

        let height: CGFloat = 22
        let screenFrame = screen.frame
        let menuBarHeight = screen.frame.height - screen.visibleFrame.height - screen.visibleFrame.origin.y
        let y = screenFrame.maxY - menuBarHeight - height

        window.setFrame(
            NSRect(x: screenFrame.origin.x, y: y, width: screenFrame.width, height: height),
            display: false
        )

        let singleLine = text
            .components(separatedBy: .newlines)
            .joined(separator: " — ")

        let hostView = NSHostingView(rootView:
            ScrollingTextView(text: singleLine)
        )
        window.contentView = hostView
        window.orderFront(nil)
    }

    private func hideOverlay() {
        window?.orderOut(nil)
    }
}

// MARK: - ScrollingTextView

private struct ScrollingTextView: View {
    let text: String

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                        containerWidth = geo.size.width
                        startScrolling()
                    }
                    .onChange(of: text) {
                        textWidth = textGeo.size.width
                        offset = containerWidth
                        startScrolling()
                    }
                })
                .offset(x: offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }

    private func startScrolling() {
        offset = containerWidth
        let totalDistance = containerWidth + textWidth
        let duration = Double(totalDistance) / 80.0 // 80 points per second

        withAnimation(.linear(duration: duration)) {
            offset = -textWidth
        }
    }
}

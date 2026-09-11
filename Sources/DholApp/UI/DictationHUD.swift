import AppKit
import Combine
import SwiftUI

/// A small floating readout near the bottom of the screen, so you can tell at a
/// glance whether Dhol is listening without looking away from what you're typing
/// into.
@MainActor
final class DictationHUD {
    fileprivate static let size = NSSize(width: 178, height: 44)

    private let panel: NSPanel
    private var observer: AnyCancellable?

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: DictationHUDView(controller: controller))

        observer = controller.$phase.sink { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .listening, .transcribing:
                reposition()
                panel.orderFrontRegardless()
            case .ready, .preparing, .failed:
                panel.orderOut(nil)
            }
        }
    }

    /// Anchors to the screen the pointer is on, which is the one the user is
    /// working on when several are connected.
    private func reposition() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.minY + 56
            )
        )
    }
}

private struct DictationHUDView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 10) {
            if controller.phase == .listening {
                LevelRing(level: controller.inputLevel)
                    .frame(width: 16, height: 16)
                Text("Listening")
            } else {
                ProgressView().controlSize(.small)
                Text("Transcribing")
            }
        }
        .font(.system(.callout, design: .rounded, weight: .semibold))
        .frame(width: DictationHUD.size.width, height: DictationHUD.size.height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.16))
        }
    }
}

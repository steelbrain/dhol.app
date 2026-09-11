import SwiftUI

/// Shows the dictation shortcut and starts a capture when clicked.
///
/// The capture itself lives on the controller, which owns the key monitor and
/// can be told to stop by whatever closes the window.
struct ShortcutRecorderField: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Button {
            if controller.isCapturingShortcut {
                controller.endShortcutCapture()
            } else {
                controller.beginShortcutCapture()
            }
        } label: {
            Text(controller.isCapturingShortcut ? "Press keys…" : controller.hotKey.displayName)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(minWidth: 124)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .tint(controller.isCapturingShortcut ? .accentColor : .secondary)
        .help(controller.isCapturingShortcut ? "Press Escape to cancel" : "Change the dictation shortcut")
    }
}

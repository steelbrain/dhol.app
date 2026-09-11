import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DictationController

    private static let accent = Color(red: 0.91, green: 0.38, blue: 0.17)

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                status
                SettingsSection("Dictation") {
                    SettingsRow("Shortcut", detail: shortcutDetail) {
                        ShortcutRecorderField(controller: controller)
                    }
                    Divider().opacity(0.5)
                    SettingsRow("Start at login", detail: loginDetail) {
                        HStack(spacing: 8) {
                            if controller.loginItemNeedsApproval {
                                Button("Approve…", action: controller.openLoginItemSettings)
                            }
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { controller.startsAtLogin },
                                    set: controller.setStartsAtLogin
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                    }
                }
                SettingsSection("Permissions") {
                    PermissionRow(
                        title: "Microphone",
                        detail: "To hear what you say.",
                        granted: controller.microphoneGranted,
                        action: controller.requestMicrophone
                    )
                    Divider().opacity(0.5)
                    PermissionRow(
                        title: "Accessibility",
                        detail: "To type into the app you're using.",
                        granted: controller.accessibilityGranted,
                        action: controller.requestAccessibility
                    )
                }
                footer
            }
            .padding(26)
        }
        .frame(width: 520, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dhol")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Speak, and it types.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            statusIndicator
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                if let detail = statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if case .failed = controller.phase {
                Button("Dismiss", action: controller.dismissFailure)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch controller.phase {
        case .listening:
            LevelRing(level: controller.inputLevel, color: .red)
                .frame(width: 22, height: 22)
        case .preparing, .transcribing:
            ProgressView().controlSize(.small).frame(width: 22)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 22)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Self.accent)
                .frame(width: 22)
        }
    }

    private var statusTitle: String {
        if case .ready = controller.phase {
            return "Ready — hold \(controller.hotKey.displayName)"
        }
        return controller.phase.title
    }

    private var statusDetail: String? {
        if case .ready = controller.phase {
            return "Your voice never leaves this Mac."
        }
        return controller.phase.detail
    }

    private var statusTint: Color {
        switch controller.phase {
        case .failed: Color.orange.opacity(0.1)
        case .listening: Color.red.opacity(0.08)
        default: Color.primary.opacity(0.04)
        }
    }

    private var shortcutDetail: String {
        controller.shortcutProblem ?? "Hold it down, speak, let go."
    }

    private var loginDetail: String {
        if let problem = controller.loginItemProblem {
            return "Couldn't update Login Items: \(problem)"
        }
        return controller.loginItemNeedsApproval
            ? "Waiting for approval in System Settings."
            : "Keep Dhol in the menu bar, ready to go."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Text("Made by Anees Iqbal")
                Spacer(minLength: 12)
                Link(
                    "github.com/steelbrain/dhol.app",
                    destination: URL(string: "https://github.com/steelbrain/dhol.app")!
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Version \(version)")
                Spacer(minLength: 12)
                Text(controller.modelID).monospaced()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            VStack(spacing: 12) {
                content
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4))
            }
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(_ title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            content
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Fixed width so the titles line up whatever the glyph, and at the
            // same indent as the status card's indicator above.
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 15))
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Allow…", action: action)
            }
        }
    }
}

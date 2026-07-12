import AppKit
import SwiftUI

enum VoiceStatus: Equatable {
    case recording
    case transcribing
    case polishing
    case inserting
    case preview(String)
    case error(String)

    var title: String {
        switch self {
        case .recording: return "正在听写…"
        case .transcribing: return "正在转写…"
        case .polishing: return "正在整理文字…"
        case .inserting: return "正在输入…"
        case .preview: return "确认听写结果"
        case .error: return "听写失败"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "waveform"
        case .transcribing: return "text.bubble"
        case .polishing: return "sparkles"
        case .inserting: return "keyboard"
        case .preview: return "checkmark.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }
}

@MainActor
final class VoiceStatusOverlayController {
    private var panel: NSPanel?

    func show(
        _ status: VoiceStatus,
        onConfirm: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        close()
        let isPreview: Bool
        if case .preview = status { isPreview = true } else { isPreview = false }
        let size = isPreview ? NSSize(width: 420, height: 220) : NSSize(width: 210, height: 62)
        let view = VoiceStatusView(
            status: status,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: isPreview ? [.titled, .fullSizeContentView] : [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        position(panel, size: size)
        if isPreview {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 72
        ))
    }
}

private struct VoiceStatusView: View {
    let status: VoiceStatus
    let onConfirm: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        Group {
            switch status {
            case .preview(let text):
                VStack(alignment: .leading, spacing: 12) {
                    Label(status.title, systemImage: status.symbol).font(.headline)
                    ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Spacer()
                        Button("取消") { onCancel?() }
                        Button("插入") { onConfirm?() }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
            case .error(let message):
                HStack(spacing: 10) {
                    Image(systemName: status.symbol).foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(status.title).font(.headline)
                        Text(message).font(.caption).lineLimit(2)
                    }
                }
                .padding(12)
            default:
                HStack(spacing: 10) {
                    Image(systemName: status.symbol).foregroundStyle(.tint)
                    Text(status.title).font(.headline)
                    if status != .recording { ProgressView().controlSize(.small) }
                }
                .padding(12)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

//
//  FloatingPanelController.swift
//  Flick
//

import AppKit
import SwiftUI

/// Custom NSPanel that can become key window to receive keyboard events
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class FloatingPanelController {
    private var panel: NSPanel?
    private var monitor: Any?

    func show(at point: NSPoint, with selectedText: String) {
        close()

        let prompts = SettingsManager.shared.customPrompts
        // Compact size: prompt list + custom input field
        let listHeight = CGFloat(50 + prompts.count * 38 + 64)
        let panelWidth: CGFloat = 320
        let panelHeight = min(listHeight, 360)

        let aiService = AIService()
        let view = PresetPromptView(
            selectedText: selectedText,
            aiService: aiService,
            onClose: { [weak self] in self?.close() },
            onResize: { [weak self] size in
                self?.resizePanel(to: size)
            }
        )

        let hostingView = NSHostingView(rootView: view)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true

        // Position near mouse cursor
        let panelOrigin = NSPoint(
            x: point.x - panelWidth / 2,
            y: point.y - panelHeight - 10
        )
        panel.setFrameOrigin(panelOrigin)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func resizePanel(to size: NSSize) {
        guard let panel else { return }
        let frame = panel.frame
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y + frame.height - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(newFrame, display: true, animate: true)
    }
}

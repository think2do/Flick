//
//  AppDelegate.swift
//  Flick
//

import AppKit
import Carbon
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: GlobalHotkeyManager?
    private let floatingPanel = FloatingPanelController()
    private let voiceDictation = VoiceDictationCoordinator()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        setupHotkey()
        checkAccessibilityPermission()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Flick")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Flick", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotkey() {
        let manager = GlobalHotkeyManager()
        manager.register(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(cmdKey),
            onPressed: { [weak self] in self?.handleHotkeyTriggered() }
        )
        manager.register(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(cmdKey | shiftKey),
            onPressed: { [weak self] in self?.voiceDictation.startRecording() },
            onReleased: { [weak self] in self?.voiceDictation.stopRecording() }
        )
        hotkeyManager = manager
        hotkeyManager?.start()
    }

    private func handleHotkeyTriggered() {
        SelectionReader.getSelectedText { [weak self] text in
            guard let self, let text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                let mouseLocation = NSEvent.mouseLocation
                self.floatingPanel.show(at: mouseLocation, with: text)
            }
        }
    }

    @objc private func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Flick 设置"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkAccessibilityPermission() {
        let trusted = TextInjector.ensureAccessibilityPermission()
        if !trusted {
            print("Accessibility permission not granted. System prompt shown.")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

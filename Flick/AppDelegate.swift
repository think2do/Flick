//
//  AppDelegate.swift
//  Flick
//

import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: GlobalHotkeyManager?
    private let floatingPanel = FloatingPanelController()
    private let voiceDictation = VoiceDictationCoordinator()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        setupHotkey()
        observeHotkeyChanges()
        checkAccessibilityPermission()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Flick")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Flick", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotkey() {
        hotkeyManager?.stop()
        let settings = SettingsManager.shared
        let manager = GlobalHotkeyManager()
        if settings.selectionHotkeyConfig.isFunctionKey {
            manager.registerFunctionKey { [weak self] in self?.handleHotkeyTriggered() }
        } else {
            manager.register(
                keyCode: settings.selectionHotkeyConfig.keyCode,
                modifiers: settings.selectionHotkeyConfig.modifiers,
                onPressed: { [weak self] in self?.handleHotkeyTriggered() }
            )
        }
        for profile in settings.voiceDictationProfiles {
            if profile.hotkey.isFunctionKey {
                manager.registerFunctionKey { [weak self] in
                    self?.voiceDictation.toggleRecording(profile: profile)
                }
            } else {
                manager.register(
                    keyCode: profile.hotkey.keyCode,
                    modifiers: profile.hotkey.modifiers,
                    onPressed: { [weak self] in
                        self?.voiceDictation.startRecording(profile: profile)
                    },
                    onReleased: { [weak self] in
                        self?.voiceDictation.stopRecording(profileID: profile.id)
                    }
                )
            }
        }
        hotkeyManager = manager
        hotkeyManager?.start()
    }

    private func observeHotkeyChanges() {
        SettingsManager.shared.$selectionHotkeyConfig
            .combineLatest(SettingsManager.shared.$voiceDictationProfiles)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.setupHotkey() }
            .store(in: &cancellables)
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
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Flick 设置"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
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

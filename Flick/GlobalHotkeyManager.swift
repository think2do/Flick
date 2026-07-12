//
//  GlobalHotkeyManager.swift
//  Flick
//

import Carbon
import AppKit

final class GlobalHotkeyManager {
    private struct Registration {
        let keyCode: UInt32
        let modifiers: UInt32
        let onPressed: () -> Void
        let onReleased: (() -> Void)?
        var hotKeyRef: EventHotKeyRef?
    }

    private static let signature = OSType(0x464C434B) // "FLCK"

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var isStarted = false

    init() {}

    /// Compatibility initializer for the existing Command-E action.
    convenience init(callback: @escaping () -> Void) {
        self.init()
        register(
            keyCode: UInt32(kVK_ANSI_E),
            modifiers: UInt32(cmdKey),
            onPressed: callback
        )
    }

    deinit {
        stop()
    }

    @discardableResult
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        onPressed: @escaping () -> Void,
        onReleased: (() -> Void)? = nil
    ) -> UInt32 {
        let id = nextID
        nextID += 1
        registrations[id] = Registration(
            keyCode: keyCode,
            modifiers: modifiers,
            onPressed: onPressed,
            onReleased: onReleased,
            hotKeyRef: nil
        )

        if isStarted {
            registerHotKey(id: id)
        }
        return id
    }

    func start() {
        stop()

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<GlobalHotkeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return manager.handle(event: event)
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[Flick] InstallEventHandler failed: \(status)")
            return
        }

        isStarted = true
        for id in registrations.keys.sorted() {
            registerHotKey(id: id)
        }
        print("[Flick] Global hotkey handler installed")
    }

    func stop() {
        for id in registrations.keys {
            guard let ref = registrations[id]?.hotKeyRef else { continue }
            UnregisterEventHotKey(ref)
            registrations[id]?.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        isStarted = false
    }

    private func registerHotKey(id: UInt32) {
        guard var registration = registrations[id] else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            registration.keyCode,
            registration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            registration.hotKeyRef = ref
            registrations[id] = registration
            print("[Flick] Hotkey \(id) registered")
        } else {
            print("[Flick] RegisterEventHotKey \(id) failed: \(status)")
        }
    }

    private func handle(event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.signature,
              let registration = registrations[hotKeyID.id]
        else {
            return OSStatus(eventNotHandledErr)
        }

        let eventKind = GetEventKind(event)
        DispatchQueue.main.async {
            if eventKind == UInt32(kEventHotKeyPressed) {
                registration.onPressed()
            } else if eventKind == UInt32(kEventHotKeyReleased) {
                registration.onReleased?()
            }
        }
        return noErr
    }
}

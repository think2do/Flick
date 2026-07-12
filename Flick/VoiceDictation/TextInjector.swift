import AppKit
import ApplicationServices

enum TextInjector {
    enum InjectionError: LocalizedError {
        case accessibilityPermissionDenied
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionDenied:
                return "没有辅助功能权限，无法把文字输入到当前应用。"
            case .eventCreationFailed:
                return "无法创建键盘输入事件。"
            }
        }
    }

    static func inject(_ text: String) throws {
        guard ensureAccessibilityPermission() else {
            throw InjectionError.accessibilityPermissionDenied
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw InjectionError.eventCreationFailed
        }

        for character in text {
            let utf16 = Array(String(character).utf16)
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            ) else {
                throw InjectionError.eventCreationFailed
            }
            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
                keyUp.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            usleep(2_000)
        }
    }

    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard prompt else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

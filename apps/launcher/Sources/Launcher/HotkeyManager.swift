import AppKit
import Carbon
import Foundation

/// Registers a global Carbon hotkey parsed from config strings like `cmd+space`, `alt+r`.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// Spec that is currently registered successfully (empty when off / failed).
    private var registeredSpec: String = ""
    /// Last requested spec, even if registration failed (allows retry).
    private var requestedSpec: String = ""

    var onHotkey: (() -> Void)?

    private init() {}

    func update(from spec: String) {
        let normalized = spec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        requestedSpec = normalized
        let disabled = normalized.isEmpty || normalized == "none" || normalized == "off"

        if disabled {
            if hotKeyRef != nil || handlerRef != nil || !registeredSpec.isEmpty {
                unregister()
                registeredSpec = ""
            }
            return
        }

        // Already live for this spec — skip. Failed prior attempts leave registeredSpec
        // empty so the same string can be retried on the next config reload.
        if normalized == registeredSpec, hotKeyRef != nil {
            return
        }

        unregister()
        registeredSpec = ""
        if register(spec: normalized) {
            registeredSpec = normalized
        }
    }

    @discardableResult
    private func register(spec: String) -> Bool {
        guard let parsed = Self.parse(spec) else {
            NSLog("[Launcher] Unrecognized hotkey: \(spec)")
            return false
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        manager.onHotkey?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        guard status == noErr else {
            NSLog("[Launcher] InstallEventHandler failed: \(status)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E4348), id: 1) // 'LNCH'
        let registerStatus = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            NSLog("[Launcher] RegisterEventHotKey failed: \(registerStatus)")
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
            hotKeyRef = nil
            return false
        }
        return true
    }

    /// Drop the Carbon hotkey and callback (used on process terminate).
    func shutdown() {
        onHotkey = nil
        unregister()
        registeredSpec = ""
        requestedSpec = ""
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }

    // MARK: - Parsing

    private struct ParsedHotkey {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private static func parse(_ spec: String) -> ParsedHotkey? {
        let parts = spec.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let keyPart = parts.last else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘":
                modifiers |= UInt32(cmdKey)
            case "alt", "option", "opt", "⌥":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃":
                modifiers |= UInt32(controlKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            default:
                return nil
            }
        }

        guard let keyCode = keyCode(for: keyPart) else { return nil }
        return ParsedHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyCode(for name: String) -> UInt32? {
        switch name {
        case "space", "spc": return UInt32(kVK_Space)
        case "return", "enter": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        case "escape", "esc": return UInt32(kVK_Escape)
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        default: return nil
        }
    }
}

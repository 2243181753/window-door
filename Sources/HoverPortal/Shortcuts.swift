import AppKit
import Carbon

enum ShortcutAction: Int, CaseIterable, Codable {
    case toggle, choose, follow, opacityUp, opacityDown, edit, center, opacityShift, pointerPassThrough, moveTarget
    var title: String {
        switch self {
        case .toggle: return "开始 / 关闭"
        case .choose: return "选择窗口"
        case .follow: return "跟随窗口"
        case .opacityUp: return "不透明度 +"
        case .opacityDown: return "不透明度 −"
        case .edit: return "进入编辑"
        case .center: return "居中"
        case .opacityShift: return "透明度平移"
        case .pointerPassThrough: return "鼠标穿透"
        case .moveTarget: return "拖动目标窗口（按住）"
        }
    }
}

struct ShortcutBinding: Codable, Equatable {
    var key: UInt32? // nil means a modifier-only hold action.
    var modifiers: UInt32
    var label: String
    static let space = ShortcutBinding(key: 49, modifiers: 0, label: "空格")
    static let option = ShortcutBinding(key: nil, modifiers: UInt32(optionKey), label: "⌥")
    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    static func modifierLabel(_ value: UInt32) -> String {
        var text = ""
        for (mask, symbol) in [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")] {
            if value & mask != 0 { text += symbol }
        }
        return text
    }
    static func from(_ event: NSEvent) -> ShortcutBinding {
        let mods = modifiers(from: event.modifierFlags)
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let keyName = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "键 \(event.keyCode)"
        return ShortcutBinding(key: UInt32(event.keyCode), modifiers: mods, label: modifierLabel(mods) + keyName)
    }
}

@MainActor
final class ShortcutController {
    private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:]
    private var refs: [EventHotKeyRef] = []
    private var scopeActive = false
    private var targetMoveEnabled = false
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var candidate: ShortcutBinding?
    private var recordingAction: ShortcutAction?
    private var held: Set<ShortcutAction> = []
    private var repeatTimer: Timer?
    private var pressedAt = Date.distantPast
    var onAction: ((ShortcutAction) -> Void)?
    var onRecorded: (() -> Void)?
    var registrationFailures: Set<ShortcutAction> = []
    var isRecording: Bool { recordingAction != nil }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = PortalPreferences.shared) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "shortcutBindingsV1"),
           let saved = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            for action in ShortcutAction.allCases { bindings[action] = saved[String(action.rawValue)] }
        } else { bindings[.edit] = .option }
        if !defaults.bool(forKey: "targetMoveShortcutInitializedV1") {
            if !bindings.values.contains(.space) { bindings[.moveTarget] = .space }
            defaults.set(true, forKey: "targetMoveShortcutInitializedV1")
            save()
        }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x48565054 else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let action = ShortcutAction(rawValue: Int(id.id)) {
                    controller.receive(action, down: GetEventKind(event) == UInt32(kEventHotKeyPressed))
                }
            }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register()
    }

    func setScopeActive(_ active: Bool) {
        guard scopeActive != active else { return }
        scopeActive = active
        register()
    }
    func setTargetMoveEnabled(_ enabled: Bool) {
        guard targetMoveEnabled != enabled else { return }
        targetMoveEnabled = enabled; register()
    }
    func targetMoveActive(flags: NSEvent.ModifierFlags) -> Bool {
        guard targetMoveEnabled, !isRecording, let binding = bindings[.moveTarget] else { return false }
        if binding.key != nil { return held.contains(.moveTarget) }
        return binding.modifiers != 0 && ShortcutBinding.modifiers(from: flags) == binding.modifiers
    }
    func shutdown() {
        cancelRecording(); unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll(); held.removeAll(); repeatTimer?.invalidate(); repeatTimer = nil
    }
    private func register() {
        unregister(); registrationFailures.removeAll()
        guard scopeActive, !isRecording else { return }
        for action in ShortcutAction.allCases {
            if action == .moveTarget && !targetMoveEnabled { continue }
            guard let binding = bindings[action], let key = binding.key else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x48565054, id: UInt32(action.rawValue))
            let status = RegisterEventHotKey(key, binding.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { registrationFailures.insert(action) }
        }
    }
    private func save() {
        var saved: [String: ShortcutBinding] = [:]
        for (action, binding) in bindings { saved[String(action.rawValue)] = binding }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "shortcutBindingsV1") }
    }
    func set(_ binding: ShortcutBinding?, for action: ShortcutAction) {
        if let binding {
            // One physical shortcut belongs to one action.
            for other in ShortcutAction.allCases where other != action {
                if bindings[other]?.key == binding.key && bindings[other]?.modifiers == binding.modifiers { bindings[other] = nil }
            }
        }
        bindings[action] = binding; save(); register()
    }
    func editActive(flags: NSEvent.ModifierFlags) -> Bool {
        guard !isRecording, let binding = bindings[.edit] else { return false }
        if binding.key != nil { return held.contains(.edit) }
        return ShortcutBinding.modifiers(from: flags) == binding.modifiers && binding.modifiers != 0
    }
    private func receive(_ action: ShortcutAction, down: Bool) {
        guard scopeActive, !isRecording else { return }
        if !down {
            held.remove(action)
            if action == .opacityUp || action == .opacityDown { repeatTimer?.invalidate(); repeatTimer = nil }
            return
        }
        guard !held.contains(action) else { return }
        held.insert(action)
        if action == .edit || action == .moveTarget { return }
        onAction?(action)
        if action == .opacityUp || action == .opacityDown {
            repeatTimer?.invalidate(); pressedAt = Date()
            repeatTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.held.contains(action), Date().timeIntervalSince(self.pressedAt) >= 0.3 else { return }
                    self.onAction?(action)
                }
            }
            RunLoop.main.add(repeatTimer!, forMode: .common)
        }
    }
    func record(_ action: ShortcutAction) {
        cancelRecording(); unregister(); recordingAction = action; candidate = nil
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.consumeRecordingEvent(event, action: action) }
            return nil
        }
    }
    private func consumeRecordingEvent(_ event: NSEvent, action: ShortcutAction) {
        if event.type == .keyDown {
            if !event.isARepeat { candidate = .from(event) }
        } else if event.type == .keyUp, let candidate, candidate.key == UInt32(event.keyCode) {
            finish(candidate, action: action)
        } else if event.type == .flagsChanged, (action == .edit || action == .moveTarget) {
            let mods = ShortcutBinding.modifiers(from: event.modifierFlags)
            if mods != 0, candidate?.key == nil {
                candidate = ShortcutBinding(key: nil, modifiers: mods, label: ShortcutBinding.modifierLabel(mods))
            } else if mods == 0, let candidate, candidate.key == nil {
                finish(candidate, action: action)
            }
        }
    }

    private func finish(_ binding: ShortcutBinding, action: ShortcutAction) {
        cancelRecording(); set(binding, for: action); onRecorded?()
    }
    func cancelRecording() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil; candidate = nil; recordingAction = nil
        register()
    }
    // Isolated developer checks do not overwrite the user's saved mappings.
    static func verify() -> [String: Bool] {
        let suite = "HoverPortal.ShortcutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let controller = ShortcutController(defaults: defaults)
        controller.setScopeActive(true)
        var checks: [String: Bool] = [:]
        checks["targetMoveDisabledWithoutPointerPass"] = !controller.targetMoveActive(flags: [])
        controller.receive(.moveTarget, down: true)
        checks["targetMoveDisabledEvenWhenHeld"] = !controller.targetMoveActive(flags: [])
        controller.receive(.moveTarget, down: false)
        controller.setTargetMoveEnabled(true)
        controller.receive(.moveTarget, down: true)
        checks["targetMoveHeld"] = controller.targetMoveActive(flags: [])
        controller.receive(.moveTarget, down: false)
        checks["targetMoveReleaseStops"] = !controller.targetMoveActive(flags: [])
        controller.setTargetMoveEnabled(false)
        checks["shortcutFreshDefaults"] = controller.bindings.count == 2 && controller.bindings[.edit] == .option && controller.bindings[.moveTarget] == .space
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                   windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: flags, timestamp: 1,
                                 windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        controller.record(.toggle)
        controller.consumeRecordingEvent(down, action: .toggle)
        checks["shortcutWaitsForRelease"] = controller.bindings[.toggle] == nil && controller.isRecording
        controller.setScopeActive(false)
        checks["shortcutRecordsWhileInactive"] = controller.isRecording
        controller.consumeRecordingEvent(up, action: .toggle)
        checks["shortcutSavedOnRelease"] = controller.bindings[.toggle] == .from(down) && !controller.isRecording
        controller.set(nil, for: .toggle); controller.set(nil, for: .edit); controller.set(nil, for: .moveTarget)
        controller.shutdown()
        let reloaded = ShortcutController(defaults: defaults)
        checks["shortcutClearedPersists"] = reloaded.bindings.isEmpty
        let binding = ShortcutBinding(key: 79, modifiers: UInt32(cmdKey | optionKey | shiftKey), label: "⌥⇧⌘F18")
        reloaded.set(binding, for: .opacityUp)
        checks["shortcutsUnregisteredOutsideHover"] = reloaded.refs.isEmpty
        reloaded.setScopeActive(true)
        checks["shortcutRegistered"] = reloaded.registrationFailures.isEmpty
        var count = 0
        reloaded.onAction = { if $0 == .opacityUp { count += 1 } }
        func send(_ down: Bool) {
            var event: EventRef?
            CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(down ? kEventHotKeyPressed : kEventHotKeyReleased), 0, 0, &event)
            if let event {
                var id = EventHotKeyID(signature: 0x48565054, id: UInt32(ShortcutAction.opacityUp.rawValue))
                SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
                SendEventToEventTarget(event, GetApplicationEventTarget()); ReleaseEvent(event)
            }
        }
        send(true)
        checks["shortcutSinglePress"] = count == 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.43))
        checks["shortcutHoldRepeats"] = count > 1
        send(false); let releasedCount = count
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        checks["shortcutReleaseStopsRepeat"] = count == releasedCount
        send(true)
        reloaded.setScopeActive(false)
        let backgroundCount = count
        send(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.43))
        checks["shortcutsInactiveOutsideHover"] = count == backgroundCount && reloaded.refs.isEmpty
        reloaded.setScopeActive(true)
        checks["shortcutsResumeOnHover"] = !reloaded.refs.isEmpty && reloaded.registrationFailures.isEmpty
        reloaded.shutdown()
        let persisted = ShortcutController(defaults: defaults)
        checks["shortcutMappingPersists"] = persisted.bindings[.opacityUp] == binding
        persisted.set(binding, for: .opacityShift)
        let second = ShortcutBinding(key: 80, modifiers: UInt32(cmdKey | optionKey | shiftKey), label: "⌥⇧⌘F19")
        persisted.set(second, for: .pointerPassThrough)
        persisted.shutdown()
        let extra = ShortcutController(defaults: defaults)
        checks["newToggleShortcutsPersist"] = extra.bindings[.opacityShift] == binding && extra.bindings[.pointerPassThrough] == second
        checks["existingShortcutIDsStable"] = ShortcutAction.center.rawValue == 6 && ShortcutAction.opacityShift.rawValue == 7
        extra.shutdown(); defaults.removePersistentDomain(forName: suite)
        return checks
    }

}

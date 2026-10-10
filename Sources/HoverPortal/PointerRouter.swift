import AppKit
import ApplicationServices

// The overlay consumes input. Never send it to whichever unrelated app happens to be underneath.
@MainActor
final class PointerRouter {
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private struct Press {
        let pid: pid_t
        let windowID: CGWindowID
        let event: CGEvent
        let background: Bool
        let bounds: CGRect
    }
    private var movingWindow: (element: AXUIElement, selection: WindowSelection, origin: CGPoint)?
    func beginTargetMove(selection: WindowSelection?, bounds: CGRect) -> Bool {
        cancel(); movingWindow = nil
        guard Self.trusted, let selection,
              let application = NSRunningApplication(processIdentifier: selection.processID),
              !application.isTerminated, application.bundleIdentifier == selection.bundleID,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, selection.id) as? [[String: Any]])?.first,
              (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == selection.processID,
              let window = accessibleWindow(selection: selection, bounds: bounds) else {
            onFailure?("无法控制目标窗口位置 · 请确认权限并重新选择窗口"); return false
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable) == .success, settable.boolValue else {
            onFailure?("目标软件不允许调整窗口位置"); return false
        }
        AXUIElementSetMessagingTimeout(window, 0.15)
        movingWindow = (window, selection, bounds.origin)
        return true
    }
    func moveTarget(delta: CGPoint) -> Bool {
        guard Self.trusted, let movingWindow,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, movingWindow.selection.id) as? [[String: Any]])?.first,
              (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == movingWindow.selection.processID else { endTargetMove(); return false }
        var point = CGPoint(x: movingWindow.origin.x + delta.x, y: movingWindow.origin.y - delta.y)
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        let result = AXUIElementSetAttributeValue(movingWindow.element, kAXPositionAttribute as CFString, value)
        if result != .success { onFailure?("目标软件未接受窗口移动"); endTargetMove(); return false }
        return true
    }
    func endTargetMove() { movingWindow = nil }
    private var presses: [Int: Press] = [:]
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func cancel() {
        for (button, press) in presses {
            let type: NSEvent.EventType = button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp
            guard let source = NSEvent(cgEvent: press.event),
                  let up = NSEvent.mouseEvent(with: type, location: source.locationInWindow,
                      modifierFlags: source.modifierFlags, timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: Int(press.windowID), context: nil, eventNumber: source.eventNumber,
                      clickCount: source.clickCount, pressure: 0),
                  let release = PointerEventFactory.make(up, point: press.event.location,
                      windowID: press.windowID, bounds: press.bounds, background: press.background) else { continue }
            Self.address(release, pid: press.pid, windowID: press.windowID)
            release.postToPid(press.pid)
        }
        presses.removeAll()
    }
    func route(_ event: NSEvent, selection: WindowSelection?, bounds: CGRect, allowed: Bool) {
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        let up = [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        let drag = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
        let button = down || up || drag ? event.buttonNumber : 0
        if up || drag {
            guard let press = presses[button] else { return }
            let point = Self.screenPoint(event)
            guard let copy = PointerEventFactory.make(event, point: point, windowID: press.windowID, bounds: bounds, background: press.background) else { return }
            guard allowed, Self.trusted else { cancel(); return }
            Self.address(copy, pid: press.pid, windowID: press.windowID)
            copy.postToPid(press.pid)
            if up { presses.removeValue(forKey: button) }
            return
        }
        guard allowed else { return }
        guard PointerEventFactory.available else { onFailure?("当前系统不支持后台坐标输入 · 未发送操作"); return }
        guard let selection else { onFailure?("缺少所选窗口身份，请重新选择窗口。"); return }
        let background = NSRunningApplication(processIdentifier: selection.processID)?.isActive == false
        guard selection.processID != ProcessInfo.processInfo.processIdentifier,
              let copy = PointerEventFactory.make(event, point: Self.screenPoint(event), windowID: selection.id, bounds: bounds, background: background) else { return }
        guard bounds.contains(copy.location) else { onFailure?("点击位置不在目标画面内。"); return }
        guard Self.trusted else { onFailure?("鼠标穿透需要辅助功能权限，请在系统设置中允许视窗之门。"); return }
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, selection.id) as? [[String: Any]])?.first,
              (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == selection.processID,
              let application = NSRunningApplication(processIdentifier: selection.processID),
              !application.isTerminated, application.bundleIdentifier == selection.bundleID else {
            onFailure?("目标窗口已失效，请重新选择窗口。"); return
        }
        Self.address(copy, pid: selection.processID, windowID: selection.id)
        if down {
            presses[button] = Press(pid: selection.processID, windowID: selection.id, event: copy, background: background, bounds: bounds)
            onStatus?("已按位置转发点击 · 目标软件可能不接收")
        }
        copy.postToPid(selection.processID)
        if event.type == .scrollWheel { onStatus?("已转发目标窗口滚动") }
    }
    private static func screenPoint(_ event: NSEvent) -> CGPoint {
        guard let window = event.window else { return event.cgEvent?.location ?? .zero }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }
    func diagnostics(selection: WindowSelection?) -> [String: Any] {
        var result: [String: Any] = ["accessibilityGranted": Self.trusted, "backgroundControlMethod": "destination-native mouse, drag and scroll events; single and double clicks share one route", "windowCoordinateRoutingAvailable": PointerEventFactory.available]
        guard let selection else { result["windowIdentityAvailable"] = false; return result }
        result["windowIdentityAvailable"] = true
        result["selectedApplication"] = selection.appName
        if let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, selection.id) as? [[String: Any]])?.first,
           let raw = info[kCGWindowBounds as String] as? NSDictionary,
           let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) {
            result["selectedWindowExists"] = true
            if Self.trusted { result["accessibleWindowMatched"] = accessibleWindow(selection: selection, bounds: bounds) != nil }
        } else { result["selectedWindowExists"] = false }
        return result
    }
    static func address(_ event: CGEvent, pid: pid_t, windowID: CGWindowID) {
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
    }
    private func accessibleWindow(selection: WindowSelection, bounds: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(selection.processID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        let matches = windows.filter { window in
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return false }
            var position = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return false }
            let sameFrame = abs(position.x - bounds.minX) < 3 && abs(position.y - bounds.minY) < 3
                && abs(size.width - bounds.width) < 3 && abs(size.height - bounds.height) < 3
            return sameFrame
        }
        if matches.count == 1 { return matches[0] }
        let named = matches.filter { window in
            var title: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            return !selection.title.isEmpty && (title as? String) == selection.title
        }
        return named.count == 1 ? named[0] : nil
    }
}

import AppKit

// Reasons are derived from live state, never from translated status text.
enum DoorStatus: String, CaseIterable {
    case targetFrontmost, closed, active, waitingMouse, editing, starting, captureUnavailable
    case learning, unenrolled, checkingOwner, ownerAbsent, others, angle, motion, quiet, gestureLocked, cameraUnavailable
    var briefExplanation: String {
        explanation.components(separatedBy: " · ").first ?? explanation
    }
    var explanation: String {
        switch self {
        case .targetFrontmost: return "目标窗口在最前 · 自动暂停"
        case .closed: return "已关闭"
        case .active: return "正在显示"
        case .waitingMouse: return "等待鼠标移入矩形"
        case .editing: return "正在移动或缩放 · 暂停显示"
        case .starting: return "正在启动或切换窗口"
        case .captureUnavailable: return "窗口画面不可用 · 请恢复或重新选择窗口"
        case .learning: return "正在登记或学习 · 暂停显示"
        case .unenrolled: return "尚未登记主人 · 无法激活"
        case .checkingOwner: return "正在确认主人 · 暂停显示"
        case .ownerAbsent: return "未检测到主人 · 暂停显示"
        case .others: return "发现他人或无法确认主人身份 · 暂停显示"
        case .angle: return "观看角度不符 · 暂停显示"
        case .motion: return "主人区域外有运动 · 暂停显示"
        case .quiet: return "等待背景恢复安静 · 暂停显示"
        case .gestureLocked: return "手势锁定 · 主人在场时再做目标手势解除"
        case .cameraUnavailable: return "摄像头异常或画面超时 · 暂停显示"
        }
    }
}

struct GuardStatusSnapshot {
    var enabled = false
    var previewing = false
    var enrolled = false
    var manualLock = false
    var cameraFault = false
    var hasFrame = false
    var faceCount = 0
    var rawOwnerMatch = false
    var confirmedOwner = false
    var enhanced = false
    var frontFacing = false
    var sceneReady = false
    var moving = false
    var automaticAllows = false
    var reason: DoorStatus? {
        if previewing { return cameraFault ? .cameraUnavailable : .learning }
        guard enabled else { return nil }
        if manualLock { return .gestureLocked }
        if cameraFault { return .cameraUnavailable }
        if !enrolled { return .unenrolled }
        if !hasFrame { return .checkingOwner }
        if faceCount == 0 { return .ownerAbsent }
        if faceCount > 1 || !rawOwnerMatch { return .others }
        if !confirmedOwner { return .checkingOwner }
        if enhanced {
            if !frontFacing { return .angle }
            if moving { return .motion }
            if !sceneReady || !automaticAllows { return .quiet }
        }
        return nil
    }
}

struct DoorStatusResolver {
    static func resolve(running: Bool, busy: Bool, captureFault: Bool, guardian: DoorStatus?,
                        hasContent: Bool, editing: Bool, activation: Bool) -> DoorStatus {
        if busy { return .starting }
        if !running { return captureFault ? .captureUnavailable : .closed }
        if let guardian { return guardian }
        if !hasContent { return .captureUnavailable }
        if editing { return .editing }
        return activation ? .active : .waitingMouse
    }
}

@MainActor enum DoorStatusIcon {
    static func verify(directory: String) -> Bool {
        let statuses = DoorStatus.allCases
        let canvas = NSImage(size: NSSize(width: 800, height: 340))
        canvas.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0,y: 0,width: 800,height: 340).fill()
        var valid = true
        for (i, status) in statuses.enumerated() {
            let icon = image(for: status)
            let x = CGFloat(i % 4) * 200, y = 255 - CGFloat(i / 4) * 80
            icon.isTemplate = false
            icon.draw(in: CGRect(x: x+78,y: y+20,width: 44,height: 40))
            let title = status.explanation.components(separatedBy: " · ")[0]
            (title as NSString).draw(in: CGRect(x:x+8,y:y,width:184,height:20), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black])
            valid = valid && icon.size.width == 22 && icon.tiffRepresentation != nil
        }
        canvas.unlockFocus()
        guard let data = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("status-icons-preview.png")) }
        catch { return false }
        return valid
    }
    static func image(for status: DoorStatus) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let border = NSBezierPath(roundedRect: CGRect(x: 1.5, y: 2, width: 19, height: 16), xRadius: 2, yRadius: 2)
            border.lineWidth = 1.2; border.stroke()
            func line(_ points: [CGPoint], width: CGFloat = 1.2) {
                let path = NSBezierPath(); guard let first = points.first else { return }
                path.move(to: first); points.dropFirst().forEach { path.line(to: $0) }
                path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
            }
            func person(_ x: CGFloat, _ y: CGFloat, _ scale: CGFloat) {
                NSBezierPath(ovalIn: CGRect(x: x-1.4*scale, y: y+2*scale, width: 2.8*scale, height: 2.8*scale)).fill()
                NSBezierPath(roundedRect: CGRect(x: x-2.2*scale, y: y-2.8*scale, width: 4.4*scale, height: 4.5*scale), xRadius: 1.3*scale, yRadius: 1.3*scale).fill()
            }
            switch status {
            case .active: NSBezierPath(ovalIn: CGRect(x: 8.5, y: 7.5, width: 5, height: 5)).fill()
            case .closed: line([CGPoint(x: 7,y: 10),CGPoint(x: 15,y: 10)])
            case .ownerAbsent:
                person(11,9,1)
                // Cut a clear gap first; then draw the diagonal so it reads as a slash.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                line([CGPoint(x: 6.5,y: 5.5),CGPoint(x: 15.5,y: 14.5)], width: 3)
                NSGraphicsContext.restoreGraphicsState()
                line([CGPoint(x: 6.5,y: 5.5),CGPoint(x: 15.5,y: 14.5)])
            case .others:
                person(5.8,9,0.68); person(16.2,9,0.68); person(11,9,1.05)
            case .angle:
                let center = CGPoint(x: 5.5,y: 6.5)
                line([CGPoint(x: 16.5,y: 6.5),center,CGPoint(x: 14.5,y: 14)])
                let arc = NSBezierPath(); arc.appendArc(withCenter: center, radius: 5, startAngle: 0, endAngle: 39.8)
                arc.lineWidth = 1.1; arc.stroke()
            case .gestureLocked:
                PortalIcons.image(.gesture).draw(in: CGRect(x: 4.5,y: 3.5,width: 13,height: 13))
            default:
                let name: String
                switch status {
                case .targetFrontmost: name = "pause.fill"
                case .waitingMouse: name = "cursorarrow"
                case .editing: name = "arrow.up.left.and.arrow.down.right"
                case .starting: name = "hourglass"
                case .captureUnavailable: name = "rectangle.slash"
                case .learning: name = "pencil"
                case .unenrolled: name = "person.badge.plus"
                case .checkingOwner: name = "person.fill.questionmark"
                case .cameraUnavailable: name = "camera.fill"
                case .motion: name = "waveform"
                case .quiet: name = "clock"
                default: name = "exclamationmark"
                }
                if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: status.explanation) {
                    symbol.draw(in: CGRect(x: 5,y: 4.5,width: 12,height: 11), from: .zero, operation: .sourceOver, fraction: 1)
                } else { line([CGPoint(x:11,y:8),CGPoint(x:11,y:14)]); NSBezierPath(ovalIn: CGRect(x:10.5,y:5.5,width:1,height:1)).fill() }
                if status == .cameraUnavailable { line([CGPoint(x:5.5,y:5.5),CGPoint(x:16.5,y:15)]) }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

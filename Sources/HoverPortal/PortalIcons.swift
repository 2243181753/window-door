import AppKit

// Native vector artwork keeps small menu icons sharp at either screen scale.
@MainActor enum PortalIcons {
    enum Kind: String, CaseIterable { case helpDocument, center, moveTarget, gesture, face, pointerPass, tracking, mouseDetection, follow, ownerEnrollment, gestureLearning, angleLearning }
    static func image(_ kind: Kind) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            func stroke(_ points: [CGPoint], width: CGFloat = 2.5) {
                let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }
                p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
            }
            func scanCorners() {
                for quarter in 0..<4 {
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: 16,yBy: 16); t.rotate(byDegrees: CGFloat(quarter * 90)); t.translateX(by: -16,yBy: -16); t.concat()
                    stroke([CGPoint(x: 3,y: 22),CGPoint(x: 3,y: 29),CGPoint(x: 10,y: 29)], width: 2.5)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            switch kind {
            case .helpDocument:
                stroke([CGPoint(x: 24,y: 21),CGPoint(x: 24,y: 3),CGPoint(x: 7,y: 3),CGPoint(x: 7,y: 29),CGPoint(x: 17,y: 29),CGPoint(x: 24,y: 21),CGPoint(x: 17,y: 21),CGPoint(x: 17,y: 29)], width: 2)
                let mark = "?" as NSString
                mark.draw(at: CGPoint(x: 11,y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 17,weight: .bold), .foregroundColor: NSColor.black])
            case .follow:
                let frame = NSBezierPath(roundedRect: NSRect(x: 3,y: 5,width: 26,height: 22), xRadius: 3,yRadius: 3)
                frame.lineWidth = 2.2; frame.stroke()
                PortalIcons.image(.tracking).draw(in: NSRect(x: 8,y: 8,width: 16,height: 16))
            case .ownerEnrollment:
                scanCorners()
                NSBezierPath(ovalIn: NSRect(x: 11,y: 15,width: 10,height: 10)).fill()
                let body = NSBezierPath(); body.move(to: CGPoint(x: 7,y: 5))
                body.curve(to: CGPoint(x: 16,y: 15), controlPoint1: CGPoint(x: 8,y: 11), controlPoint2: CGPoint(x: 11,y: 15))
                body.curve(to: CGPoint(x: 25,y: 5), controlPoint1: CGPoint(x: 21,y: 15), controlPoint2: CGPoint(x: 24,y: 11)); body.close(); body.fill()
            case .gestureLearning:
                scanCorners(); PortalIcons.image(.gesture).draw(in: NSRect(x: 7,y: 6,width: 19,height: 20))
            case .angleLearning:
                scanCorners()
                let center = CGPoint(x: 9,y: 10)
                stroke([CGPoint(x: 24,y: 10),center,CGPoint(x: 22,y: 21)], width: 2.1)
                let arc = NSBezierPath(); arc.appendArc(withCenter: center,radius: 7,startAngle: 0,endAngle: 40.2)
                arc.lineWidth = 1.7; arc.stroke()
            case .tracking:
                let ring = NSBezierPath(ovalIn: NSRect(x: 5,y: 5,width: 22,height: 22))
                ring.lineWidth = 2.6; ring.stroke()
                for segment in [[CGPoint(x: 16,y: 1),CGPoint(x: 16,y: 9)],
                                [CGPoint(x: 16,y: 23),CGPoint(x: 16,y: 31)],
                                [CGPoint(x: 1,y: 16),CGPoint(x: 9,y: 16)],
                                [CGPoint(x: 23,y: 16),CGPoint(x: 31,y: 16)]] {
                    stroke(segment, width: 3)
                }
                NSBezierPath(ovalIn: NSRect(x: 13.5,y: 13.5,width: 5,height: 5)).fill()
            case .mouseDetection:
                // Four scanner corners frame a standard mouse pointer.
                for quarter in 0..<4 {
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: 16,yBy: 16); t.rotate(byDegrees: CGFloat(quarter * 90)); t.translateX(by: -16,yBy: -16); t.concat()
                    stroke([CGPoint(x: 3,y: 22),CGPoint(x: 3,y: 29),CGPoint(x: 10,y: 29)], width: 2.4)
                    NSGraphicsContext.restoreGraphicsState()
                }
                let arrow = NSBezierPath(); arrow.move(to: CGPoint(x: 11,y: 25)); arrow.line(to: CGPoint(x: 11,y: 9))
                arrow.line(to: CGPoint(x: 15,y: 13)); arrow.line(to: CGPoint(x: 19,y: 5)); arrow.line(to: CGPoint(x: 22,y: 7))
                arrow.line(to: CGPoint(x: 18,y: 15)); arrow.line(to: CGPoint(x: 24,y: 15)); arrow.close(); arrow.fill()
            case .center:
                let frame = NSBezierPath(roundedRect: NSRect(x: 3, y: 6, width: 26, height: 20), xRadius: 3, yRadius: 3)
                frame.lineWidth = 2.2; frame.stroke()
                stroke([CGPoint(x: 16,y: 3),CGPoint(x: 16,y: 29)], width: 1.8)
                stroke([CGPoint(x: 1,y: 16),CGPoint(x: 31,y: 16)], width: 1.8)
            case .moveTarget:
                // Four distinct heavy arrows, with space around their shared center.
                for quarter in 0..<4 {
                    NSGraphicsContext.saveGraphicsState()
                    let transform = AffineTransform(translationByX: 16, byY: 16)
                    var rotation = transform; rotation.rotate(byDegrees: CGFloat(quarter * 90)); rotation.translate(x: -16,y: -16)
                    (rotation as NSAffineTransform).concat()
                    stroke([CGPoint(x: 16,y: 20),CGPoint(x: 16,y: 29)], width: 3.7)
                    stroke([CGPoint(x: 11,y: 24),CGPoint(x: 16,y: 29),CGPoint(x: 21,y: 24)], width: 3.7)
                    NSGraphicsContext.restoreGraphicsState()
                }
            case .gesture:
                // Upright V fingers, rounded palm, folded fingers and a bent thumb.
                let p = NSBezierPath(); p.move(to: CGPoint(x: 10,y: 3))
                p.curve(to: CGPoint(x: 6,y: 12), controlPoint1: CGPoint(x: 6,y: 4), controlPoint2: CGPoint(x: 5,y: 8))
                p.line(to: CGPoint(x: 4.2,y: 26))
                p.curve(to: CGPoint(x: 8.6,y: 27), controlPoint1: CGPoint(x: 3.8,y: 30), controlPoint2: CGPoint(x: 7.8,y: 31))
                p.line(to: CGPoint(x: 12.1,y: 18)); p.line(to: CGPoint(x: 17.5,y: 28))
                p.curve(to: CGPoint(x: 22,y: 26), controlPoint1: CGPoint(x: 19.4,y: 31), controlPoint2: CGPoint(x: 23.9,y: 29))
                p.line(to: CGPoint(x: 18.4,y: 17))
                p.curve(to: CGPoint(x: 25.7,y: 14), controlPoint1: CGPoint(x: 23,y: 20), controlPoint2: CGPoint(x: 28,y: 17))
                p.curve(to: CGPoint(x: 27,y: 8), controlPoint1: CGPoint(x: 29,y: 13), controlPoint2: CGPoint(x: 29,y: 10))
                p.curve(to: CGPoint(x: 23,y: 3), controlPoint1: CGPoint(x: 27,y: 5), controlPoint2: CGPoint(x: 26,y: 3))
                p.close(); p.lineWidth = 2.4; p.lineJoinStyle = .round; p.lineCapStyle = .round; p.stroke()
                let thumb = NSBezierPath(); thumb.move(to: CGPoint(x: 9,y: 15)); thumb.line(to: CGPoint(x: 11,y: 17)); thumb.line(to: CGPoint(x: 13,y: 10))
                thumb.curve(to: CGPoint(x: 18,y: 12), controlPoint1: CGPoint(x: 14,y: 6), controlPoint2: CGPoint(x: 18,y: 8))
                thumb.lineWidth = 2.4; thumb.lineCapStyle = .round; thumb.lineJoinStyle = .round; thumb.stroke()
                stroke([CGPoint(x: 20,y: 15),CGPoint(x: 25,y: 13)], width: 2)
                stroke([CGPoint(x: 20,y: 9),CGPoint(x: 25,y: 7)], width: 2)
            case .face:
                for quarter in 0..<4 {
                    NSGraphicsContext.saveGraphicsState()
                    let t = NSAffineTransform(); t.translateX(by: 16,yBy: 16); t.rotate(byDegrees: CGFloat(quarter * 90)); t.translateX(by: -16,yBy: -16); t.concat()
                    let corner = NSBezierPath(); corner.move(to: CGPoint(x: 3,y: 22)); corner.line(to: CGPoint(x: 3,y: 24))
                    corner.curve(to: CGPoint(x: 8,y: 29), controlPoint1: CGPoint(x: 3,y: 27), controlPoint2: CGPoint(x: 5,y: 29))
                    corner.line(to: CGPoint(x: 11,y: 29)); corner.lineWidth = 2.5; corner.lineCapStyle = .round; corner.stroke()
                    NSGraphicsContext.restoreGraphicsState()
                }
                stroke([CGPoint(x: 10,y: 18),CGPoint(x: 10,y: 21)],width: 2.5)
                stroke([CGPoint(x: 23,y: 18),CGPoint(x: 23,y: 21)],width: 2.5)
                let nose = NSBezierPath(); nose.move(to: CGPoint(x: 17,y: 21)); nose.line(to: CGPoint(x: 17,y: 15)); nose.curve(to: CGPoint(x: 14,y: 13), controlPoint1: CGPoint(x: 17,y: 13), controlPoint2: CGPoint(x: 16,y: 13)); nose.lineWidth = 2.2; nose.lineCapStyle = .round; nose.stroke()
                let smile = NSBezierPath(); smile.move(to: CGPoint(x: 10,y: 10)); smile.curve(to: CGPoint(x: 23,y: 10), controlPoint1: CGPoint(x: 14,y: 6), controlPoint2: CGPoint(x: 20,y: 6)); smile.lineWidth = 2.4; smile.lineCapStyle = .round; smile.stroke()
            case .pointerPass:
                let hole = NSBezierPath(ovalIn: NSRect(x: 2,y: 5,width: 28,height: 10))
                NSColor.black.withAlphaComponent(0.18).setFill(); hole.fill()
                NSColor.black.setStroke(); hole.lineWidth = 2; hole.stroke()
                // Erase behind the emerging arrow, so it remains readable over the rim.
                let pointer = NSBezierPath(); pointer.move(to: CGPoint(x: 12,y: 30)); pointer.line(to: CGPoint(x: 12,y: 9)); pointer.line(to: CGPoint(x: 17,y: 14)); pointer.line(to: CGPoint(x: 21,y: 5)); pointer.line(to: CGPoint(x: 25,y: 7)); pointer.line(to: CGPoint(x: 21,y: 16)); pointer.line(to: CGPoint(x: 28,y: 16)); pointer.close()
                NSGraphicsContext.saveGraphicsState(); pointer.lineWidth = 2.6; NSColor.clear.setStroke()
                NSGraphicsContext.current?.compositingOperation = .copy; pointer.stroke(); NSGraphicsContext.restoreGraphicsState()
                NSGradient(starting: NSColor.black.withAlphaComponent(0.05), ending: .black)?.draw(in: pointer, angle: 90)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

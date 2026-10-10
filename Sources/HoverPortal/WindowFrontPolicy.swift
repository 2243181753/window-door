import CoreGraphics
import Foundation

enum WindowFrontPolicy {
    // The list is ordered from front to back. Ignore our overlay and unrelated areas.
    static func targetIsFrontmost(_ windows: [[String: Any]], target: CGWindowID?, ownPID: Int32) -> Bool {
        guard let target, let targetIndex = windows.firstIndex(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == target }),
              let data = windows[targetIndex][kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: data) else { return false }
        for window in windows.prefix(targetIndex) {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != ownPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let rectData = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: rectData), !rect.isEmpty else { continue }
            if rect.intersects(bounds) { return false }
        }
        return true
    }
}

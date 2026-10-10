import Foundation
import ScreenCaptureKit

enum CaptureFailure {
    static func describe(_ error: Error, operation: String) -> String {
        let failure = error as NSError
        let detail = "\(operation)：\(failure.localizedDescription) [\(failure.domain) / \(failure.code)]"
        NSLog("%@", detail)
        guard failure.domain == SCStreamErrorDomain else { return detail }
        switch failure.code {
        case -3801:
            return detail + " 当前运行进程未获准采集。请用“选择下层窗口…”重新选择；VS Code 启动与旧 App 的全屏录制授权可能属于不同进程。"
        case -3817, -3821:
            return detail + " 共享已结束，请重新选择窗口。"
        case -3813, -3815:
            return detail + " 没有可用采集目标，请恢复窗口并重新选择。"
        default:
            return detail // Do not label connection, parameter or capture failures as permission denial.
        }
    }
}

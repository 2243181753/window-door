import AppKit
import ScreenCaptureKit
import CoreImage

struct CapturedFrame {
    let image: CGImage
    let contentRect: CGRect // pixel coordinates, top-left origin
    let screenRect: CGRect? // Frame metadata; works even without global window-list permission.
}

final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "HoverPortal.capture", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let demand = CaptureDeliveryDemand()
    @MainActor private var requestedDisplayDemand = false
    private weak var lastRenderedStream: SCStream?
    private var lastRenderedAt = 0.0
    @MainActor func setDisplayDemand(_ visible: Bool) {
        guard requestedDisplayDemand != visible else { return }
        requestedDisplayDemand = visible
        queue.async { [demand] in demand.visible = visible }
    }
    @MainActor private lazy var lifecycle = CaptureLifecycle<NativeCaptureSession>()
    @MainActor private var stream: SCStream? { lifecycle.current?.stream }
    @MainActor var activeStream: SCStream? { stream }
    var onScreenRect: ((CGRect) -> Void)?
    var onFrame: ((CapturedFrame) -> Void)?
    var onUnavailable: ((String) -> Void)?
    var onError: ((String) -> Void)?

    @MainActor func start(window: SCWindow) async throws {
        try await start(filter: SCContentFilter(desktopIndependentWindow: window))
    }

    private func configuration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(2, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        config.height = max(2, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        return config
    }

    @MainActor func start(filter: SCContentFilter) async throws {
        try await lifecycle.replace {
            try NativeCaptureSession(filter: filter, configuration: configuration(for: filter), engine: self, queue: queue)
        }
    }
    @MainActor func stopForReplacement() async throws { try await lifecycle.stop() }
    @MainActor func stop() async { try? await lifecycle.stop() }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        autoreleasepool { process(stream, buffer: buffer, type: type) }
    }
    private func process(_ stream: SCStream, buffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let array = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = array.first,
              let rawStatus = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }
        var screenRect: CGRect?
        if let raw = info[.screenRect] as? NSDictionary {
            screenRect = CGRect(dictionaryRepresentation: raw as CFDictionary)
            if let rect = screenRect, rect.width > 0, rect.height > 0 {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.stream === stream else { return }
                    self.onScreenRect?(rect)
                }
            }
        }
        if status == .idle { return } // Static windows legitimately produce no new frames.
        guard status == .complete, let pixels = buffer.imageBuffer else {
            if status == .blank || status == .suspended || status == .stopped {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.stream === stream else { return }
                    self.onUnavailable?("窗口采集暂停；矩形暂时透明，收到新帧后自动恢复。")
                }
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard ResourcePolicy.renderFrame(visible: demand.visible, sameStream: lastRenderedStream === stream, elapsed: now-lastRenderedAt) else { return }
        lastRenderedStream = stream; lastRenderedAt = now
        let input = CIImage(cvPixelBuffer: pixels)
        guard let image = context.createCGImage(input, from: input.extent) else { return }
        var rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if let dictionary = info[.contentRect] as? NSDictionary,
           let content = CGRect(dictionaryRepresentation: dictionary as CFDictionary), content.width > 0, content.height > 0 {
            let scale = (info[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
            rect = CGRect(x: content.minX * scale, y: content.minY * scale,
                          width: content.width * scale, height: content.height * scale)
        }
        let frame = CapturedFrame(image: image, contentRect: rect, screenRect: screenRect)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.onFrame?(frame)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            Task { @MainActor in
                guard self.stream === stream else { return }
                self.onError?(CaptureFailure.describe(error, operation: "采集停止"))
                try? await self.lifecycle.stop()
            }
        }
    }
}

@MainActor private final class NativeCaptureSession: CaptureSessionResource {
    let stream: SCStream
    private weak var output: CaptureEngine?
    init(filter: SCContentFilter, configuration: SCStreamConfiguration, engine: CaptureEngine, queue: DispatchQueue) throws {
        stream = SCStream(filter: filter, configuration: configuration, delegate: engine)
        output = engine
        try stream.addStreamOutput(engine, type: .screen, sampleHandlerQueue: queue)
    }
    func startSession() async throws { try await stream.startCapture() }
    func stopSession() async throws { try await stream.stopCapture() }
    func detachOutput() { if let output { try? stream.removeStreamOutput(output, type: .screen) } }
}

// This small state is read and written exclusively on the serial sample queue.
private final class CaptureDeliveryDemand: @unchecked Sendable { var visible = false }

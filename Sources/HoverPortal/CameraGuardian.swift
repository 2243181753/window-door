import AppKit
import AVFoundation
import Vision
import CoreImage

// Local open-source SFace face embeddings. No liveness or authentication guarantee.
private final class FaceCameraWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "WindowDoor.FaceCamera", qos: .userInitiated)
    private var recognizer: SFaceRecognizer?
    private var profiles: [FaceDescriptor] = []
    private var enrolling = false
    private var enrollment: [FaceDescriptor] = []
    private var enrollmentStarted = Date.distantPast
    private var lastEnrollmentSample = 0.0
    private var running = false
    private var lastAnalysis = 0.0
    private let facesRequest = VNDetectFaceLandmarksRequest()
    private let humansRequest: VNDetectHumanRectanglesRequest = { let request = VNDetectHumanRectanglesRequest(); request.upperBodyOnly = true; return request }()
    private let poseRequest: VNDetectFaceRectanglesRequest = { let request = VNDetectFaceRectanglesRequest(); request.revision = VNDetectFaceRectanglesRequestRevision3; return request }()
    private let handsRequest: VNDetectHumanHandPoseRequest = { let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 4; return request }()
    private var generation = 0
    private var enhanced = false
    private var gestureMonitoring = false
    private var gesturePreview = false
    private var gestureEnrolling = false
    private var gestureProfile: GestureProfile?
    private var gestureConfigured = false
    private var gestureSamples: [GestureDescriptor] = []
    private var gestureStarted = 0.0
    private var lastGestureSample = 0.0
    private var gestureStatusUntil = 0.0
    private var gestureToken = 0
    private var learningFingerStates: [Int]?
    private var pendingFingerStates: [Int]?
    private var pendingFingerCount = 0
    private var gestureConfirmations = 0
    var onGestureStatus: ((String) -> Void)?
    var onGestureEnrollment: ((Data?, String, Int) -> Void)?
    func loadGesture(_ data: Data?, configured: Bool? = nil) {
        queue.async { [self] in
            gestureConfirmations = 0; gestureConfigured = configured ?? (data != nil)
            if let data, let profile = try? JSONDecoder().decode(GestureProfile.self, from: data), profile.valid { gestureProfile = profile }
            else { gestureProfile = nil }
        }
    }
    func setGesturePreview(_ value: Bool) { queue.async { [self] in gesturePreview = value; gestureConfirmations = 0 } }
    func learnGesture(token: Int) {
        queue.async { [self] in
            gestureToken = token; gestureEnrolling = true; gestureSamples.removeAll()
            learningFingerStates = nil; pendingFingerStates = nil; pendingFingerCount = 0
            gestureStarted = ProcessInfo.processInfo.systemUptime; lastGestureSample = 0; gestureStatusUntil = 0
        }
    }
    func cancelGestureLearning() { queue.async { [self] in gestureEnrolling = false; gestureSamples.removeAll() } }
    private func sampleGesture(_ hands: [VNHumanHandPoseObservation], time: Double) {
        guard gestureEnrolling else {
            if gesturePreview, time >= gestureStatusUntil { onGestureStatus?(scene.peace ? "已识别目标手势 · 可转动手掌测试" : "未识别目标手势 · 完整举手入镜，可点击开始学习") }
            return
        }
        if time - gestureStarted > 30 {
            gestureEnrolling = false; gestureSamples.removeAll(); gestureStatusUntil = time + 3
            onGestureEnrollment?(nil, "学习超时 · 请让一只手完整入镜，再试一次", gestureToken)
            return
        }
        guard hands.count == 1 else { onGestureStatus?("学习中 · 请只举一只手，完整入镜"); return }
        let points = PeaceGesture.points(hands[0], minimumConfidence: 0.55)
        guard let sample = GestureDescriptor(points: points, includeAllJoints: true, palmAnchor: true) else {
            onGestureStatus?("学习中 \(gestureSamples.count)/24 · 保持你选的手势，让手指和手腕完整入镜")
            return
        }
        guard let fingers = FingerShape.signature(points) else { return }
        let states = fingers.map(\.state)
        if learningFingerStates == nil {
            pendingFingerCount = pendingFingerStates == states ? pendingFingerCount + 1 : 1
            pendingFingerStates = states
            guard pendingFingerCount >= 3 else { onGestureStatus?("请保持同一个动作 · 正在确认伸指组合"); return }
            learningFingerStates = states
        }
        guard learningFingerStates == states else {
            onGestureStatus?("手指组合改变或遮挡 · 不录入，请保持最初的同一个动作"); return
        }
        guard time - lastGestureSample >= 0.25 else { return }
        lastGestureSample = time; gestureSamples.append(sample)
        if gestureSamples.count == 24 {
            gestureEnrolling = false; gestureStatusUntil = time + 3
            let profile = GestureProfile(revision: 3, samples: gestureSamples); gestureSamples.removeAll()
            if let data = try? JSONEncoder().encode(profile) { onGestureEnrollment?(data, "学习完成 · 放下后再举起，转动手掌测试识别", gestureToken) }
            else { onGestureEnrollment?(nil, "学习保存失败，请重试", gestureToken) }
        } else {
            let angle = gestureSamples.count < 8 ? "正对镜头" : (gestureSamples.count < 16 ? "换一个常用倾斜角度" : "展示掌心或手背角度")
            onGestureStatus?("学习中 \(gestureSamples.count)/24 · \(angle)")
        }
    }
    private var angleProfile: ViewingAngleProfile?
    private var angleConfigured = false
    private var anglePreview = false
    private var angleLearning: ViewingAngleLearning?
    private var angleToken = 0
    private var angleStatusUntil = 0.0
    var onAngleStatus: ((String) -> Void)?
    var onAngleEnrollment: ((Data?, String, Int) -> Void)?
    func loadAngles(_ data: Data?, configured: Bool? = nil) {
        queue.async { [self] in
            angleConfigured = configured ?? (data != nil)
            angleProfile = data.flatMap { try? JSONDecoder().decode(ViewingAngleProfile.self, from: $0) }
        }
    }
    func setAnglePreview(_ value: Bool) { queue.async { [self] in anglePreview = value } }
    func learnAngles(token: Int, append: Bool = false) {
        queue.async { [self] in
            angleToken = token; angleStatusUntil = 0
            angleLearning = ViewingAngleLearning(existing: append && angleProfile?.valid == true ? angleProfile!.samples : [])
        }
    }
    func cancelAngles() { queue.async { [self] in angleLearning = nil } }
    func finishAngles() {
        queue.async { [self] in
            guard let learning = angleLearning else { onAngleStatus?("请先点击开始学习"); return }
            guard let profile = learning.profile, let data = try? JSONEncoder().encode(profile) else {
                onAngleStatus?("样本不足 · 请继续正常观看并转头，至少录入 12 个样本"); return
            }
            angleLearning = nil; angleStatusUntil = ProcessInfo.processInfo.systemUptime + 2
            onAngleEnrollment?(data, "观看角度已保存 · 增强模式只允许已学习角度", angleToken)
        }
    }
    private func observeAngle(_ angle: ViewingAngle?, ownerAlone: Bool, time: Double) {
        guard anglePreview else { return }
        if angleLearning != nil {
            angleLearning?.observe(angle, ownerAlone: ownerAlone, time: time)
            onAngleStatus?(ownerAlone && angle != nil ? "已录入 \(angleLearning!.samples.count) 个样本 · 只展示能正常看屏幕的角度，结束后点击保存" : "无法确认主人独自在场或角度缺失 · 当前角度不录入")
        } else if time >= angleStatusUntil {
            guard ownerAlone, let angle else { onAngleStatus?("未确认主人独自在场，或角度不可用 · 不能激活"); return }
            let current = String(format: "左右 %.0f° / 上下 %.0f° / 侧倾 %.0f°", angle.yaw * 180 / .pi, angle.pitch * 180 / .pi, angle.roll * 180 / .pi)
            if let profile = angleProfile, profile.valid, let delta = profile.nearestDifferences(angle) {
                let difference = String(format: "最近样本差：%.1f° / %.1f° / %.1f°", delta[0], delta[1], delta[2])
                onAngleStatus?("\(profile.permits(angle) ? "角度匹配" : "角度不匹配") · \(current)\n\(difference) · 这里只测试角度；背景等条件仍单独生效")
            } else { onAngleStatus?("\(current) · 尚无有效观看角度，请开始学习") }
        }
    }
    private var motion = BackgroundMotion()
    private var scene = SceneFacts()
    var onResult: ((Int, Bool, TimeInterval, String, Int, SceneFacts) -> Void)?
    func setGestureMonitoring(_ value: Bool) { queue.async { [self] in gestureMonitoring = value; gestureConfirmations = 0 } }
    func setEnhanced(_ value: Bool) {
        queue.async { [self] in enhanced = value; motion.reset() }
    }
    private func emit(_ count: Int, _ matches: Bool, _ time: TimeInterval, _ message: String, _ token: Int) {
        onResult?(count, matches, time, message, token, scene)
    }
    var onEnrollment: ((Data?, String) -> Void)?
    var onFailure: ((String) -> Void)?

    func load(_ data: Data?) {
        queue.async { [self] in
            if let data, let profile = try? JSONDecoder().decode(OwnerProfile.self, from: data), profile.valid {
                profiles = profile.descriptors
            } else { profiles = [] }
        }
    }
    func start(generation token: Int) {
        queue.async { [self] in
            generation = token
            guard !running else { return }
            do {
                if recognizer == nil { recognizer = try SFaceRecognizer() }
                if session.inputs.isEmpty {
                    guard let camera = AVCaptureDevice.default(for: .video) else { throw CameraFailure.unavailable }
                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: queue)
                    session.beginConfiguration()
                    session.sessionPreset = .vga640x480
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        session.commitConfiguration(); throw CameraFailure.unavailable
                    }
                    session.addInput(input); session.addOutput(output); session.commitConfiguration()
                }
                running = true; session.startRunning()
                if !session.isRunning { running = false; onFailure?("摄像头无法启动，已禁止显示") }
            } catch { running = false; onFailure?("摄像头不可用，已禁止显示") }
        }
    }
    func stop() {
        queue.async { [self] in
            running = false; enrolling = false; enrollment.removeAll(); gestureEnrolling = false; gestureSamples.removeAll(); angleLearning = nil
            if session.isRunning { session.stopRunning() }
            recognizer = nil; motion.reset()
        }
    }
    func enroll() {
        queue.async { [self] in
            enrolling = true; enrollment.removeAll(); enrollmentStarted = Date(); lastEnrollmentSample = 0
        }
    }
    func cancelEnrollment() {
        queue.async { [self] in enrolling = false; enrollment.removeAll() }
    }
    func clearProfile() {
        queue.async { [self] in profiles.removeAll(); enrolling = false; enrollment.removeAll() }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard running, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let arrival = ProcessInfo.processInfo.systemUptime
        guard arrival - lastAnalysis >= 1.0 / 15 else { return }
        lastAnalysis = arrival
        autoreleasepool { analyze(buffer: buffer, arrival: arrival) }
    }
    private func analyze(buffer: CVPixelBuffer, arrival: Double) {
        scene = SceneFacts()
        do {
            facesRequest.inputFaceObservations = nil
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            // Observe gestures before any early identity rejection: closing needs no owner.
            if gestureMonitoring || gesturePreview {
                let hands = handsRequest
                try handler.perform([hands])
                let recognized = (gestureConfigured && gestureProfile == nil) ? false : PeaceGesture.detected(hands.results ?? [], profile: gestureProfile)
                gestureConfirmations = recognized ? min(3, gestureConfirmations + 1) : 0
                scene.peace = gestureConfirmations >= 3
                sampleGesture(hands.results ?? [], time: arrival)
            }
            if enhanced || anglePreview {
                // Revision 3 supplies continuous yaw/pitch; landmark default detection can omit pitch.
                try handler.perform([poseRequest, humansRequest])
                facesRequest.inputFaceObservations = poseRequest.results
                try handler.perform([facesRequest])
            } else { try handler.perform([facesRequest, humansRequest]) }
            let faces = facesRequest.results ?? []
            if enrolling, Date().timeIntervalSince(enrollmentStarted) > 25 {
                enrolling = false; enrollment.removeAll(); onEnrollment?(nil, "登记超时，请单独面对镜头重试")
            }
            let humanCount = (humansRequest.results ?? []).filter { $0.confidence >= 0.5 }.count
            guard faces.count == 1, humanCount <= 1 else {
                observeAngle(nil, ownerAlone: false, time: arrival)
                if enrolling, max(faces.count, humanCount) > 1 { enrollment.removeAll() }
                emit(max(faces.count, humanCount), false, arrival, faces.isEmpty && humanCount <= 1 ? "未见主人 · 已禁止显示" : "发现多人 · 已禁止显示", generation)
                return
            }
            let face = faces[0]
            guard face.confidence >= 0.5,
                  face.boundingBox.width * CGFloat(CVPixelBufferGetWidth(buffer)) >= 50,
                  face.boundingBox.height * CGFloat(CVPixelBufferGetHeight(buffer)) >= 50 else {
                observeAngle(nil, ownerAlone: false, time: arrival)
                emit(1, false, arrival, "请靠近一点，让脸部完整入镜 · 暂停显示", generation); return
            }
            if profiles.isEmpty, !enrolling {
                observeAngle(nil, ownerAlone: false, time: arrival)
                emit(1, false, arrival, "新版需要重新登记主人 · 暂停显示", generation); return
            }
            guard let recognizer else { throw CameraFailure.unavailable }
            let descriptor = try recognizer.descriptor(buffer: buffer, face: face)
            if enrolling {
                // Restart if the person changes during enrollment; never silently enroll a second face.
                if let first = enrollment.first {
                    let similarity = first.similarity(to: descriptor)
                    if similarity < 0.35 { enrollment.removeAll() }
                }
                guard arrival - lastEnrollmentSample >= 0.18 else {
                    emit(1, false, arrival, "登记主人 \(enrollment.count)/24 · 请缓慢转动脸部", generation); return
                }
                lastEnrollmentSample = arrival
                enrollment.append(descriptor)
                if enrollment.count >= 24 {
                    let data = try JSONEncoder().encode(OwnerProfile(revision: 3, descriptors: enrollment))
                    profiles = enrollment; enrolling = false; enrollment.removeAll()
                    onEnrollment?(data, "主人已登记 · 请测试本人离开及其他人出现")
                } else { emit(1, false, arrival, "登记主人 \(enrollment.count)/24 · 请缓慢转动脸部 · 暂停显示", generation) }
                return
            }
            let matches = FaceMatcher.matches(descriptor, profiles: profiles)
            let angle = ViewingAngle(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, roll: face.roll?.doubleValue)
            observeAngle(angle, ownerAlone: matches, time: arrival)
            if enhanced, matches {
                let background = motion.analyze(buffer: buffer, face: face.boundingBox)
                scene.ready = background.ready; scene.moving = background.moving
                scene.poseAvailable = angle != nil
                scene.frontFacing = angleConfigured ? (angleProfile?.permits(angle) ?? false) : FaceFacing.isFront(yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue)
                if !scene.frontFacing && angleConfigured { scene.viewingAngleDifference = angleProfile?.nearestDifferences(angle) }
            } else { motion.reset() }
            emit(1, matches, arrival, matches ? "仅见主人面部 · 允许显示" : "非主人或无法确认 · 已禁止显示", generation)
        } catch SFaceRecognizer.RecognitionError.landmarks {
            observeAngle(nil, ownerAlone: false, time: arrival)
            emit(1, false, arrival, "请让双眼和鼻口完整入镜 · 暂停显示", generation)
        } catch { scene.analysisFailed = true; observeAngle(nil, ownerAlone: false, time: arrival); emit(0, false, arrival, "人脸识别异常 · 已禁止显示", generation) }
    }
    private enum CameraFailure: Error { case unavailable }
}

@MainActor
final class CameraGuardian {
    private let worker = FaceCameraWorker()
    private(set) var enabled = false
    private(set) var enrolled = false
    private(set) var enhanced = false
    private var enhancedGate = EnhancedGate()
    private(set) var recoveryDelayEnabled = PortalPreferences.shared.object(forKey: "recoveryDelayEnabled") as? Bool ?? true
    private(set) var recoveryDelaySeconds = RecoveryDelay.clamp((PortalPreferences.shared.object(forKey: "recoveryDelaySeconds") as? NSNumber)?.doubleValue ?? 3)
    private(set) var gestureEnabled = false
    private var faceCount = 0
    private var ownerMatches = false
    private var ownerStreak = 0
    private var lastFrame: TimeInterval?
    private var rawOwnerMatch = false
    private var lastScene = SceneFacts()
    private var cameraFault = false
    private var portalRunning = false
    private var epoch = 0
    private var enrollmentWindow: NSWindow?
    private var previewing = false
    private var learningGesture = false
    private var gestureEpoch = 0
    private var learningAngles = false
    private var angleEpoch = 0
    private var anglesConfigured = false
    private let angleURL: URL
    private let enrollmentLabel = NSTextField(wrappingLabelWithString: "请确保镜头前只有自己。登记时缓慢向左右略微转脸，收集不同角度。")
    private let profileURL: URL
    private let gestureURL: URL
    var onChange: ((String) -> Void)?
    private var angleStability = RevealStability()
    var allowsReveal: Bool {
        !previewing && (!gestureEnabled || !enhancedGate.manuallyPaused) && (!enhanced || !enhancedGate.locked) && GuardianPolicy.permits(enabled: enabled, enrolled: enrolled, faceCount: faceCount, ownerMatches: ownerMatches,
                               lastFrame: lastFrame, now: ProcessInfo.processInfo.systemUptime)
    }
    var blockingStatus: DoorStatus? {
        GuardStatusSnapshot(enabled: enabled, previewing: previewing, enrolled: enrolled,
            manualLock: gestureEnabled && enhancedGate.manuallyPaused, cameraFault: cameraFault,
            hasFrame: lastFrame != nil, faceCount: faceCount, rawOwnerMatch: rawOwnerMatch,
            confirmedOwner: ownerMatches, enhanced: enhanced, frontFacing: lastScene.frontFacing,
            sceneReady: lastScene.ready, moving: lastScene.moving, automaticAllows: enhancedGate.allowsReveal).reason
    }
    init() {
        enhancedGate.recoveryDelay = recoveryDelayEnabled ? recoveryDelaySeconds : 0
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowDoorCamera", isDirectory: true)
        profileURL = directory.appendingPathComponent("owner.sface.v3")
        gestureURL = directory.appendingPathComponent("peace.gesture.v1")
        angleURL = directory.appendingPathComponent("viewing.angles.v1")
        let angleData = try? Data(contentsOf: angleURL)
        anglesConfigured = FileManager.default.fileExists(atPath: angleURL.path); worker.loadAngles(angleData, configured: anglesConfigured)
        worker.onAngleStatus = { [weak self] message in
            Task { @MainActor in
                guard let self, self.previewing, self.learningAngles else { return }
                self.enrollmentLabel.stringValue = message
            }
        }
        worker.onAngleEnrollment = { [weak self] data, message, token in
            Task { @MainActor in
                guard let self, self.previewing, self.learningAngles, self.angleEpoch == token, let data else { return }
                do {
                    try FileManager.default.createDirectory(at: self.angleURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try data.write(to: self.angleURL, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.angleURL.path)
                    self.anglesConfigured = true; self.worker.loadAngles(data)
                    self.enrollmentLabel.stringValue = message
                } catch { self.enrollmentLabel.stringValue = "角度资料保存失败 · 原有学习保留，请重新学习" }
            }
        }
        PortalPreferences.shared.removeObject(forKey: "enhancedGesturePaused")
        worker.loadGesture(try? Data(contentsOf: gestureURL), configured: FileManager.default.fileExists(atPath: gestureURL.path))
        worker.onGestureStatus = { [weak self] message in
            Task { @MainActor in
                guard let self, self.previewing, self.learningGesture else { return }
                self.enrollmentLabel.stringValue = message
            }
        }
        worker.onGestureEnrollment = { [weak self] data, message, token in
            Task { @MainActor in
                guard let self, self.previewing, self.learningGesture else { return }
                guard self.gestureEpoch == token else { return }
                do {
                    if let data {
                        try FileManager.default.createDirectory(at: self.gestureURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        try data.write(to: self.gestureURL, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.gestureURL.path)
                        self.worker.loadGesture(data)
                    }
                    self.enrollmentLabel.stringValue = message
                } catch { self.enrollmentLabel.stringValue = "手势资料无法保存 · 原有学习保留" }
            }
        }
        if let data = try? Data(contentsOf: profileURL),
           let profile = try? JSONDecoder().decode(OwnerProfile.self, from: data), profile.valid {
            enrolled = true; worker.load(data)
        }
        worker.onResult = { [weak self] count, matches, time, message, generation, scene in
            Task { @MainActor in
                guard let self, self.epoch == generation, self.enabled || self.previewing else { return }
                var scene = scene
                if self.enhanced {
                    self.angleStability.observe(safe: scene.frontFacing, time: time)
                    scene.frontFacing = scene.frontFacing && self.angleStability.confirmed
                }
                self.faceCount = count; self.rawOwnerMatch = matches; self.lastScene = scene; self.cameraFault = scene.analysisFailed
                self.ownerStreak = count == 1 && matches ? self.ownerStreak + 1 : 0
                self.ownerMatches = self.ownerStreak >= 3; self.lastFrame = time
                if !self.learningGesture && !self.learningAngles { self.enrollmentLabel.stringValue = message }
                var status = matches && !self.ownerMatches ? "正在确认主人 · 暂停显示" : message
                if (self.enhanced || self.gestureEnabled) && !self.previewing {
                    let safe = self.ownerMatches && count == 1 && self.enrolled && !self.previewing
                        && ProcessInfo.processInfo.systemUptime - time <= GuardianPolicy.freshness
                    let gestureEligible = count == 1 && self.ownerMatches && self.enrolled && !self.previewing
                        && ProcessInfo.processInfo.systemUptime - time <= GuardianPolicy.freshness
                    self.enhancedGate.update(ownerSafe: safe, scene: scene, now: time, gestureEligible: gestureEligible, gesturesEnabled: self.gestureEnabled, otherPersonPresent: count > 1 || (count > 0 && !matches))
                    if self.enhancedGate.manuallyPaused {
                        status = "临时手动保护 · 主人在场时再做手势解除"
                    } else if safe && self.enhanced {
                        if !scene.frontFacing {
                            if self.anglesConfigured, let delta = scene.viewingAngleDifference {
                                status = String(format: "角度不匹配 · 最近样本差 左右 %.1f° / 上下 %.1f° / 侧倾 %.1f°", delta[0], delta[1], delta[2])
                            } else if self.anglesConfigured && !scene.poseAvailable { status = "当前角度无法读取 · 暂停显示" }
                            else { status = self.anglesConfigured ? "观看角度资料不可用，请重新学习" : "请将面部朝向摄像头 · 暂停显示" }
                        }
                        else if scene.moving { status = "主人区域外有运动 · 暂停显示" }
                        else { status = self.enhancedGate.allowsReveal ? (self.anglesConfigured ? "主人观看角度匹配 · 允许显示" : "主人面部朝向摄像头 · 允许显示") : String(format: "等待安全环境稳定 %.1f 秒 · 暂停显示", self.recoveryDelayEnabled ? self.recoveryDelaySeconds : 0) }
                    }
                }
                self.onChange?(status)
            }
        }
        worker.onFailure = { [weak self] message in
            Task { @MainActor in
                self?.block(message, fault: true)
                if self?.previewing == true { self?.enrollmentLabel.stringValue = message }
            }
        }
        worker.onEnrollment = { [weak self] data, message in
            Task { @MainActor in
                guard let self else { return }
                do {
                    if let data {
                        try FileManager.default.createDirectory(at: self.profileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                               attributes: [.posixPermissions: 0o700])
                        try data.write(to: self.profileURL, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.profileURL.path)
                        self.enrolled = true
                        self.clearAngles()
                    }
                    self.enrollmentLabel.stringValue = message; self.block(message)
                } catch {
                    try? FileManager.default.removeItem(at: self.profileURL)
                    self.enrolled = false; self.worker.clearProfile(); self.block("主人资料无法保存，已禁止显示")
                }
            }
        }
    }
    func setEnabled(_ value: Bool) {
        if !value && enhanced { setEnhanced(false) }
        if !value && gestureEnabled { setGestureEnabled(false) }
        enabled = value; epoch += 1
        PortalPreferences.shared.set(value, forKey: "cameraGuardEnabled")
        block(value ? (enrolled ? "检查摄像头 · 暂停显示" : "SFace 需要重新登记主人 · 暂停显示") : "摄像头守护已关闭")
        reconcileCamera()
    }
    func setGestureEnabled(_ value: Bool) {
        gestureEnabled = value; enhancedGate.resetManualProtection(); worker.setGestureMonitoring(value)
        PortalPreferences.shared.set(value, forKey: "gestureProtectionEnabled")
        if value && !enabled { setEnabled(true) }
        else { onChange?(value ? "手势保护已开启 · 做手势可暂停" : "手势保护已关闭") }
    }
    func setRecoveryDelay(enabled: Bool, seconds: Double) {
        recoveryDelayEnabled = enabled; recoveryDelaySeconds = RecoveryDelay.clamp(seconds)
        enhancedGate.recoveryDelay = enabled ? recoveryDelaySeconds : 0
        PortalPreferences.shared.set(enabled, forKey: "recoveryDelayEnabled")
        PortalPreferences.shared.set(recoveryDelaySeconds, forKey: "recoveryDelaySeconds")
    }
    func setEnhanced(_ value: Bool) {
        enhanced = value; enhancedGate.invalidateFrame(); worker.setEnhanced(value)
        PortalPreferences.shared.set(value, forKey: "enhancedMode")
        if value && !enabled { setEnabled(true) }
        else { block(value ? "增强模式 · 等待主人面部朝向摄像头" : "增强模式已关闭 · 等待确认主人") }
    }
    func setPortalRunning(_ value: Bool) {
        guard portalRunning != value else { return }
        portalRunning = value; epoch += 1
        block(value ? "等待重新确认主人" : "窗口已关闭 · 摄像头暂停")
        reconcileCamera()
    }
    private var cameraNeeded: Bool { ResourcePolicy.needsCamera(guardEnabled: enabled, portalRunning: portalRunning, previewing: previewing) }
    private func reconcileCamera() {
        if cameraNeeded { requestCamera() } else { worker.stop() }
    }
    private func requestCamera() {
        guard cameraNeeded, !ProcessInfo.processInfo.arguments.contains("--ui-smoke-test"), !ProcessInfo.processInfo.arguments.contains("--face-model-test") else { return }
        epoch += 1; let token = epoch
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard token == epoch, cameraNeeded else { return }
            if allowed { worker.start(generation: token) }
            else {
                block("请在系统设置中允许摄像头 · 已禁止显示", fault: true)
                if previewing { enrollmentLabel.stringValue = "请在系统设置中允许摄像头，再重新打开学习或登记界面" }
            }
        }
    }
    private func block(_ message: String, fault: Bool = false) {
        angleStability.reset()
        cameraFault = fault; rawOwnerMatch = false; lastScene = SceneFacts()
        if enhanced { enhancedGate.invalidateFrame() }
        faceCount = 0; ownerMatches = false; ownerStreak = 0; lastFrame = nil; onChange?(message)
    }
    func showGestureLearning() { showEnrollment(learning: true) }
    func showAngleLearning() { showEnrollment(angles: true) }
    func showEnrollment(learning: Bool = false, angles: Bool = false, cameraAccess: Bool = true) {
        if let enrollmentWindow {
            if learningGesture == learning && learningAngles == angles { enrollmentWindow.makeKeyAndOrderFront(nil); return }
            enrollmentWindow.close()
        }
        learningGesture = learning; learningAngles = angles; previewing = true
        worker.setAnglePreview(angles)
        worker.setGesturePreview(learning)
        enrollmentLabel.stringValue = angles ? "先登记主人。点击开始后，只展示你能正常看屏幕的转头、抬头或低头角度，结束后点击保存。" : learning ? "只举一只手，保持你选的手势。点击开始后，始终保持同一个伸指组合，展示清晰掌心、手背和小幅倾斜，录入 24 个样本。不要混入其他动作。" : "请确保镜头前只有自己。登记时缓慢向左右略微转脸。"
        block(angles ? "正在学习观看角度 · 暂停显示" : learning ? "正在学习手势 · 暂停显示" : "正在登记主人 · 暂停显示")
        let window = EnrollmentWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: angles ? 420 : 390),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "视窗之门"
        window.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 420, height: angles ? 420 : 390))
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 12; root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), root.topAnchor.constraint(equalTo: container.topAnchor, constant: 16)])
        let preview = NSView(frame: CGRect(x: 0, y: 0, width: 388, height: 260)); preview.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: worker.session); layer.videoGravity = .resizeAspectFill
        preview.layer = layer
        preview.widthAnchor.constraint(equalToConstant: 388).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 260).isActive = true
        root.addArrangedSubview(preview)
        enrollmentLabel.constraints.filter { $0.firstAttribute == .width || $0.firstAttribute == .height }.forEach { $0.isActive = false }
        enrollmentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        enrollmentLabel.maximumNumberOfLines = angles ? 4 : 3; enrollmentLabel.lineBreakMode = .byWordWrapping
        root.addArrangedSubview(enrollmentLabel)
        NSLayoutConstraint.activate([enrollmentLabel.widthAnchor.constraint(equalToConstant: 388), enrollmentLabel.heightAnchor.constraint(equalToConstant: angles ? 60 : 48)])
        let register = NSButton(title: angles ? "开始学习" : learning ? "开始学习" : "登记当前主人", target: self, action: angles ? #selector(learnAngles) : learning ? #selector(learnGesture) : #selector(enrollOwner))
        let clear = NSButton(title: angles ? "清除角度" : learning ? "清除手势学习" : "删除主人资料", target: self, action: angles ? #selector(clearAngles) : learning ? #selector(clearGesture) : #selector(clearOwner))
        let done = NSButton(title: "完成", target: self, action: #selector(closeEnrollment))
        for button in [register, clear, done] { button.bezelStyle = .rounded; button.isBordered = false; button.font = .systemFont(ofSize: 12) }
        var buttons = [register, clear, done]
        if angles {
            let save = NSButton(title: "保存角度", target: self, action: #selector(finishAngles)); save.bezelStyle = .rounded; save.isBordered = false; save.font = .systemFont(ofSize: 12)
            buttons.insert(save, at: 1)
            let append = NSButton(title: "追加视角", target: self, action: #selector(appendAngles)); append.bezelStyle = .rounded; append.isBordered = false; append.font = .systemFont(ofSize: 12)
            buttons.insert(append, at: 1)
        }
        let buttonRow = NSStackView(views: buttons); buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually; buttonRow.spacing = 6
        NSLayoutConstraint.activate([buttonRow.widthAnchor.constraint(equalToConstant: 388), buttonRow.heightAnchor.constraint(equalToConstant: 26)])
        buttons.forEach { $0.heightAnchor.constraint(equalToConstant: 26).isActive = true }
        root.addArrangedSubview(buttonRow)
        window.contentView = container
        window.onClose = { [weak self] in
            guard let self else { return }
            self.gestureEpoch += 1; self.angleEpoch += 1; self.previewing = false; self.learningGesture = false; self.learningAngles = false; self.enrollmentWindow = nil
            self.worker.cancelAngles(); self.worker.setAnglePreview(false); self.worker.cancelEnrollment(); self.worker.cancelGestureLearning(); self.worker.setGesturePreview(false)
            self.reconcileCamera()
            self.block("登记结束 · 等待重新确认主人")
        }
        enrollmentWindow = window; window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); if cameraAccess { requestCamera() }
    }
    // Checks the actual learning controls without starting the camera or recording samples.
    func verifyGestureLearningUI(directory: String) -> Bool { verifyLearningUI(directory: directory, angles: false) }
    func verifyAngleLearningUI(directory: String) -> Bool { verifyLearningUI(directory: directory, angles: true) }
    private func verifyLearningUI(directory: String, angles: Bool) -> Bool {
        showEnrollment(learning: !angles, angles: angles, cameraAccess: false)
        guard let window = enrollmentWindow, let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        var fits = true
        func checkControls(_ node: NSView) {
            if node is NSButton || node is NSTextField {
                let rect = node.convert(node.bounds, to: view)
                fits = fits && rect.minX >= 0 && rect.maxX <= view.bounds.width && rect.minY >= 0 && rect.maxY <= view.bounds.height
            }
            node.subviews.forEach(checkControls)
        }
        checkControls(view)
        var controls: [NSView] = []
        func collect(_ node: NSView) { if node is NSButton { controls.append(node) }; node.subviews.forEach(collect) }
        collect(view)
        let frames = controls.map { $0.convert($0.bounds, to: view) }
        let originalText = enrollmentLabel.stringValue
        for text in ["左右 0° / 上下 1° / 侧倾 9°", "角度不匹配 · 左右 -179° / 上下 100° / 侧倾 -99°\n最近样本差：179.9° / 100.0° / 99.9° · 这里只测试角度；背景等条件仍单独生效", "已录入 999 个样本 · 只展示能正常看屏幕的角度，结束后点击保存"] {
            enrollmentLabel.stringValue = text; view.layoutSubtreeIfNeeded()
            fits = fits && controls.enumerated().allSatisfy { $0.element.convert($0.element.bounds, to: view) == frames[$0.offset] }
        }
        enrollmentLabel.stringValue = originalText
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(angles ? "viewing-angle-learning-preview.png" : "gesture-learning-preview.png"))
        }
        let blockedWhileLearning = !allowsReveal
        window.close()
        return fits && blockedWhileLearning && !previewing
    }
    @objc private func learnAngles() {
        guard enrolled else { enrollmentLabel.stringValue = "请先关闭此页并登记主人，再学习观看角度"; return }
        angleEpoch += 1; worker.learnAngles(token: angleEpoch)
        enrollmentLabel.stringValue = "学习中 · 只展示能正常看屏幕的角度，结束后点击保存角度"
    }
    @objc private func appendAngles() {
        guard enrolled else { enrollmentLabel.stringValue = "请先登记主人"; return }
        angleEpoch += 1; worker.learnAngles(token: angleEpoch, append: true)
        enrollmentLabel.stringValue = "补充学习中 · 保留旧样本，展示遗漏的正常观看视角后点击保存"
    }
    @objc private func finishAngles() { worker.finishAngles() }
    @objc private func clearAngles() {
        angleEpoch += 1; worker.cancelAngles()
        do {
            if FileManager.default.fileExists(atPath: angleURL.path) { try FileManager.default.removeItem(at: angleURL) }
            anglesConfigured = false; worker.loadAngles(nil)
            enrollmentLabel.stringValue = "角度学习已清除 · 恢复默认正对镜头规则"
        } catch { enrollmentLabel.stringValue = "角度清除失败 · 原有规则保留" }
    }
    @objc private func learnGesture() {
        enrollmentLabel.stringValue = "请保持你选的手势，缓慢转动手掌 · 0/24"
        gestureEpoch += 1; worker.learnGesture(token: gestureEpoch)
    }
    @objc private func clearGesture() {
        gestureEpoch += 1
        do {
            if FileManager.default.fileExists(atPath: gestureURL.path) { try FileManager.default.removeItem(at: gestureURL) }
            worker.cancelGestureLearning(); worker.loadGesture(nil)
            enrollmentLabel.stringValue = "手势学习已清除 · 恢复标准比耶识别"
        } catch { enrollmentLabel.stringValue = "手势学习清除失败，请重试" }
    }
    @objc private func enrollOwner() {
        block("正在登记主人 · 暂停显示"); worker.enroll()
    }
    @objc private func clearOwner() {
        do {
            for url in [angleURL, profileURL, profileURL.deletingLastPathComponent().appendingPathComponent("owner.v2")] {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        }
        catch { block("主人资料删除失败"); return }
        anglesConfigured = false; worker.loadAngles(nil)
        enrolled = false; worker.clearProfile(); block("主人资料已删除 · 请重新登记")
        enrollmentLabel.stringValue = "主人资料已删除 · 请重新登记"
    }
    @objc private func closeEnrollment() { enrollmentWindow?.close() }
    // Run the actual bundled open-source model and verify the saved descriptor schema.
    static func verifyFeatureStorage() -> Bool {
        do {
            let recognizer = try SFaceRecognizer()
            let context = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 384,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            // No face in this pattern: landmarks must reject it rather than invent an identity.
            do { _ = try recognizer.descriptor(image: context.makeImage()!); return false }
            catch SFaceRecognizer.RecognitionError.landmarks { }
            var values = [Float](repeating: 0, count: 128); values[0] = 1
            let descriptor = FaceDescriptor(values: values)
            let profile = OwnerProfile(revision: 3, descriptors: Array(repeating: descriptor, count: 24))
            let archive = try JSONEncoder().encode(profile)
            let restored = try JSONDecoder().decode(OwnerProfile.self, from: archive)
            return restored.valid && restored.descriptors.first!.similarity(to: descriptor) > 0.999
        } catch { print("SFace storage test: \(error)"); return false }
    }
    func refresh() {
        if enabled, let lastFrame, ProcessInfo.processInfo.systemUptime - lastFrame > GuardianPolicy.freshness {
            block("摄像头画面超时 · 已禁止显示", fault: true)
        }
    }
    func stop() { epoch += 1; worker.stop() }
}

private final class EnrollmentWindow: NSWindow {
    var onClose: (() -> Void)?
    override func close() { onClose?(); super.close() }
}

import AppKit
import ScreenCaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SCContentSharingPickerObserver, NSPopoverDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let detailPopover = NSPopover()
    private var gridRows: [NSView] = []
    private var gridStacks: [NSStackView] = []
    private var expandedRow: Int?
    private var expandedCard: NSView?
    private var expandedTile: SettingsTile?
    private var remainingTile: SettingsTile?
    private var compactTile: SettingsTile?
    private let compactNames: Set<String> = ["跟随窗口", "摄像头守护", "手势保护"]
    private var dismissGridMonitor: Any?
    private var sideCardsReady = false
    private var detailName = ""
    private var opacityPreviewTag: Int?
    private var helpMode = false
    private var helpModeButton: TileButton!
    private var helpDocumentTile: SettingsTile!
    private let briefStatus = NSTextField(labelWithString: "已关闭")
    private var helpHoverMonitor: Any?
    private let contextHelp = NSTextField(wrappingLabelWithString: "移到按钮上查看说明。")
    private let expandableNames: Set<String> = ["跟随窗口", "摄像头守护", "增强模式", "手势保护", "透明度平移"]
    private var sideSliders: [Int: NSSlider] = [:]
    private var sideFields: [Int: NSTextField] = [:]
    private var sideSwitches: [Int: NSSwitch] = [:]
    private var sideActions: [NSButton] = []
    private let shortcuts = ShortcutController()
    private let guardian = CameraGuardian()
    private let guardianSwitch = NSSwitch()
    private let enhancedSwitch = NSSwitch()
    private let recoveryDelaySwitch = NSSwitch()
    private let recoveryDelayField = NSTextField(string: "3")
    private var recoveryDelayRow: NSStackView!
    private let mouseSwitch = NSSwitch()
    private let gestureSwitch = NSSwitch()
    private let guardianLabel = NSTextField(wrappingLabelWithString: "摄像头守护已关闭")
    private var settingsController: NSViewController?
    private var tiles: [SettingsTile] = []
    private var buttonNames = PortalPreferences.shared.bool(forKey: "showButtonNames")
    private var nameButton: NSButton!
    private var toolbarButtons: [(button: NSButton, name: String, symbol: String)] = []
    private var tileHeaderKey = ""
    private var opacityDetailsOpen = false
    private var delayDetailsOpen = false
    private var delayDetails: NSStackView!
    private var tileControlsReady = false
    private var shortcutButtons: [ShortcutAction: NSButton] = [:]
    private let editHelp = NSTextField(labelWithString: "")
    private var portal: PortalPanel!
    private let portalView = PortalView()
    private let engine = CaptureEngine()
    private let systemPicker = SCContentSharingPicker.shared
    private let sourceLabel = NSTextField(labelWithString: "尚未选择窗口")
    private let statusLabel = NSTextField(wrappingLabelWithString: "选择窗口后，移入矩形查看。")
    private let chooseButton = NSButton(title: "选择窗口…", target: nil, action: nil)
    private let startButton = NSButton(title: "开始", target: nil, action: nil)
    private let borderSwitch = NSSwitch()
    private let followSwitch = NSSwitch()
    private let trackSwitch = NSSwitch()
    private var trackRow: NSStackView!
    private var sourceFollower = SourcePositionFollower()
    private var selectedWindowID: CGWindowID?
    private var rememberedWindow: WindowSelection?
    private var nextPositionPoll = 0.0
    private let opacitySlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let opacityShiftSwitch = NSSwitch()
    private let pointerPassSwitch = NSSwitch()
    private let pointerRouter = PointerRouter()
    private let pointerLabel = NSTextField(wrappingLabelWithString: "后台输入 · 等待操作")
    private var lastPointerPermission: Bool?
    private var nextPointerPermissionPoll = 0.0
    private let minimumSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let maximumSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let minimumField = NSTextField(string: "0")
    private let maximumField = NSTextField(string: "100")
    private var opacityRange = OpacityRange(minimum: 0, maximum: 100)
    private var normalOpacityRow: NSStackView!
    private var rangeRows: NSStackView!
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private var selectionSizing = SelectionSizing()
    private var selectedFilter: SCContentFilter?
    private var enabled = false
    private var busy = false
    private var timer: Timer?
    private var receivedFrame = false
    private var captureStartedAt = Date.distantPast
    private var generation = 0
    private var captureFault = false
    private var displayedStatus: DoorStatus?
    private var targetFrontmost = false
    private var nextStackPoll: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let data = PortalPreferences.shared.data(forKey: "selectedWindowV1") {
            rememberedWindow = try? JSONDecoder().decode(WindowSelection.self, from: data)
            if let rememberedWindow { sourceLabel.stringValue = rememberedWindow.displayName }
        }
        makePopover()
        makeStatusItem()
        makePortal()
        shortcuts.onAction = { [weak self] action in self?.performShortcut(action) }
        shortcuts.onRecorded = { [weak self] in self?.showShortcutPage() }
        guardian.onChange = { [weak self] message in
            guard let self else { return }
            if self.guardianLabel.stringValue != message { self.guardianLabel.stringValue = message }
            self.updateStatusIcon()
            self.gestureSwitch.state = self.guardian.gestureEnabled ? .on : .off
            self.guardianSwitch.state = self.guardian.enabled ? .on : .off
            self.guardianSwitch.isEnabled = true
            self.enhancedSwitch.state = self.guardian.enhanced ? .on : .off
            if !self.guardian.allowsReveal {
                self.applyAppearance(active: false)
                self.shortcuts.setScopeActive(false)
            }
        }
        if !ProcessInfo.processInfo.arguments.contains("--ui-smoke-test"),
           !ProcessInfo.processInfo.arguments.contains("--face-model-test"),
           !ProcessInfo.processInfo.arguments.contains("--pointer-diagnostics"),
           (PortalPreferences.shared.bool(forKey: "cameraGuardEnabled") || PortalPreferences.shared.bool(forKey: "enhancedMode") || PortalPreferences.shared.bool(forKey: "gestureProtectionEnabled")) {
            guardian.setEnabled(true)
            if PortalPreferences.shared.bool(forKey: "enhancedMode") { guardian.setEnhanced(true) }
            if PortalPreferences.shared.bool(forKey: "gestureProtectionEnabled") { guardian.setGestureEnabled(true) }
        }
        systemPicker.add(self)
        engine.onScreenRect = { [weak self] bounds in
            guard let self, self.enabled else { return }
            self.observeSourceBounds(bounds)
        }
        engine.onFrame = { [weak self] frame in
            guard let self, self.enabled else { return }
            if !self.receivedFrame || self.portalView.frameImage == nil {
                self.statusLabel.stringValue = self.mouseSwitch.state == .on ? "正在运行 · 悬停矩形查看" : "正在运行 · 由人脸控制显示"
            }
            self.receivedFrame = true; self.captureFault = false
            self.portalView.frameImage = frame
            if self.portalView.reveal { self.portalView.needsDisplay = true }
        }
        engine.onUnavailable = { [weak self] message in
            self?.captureFault = true
            self?.pointerRouter.cancel()
            self?.shortcuts.setScopeActive(false)
            self?.portalView.frameImage = nil
            self?.portalView.reveal = false
            self?.portalView.needsDisplay = true
            self?.statusLabel.stringValue = message
        }
        engine.onError = { [weak self] message in
            guard let self else { return }
            self.captureFault = true; self.enabled = false; self.selectedFilter = nil
            self.portalView.frameImage = nil; self.portalView.reveal = false
            self.portalView.needsDisplay = true
            self.statusLabel.stringValue = message
            self.updateControls()
        }
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        if ProcessInfo.processInfo.arguments.contains("--pointer-diagnostics") {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let report = self.pointerRouter.diagnostics(selection: self.rememberedWindow)
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { print(String(data: data, encoding: .utf8)!) }
                NSApp.terminate(nil)
            }
        } else if ProcessInfo.processInfo.arguments.contains("--face-model-test") {
            DispatchQueue.main.async { SFaceValidation.run(); NSApp.terminate(nil) }
        } else if ProcessInfo.processInfo.arguments.contains("--ui-smoke-test") {
            // Keep this app's test popover open if the user interacts with another app.
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.toggleSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.verifySettingsUI() }
            }
        } else if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.toggleSettings() }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if shortcuts.isRecording { shortcuts.cancelRecording() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggleSettings() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pointerRouter.cancel()
        shortcuts.shutdown()
        guardian.stop()
        systemPicker.remove(self); systemPicker.isActive = false
    }

    // Developer-only UI smoke check: renders this app's own settings, never captures the desktop.
    private func verifySettingsUI() {
        guard let view = popover.contentViewController?.view else { NSApp.terminate(nil); return }
        view.layoutSubtreeIfNeeded()
        let delayWasHidden = recoveryDelayRow.isHidden
        recoveryDelayRow.isHidden = false; refreshOpacityControls(); view.layoutSubtreeIfNeeded()
        let delayFrame = recoveryDelayRow.convert(recoveryDelayRow.bounds, to: view)
        let recoveryControlsFit = delayFrame.minY >= 0 && delayFrame.maxY <= view.bounds.height && recoveryDelayField.isEditable
        recoveryDelayRow.isHidden = delayWasHidden; refreshOpacityControls(); view.layoutSubtreeIfNeeded()
        let originalOutline = portalView.showOutline
        portalView.showOutline = false
        let borderDisabled = !portalView.showOutline
        portalView.showOutline = originalOutline
        var fits = true
        if let root = view.subviews.first as? NSStackView {
            for child in root.arrangedSubviews where !child.isHidden {
                let rect = child.convert(child.bounds, to: view)
                fits = fits && rect.minY >= 0 && rect.maxY <= view.bounds.height
            }
        }
        // Check partial alpha using a synthetic image, not the user's captured window.
        let originalNames = buttonNames
        buttonNames = true; refreshTiles()
        let tileNamesVisible = tiles.count == 9 && tiles.allSatisfy { $0.main.image == nil && !$0.main.title.isEmpty }
        buttonNames = false; refreshTiles()
        let tileIconsVisible = tiles.allSatisfy { $0.main.image != nil && $0.main.title.isEmpty }
        let beforeRefresh = tiles.map { $0.main.refreshCount }
        for _ in 0..<100 { refreshTiles() }
        let tileRenderingCached = beforeRefresh == tiles.map { $0.main.refreshCount }
        buttonNames = originalNames; refreshTiles()
        let originalFrame = portal.frame
        let originalSource = portalView.sourceBounds
        let originalOpacity = portalView.contentOpacity
        let originalRange = opacityRange
        let savedShiftState = opacityShiftSwitch.state
        let originalEnabled = enabled
        portalView.showOutline = false
        portalView.editing = false
        portalView.reveal = true
        portalView.sourceBounds = PortalGeometry.quartzRect(portal.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        portalView.frameImage = CapturedFrame(image: context.makeImage()!, contentRect: CGRect(x: 0, y: 0, width: 32, height: 32), screenRect: nil)
        portalView.contentOpacity = 0.35
        var partialAlpha = false
        if let rep = portalView.bitmapImageRepForCachingDisplay(in: portalView.bounds) {
            portalView.cacheDisplay(in: portalView.bounds, to: rep)
            let alpha = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? -1
            partialAlpha = abs(alpha - 0.35) < 0.03
        }
        func renderedAlpha() -> CGFloat {
            guard let rep = portalView.bitmapImageRepForCachingDisplay(in: portalView.bounds) else { return -1 }
            portalView.cacheDisplay(in: portalView.bounds, to: rep)
            return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? -1
        }
        opacityShiftSwitch.state = .on; opacityRange = OpacityRange(minimum: 20, maximum: 80)
        enabled = true; applyAppearance(active: false)
        let minimumRendered = portalView.reveal && abs(renderedAlpha() - 0.2) < 0.03
        applyAppearance(active: true)
        let maximumRendered = portalView.reveal && abs(renderedAlpha() - 0.8) < 0.03
        portalView.editing = true; applyAppearance(active: true)
        let editingKeepsVisible = portalView.reveal && abs(renderedAlpha() - 0.8) < 0.03
        portalView.editing = false
        opacityRange = OpacityRange(minimum: 0, maximum: 80); applyAppearance(active: false)
        let zeroMinimumClosesPanel = !portal.isVisible && portal.ignoresMouseEvents && !portalView.reveal
        applyAppearance(active: true)
        let reactivationShowsPanel = portal.isVisible && !portal.ignoresMouseEvents && portalView.reveal
        enabled = false; applyAppearance(active: false)
        let shiftStopsHidden = !portalView.reveal
        opacityRange = originalRange; opacityShiftSwitch.state = savedShiftState; enabled = originalEnabled
        refreshOpacityControls()
        portalView.frameImage = nil; portalView.reveal = false
        portalView.sourceBounds = originalSource; portalView.contentOpacity = originalOpacity
        portalView.showOutline = originalOutline
        selectionSizing.beginSelection(); applySelectionSize(CGSize(width: 640, height: 480))
        portal.setFrame(CGRect(x: 100, y: 100, width: 250, height: 150), display: true)
        applySelectionSize(CGSize(width: 900, height: 700))
        let manualSizePreserved = portal.frame.size == CGSize(width: 250, height: 150)
        let originalPointerCallback = portalView.onPointerEvent
        let originalManipulation = portalView.allowsManipulation
        var routedEvents: [NSEvent.EventType] = []
        portalView.onPointerEvent = { routedEvents.append($0.type) }
        portalView.allowsManipulation = false; portalView.editing = false
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
                                      windowNumber: portal.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let release = NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0.1,
                                        windowNumber: portal.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        portalView.mouseDown(with: click); portalView.mouseUp(with: release)
        let pointerViewRoutesClicks = routedEvents == [.leftMouseDown, .leftMouseUp]
        portalView.onPointerEvent = originalPointerCallback; portalView.allowsManipulation = originalManipulation
        let originalFollow = followSwitch.state
        let originalTrack = trackSwitch.state
        trackSwitch.state = .off
        followSwitch.state = .on
        let target = CGRect(x: 140, y: 230, width: 900, height: 700)
        observeSourceBounds(target)
        let followsSizeAndPosition = portal.frame == PortalGeometry.quartzRect(target, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        followSwitch.state = .off
        let beforeFreeze = portal.frame
        observeSourceBounds(CGRect(x: 200, y: 300, width: 1200, height: 900))
        let followOffStaysPut = portal.frame == beforeFreeze
        let savedTrack = trackSwitch.state
        trackSwitch.state = .on; sourceFollower.reset(to: portalView.sourceBounds.origin)
        let beforeTracking = portal.frame
        observeSourceBounds(CGRect(x: 230, y: 340, width: 1400, height: 1000))
        let trackingPreservesSizeOffset = portal.frame == beforeTracking.offsetBy(dx: 30, dy: -40)
        trackSwitch.state = savedTrack
        followSwitch.state = .on
        followChanged()
        let resumesAligned = portal.frame == PortalGeometry.quartzRect(portalView.sourceBounds, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        enabled = true; updateControls(); tick()
        let inactivePanelHidden = !portal.isVisible && portal.ignoresMouseEvents
        portalView.frameImage = CapturedFrame(image: context.makeImage()!, contentRect: CGRect(x: 0, y: 0, width: 32, height: 32), screenRect: nil)
        applyAppearance(active: true)
        let pointerPassesThrough = !portal.ignoresMouseEvents // Visible input is explicitly routed.
        let followDisablesEditing = !portalView.allowsManipulation && portal.isVisible && startButton.title == "关闭"
        enabled = false; updateControls()
        let stoppedHidden = !portal.isVisible && startButton.title == "开始"
        followSwitch.state = originalFollow; trackSwitch.state = originalTrack
        PortalPreferences.shared.set(originalFollow == .on, forKey: "followWindow")
        portalView.sourceBounds = originalSource
        portal.setFrame(originalFrame, display: true)
        let nonactivating = !portal.canBecomeKey && !portal.canBecomeMain
        var passed = tileNamesVisible && tileIconsVisible && tileRenderingCached && editingKeepsVisible && trackingPreservesSizeOffset && pointerViewRoutesClicks && minimumRendered && maximumRendered && shiftStopsHidden && followsSizeAndPosition && followOffStaysPut && resumesAligned && followDisablesEditing && stoppedHidden && pointerPassesThrough && partialAlpha && manualSizePreserved && nonactivating && statusItem.button != nil && popover.isShown && fits && borderDisabled && portal.frame.size == PortalGeometry.defaultSize
        let directory = ProcessInfo.processInfo.environment["HOVERPORTAL_UI_REPORT_DIR"] ?? NSTemporaryDirectory()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-preview.png"))
        }
        buttonNames = true; refreshTiles(); view.layoutSubtreeIfNeeded()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-names-preview.png"))
        }
        buttonNames = originalNames; refreshTiles()
        let initialShift = opacityShiftSwitch.state
        let originalOpacityDetails = opacityDetailsOpen
        opacityDetailsOpen = true
        opacityShiftSwitch.state = .on; refreshOpacityControls(); view.layoutSubtreeIfNeeded()
        var expandedFits = true
        if let root = view.subviews.first as? NSStackView {
            for child in root.arrangedSubviews where !child.isHidden {
                let rect = child.convert(child.bounds, to: view)
                expandedFits = expandedFits && rect.minY >= 0 && rect.maxY <= view.bounds.height
            }
        }
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("opacity-range-preview.png"))
        }
        opacityShiftSwitch.state = initialShift; opacityDetailsOpen = originalOpacityDetails; refreshOpacityControls()
        passed = passed && expandedFits
        showShortcutPage()
        let shortcutView = popover.contentViewController!.view
        shortcutView.layoutSubtreeIfNeeded()
        var shortcutsFit = shortcutButtons.count == ShortcutAction.allCases.count
        for button in shortcutButtons.values {
            let rect = button.convert(button.bounds, to: shortcutView)
            shortcutsFit = shortcutsFit && rect.minY >= 0 && rect.maxY <= shortcutView.bounds.height && rect.minX >= 0 && rect.maxX <= shortcutView.bounds.width
        }
        if let rep = shortcutView.bitmapImageRepForCachingDisplay(in: shortcutView.bounds) {
            shortcutView.cacheDisplay(in: shortcutView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("shortcuts-preview.png"))
        }
        finishShortcuts()
        let shortcutsReturn = popover.contentViewController === settingsController
        showHelpPage()
        let helpView = popover.contentViewController!.view
        helpView.layoutSubtreeIfNeeded()
        if let rep = helpView.bitmapImageRepForCachingDisplay(in: helpView.bounds) {
            helpView.cacheDisplay(in: helpView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("help-preview.png"))
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        let helpScroll = findScroll(helpView)
        let helpContentVisible = helpScroll?.documentView?.isFlipped == true
            && (helpScroll?.documentView?.bounds.height ?? 0) > (helpScroll?.contentView.bounds.height ?? 0)
            && helpScroll?.contentView.bounds.minY == 0
        passed = passed && helpContentVisible
        finishShortcuts()
        let helpReturns = popover.contentViewController === settingsController
        passed = passed && helpReturns
        let oldOpacity = opacitySlider.doubleValue
        let originalShift = opacityShiftSwitch.state
        opacityShiftSwitch.state = .off
        opacitySlider.doubleValue = 50
        performShortcut(.opacityUp); let upFive = opacitySlider.doubleValue == 55
        performShortcut(.opacityDown); let downFive = opacitySlider.doubleValue == 50
        opacitySlider.doubleValue = oldOpacity; opacityChanged()
        let savedRange = opacityRange
        opacityShiftSwitch.state = .on; opacityRange = OpacityRange(minimum: 15, maximum: 60)
        performShortcut(.opacityUp); let shiftedUp = opacityRange.maximum == 65 && opacityRange.minimum == 15
        performShortcut(.opacityDown); let shiftedDown = opacityRange.maximum == 60 && opacityRange.minimum == 15
        opacityRange = savedRange; saveOpacityRange()
        passed = passed && shiftedUp && shiftedDown
        opacityShiftSwitch.state = originalShift; refreshOpacityControls()
        let savedHelpNames = buttonNames
        buttonNames = true; refreshTiles(); toggleContextHelp(); showContextHelp("跟随窗口")
        let hoverHelpWorks = helpMode && contextHelp.stringValue == "同步目标窗口的位置和大小。"
            && helpModeButton.title.isEmpty && helpModeButton.image != nil && guardianLabel.isHidden
            && !helpDocumentTile.isHidden && helpDocumentTile.main.title.isEmpty && helpDocumentTile.main.image != nil
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("hover-help-preview.png"))
        }
        let savedHelpFrame = nameButton.convert(nameButton.bounds, to: settingsController?.view)
        showContextHelp("摄像头守护"); settingsController?.view.layoutSubtreeIfNeeded()
        let hoverHelpStable = nameButton.convert(nameButton.bounds, to: settingsController?.view) == savedHelpFrame
        toggleContextHelp(); buttonNames = savedHelpNames; refreshTiles()
        passed = passed && hoverHelpWorks && hoverHelpStable && contextHelp.isHidden && helpDocumentTile.isHidden
            && guardianLabel.isHidden && pointerLabel.isHidden && statusLabel.isHidden && editHelp.isHidden
        let shortcutChecks = ShortcutController.verify()
        passed = passed && shortcutsFit && shortcutsReturn && upFive && downFive && shortcutChecks.values.allSatisfy { $0 }
        let cameraPreferenceKeys = ["cameraGuardEnabled", "enhancedMode", "gestureProtectionEnabled"]
        let savedCameraPreferences = cameraPreferenceKeys.map { PortalPreferences.shared.object(forKey: $0) }
        let savedCameraSwitchStates = [guardianSwitch.state, enhancedSwitch.state, gestureSwitch.state]
        guardian.setPortalRunning(false); guardian.setEnhanced(true)
        let cameraRemainsClickable = guardianSwitch.isEnabled
        guardian.setEnabled(false)
        let cameraOffDisablesChildren = !guardian.enabled && !guardian.enhanced && !guardian.gestureEnabled
            && guardianSwitch.state == .off && enhancedSwitch.state == .off
        let savedPreviewRange = opacityRange
        opacityRange = OpacityRange(minimum: 22, maximum: 77)
        opacityPreviewTag = 1; applyAppearance(active: true)
        let minimumPreview = abs(portalView.contentOpacity - 0.22) < 0.001
        opacityPreviewTag = 2; applyAppearance(active: true)
        let maximumPreview = abs(portalView.contentOpacity - 0.77) < 0.001
        opacityPreviewTag = nil; opacityRange = savedPreviewRange; applyAppearance(active: false)
        let opacityPreviewChecks = minimumPreview && maximumPreview
        passed = passed && opacityPreviewChecks
        for (key, value) in zip(cameraPreferenceKeys, savedCameraPreferences) {
            if let value { PortalPreferences.shared.set(value, forKey: key) } else { PortalPreferences.shared.removeObject(forKey: key) }
        }
        guardianSwitch.state = savedCameraSwitchStates[0]; enhancedSwitch.state = savedCameraSwitchStates[1]; gestureSwitch.state = savedCameraSwitchStates[2]
        let savedSideFollow = followSwitch.state
        followSwitch.state = .on; showTileDetails("跟随窗口")
        let sideCardShows = expandedCard?.superview != nil && gridStacks[0].isHidden
        let sideTrackBlocked = sideSwitches[5]?.isEnabled == false
        followSwitch.state = .off; refreshSideControls()
        let sideTrackAvailable = sideSwitches[5]?.isEnabled == true
        followSwitch.state = savedSideFollow; closeSideCard()
        let savedSideShift = opacityShiftSwitch.state, savedSideRange = opacityRange
        opacityShiftSwitch.state = .on; showTileDetails("透明度平移")
        let sideRangeAvailable = sideFields[1]?.isEnabled == true && sideFields[2]?.isEnabled == true && sideFields[0] == nil && sideSliders.count == 2
        if let slider = sideSliders[2] { slider.doubleValue = 57; sideValueChanged(slider) }
        let sideValueApplied = opacityRange.maximum == 57
        let readOnlySliderValues = sideFields.values.allSatisfy { !$0.isEditable && !$0.isBordered } && sideSliders.values.allSatisfy { $0.cell is MinimalSliderCell }
        if let detailView = detailPopover.contentViewController?.view,
           let rep = detailView.bitmapImageRepForCachingDisplay(in: detailView.bounds) {
            detailView.cacheDisplay(in: detailView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("side-card-preview.png"))
        }
        opacityRange = savedSideRange; saveOpacityRange(); opacityShiftSwitch.state = savedSideShift; refreshOpacityControls(); closeSideCard()
        let savedDelayEnabled = guardian.recoveryDelayEnabled, savedDelaySeconds = guardian.recoveryDelaySeconds
        let savedEnhancedUI = enhancedSwitch.state
        enhancedSwitch.state = .on; showTileDetails("增强模式")
        var delaySliderOnly = sideSwitches[4] == nil && sideSliders[3]?.isEnabled == true
        if let slider = sideSliders[3] {
            slider.doubleValue = 2.4; sideValueChanged(slider)
            delaySliderOnly = delaySliderOnly && guardian.recoveryDelayEnabled && guardian.recoveryDelaySeconds == 2.4
            slider.doubleValue = 0; sideValueChanged(slider)
            delaySliderOnly = delaySliderOnly && !guardian.recoveryDelayEnabled && guardian.recoveryDelaySeconds == 0
        } else { delaySliderOnly = false }
        guardian.setRecoveryDelay(enabled: savedDelayEnabled, seconds: savedDelaySeconds)
        recoveryDelaySwitch.state = savedDelayEnabled ? .on : .off; recoveryDelayField.doubleValue = savedDelaySeconds
        enhancedSwitch.state = savedEnhancedUI; closeSideCard()
        passed = passed && delaySliderOnly
        var gridDirections = true
        for (index, tile) in tiles.enumerated() {
            if !expandableNames.contains(tile.main.name) {
                showTileDetails(tile.main.name)
                gridDirections = gridDirections && tile.main.expand == nil && expandedCard == nil
                continue
            }
            showTileDetails(tile.main.name)
            settingsController?.view.layoutSubtreeIfNeeded()
            let expectedX: CGFloat = index % 3 == 2 ? (compactNames.contains(tile.main.name) ? 92 : gridRows[index / 3].bounds.width - 84) : 0
            gridDirections = gridDirections && expandedRow == index / 3 && gridStacks[index / 3].isHidden
                && abs((expandedTile?.frame.minX ?? -100) - expectedX) < 1
                && abs((expandedTile?.frame.width ?? 0) - (expandedTile?.frame.height ?? 1)) < 1
                && abs((expandedCard?.frame.width ?? 0) - (compactNames.contains(tile.main.name) ? 176 : 268)) < 1
                && (compactNames.contains(tile.main.name) ? remainingTile != nil && compactTile != nil : remainingTile == nil)
            if let view = settingsController?.view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("expanded-grid-\(index+1).png"))
            }
            closeSideCard()
            gridDirections = gridDirections && !gridStacks[index / 3].isHidden && expandedCard == nil
        }
        let savedGuardianMessage = guardianLabel.stringValue
        let savedStatusMessage = statusLabel.stringValue
        refreshOpacityControls(); settingsController?.view.layoutSubtreeIfNeeded()
        let toolbarFrame = nameButton.convert(nameButton.bounds, to: settingsController?.view)
        var statusLayoutStable = true
        for message in ["左右 0° / 上下 1°", "角度不匹配 · 最近样本差 左右 179.9° / 上下 100.0° / 侧倾 -99.9°"] {
            guardianLabel.stringValue = message; statusLabel.stringValue = message
            refreshOpacityControls(); settingsController?.view.layoutSubtreeIfNeeded()
            statusLayoutStable = statusLayoutStable && nameButton.convert(nameButton.bounds, to: settingsController?.view) == toolbarFrame
        }
        guardianLabel.stringValue = savedGuardianMessage; statusLabel.stringValue = savedStatusMessage
        passed = passed && gridDirections && readOnlySliderValues && statusLayoutStable
        let simpleTiles = tiles.allSatisfy { $0.children.isEmpty }
        passed = passed && cameraRemainsClickable && cameraOffDisablesChildren && sideCardShows && sideTrackBlocked && sideTrackAvailable && sideRangeAvailable && sideValueApplied && simpleTiles
        func windowInfo(_ id: Int, _ pid: Int, _ x: CGFloat) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: x,y: 0,width: 100,height: 100).dictionaryRepresentation]
        }
        let targetWindow = windowInfo(1, 10, 0), coveredWindow = windowInfo(2, 20, 20), ownOverlay = windowInfo(3, 30, 0), unrelated = windowInfo(4, 40, 300)
        let automaticFrontChecks = WindowFrontPolicy.targetIsFrontmost([targetWindow, coveredWindow], target: 1, ownPID: 30)
            && !WindowFrontPolicy.targetIsFrontmost([coveredWindow, targetWindow], target: 1, ownPID: 30)
            && WindowFrontPolicy.targetIsFrontmost([ownOverlay, targetWindow], target: 1, ownPID: 30)
            && WindowFrontPolicy.targetIsFrontmost([unrelated, targetWindow], target: 1, ownPID: 30)
        passed = passed && automaticFrontChecks
        let now = 100.0
        let guardianChecks: [String: Bool] = [
            "statusReasonIconsRendered": DoorStatusIcon.verify(directory: directory),
            "guardianFeatureArchiveRoundTrip": CameraGuardian.verifyFeatureStorage(),
            "gestureLearningUIFitsAndBlocksReveal": guardian.verifyGestureLearningUI(directory: directory),
            "viewingAngleLearningUIFitsAndBlocksReveal": guardian.verifyAngleLearningUI(directory: directory),
            "guardianOwnerOnly": GuardianPolicy.permits(enabled: true, enrolled: true, faceCount: 1, ownerMatches: true, lastFrame: now, now: now),
            "guardianRejectsOthers": !GuardianPolicy.permits(enabled: true, enrolled: true, faceCount: 1, ownerMatches: false, lastFrame: now, now: now),
            "guardianRejectsMultiple": !GuardianPolicy.permits(enabled: true, enrolled: true, faceCount: 2, ownerMatches: true, lastFrame: now, now: now),
            "guardianRejectsNoFace": !GuardianPolicy.permits(enabled: true, enrolled: true, faceCount: 0, ownerMatches: false, lastFrame: now, now: now),
            "guardianRejectsStaleCamera": !GuardianPolicy.permits(enabled: true, enrolled: true, faceCount: 1, ownerMatches: true, lastFrame: now - 1, now: now),
            "guardianRejectsUnenrolled": !GuardianPolicy.permits(enabled: true, enrolled: false, faceCount: 1, ownerMatches: true, lastFrame: now, now: now)]
        passed = passed && recoveryControlsFit && guardianChecks.values.allSatisfy { $0 }
        passed = passed && zeroMinimumClosesPanel && reactivationShowsPanel && inactivePanelHidden
        var report: [String: Any] = ["result": passed ? "passed" : "failed", "menuBarButton": statusItem.button != nil,
            "popoverVisible": popover.isShown, "controlsFit": fits, "borderCanDisable": borderDisabled,
            "defaultWidth": portal.frame.width, "followsSizeAndPosition": followsSizeAndPosition, "followOffStaysPut": followOffStaysPut, "resumesAligned": resumesAligned, "followDisablesEditing": followDisablesEditing, "stoppedHidden": stoppedHidden, "pointerPassesThrough": pointerPassesThrough,
            "partialOpacityRendered": partialAlpha, "manualSizePreserved": manualSizePreserved, "panelCannotFocus": nonactivating,
            "defaultHeight": portal.frame.height,
            "note": "Checks the real AppKit status item, popover and own settings rendering. Hardware Option gestures still need manual verification."]
        report["recoveryDelayControlsFit"] = recoveryControlsFit
        report["expandedOpacityControlsFit"] = expandedFits
        report["minimumOpacityRendered"] = minimumRendered
        report["maximumOpacityRendered"] = maximumRendered
        report["zeroMinimumClosesPanel"] = zeroMinimumClosesPanel
        report["reactivationShowsPanel"] = reactivationShowsPanel
        report["inactivePanelHidden"] = inactivePanelHidden
        report["shiftStopsHidden"] = shiftStopsHidden
        report["pointerViewRoutesClicks"] = pointerViewRoutesClicks
        report["cameraRemainsClickable"] = cameraRemainsClickable
        report["cameraOffDisablesChildren"] = cameraOffDisablesChildren
        report["sideCardShows"] = sideCardShows
        report["sideTrackBlocked"] = sideTrackBlocked
        report["sideTrackAvailable"] = sideTrackAvailable
        report["sideRangeAvailable"] = sideRangeAvailable
        report["sideValueApplied"] = sideValueApplied
        report["hoverHelpWorksAndKeepsQuestionIcon"] = hoverHelpWorks
        report["hoverHelpStable"] = hoverHelpStable
        report["automaticFrontPausePolicy"] = automaticFrontChecks
        report["opacitySliderPreviewsBothValues"] = opacityPreviewChecks
        report["simpleTiles"] = simpleTiles
        report["gridDirectionsAndRestore"] = gridDirections
        report["readOnlySliderValues"] = readOnlySliderValues
        report["statusLayoutStable"] = statusLayoutStable
        report["delaySliderOnlyAndZeroDisables"] = delaySliderOnly
        report["tileNamesVisible"] = tileNamesVisible
        report["tileIconsVisible"] = tileIconsVisible
        report["tileRenderingCached"] = tileRenderingCached
        report["editingKeepsVisible"] = editingKeepsVisible
        report["trackingPreservesSizeOffset"] = trackingPreservesSizeOffset
        report["pointerInputConsumedByOverlay"] = pointerPassesThrough
        report["pointerAccessibilityGranted"] = PointerRouter.trusted
        report["pointerRouting"] = "Destination addressing verified separately; actual third-party delivery requires Accessibility permission and manual testing."
        report["helpReturns"] = helpReturns
        report["helpContentVisible"] = helpContentVisible
        report["shortcutsFit"] = shortcutsFit; report["shortcutsReturn"] = shortcutsReturn
        report["opacityShortcutFivePercent"] = upFive && downFive
        report["shiftShortcutAdjustsMaximum"] = shiftedUp && shiftedDown
        for (key, value) in shortcutChecks { report[key] = value }
        for (key, value) in guardianChecks { report[key] = value }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("menu-verification.json"))
            print(String(data: data, encoding: .utf8)!)
        }
        NSApp.terminate(nil)
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "视窗之门 设置")
            button.image?.isTemplate = true
            button.toolTip = "视窗之门"
            button.target = self; button.action = #selector(toggleSettings)
        }
    }

    private func makePopover() {
        let viewController = NSViewController()
        viewController.view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 610))
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: viewController.view.topAnchor, constant: 16)
        ])
        let title = NSTextField(labelWithString: "视窗之门")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)
        sourceLabel.font = .systemFont(ofSize: 12)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(sourceLabel)
        sourceLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        chooseButton.target = self; chooseButton.action = #selector(chooseSource)
        startButton.target = self; startButton.action = #selector(toggleCapture)
        let actions = NSStackView(views: [chooseButton, startButton]); actions.spacing = 8; actions.distribution = .fillEqually
        root.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let borderLabel = NSTextField(labelWithString: "显示边框")
        let spacer = NSView()
        borderSwitch.state = PortalPreferences.shared.object(forKey: "showOutline") as? Bool == false ? .off : .on
        borderSwitch.target = self; borderSwitch.action = #selector(outlineChanged)
        borderSwitch.setAccessibilityLabel("显示边框")
        let borderRow = NSStackView(views: [borderLabel, spacer, borderSwitch])
        root.addArrangedSubview(borderRow); borderRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        followSwitch.state = PortalPreferences.shared.object(forKey: "followWindow") as? Bool == false ? .off : .on
        followSwitch.target = self; followSwitch.action = #selector(followChanged)
        followSwitch.setAccessibilityLabel("跟随窗口")
        let followRow = NSStackView(views: [NSTextField(labelWithString: "跟随窗口"), NSView(), followSwitch])
        root.addArrangedSubview(followRow); followRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        trackSwitch.state = PortalPreferences.shared.bool(forKey: "trackTargetPosition") ? .on : .off
        trackSwitch.target = self; trackSwitch.action = #selector(trackChanged)
        trackSwitch.setAccessibilityLabel("跟踪目标")
        trackRow = NSStackView(views: [NSTextField(labelWithString: "跟踪目标"), NSView(), trackSwitch])
        trackRow.isHidden = followSwitch.state == .on
        root.addArrangedSubview(trackRow); trackRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        mouseSwitch.state = PortalPreferences.shared.object(forKey: "mouseDetectionEnabled") as? Bool == false ? .off : .on
        mouseSwitch.target = self; mouseSwitch.action = #selector(mouseDetectionChanged)
        mouseSwitch.setAccessibilityLabel("鼠标检测")
        let mouseRow = NSStackView(views: [NSTextField(labelWithString: "鼠标检测"), NSView(), mouseSwitch])
        root.addArrangedSubview(mouseRow); mouseRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        guardianSwitch.state = PortalPreferences.shared.bool(forKey: "cameraGuardEnabled") ? .on : .off
        guardianSwitch.target = self; guardianSwitch.action = #selector(guardianChanged)
        guardianSwitch.setAccessibilityLabel("摄像头守护")
        let guardRow = NSStackView(views: [NSTextField(labelWithString: "摄像头守护 · SFace"), NSView(), guardianSwitch])
        root.addArrangedSubview(guardRow); guardRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        enhancedSwitch.state = PortalPreferences.shared.bool(forKey: "enhancedMode") ? .on : .off
        enhancedSwitch.target = self; enhancedSwitch.action = #selector(enhancedChanged)
        enhancedSwitch.setAccessibilityLabel("增强模式")
        guardianSwitch.isEnabled = true
        if enhancedSwitch.state == .on { guardianSwitch.state = .on }
        let enhancedRow = NSStackView(views: [NSTextField(labelWithString: "增强模式"), NSView(), enhancedSwitch])
        root.addArrangedSubview(enhancedRow); enhancedRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        recoveryDelaySwitch.state = guardian.recoveryDelayEnabled ? .on : .off
        recoveryDelaySwitch.target = self; recoveryDelaySwitch.action = #selector(recoveryDelayChanged)
        recoveryDelaySwitch.setAccessibilityLabel("恢复延迟")
        let delaySwitchRow = NSStackView(views: [NSTextField(labelWithString: "恢复延迟"), NSView(), recoveryDelaySwitch])
        root.addArrangedSubview(delaySwitchRow); delaySwitchRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        recoveryDelayField.stringValue = String(format: "%g", guardian.recoveryDelaySeconds)
        recoveryDelayField.setAccessibilityLabel("恢复延迟秒数")
        recoveryDelayField.target = self; recoveryDelayField.action = #selector(recoveryDelayChanged)
        recoveryDelayField.delegate = self
        recoveryDelayField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        recoveryDelayRow = NSStackView(views: [NSTextField(labelWithString: "等待"), NSView(), recoveryDelayField, NSTextField(labelWithString: "秒")])
        root.addArrangedSubview(recoveryDelayRow); recoveryDelayRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        recoveryDelayRow.isHidden = recoveryDelaySwitch.state != .on
        gestureSwitch.state = PortalPreferences.shared.bool(forKey: "gestureProtectionEnabled") ? .on : .off
        gestureSwitch.target = self; gestureSwitch.action = #selector(gestureProtectionChanged)
        gestureSwitch.setAccessibilityLabel("手势保护")
        let gestureRow = NSStackView(views: [NSTextField(labelWithString: "手势保护"), NSView(), gestureSwitch])
        root.addArrangedSubview(gestureRow); gestureRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        guardianSwitch.isEnabled = true

        let enroll = NSButton(title: guardian.enrolled ? "重新登记主人…" : "登记主人…", target: self, action: #selector(enrollOwner))
        enroll.bezelStyle = .inline
        let learn = NSButton(title: "学习自定义手势…", target: self, action: #selector(learnGesture))
        learn.bezelStyle = .inline
        let enrollmentRow = NSStackView(views: [enroll, learn]); enrollmentRow.spacing = 8
        root.addArrangedSubview(enrollmentRow)
        let angles = NSButton(title: "学习观看角度…", target: self, action: #selector(learnViewingAngles)); angles.bezelStyle = .inline
        root.addArrangedSubview(angles)
        guardianLabel.font = .systemFont(ofSize: 11); guardianLabel.textColor = .secondaryLabelColor
        guardianLabel.maximumNumberOfLines = 2
        root.addArrangedSubview(guardianLabel); guardianLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let opacityTitle = NSTextField(labelWithString: "不透明度")
        opacityTitle.font = .systemFont(ofSize: 12)
        let savedOpacity = (PortalPreferences.shared.object(forKey: "contentOpacity") as? NSNumber)?.doubleValue ?? 1
        opacitySlider.doubleValue = Double(PortalGeometry.opacity(savedOpacity)) * 100
        opacitySlider.target = self; opacitySlider.action = #selector(opacityChanged)
        opacitySlider.isContinuous = true; opacitySlider.setAccessibilityLabel("画面不透明度")
        opacitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityLabel.alignment = .right
        opacityLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true
        opacityLabel.stringValue = "\(Int(opacitySlider.doubleValue.rounded()))%"
        opacityShiftSwitch.state = PortalPreferences.shared.bool(forKey: "opacityShiftEnabled") ? .on : .off
        opacityShiftSwitch.target = self; opacityShiftSwitch.action = #selector(opacityShiftChanged)
        pointerPassSwitch.state = PortalPreferences.shared.bool(forKey: "pointerPassThroughEnabled") ? .on : .off
        pointerPassSwitch.target = self; pointerPassSwitch.action = #selector(pointerPassChanged)
        for (title, control) in [("透明度平移", opacityShiftSwitch), ("鼠标穿透", pointerPassSwitch)] {
            control.setAccessibilityLabel(title)
            let row = NSStackView(views: [NSTextField(labelWithString: title), NSView(), control])
            root.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        pointerLabel.font = .systemFont(ofSize: 10); pointerLabel.textColor = .secondaryLabelColor
        pointerLabel.maximumNumberOfLines = 2
        root.addArrangedSubview(pointerLabel); pointerLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        opacityRange = OpacityRange(minimum: (PortalPreferences.shared.object(forKey: "minimumOpacityPercent") as? NSNumber)?.doubleValue ?? 0,
            maximum: (PortalPreferences.shared.object(forKey: "maximumOpacityPercent") as? NSNumber)?.doubleValue ?? opacitySlider.doubleValue)
        normalOpacityRow = NSStackView(views: [opacityTitle, opacitySlider, opacityLabel]); normalOpacityRow.spacing = 8
        root.addArrangedSubview(normalOpacityRow); normalOpacityRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        rangeRows = NSStackView(); rangeRows.orientation = .vertical; rangeRows.spacing = 8
        for (title, slider, field) in [("最小值", minimumSlider, minimumField), ("最大值", maximumSlider, maximumField)] {
            slider.target = self; slider.action = #selector(rangeChanged(_:)); slider.isContinuous = true
            slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
            slider.setAccessibilityLabel(title + "不透明度")
            field.target = self; field.action = #selector(rangeChanged(_:))
            (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 36).isActive = true
            field.setAccessibilityLabel(title + "不透明度百分比")
            let row = NSStackView(views: [NSTextField(labelWithString: title), slider, field, NSTextField(labelWithString: "%")]); row.spacing = 6
            rangeRows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rangeRows.widthAnchor).isActive = true
        }
        root.addArrangedSubview(rangeRows); rangeRows.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        refreshOpacityControls()

        let help = editHelp
        updateEditHelp()
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        root.addArrangedSubview(help)
        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2; statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isSelectable = true; root.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let center = NSButton(title: "居中", target: self, action: #selector(centerPortal))
        let quit = NSButton(title: "退出", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        center.bezelStyle = .inline; quit.bezelStyle = .inline
        let shortcutButton = NSButton(title: "快捷键", target: self, action: #selector(showShortcutPage))
        shortcutButton.bezelStyle = .inline
        let details = TileButton(name: "说明模式", icon: NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)!, secondary: true,
            state: { [weak self] in TileState(on: self?.helpMode == true, help: "开启后，移到按钮上查看说明") }, action: { [weak self] in self?.toggleContextHelp() })
        helpModeButton = details
        let bottom = NSStackView(views: [details, center, NSView(), shortcutButton, NSView(), quit])
        root.addArrangedSubview(bottom); bottom.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        for child in root.arrangedSubviews { root.removeArrangedSubview(child); child.removeFromSuperview() }
        root.spacing = 9
        func add(_ child: NSView) {
            root.addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        add(title); add(sourceLabel); add(actions)
        func symbol(_ name: String, size: CGFloat = 26) -> NSImage {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)!
            return image.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) ?? image
        }
        func toggle(_ name: String, _ icon: NSImage, _ control: NSSwitch,
                    secondary: Bool = false, available: @escaping () -> Bool = { true }, reason: String = "") -> TileButton {
            TileButton(name: name, icon: icon, secondary: secondary, state: {
                TileState(on: control.state == .on, enabled: control.isEnabled && available(),
                    help: control.isEnabled && available() ? "点击切换" : (reason.isEmpty ? "其他已开启功能依赖此设置" : reason))
            }, action: { [weak self] in
                control.performClick(nil); self?.refreshTiles(); self?.refreshOpacityControls()
            })
        }
        func action(_ name: String, _ icon: NSImage, secondary: Bool = true,
                    available: @escaping () -> Bool = { true }, reason: String = "",
                    perform: @escaping () -> Void) -> TileButton {
            TileButton(name: name, icon: icon, secondary: secondary,
                state: { TileState(enabled: available(), help: available() ? name : reason) }, action: perform)
        }
        tiles = [
            SettingsTile(main: toggle("跟随窗口", PortalIcons.image(.follow), followSwitch), children: [
                toggle("跟踪目标", PortalIcons.image(.tracking), trackSwitch, secondary: true,
                    available: { [weak self] in self?.followSwitch.state == .off }, reason: "关闭跟随窗口后可用")]),
            SettingsTile(main: toggle("鼠标检测", PortalIcons.image(.mouseDetection), mouseSwitch)),
            SettingsTile(main: toggle("显示边框", symbol("rectangle.dashed"), borderSwitch)),
            SettingsTile(main: toggle("摄像头守护", PortalIcons.image(.face), guardianSwitch), children: [
                action("登记", symbol("person.badge.plus", size: 13), perform: { enroll.performClick(nil) })]),
            SettingsTile(main: toggle("增强模式", symbol("shield.lefthalf.filled"), enhancedSwitch), children: [
                action("角度", DoorStatusIcon.image(for: .angle), available: { [weak self] in self?.enhancedSwitch.state == .on }, reason: "开启增强模式后可用", perform: { angles.performClick(nil) }),
                action("延迟", symbol("clock", size: 13), available: { [weak self] in self?.enhancedSwitch.state == .on }, reason: "开启增强模式后可用", perform: { [weak self] in self?.toggleDelayDetails() })]),
            SettingsTile(main: toggle("手势保护", PortalIcons.image(.gesture), gestureSwitch), children: [
                action("学习", symbol("hand.draw", size: 13), perform: { learn.performClick(nil) })]),
            SettingsTile(main: toggle("透明度平移", symbol("circle.lefthalf.filled"), opacityShiftSwitch), children: [
                action("最小", symbol("minus", size: 13), available: { [weak self] in self?.opacityShiftSwitch.state == .on }, reason: "开启透明度平移后可用", perform: { [weak self] in self?.openOpacityDetails(minimum: true) }),
                action("最大", symbol("plus", size: 13), available: { [weak self] in self?.opacityShiftSwitch.state == .on }, reason: "开启透明度平移后可用", perform: { [weak self] in self?.openOpacityDetails(minimum: false) })]),
            SettingsTile(main: toggle("鼠标穿透", PortalIcons.image(.pointerPass), pointerPassSwitch)),
            SettingsTile(main: action("居中", PortalIcons.image(.center), secondary: false, perform: { center.performClick(nil) }))
        ]
        tiles = tiles.map { SettingsTile(main: $0.main) }
        for (index, tile) in tiles.enumerated() where expandableNames.contains(tile.main.name) {
            tile.configureExpansion(left: index % 3 == 2) { [weak self] in self?.showTileDetails(tile.main.name) }
        }
        for row in 0..<3 {
            let stack = NSStackView(views: Array(tiles[(row*3)..<(row*3+3)]))
            stack.spacing = 8; stack.distribution = .fillEqually
            let host = NSView(); host.translatesAutoresizingMaskIntoConstraints = false
            host.heightAnchor.constraint(equalToConstant: 84).isActive = true
            stack.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: host.leadingAnchor), stack.trailingAnchor.constraint(equalTo: host.trailingAnchor), stack.topAnchor.constraint(equalTo: host.topAnchor), stack.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
            gridRows.append(host); gridStacks.append(stack); add(host)
        }
        add(normalOpacityRow); add(rangeRows)
        normalOpacityRow.isHidden = true; rangeRows.isHidden = true
        let closeOpacity = NSButton(title: "收起不透明度", target: self, action: #selector(closeOpacityDetails))
        closeOpacity.bezelStyle = .inline
        rangeRows.addArrangedSubview(closeOpacity)
        // Remove old root-width constraints before nesting the delay controls.
        root.constraints.filter { ($0.firstItem as? NSView) === delaySwitchRow || ($0.firstItem as? NSView) === recoveryDelayRow }.forEach { $0.isActive = false }
        delayDetails = NSStackView(views: [delaySwitchRow, recoveryDelayRow]); delayDetails.orientation = .vertical; delayDetails.alignment = .leading; delayDetails.spacing = 6
        delaySwitchRow.widthAnchor.constraint(equalTo: delayDetails.widthAnchor).isActive = true
        recoveryDelayRow.widthAnchor.constraint(equalTo: delayDetails.widthAnchor).isActive = true
        guardianLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        guardianLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        statusLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        add(delayDetails); add(guardianLabel); add(pointerLabel)
        help.maximumNumberOfLines = 2; help.lineBreakMode = .byWordWrapping
        add(help); add(statusLabel)
        briefStatus.font = .systemFont(ofSize: 11); briefStatus.textColor = .secondaryLabelColor
        briefStatus.lineBreakMode = .byTruncatingTail
        briefStatus.heightAnchor.constraint(equalToConstant: 18).isActive = true; add(briefStatus)
        contextHelp.font = .systemFont(ofSize: 12); contextHelp.maximumNumberOfLines = 3
        contextHelp.heightAnchor.constraint(equalToConstant: 60).isActive = true; contextHelp.isHidden = true; add(contextHelp)
        nameButton = NSButton(title: "", target: self, action: #selector(toggleButtonNames))
        nameButton.bezelStyle = .inline; nameButton.setAccessibilityLabel("显示名称")
        nameButton.image = symbol("textformat", size: 14); nameButton.toolTip = "显示名称 / 图标"
        let helpTile = SettingsTile(main: details); helpTile.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let documentButton = TileButton(name: "操作详情", icon: PortalIcons.image(.helpDocument), secondary: true,
            state: { TileState(on: false, help: "查看操作与授权说明") },
            action: { [weak self] in self?.showHelpPage() })
        helpDocumentTile = SettingsTile(main: documentButton)
        helpDocumentTile.widthAnchor.constraint(equalToConstant: 28).isActive = true
        helpDocumentTile.isHidden = true
        let compactBottom = NSStackView(views: [helpTile, helpDocumentTile, nameButton, NSView(), shortcutButton, NSView(), quit])
        add(compactBottom)
        toolbarButtons = [(shortcutButton, "快捷键", "keyboard"),
                          (quit, "退出", "power"), (closeOpacity, "收起不透明度", "chevron.up")]
        tileControlsReady = true; sideCardsReady = true
        detailPopover.behavior = .semitransient; detailPopover.animates = false
        settingsController = viewController
        refreshTiles()
        refreshOpacityControls()
        popover.contentViewController = viewController
        popover.contentSize = viewController.view.frame.size
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
    }

    private func showTileDetails(_ name: String) {
        guard sideCardsReady, expandableNames.contains(name), let index = tiles.firstIndex(where: { $0.main.name == name }), popover.isShown else { return }
        if expandedRow != nil && detailName == name { closeSideCard(); return }
        closeSideCard()
        let tile = tiles[index]
        let compact = compactNames.contains(name)
        detailName = name; sideSliders.removeAll(); sideFields.removeAll(); sideSwitches.removeAll(); sideActions.removeAll()
        let controller = NSViewController(); controller.view = GridDetailsView(frame: CGRect(x: 0, y: 0, width: 176, height: 84))
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 3
        root.translatesAutoresizingMaskIntoConstraints = false; controller.view.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 6), root.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -6), root.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 5)])
        func add(_ view: NSView) { root.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        controller.view.setAccessibilityLabel(name + "设置")
        func note(_ text: String) {
            guard ["鼠标检测", "显示边框", "居中"].contains(name) else { return }
            let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor; add(label)
        }
        func compactButton(_ name: String, icon: NSImage, state: @escaping () -> TileState, perform: @escaping () -> Void) {
            let button = TileButton(name: name, icon: icon, state: state, action: perform)
            let tile = SettingsTile(main: button); compactTile = tile
            let holder = NSView(); holder.translatesAutoresizingMaskIntoConstraints = false
            holder.heightAnchor.constraint(equalToConstant: 74).isActive = true; add(holder); holder.addSubview(tile)
            NSLayoutConstraint.activate([tile.widthAnchor.constraint(equalToConstant: 60), tile.centerXAnchor.constraint(equalTo: holder.centerXAnchor), tile.centerYAnchor.constraint(equalTo: holder.centerYAnchor)])
        }
        func action(_ title: String, _ selector: Selector, tag: Int = 0) {
            let button = CardActionButton(title: title, target: self, action: selector); button.tag = tag; button.bezelStyle = .rounded
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            if tag == 2 { button.image = PortalIcons.image(.moveTarget) }
            sideActions.append(button)
            if compact {
                let caption = name == "摄像头守护" ? "登记主人" : name == "手势保护" ? "学习手势" : "拖动目标"
                let icon = name == "摄像头守护" ? PortalIcons.image(.ownerEnrollment) : name == "手势保护" ? PortalIcons.image(.gestureLearning) : PortalIcons.image(.moveTarget)
                compactButton(caption, icon: icon, state: { TileState(on: true, enabled: button.isEnabled, help: title) }, perform: { button.performClick(nil) })
            } else { add(button) }
        }
        func toggle(_ title: String, tag: Int) {
            let control = NSSwitch(); control.tag = tag; control.target = self; control.action = #selector(sideValueChanged(_:)); control.setAccessibilityLabel(title)
            sideSwitches[tag] = control
            if compact {
                compactButton(title, icon: PortalIcons.image(.tracking), state: { TileState(on: control.state == .on, enabled: control.isEnabled, help: control.toolTip ?? title) }, perform: { control.performClick(nil) })
                return
            }
            var views: [NSView] = []
            if tag == 5 {
                let icon = NSImageView(image: PortalIcons.image(.tracking))
                icon.widthAnchor.constraint(equalToConstant: 16).isActive = true; icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
                views.append(icon)
            }
            views += [NSTextField(labelWithString: title), NSView(), control]
            add(NSStackView(views: views))
        }
        func value(_ title: String, tag: Int, slider: Bool) {
            let field = NSTextField(labelWithString: "")
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            field.alignment = .right; field.widthAnchor.constraint(equalToConstant: tag == 3 ? 44 : 32).isActive = true
            field.setAccessibilityLabel(title + "数值"); sideFields[tag] = field
            let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11)
            label.widthAnchor.constraint(equalToConstant: 45).isActive = true
            let control = OpacityPreviewSlider(value: 0, minValue: 0, maxValue: tag == 3 ? 60 : 100, target: self, action: #selector(sideValueChanged(_:)))
            if tag == 1 || tag == 2 {
                control.onTracking = { [weak self] tracking in
                    guard let self else { return }
                    self.opacityPreviewTag = tracking ? tag : nil
                    self.tick()
                }
            }
            control.cell = MinimalSliderCell(); control.minValue = 0; control.maxValue = tag == 3 ? 60 : 100
            control.tag = tag; control.target = self; control.action = #selector(sideValueChanged(_:)); control.isContinuous = true
            control.setAccessibilityLabel(title); control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            control.heightAnchor.constraint(equalToConstant: 20).isActive = true; sideSliders[tag] = control
            if tag == 3 {
                let line = NSStackView(views: [control, field]); line.spacing = 5
                let row = NSStackView(views: [label, line]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 5
                line.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true; add(row)
            } else {
                let row = NSStackView(views: [label, control, field]); row.spacing = 5; add(row)
            }
        }
        switch name {
        case "跟随窗口":
            note("跟随同步位置和大小。关闭跟随后，可只跟踪位置，保留矩形大小与偏移。")
            toggle("跟踪目标", tag: 5)
        case "鼠标检测": note("开启时鼠标移入矩形才显示；关闭时由摄像头识别决定是否显示。")
        case "显示边框": note("只改变矩形边框显示。关闭跟随后，按住编辑快捷键仍可拖动或四角缩放。")
        case "摄像头守护":
            note("摄像头是总开关。关闭时增强模式和手势检测一起关闭；登记资料和学习结果会保留。")
            action("登记 / 重新登记主人…", #selector(enrollOwner))
        case "增强模式":
            note("开启后检查观看角度和背景运动。关闭摄像头也会关闭增强模式。")
            let learn = NSButton(title: "学习观看角度", target: self, action: #selector(learnViewingAngles)); learn.tag = 1; sideActions.append(learn)
            compactButton("学习角度", icon: PortalIcons.image(.angleLearning), state: { TileState(on: true, enabled: learn.isEnabled, help: "学习观看角度") }, perform: { learn.performClick(nil) })
            let holder = root.arrangedSubviews.last!
            value("恢复延迟", tag: 3, slider: true)
            let delay = root.arrangedSubviews.last!
            root.constraints.filter { ($0.firstItem as? NSView) === holder || ($0.firstItem as? NSView) === delay }.forEach { $0.isActive = false }
            for view in [holder, delay] { root.removeArrangedSubview(view); view.removeFromSuperview() }
            holder.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let row = NSStackView(views: [holder, delay]); row.spacing = 6; row.alignment = .centerY; add(row)
        case "手势保护":
            note("做已学习的手势可临时暂停；再次做手势且主人在场时解除。学习可在关闭状态下进行。")
            action("学习自定义手势…", #selector(learnGesture))
        case "透明度平移":
            note("开启时，激活使用最大值，未激活使用最小值。关闭时使用普通不透明度。")
            value("最小值", tag: 1, slider: true); value("最大值", tag: 2, slider: true)
        case "居中": note("点击图标，将矩形移到屏幕中央。")
        default: return
        }
        controller.view.layoutSubtreeIfNeeded()
        controller.view.setFrameSize(NSSize(width: compact ? 84 : 176, height: max(84, ceil(root.fittingSize.height) + 10)))
        detailPopover.contentViewController = controller
        refreshSideControls()
        let host = gridRows[index / 3]
        gridStacks[index / 3].isHidden = true
        let card = NSView(); card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true; card.layer?.cornerRadius = 13; card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.borderWidth = 0.5; card.layer?.borderColor = NSColor.separatorColor.cgColor
        host.addSubview(card)
        let right = index % 3 == 2
        var cardConstraints = [card.topAnchor.constraint(equalTo: host.topAnchor), card.bottomAnchor.constraint(equalTo: host.bottomAnchor)]
        if compact {
            cardConstraints += [card.widthAnchor.constraint(equalToConstant: 176), right ? card.trailingAnchor.constraint(equalTo: host.trailingAnchor) : card.leadingAnchor.constraint(equalTo: host.leadingAnchor)]
            let remainingIndex = index / 3 * 3 + (right ? 0 : 2)
            let remaining = SettingsTile(main: tiles[remainingIndex].main.duplicate())
            if expandableNames.contains(remaining.main.name) {
                let remainingName = remaining.main.name
                remaining.configureExpansion(left: right == false) { [weak self] in self?.showTileDetails(remainingName) }
            }
            remaining.refresh(names: buttonNames); host.addSubview(remaining); remainingTile = remaining
            NSLayoutConstraint.activate([remaining.widthAnchor.constraint(equalToConstant: 84), remaining.topAnchor.constraint(equalTo: host.topAnchor), remaining.bottomAnchor.constraint(equalTo: host.bottomAnchor), right ? remaining.leadingAnchor.constraint(equalTo: host.leadingAnchor) : remaining.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
        } else {
            cardConstraints += [card.leadingAnchor.constraint(equalTo: host.leadingAnchor), card.trailingAnchor.constraint(equalTo: host.trailingAnchor)]
        }
        NSLayoutConstraint.activate(cardConstraints)
        let selected = SettingsTile(main: tile.main.duplicate())
        selected.configureExpansion(left: index % 3 == 2) { [weak self] in self?.closeSideCard() }
        selected.refresh(names: buttonNames); card.addSubview(selected)
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = controller.view; card.addSubview(scroll)
        NSLayoutConstraint.activate([selected.widthAnchor.constraint(equalToConstant: 84), selected.topAnchor.constraint(equalTo: card.topAnchor), selected.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            (right ? selected.trailingAnchor.constraint(equalTo: card.trailingAnchor) : selected.leadingAnchor.constraint(equalTo: card.leadingAnchor)),
            scroll.topAnchor.constraint(equalTo: card.topAnchor), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            (right ? scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor) : scroll.leadingAnchor.constraint(equalTo: selected.trailingAnchor, constant: 8)),
            (right ? scroll.trailingAnchor.constraint(equalTo: selected.leadingAnchor, constant: -8) : scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor))])
        expandedRow = index / 3; expandedCard = card; expandedTile = selected
        host.layoutSubtreeIfNeeded()
        controller.view.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(84, ceil(root.fittingSize.height) + 10)))
        dismissGridMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let card = self.expandedCard else { return event }
            if event.window !== card.window || !card.bounds.contains(card.convert(event.locationInWindow, from: nil)) { self.closeSideCard() }
            return event
        }
    }
    @objc private func closeSideCard() {
        let wasPreviewing = opacityPreviewTag != nil
        opacityPreviewTag = nil
        if let dismissGridMonitor { NSEvent.removeMonitor(dismissGridMonitor); self.dismissGridMonitor = nil }
        expandedCard?.removeFromSuperview(); expandedCard = nil; expandedTile = nil; compactTile = nil
        remainingTile?.removeFromSuperview(); remainingTile = nil
        if let expandedRow { gridStacks[expandedRow].isHidden = false }
        expandedRow = nil
        detailPopover.contentViewController = nil
        if wasPreviewing { tick() }
    }
    private func refreshSideControls() {
        guard detailPopover.contentViewController != nil else { return }
        let values = [0: opacitySlider.doubleValue, 1: opacityRange.minimum, 2: opacityRange.maximum, 3: guardian.recoveryDelayEnabled ? guardian.recoveryDelaySeconds : 0]
        for (tag, slider) in sideSliders {
            let value = values[tag] ?? 0
            if slider.doubleValue != value { slider.doubleValue = value }
            slider.isEnabled = tag == 3 ? enhancedSwitch.state == .on : tag == 0 ? opacityShiftSwitch.state == .off : opacityShiftSwitch.state == .on
        }
        for (tag, field) in sideFields {
            let text = String(format: tag == 3 ? "%.1f秒" : "%.0f%%", values[tag] ?? 0)
            if field.stringValue != text { field.stringValue = text }
            field.isEnabled = sideSliders[tag]?.isEnabled ?? false
            field.textColor = field.isEnabled ? .labelColor : .tertiaryLabelColor
        }
        for (tag, control) in sideSwitches {
            let source = tag == 5 ? trackSwitch : recoveryDelaySwitch
            if control.state != source.state { control.state = source.state }
            control.isEnabled = tag == 5 ? followSwitch.state == .off : enhancedSwitch.state == .on
            control.toolTip = control.isEnabled ? nil : tag == 5 ? "关闭跟随窗口后可用" : "开启增强模式后可用"
        }
        for action in sideActions {
            action.isEnabled = action.tag == 1 ? enhancedSwitch.state == .on : action.tag == 2 ? pointerPassSwitch.state == .on : true
        }
        compactTile?.refresh(names: buttonNames)
    }
    @objc private func sideValueChanged(_ sender: NSControl) {
        if sender.tag == 4, let control = sender as? NSSwitch {
            recoveryDelaySwitch.state = control.state; recoveryDelayChanged()
        } else if sender.tag == 5, let control = sender as? NSSwitch {
            trackSwitch.state = control.state; trackChanged()
        } else {
            guard let slider = sender as? NSSlider, slider.doubleValue.isFinite else { refreshSideControls(); return }
            let value = sender.tag == 3 ? (slider.doubleValue * 10).rounded() / 10 : slider.doubleValue.rounded()
            switch sender.tag {
            case 0: opacitySlider.doubleValue = min(100, max(0, value)); opacityChanged()
            case 1: minimumField.doubleValue = value; rangeChanged(minimumField)
            case 2: maximumField.doubleValue = value; rangeChanged(maximumField)
            case 3: recoveryDelaySwitch.state = value > 0 ? .on : .off; recoveryDelayField.doubleValue = value; recoveryDelayChanged()
            default: break
            }
        }
        refreshSideControls()
    }

    private func helpText(_ name: String?) -> String {
        guard let name else { return "移到按钮上查看说明。" }
        let descriptions = [
            "跟随窗口": "同步目标窗口的位置和大小。",
            "跟踪目标": "只跟随位置，保留矩形大小和偏移。",
            "鼠标检测": "鼠标移入矩形时显示画面。",
            "显示边框": "显示或隐藏矩形边框。",
            "摄像头守护": "确认主人在场；关闭时也关闭增强与手势保护。",
            "增强模式": "检查观看角度、他人和背景运动。",
            "手势保护": "做已学习手势，暂停或恢复显示。",
            "透明度平移": "激活用最大值，未激活用最小值。",
            "鼠标穿透": "向目标窗口发送点击、拖动和滚动。",
            "居中": "把矩形移到屏幕中央。",
            "登记主人": "录入主人的面部，供摄像头识别。",
            "学习手势": "录入用于暂停和恢复的手势。",
            "学习角度": "录入允许显示画面的观看角度。",
            "最小值": "设置未激活时的不透明度；拖动可预览。",
            "最大值": "设置激活时的不透明度；拖动可预览。",
            "恢复延迟": "安全环境持续指定时间后恢复；0 秒不延迟。",
            "选择窗口": "选择矩形显示和控制的目标窗口。",
            "开始": "开始显示已选择的窗口。", "关闭": "停止显示目标窗口。",
            "显示名称": "切换功能按钮的图标和名称。",
            "快捷键": "设置各功能和拖动目标的快捷键。",
            "退出": "退出视窗之门。",
            "说明模式": "移到按钮上查看简要说明；再次点击关闭。",
            "操作详情": "查看操作、学习、授权与保存说明。"
        ]
        let key = name.hasPrefix("展开") ? String(name.dropFirst(2)) : name
        return descriptions[key] ?? "移到按钮上查看说明。"
    }
    private func showContextHelp(_ name: String?) {
        let text = helpText(name)
        if contextHelp.stringValue != text { contextHelp.stringValue = text }
    }
    private func toggleContextHelp() {
        helpMode.toggle(); showContextHelp(nil)
        if let helpHoverMonitor { NSEvent.removeMonitor(helpHoverMonitor); self.helpHoverMonitor = nil }
        if helpMode {
            settingsController?.view.window?.acceptsMouseMovedEvents = true
            helpHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                guard let self, self.helpMode, let view = self.settingsController?.view, event.window === view.window else { return event }
                let point = view.superview?.convert(event.locationInWindow, from: nil) ?? view.convert(event.locationInWindow, from: nil)
                var hit = view.hitTest(point)
                var name: String?
                while let node = hit, node !== view {
                    if let control = node as? NSControl {
                        name = control.accessibilityLabel() ?? (control as? NSButton)?.title
                        if name != nil { break }
                    }
                    hit = node.superview
                }
                self.showContextHelp(name)
                return event
            }
        }
        refreshTiles(); refreshOpacityControls()
    }

    @objc private func toggleButtonNames() {
        buttonNames.toggle(); PortalPreferences.shared.set(buttonNames, forKey: "showButtonNames")
        refreshTiles()
    }
    private func refreshTiles() {
        guard tileControlsReady else { return }
        helpModeButton?.refresh(names: false)
        helpDocumentTile?.refresh(names: false)
        tiles.forEach { $0.refresh(names: buttonNames) }
        expandedTile?.refresh(names: buttonNames)
        remainingTile?.refresh(names: buttonNames)
        refreshSideControls()
        let headerKey = "\(buttonNames)-\(enabled)"
        guard tileHeaderKey != headerKey || chooseButton.imagePosition != (buttonNames ? .noImage : .imageOnly)
            || startButton.imagePosition != (buttonNames ? .noImage : .imageOnly) else { return }
        tileHeaderKey = headerKey
        nameButton.state = buttonNames ? .on : .off
        nameButton.contentTintColor = buttonNames ? .controlAccentColor : .labelColor
        for item in toolbarButtons {
            item.button.title = item.name
            item.button.image = buttonNames ? nil : NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.name)
            item.button.imagePosition = buttonNames ? .noImage : .imageOnly
            item.button.setAccessibilityLabel(item.name); item.button.toolTip = item.name
        }
        for (button, name, symbol) in [(chooseButton, "选择窗口", "macwindow"),
                                       (startButton, enabled ? "关闭" : "开始", enabled ? "stop.fill" : "play.fill")] {
            button.setAccessibilityLabel(name); button.toolTip = name
            if button === chooseButton { button.title = name }
            button.image = buttonNames ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            button.imagePosition = buttonNames ? .noImage : .imageOnly
            // Preserve startButton.title, used by action/state verification.
        }
    }
    @objc private func openOpacityDetails(minimum: Bool) {
        opacityDetailsOpen = true; delayDetailsOpen = false; refreshOpacityControls()
        settingsController?.view.window?.makeFirstResponder(minimum ? minimumField : maximumField)
    }
    @objc private func closeOpacityDetails() { opacityDetailsOpen = false; refreshOpacityControls() }
    @objc private func toggleDelayDetails() {
        delayDetailsOpen.toggle(); opacityDetailsOpen = false; refreshOpacityControls()
    }

    private func updateEditHelp() {
        let label = shortcuts.bindings[.edit]?.label ?? "未设置"
        let move = shortcuts.bindings[.moveTarget]?.label ?? "未设置"
        editHelp.stringValue = "\(label) 调整矩形 · \(move) 拖动目标（穿透开启）"
    }
    private func performShortcut(_ action: ShortcutAction) {
        switch action {
        case .toggle: toggleCapture()
        case .choose: chooseSource()
        case .follow:
            followSwitch.state = followSwitch.state == .on ? .off : .on
            followChanged()
        case .opacityUp, .opacityDown:
            if opacityShiftSwitch.state == .on {
                opacityRange.setMaximum(opacityRange.maximum + (action == .opacityUp ? 5 : -5))
                saveOpacityRange(); refreshOpacityControls(); tick()
            } else {
                opacitySlider.doubleValue = min(100, max(0, opacitySlider.doubleValue + (action == .opacityUp ? 5 : -5)))
                opacityChanged()
            }
        case .center: centerPortal()
        case .opacityShift:
            opacityShiftSwitch.state = opacityShiftSwitch.state == .on ? .off : .on; opacityShiftChanged()
        case .pointerPassThrough:
            pointerPassSwitch.state = pointerPassSwitch.state == .on ? .off : .on; pointerPassChanged()
        case .edit, .moveTarget: break
        }
    }
    @objc private func showShortcutPage() {
        closeSideCard()
        shortcuts.cancelRecording()
        let controller = NSViewController()
        controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16)
        ])
        let title = NSTextField(labelWithString: "快捷键")
        title.font = .systemFont(ofSize: 15, weight: .semibold); root.addArrangedSubview(title)
        shortcutButtons.removeAll()
        for action in ShortcutAction.allCases {
            let label = NSTextField(labelWithString: action.title); label.font = .systemFont(ofSize: 12)
            let button = NSButton(title: shortcuts.bindings[action]?.label ?? "未设置", target: self, action: #selector(recordShortcut(_:)))
            button.tag = action.rawValue; button.font = .systemFont(ofSize: 12)
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.setAccessibilityLabel("设置" + action.title + "快捷键")
            if shortcuts.registrationFailures.contains(action) { button.title = "冲突 · " + button.title }
            let clear = NSButton(title: "×", target: self, action: #selector(clearShortcut(_:)))
            clear.tag = action.rawValue; clear.bezelStyle = .inline
            clear.setAccessibilityLabel("清空" + action.title + "快捷键")
            var contents: [NSView] = [label, NSView(), button, clear]
            if action == .moveTarget {
                label.stringValue = "拖动目标（按住）"
                let icon = NSImageView(image: PortalIcons.image(.moveTarget)); icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 14).isActive = true; contents.insert(icon, at: 0)
            }
            let row = NSStackView(views: contents); row.spacing = 6
            root.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            shortcutButtons[action] = button
        }
        let hint = NSTextField(labelWithString: "悬停显示时生效 · 点击录入，松键保存")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        let done = NSButton(title: "完成", target: self, action: #selector(finishShortcuts))
        root.addArrangedSubview(done); done.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        controller.view.layoutSubtreeIfNeeded()
        controller.view.setFrameSize(NSSize(width: 320, height: ceil(root.fittingSize.height) + 32))
        popover.contentViewController = controller; popover.contentSize = controller.view.frame.size
    }
    @objc private func recordShortcut(_ sender: NSButton) {
        guard let action = ShortcutAction(rawValue: sender.tag) else { return }
        for (other, button) in shortcutButtons { button.title = shortcuts.bindings[other]?.label ?? "未设置" }
        sender.title = "请按下快捷键…"
        shortcuts.record(action)
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }
    @objc private func clearShortcut(_ sender: NSButton) {
        guard let action = ShortcutAction(rawValue: sender.tag) else { return }
        shortcuts.cancelRecording(); shortcuts.set(nil, for: action); showShortcutPage()
    }
    @objc private func finishShortcuts() {
        shortcuts.cancelRecording(); updateEditHelp()
        guard let controller = settingsController else { return }
        popover.contentViewController = controller; popover.contentSize = controller.view.frame.size
    }

    func popoverDidClose(_ notification: Notification) {
        closeSideCard()
        shortcuts.cancelRecording()
        if settingsController != nil { finishShortcuts() }
    }

    @objc private func mouseDetectionChanged() {
        PortalPreferences.shared.set(mouseSwitch.state == .on, forKey: "mouseDetectionEnabled"); tick()
    }
    @objc private func gestureProtectionChanged() {
        guardian.setGestureEnabled(gestureSwitch.state == .on)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === recoveryDelayField { recoveryDelayChanged() }
    }
    @objc private func recoveryDelayChanged() {
        let seconds = Double(recoveryDelayField.stringValue) ?? guardian.recoveryDelaySeconds
        guardian.setRecoveryDelay(enabled: recoveryDelaySwitch.state == .on, seconds: seconds)
        recoveryDelayField.stringValue = String(format: "%g", guardian.recoveryDelaySeconds)
        recoveryDelayRow.isHidden = recoveryDelaySwitch.state != .on
        refreshOpacityControls(); tick()
    }
    @objc private func enhancedChanged() {
        let active = enhancedSwitch.state == .on
        guardian.setEnhanced(active)
        if active { guardianSwitch.state = .on }
        guardianSwitch.isEnabled = true
    }
    @objc private func showHelpPage() {
        closeSideCard()
        shortcuts.cancelRecording()
        let controller = NSViewController()
        controller.view = NSView(frame: CGRect(x: 0, y: 0, width: 340, height: 470))
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 9
        root.translatesAutoresizingMaskIntoConstraints = false; controller.view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -16)])
        let title = NSTextField(labelWithString: "操作详情"); title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let document = NSStackView(); document.orientation = .vertical; document.alignment = .leading; document.spacing = 10
        document.translatesAutoresizingMaskIntoConstraints = false
        let canvas = HelpDocumentView(frame: CGRect(x: 0, y: 0, width: 292, height: 1))
        scroll.documentView = canvas; canvas.addSubview(document)
        let descriptions: [(String, String)] = [
            ("开始与窗口", "所选窗口仍在时可直接开始。目标在最前自动暂停，被遮挡后恢复；手动关闭后保持关闭。"),
            ("移动与缩放", "关闭跟随，按住 Option 拖动或在四角缩放。穿透开启时，按住拖动目标快捷键（默认空格）移动真实窗口。"),
            ("快捷键", "点击录入，松键保存，× 清空。允许显示时生效；不透明度单次调整 5%，长按连续调节。"),
            ("登记与学习", "先单独面对镜头登记主人。角度只录正常观看视角；手势保持同一指型，展示掌心、手背和倾斜后保存。"),
            ("保护与预览", "完全隐藏请把最小不透明度设为 0%。调整滑杆临时预览，仍受摄像头守护限制。"),
            ("系统授权", "采集需屏幕录制，识别需摄像头，鼠标控制需辅助功能（设备控制和数据访问）。更新后若失效，请重新授权当前软件。"),
            ("使用限制", "最小化、切换桌面或受保护内容可能无法采集。后台输入取决于目标软件；运动与手势识别可能误判。"),
            ("保存与隐私", "设置、快捷键与学习结果自动保存本机。画面不保存、不上传。")]
        for (name, detail) in descriptions {
            let heading = NSTextField(labelWithString: name); heading.font = .systemFont(ofSize: 12, weight: .semibold)
            let body = NSTextField(wrappingLabelWithString: detail); body.font = .systemFont(ofSize: 11); body.textColor = .secondaryLabelColor
            document.addArrangedSubview(heading); document.addArrangedSubview(body)
            body.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            document.widthAnchor.constraint(equalToConstant: 292),
            document.topAnchor.constraint(equalTo: canvas.topAnchor)])
        let done = NSButton(title: "完成", target: self, action: #selector(finishShortcuts)); done.bezelStyle = .inline
        let footer = NSStackView(views: [NSView(), done, NSView()]); footer.distribution = .fillEqually; root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        popover.contentViewController = controller; popover.contentSize = controller.view.frame.size
        controller.view.layoutSubtreeIfNeeded()
        canvas.setFrameSize(NSSize(width: 292, height: document.fittingSize.height))
        canvas.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func guardianChanged() {
        guardian.setEnabled(guardianSwitch.state == .on)
        if !guardian.allowsReveal { applyAppearance(active: false); shortcuts.setScopeActive(false) }
    }
    @objc private func learnViewingAngles() { popover.performClose(nil); guardian.showAngleLearning() }
    @objc private func learnGesture() {
        popover.performClose(nil); guardian.showGestureLearning()
    }
    @objc private func enrollOwner() {
        popover.performClose(nil); guardian.showEnrollment()
    }

    @objc private func toggleSettings() {
        if popover.isShown { shortcuts.cancelRecording(); popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func makePortal() {
        portal = PortalPanel(contentRect: CGRect(origin: .zero, size: PortalGeometry.defaultSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        portal.isOpaque = false; portal.backgroundColor = .clear; portal.hasShadow = false
        portal.level = .floating
        portal.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        portal.hidesOnDeactivate = false; portal.ignoresMouseEvents = true
        portal.acceptsMouseMovedEvents = true
        portal.becomesKeyOnlyIfNeeded = true
        portal.contentView = portalView
        portalView.showOutline = borderSwitch.state == .on
        portalView.contentOpacity = PortalGeometry.opacity(opacitySlider.doubleValue / 100)
        pointerRouter.onFailure = { [weak self] message in self?.showPointerFeedback(message) }
        pointerRouter.onStatus = { [weak self] message in self?.showPointerFeedback(message) }
        portalView.onPointerEvent = { [weak self] event in
            guard let self else { return }
            let allowed = self.enabled && self.portal.isVisible && self.portalView.reveal && self.pointerPassSwitch.state == .on
                && self.portalView.frameImage != nil && !self.portalView.editing && !self.popover.isShown
            let selection = self.rememberedWindow.flatMap { $0.id == self.selectedWindowID ? $0 : nil }
            self.pointerRouter.route(event, selection: selection, bounds: self.portalView.sourceBounds, allowed: allowed)
        }
        portalView.editGestureActive = { [weak self] in
            self?.shortcuts.editActive(flags: NSEvent.modifierFlags) ?? false
        }
        portalView.targetMoveActive = { [weak self] in
            guard let self else { return false }
            return self.enabled && self.pointerPassSwitch.state == .on && !self.popover.isShown
                && self.shortcuts.targetMoveActive(flags: NSEvent.modifierFlags)
        }
        portalView.onTargetMoveBegin = { [weak self] in
            guard let self else { return false }
            self.pollSourcePosition()
            let selection = self.rememberedWindow.flatMap { $0.id == self.selectedWindowID ? $0 : nil }
            return self.pointerRouter.beginTargetMove(selection: selection, bounds: self.portalView.sourceBounds)
        }
        portalView.onTargetMove = { [weak self] delta in
            guard let self else { return }
            if self.pointerRouter.moveTarget(delta: delta) { self.pollSourcePosition() }
            else { self.portalView.endTargetMove() }
        }
        portalView.onTargetMoveEnd = { [weak self] in self?.pointerRouter.endTargetMove() }
        portalView.onUserManipulation = { [weak self] in
            self?.pointerRouter.cancel()
            self?.selectionSizing.cancel()
        }
        centerPortal(); portal.orderOut(nil)
        updateControls()
    }
    @objc private func centerPortal() {
        guard portal != nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        portal.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - portal.frame.width / 2,
                                      y: screen.visibleFrame.midY - portal.frame.height / 2))
        if enabled && portalView.reveal { portal.orderFrontRegardless() }
    }
    @objc private func outlineChanged() {
        portalView.showOutline = borderSwitch.state == .on
        PortalPreferences.shared.set(portalView.showOutline, forKey: "showOutline")
        portalView.needsDisplay = true
    }

    @objc private func opacityChanged() {
        let opacity = PortalGeometry.opacity(opacitySlider.doubleValue / 100)
        opacityLabel.stringValue = "\(Int((opacity * 100).rounded()))%"
        PortalPreferences.shared.set(Double(opacity), forKey: "contentOpacity")
        if portal != nil { tick() }
    }
    private func refreshOpacityControls() {
        let shift = opacityShiftSwitch.state == .on
        normalOpacityRow.isHidden = sideCardsReady || shift
        rangeRows.isHidden = sideCardsReady || !shift || (tileControlsReady && !opacityDetailsOpen)
        if tileControlsReady { delayDetails.isHidden = sideCardsReady || !delayDetailsOpen || enhancedSwitch.state != .on }
        pointerLabel.isHidden = true
        guardianLabel.isHidden = true; editHelp.isHidden = true; statusLabel.isHidden = true
        helpDocumentTile?.isHidden = !helpMode
        contextHelp.isHidden = !helpMode
        minimumSlider.doubleValue = opacityRange.minimum; maximumSlider.doubleValue = opacityRange.maximum
        minimumField.stringValue = "\(Int(opacityRange.minimum.rounded()))"
        maximumField.stringValue = "\(Int(opacityRange.maximum.rounded()))"
        if let controller = settingsController {
            controller.view.layoutSubtreeIfNeeded()
            let height = (controller.view.subviews.first as? NSStackView).map { ceil($0.fittingSize.height) + 32 } ?? 610
            controller.view.setFrameSize(NSSize(width: 300, height: height))
            if popover.contentViewController === controller { popover.contentSize = controller.view.frame.size }
        }
    }
    private func saveOpacityRange() {
        PortalPreferences.shared.set(opacityRange.minimum, forKey: "minimumOpacityPercent")
        PortalPreferences.shared.set(opacityRange.maximum, forKey: "maximumOpacityPercent")
    }
    @objc private func rangeChanged(_ sender: NSControl) {
        // Reject incomplete/non-numeric text instead of silently replacing it with zero.
        let value: Double
        if let field = sender as? NSTextField {
            guard let parsed = Double(field.stringValue), parsed.isFinite else { refreshOpacityControls(); return }
            value = parsed.rounded()
        } else { value = sender.doubleValue.rounded() }
        if sender === minimumSlider || sender === minimumField { opacityRange.setMinimum(value) }
        else { opacityRange.setMaximum(value) }
        saveOpacityRange(); refreshOpacityControls(); tick()
    }
    @objc private func opacityShiftChanged() {
        PortalPreferences.shared.set(opacityShiftSwitch.state == .on, forKey: "opacityShiftEnabled")
        refreshOpacityControls(); tick()
    }
    @objc private func pointerPassChanged() {
        pointerRouter.cancel(); portalView.endTargetMove()
        lastPointerPermission = nil; nextPointerPermissionPoll = 0
        refreshOpacityControls()
        PortalPreferences.shared.set(pointerPassSwitch.state == .on, forKey: "pointerPassThroughEnabled")
        if pointerPassSwitch.state == .on && !PointerRouter.trusted {
            PointerRouter.requestPermission()
            showPointerFeedback("请在系统设置 → 隐私与安全性 → 辅助功能允许视窗之门。")
        }
        tick()
    }
    private func showPointerFeedback(_ message: String) {
        if pointerLabel.stringValue != message { pointerLabel.stringValue = message; refreshOpacityControls() }
        pointerPassSwitch.toolTip = message
    }
    private func applyAppearance(active: Bool) {
        let preview = active && guardian.allowsReveal ? opacityPreviewTag : nil
        let opacity = preview.map { CGFloat(($0 == 1 ? opacityRange.minimum : opacityRange.maximum) / 100) }
            ?? CGFloat(opacityRange.opacity(shift: opacityShiftSwitch.state == .on, active: active, normal: opacitySlider.doubleValue))
        if portalView.contentOpacity != opacity { portalView.contentOpacity = opacity }
        let reveal = enabled && !targetFrontmost && portalView.frameImage != nil && opacity > 0
        if portalView.reveal != reveal { portalView.reveal = reveal; portalView.needsDisplay = true }
        engine.setDisplayDemand(reveal)
        portal.ignoresMouseEvents = !reveal
        if reveal {
            if !portal.isVisible { portal.orderFrontRegardless() }
        } else {
            pointerRouter.cancel(); portalView.endTargetMove()
            if portal.isVisible { portal.orderOut(nil) }
        }
    }
    @objc private func trackChanged() {
        PortalPreferences.shared.set(trackSwitch.state == .on, forKey: "trackTargetPosition")
        sourceFollower.reset(to: portalView.sourceBounds.origin)
        pollSourcePosition(); tick()
    }
    @objc private func followChanged() {
        PortalPreferences.shared.set(followSwitch.state == .on, forKey: "followWindow")
        trackRow?.isHidden = followSwitch.state == .on
        sourceFollower.reset(to: portalView.sourceBounds.origin)
        refreshOpacityControls()
        portalView.allowsManipulation = enabled && followSwitch.state == .off
        portalView.endManipulation()
        portalView.editing = false
        if followSwitch.state == .on {
            pollSourcePosition()
            observeSourceBounds(portalView.sourceBounds)
        }
    }
    private func observeSourceBounds(_ bounds: CGRect) {
        let target = PortalGeometry.quartzRect(bounds, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        guard bounds != portalView.sourceBounds || selectionSizing.pending || (followSwitch.state == .on && portal.frame != target) else { return }
        guard bounds.width > 0, bounds.height > 0,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return }
        let translation = sourceFollower.translation(to: bounds.origin,
            enabled: followSwitch.state == .off && trackSwitch.state == .on,
            manipulating: portalView.isManipulating)
        portalView.sourceBounds = bounds
        if followSwitch.state == .on {
            selectionSizing.cancel()
            let height = NSScreen.screens.first?.frame.height ?? 0
            portal.setFrame(PortalGeometry.quartzRect(bounds, primaryHeight: height), display: true)
        } else if selectionSizing.pending {
            applySelectionSize(bounds.size, source: bounds)
        } else if let translation {
            portal.setFrameOrigin(CGPoint(x: portal.frame.minX + translation.x, y: portal.frame.minY + translation.y))
        }
        portalView.needsDisplay = true
    }
    private func pollSourcePosition() {
        guard enabled, let id = selectedWindowID else { return }
        let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        guard let entry = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              (entry[kCGWindowIsOnscreen as String] as? Bool) == true,
              let raw = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else {
            return
        }
        if let name = entry[kCGWindowName as String] as? String, !name.isEmpty, let saved = rememberedWindow, name != saved.title {
            let updated = WindowSelection(id: saved.id, processID: saved.processID, bundleID: saved.bundleID, appName: saved.appName, title: name)
            rememberedWindow = updated; sourceLabel.stringValue = updated.displayName; sourceLabel.toolTip = updated.displayName
            if let data = try? JSONEncoder().encode(updated) { PortalPreferences.shared.set(data, forKey: "selectedWindowV1") }
        }
        observeSourceBounds(bounds)
    }
    private func applySelectionSize(_ proposed: CGSize, source: CGRect? = nil) {
        guard let size = selectionSizing.takeSize(proposed) else { return }
        let center = CGPoint(x: portal.frame.midX, y: portal.frame.midY)
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        if followSwitch.state == .on, let source {
            let height = NSScreen.screens.first?.frame.height ?? 0
            origin = CGPoint(x: source.minX, y: height - source.minY - size.height)
        }
        portal.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    @objc private func chooseSource() {
        guard !busy else { return }
        popover.performClose(nil)
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        var excluded = [portal.windowNumber]
        if let window = popover.contentViewController?.view.window { excluded.append(window.windowNumber) }
        configuration.excludedWindowIDs = excluded
        configuration.allowsChangingSelectedContent = true
        systemPicker.defaultConfiguration = configuration
        systemPicker.isActive = true
        statusLabel.stringValue = "在系统选择器中选择窗口。"
        NSApp.activate(ignoringOtherApps: true)
        systemPicker.present(using: .window)
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self, !self.busy else { return }
            self.captureFault = false; self.busy = true; self.enabled = false; self.generation += 1
            self.portalView.frameImage = nil; self.portalView.reveal = false; self.portalView.sourceBounds = .zero
            self.portalView.endManipulation(); self.portalView.needsDisplay = true
            self.shortcuts.setScopeActive(false); self.updateControls()
            do { try await self.engine.stopForReplacement() }
            catch {
                self.busy = false; self.updateControls()
                self.captureFault = true; self.updateStatusIcon()
                self.statusLabel.stringValue = CaptureFailure.describe(error, operation: "旧窗口采集停止失败")
                return
            }
            self.selectedFilter = filter
            self.selectionSizing.beginSelection()
            self.selectedWindowID = nil
            self.sourceLabel.stringValue = "已选择窗口"
            self.portalView.sourceBounds = .zero
            if #available(macOS 15.2, *), let window = filter.includedWindows.first {
                self.remember(window)
                self.portalView.sourceBounds = window.frame
                self.applySelectionSize(window.frame.size, source: window.frame)
            } else {
                self.applySelectionSize(filter.contentRect.size)
            }
            self.busy = false
            await self.startCapture()
        }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in self?.statusLabel.stringValue = "已取消选择。" }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.statusLabel.stringValue = CaptureFailure.describe(error, operation: "选择窗口失败")
        }
    }
    @objc private func toggleCapture() {
        guard !busy else { return }
        guard enabled else {
            Task { await resumeSelection() }
            return
        }
        captureFault = false; generation += 1; enabled = false; busy = true
        portalView.reveal = false; portalView.frameImage = nil
        portalView.endManipulation(); portalView.editing = false
        statusLabel.stringValue = "已关闭"
        updateControls()
        Task {
            await engine.stop()
            busy = false
            updateControls()
        }
    }
    private func identity(_ window: SCWindow) -> WindowSelection {
        WindowSelection(id: window.windowID, processID: window.owningApplication?.processID ?? 0,
                        bundleID: window.owningApplication?.bundleIdentifier ?? "",
                        appName: window.owningApplication?.applicationName ?? "",
                        title: window.title ?? "")
    }
    private func remember(_ window: SCWindow) {
        let selection = identity(window)
        sourceFollower.reset(to: window.frame.origin)
        rememberedWindow = selection; selectedWindowID = window.windowID
        sourceLabel.stringValue = selection.displayName; sourceLabel.toolTip = selection.displayName
        if let data = try? JSONEncoder().encode(selection) { PortalPreferences.shared.set(data, forKey: "selectedWindowV1") }
    }
    private func resumeSelection() async {
        guard !busy else { return }
        // A picker filter may be reused without requesting global screen-recording access.
        if selectedFilter != nil {
            if let id = selectedWindowID,
               let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
               !list.contains(where: {
                   ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id
                       && (rememberedWindow == nil || ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == rememberedWindow?.processID)
               }) {
                selectedFilter = nil
            } else { await startCapture(); return }
        }
        guard let rememberedWindow else { chooseSource(); return }
        // A saved title is not an authorization. Across launches enumerate only with existing permission.
        guard CGPreflightScreenCaptureAccess() else {
            chooseSource()
            statusLabel.stringValue = "已记住窗口；系统共享授权已结束，请重新确认。"
            return
        }
        busy = true; updateControls(); statusLabel.stringValue = "查找已选择的窗口…"
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let candidates = content.windows.map { identity($0) }
            guard let match = rememberedWindow.resolve(in: candidates),
                  let window = content.windows.first(where: { $0.windowID == match.id }) else {
                busy = false; updateControls(); chooseSource()
                statusLabel.stringValue = "原窗口不存在或有同名窗口，请重新选择。"
                return
            }
            remember(window)
            selectedFilter = SCContentFilter(desktopIndependentWindow: window)
            portalView.sourceBounds = window.frame
            busy = false; updateControls()
            await startCapture()
        } catch {
            busy = false; updateControls()
            statusLabel.stringValue = CaptureFailure.describe(error, operation: "恢复窗口失败")
        }
    }
    private func startCapture() async {
        guard !busy, let filter = selectedFilter else { return }
        busy = true; updateControls()
        defer { busy = false; updateControls() }
        generation += 1; let token = generation
        captureFault = false; receivedFrame = false; captureStartedAt = Date()
        portalView.frameImage = nil; portalView.reveal = false; portalView.needsDisplay = true
        do {
            enabled = true
            updateControls()
            pollSourcePosition()
            observeSourceBounds(portalView.sourceBounds)
            try await engine.start(filter: filter)
            guard generation == token else { await engine.stop(); return }
            if !receivedFrame { statusLabel.stringValue = "等待窗口画面…" }
        } catch {
            captureFault = true; enabled = false; selectedFilter = nil
            statusLabel.stringValue = CaptureFailure.describe(error, operation: "采集失败")
        }
    }
    private func updateControls() {
        guardian.setPortalRunning(enabled)
        if !enabled { pointerRouter.cancel(); portalView.endTargetMove() }
        startButton.title = enabled ? "关闭" : "开始"
        startButton.isEnabled = !busy; chooseButton.isEnabled = !busy
        portalView.allowsManipulation = enabled && followSwitch.state == .off
        if enabled && portalView.reveal { portal.orderFrontRegardless() }
        else {
            shortcuts.setScopeActive(false)
            portalView.endManipulation(); portalView.editing = false
            portalView.reveal = false; portal.ignoresMouseEvents = true
            portal.orderOut(nil)
        }
        updateStatusIcon()
    }
    private func updateStatusIcon() {
        if popover.isShown { refreshTiles() }
        guard statusItem != nil, portal != nil else { return }
        let activation = ActivationPolicy.triggered(mouseEnabled: mouseSwitch.state == .on,
            hovering: portal.frame.contains(NSEvent.mouseLocation), faceEnabled: guardian.enabled) || opacityPreviewTag != nil
        let quartzFrame = PortalGeometry.quartzRect(portal.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        let available = portalView.frameImage != nil && PortalGeometry.crop(portal: quartzFrame, source: portalView.sourceBounds) != nil
        let state: DoorStatus = enabled && targetFrontmost ? .targetFrontmost : DoorStatusResolver.resolve(running: enabled, busy: busy, captureFault: captureFault,
            guardian: guardian.blockingStatus, hasContent: available, editing: portalView.editing, activation: activation)
        if briefStatus.stringValue != state.briefExplanation { briefStatus.stringValue = state.briefExplanation }
        if displayedStatus != state {
            displayedStatus = state
            statusItem.button?.image = DoorStatusIcon.image(for: state)
        }
        let detail = (state == .cameraUnavailable || state == .angle) ? guardianLabel.stringValue : state == .captureUnavailable ? statusLabel.stringValue : state.explanation
        let tooltip = "视窗之门 · \(state.explanation)" + (detail == state.explanation ? "" : "\n" + detail)
        if statusItem.button?.toolTip != tooltip {
            statusItem.button?.toolTip = tooltip
            statusItem.button?.setAccessibilityLabel(tooltip)
        }
    }
    private func tick() {
        defer { updateStatusIcon() }
        guardian.refresh()
        let now = ProcessInfo.processInfo.systemUptime
        if pointerPassSwitch.state == .on && now >= nextPointerPermissionPoll {
            nextPointerPermissionPoll = now + 0.5
            let trusted = PointerRouter.trusted
            if lastPointerPermission != trusted {
                lastPointerPermission = trusted
                showPointerFeedback(trusted ? "辅助功能已授权 · 后台输入就绪" : "辅助功能未授权 · 点击无法发送")
                if !trusted { pointerRouter.cancel() }
            }
        }
        if enabled && now >= nextPositionPoll {
            nextPositionPoll = now + 0.1
            pollSourcePosition()
        }
        if enabled && now >= nextStackPoll {
            nextStackPoll = now + 0.2
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            targetFrontmost = WindowFrontPolicy.targetIsFrontmost(windows, target: selectedWindowID, ownPID: ProcessInfo.processInfo.processIdentifier)
        }
        if enabled && targetFrontmost {
            shortcuts.setScopeActive(false); shortcuts.setTargetMoveEnabled(false)
            portalView.endTargetMove(); portalView.endManipulation(); portalView.editing = false
            applyAppearance(active: false); portal.ignoresMouseEvents = true; portal.orderOut(nil)
            return
        }
        shortcuts.setTargetMoveEnabled(enabled && pointerPassSwitch.state == .on)
        let movingKey = enabled && pointerPassSwitch.state == .on && shortcuts.targetMoveActive(flags: NSEvent.modifierFlags)
        if !movingKey { portalView.endTargetMove() }
        let option = !movingKey && enabled && followSwitch.state == .off && shortcuts.editActive(flags: NSEvent.modifierFlags)
        if !option, portalView.isManipulating { portalView.endManipulation() }
        let mouse = NSEvent.mouseLocation
        let hovering = portal.frame.contains(mouse)
        let quartzFrame = PortalGeometry.quartzRect(portal.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        let activation = ActivationPolicy.triggered(mouseEnabled: mouseSwitch.state == .on, hovering: hovering, faceEnabled: guardian.enabled)
        let hasContent = guardian.allowsReveal && portalView.frameImage != nil && PortalGeometry.crop(portal: quartzFrame, source: portalView.sourceBounds) != nil
        shortcuts.setScopeActive(PortalGeometry.shortcutScope(enabled: enabled,
            hovering: activation || portalView.isManipulating || portalView.isMovingTarget || movingKey,
            hasFrame: hasContent || (guardian.allowsReveal && (portalView.isManipulating || portalView.isMovingTarget)), settingsShown: popover.isShown))
        portalView.editing = option && (hovering || portalView.isManipulating)
        portalView.updateCursor(mouse: mouse, option: option)
        let reveal = guardian.allowsReveal && PortalGeometry.reveals(enabled: enabled, hovering: activation || opacityPreviewTag != nil,
            dragging: portalView.editing || portalView.isManipulating || portalView.isMovingTarget || movingKey,
            hasFrame: portalView.frameImage != nil)
        applyAppearance(active: reveal)
        if enabled, !receivedFrame, Date().timeIntervalSince(captureStartedAt) > 3 {
            statusLabel.stringValue = "未收到画面，请恢复或重新选择窗口。"
        }
    }
}

@main
struct HoverPortalMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

private final class HelpDocumentView: NSView { override var isFlipped: Bool { true } }

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc -swift-version 5 Sources/HoverPortal/Geometry.swift Sources/HoverPortal/CaptureFailure.swift Tests/GeometryTests.swift -o .build/geometry-tests
.build/geometry-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/SceneSafety.swift Sources/HoverPortal/RecoveryDelay.swift Sources/HoverPortal/GestureProfile.swift Tests/SceneSafetyTests.swift -o .build/scene-safety-tests
.build/scene-safety-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/WindowSelection.swift Tests/WindowSelectionTests.swift -o .build/window-selection-tests
.build/window-selection-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/SceneSafety.swift Sources/HoverPortal/GestureProfile.swift Tests/GestureLearningTests.swift -o .build/gesture-learning-tests
.build/gesture-learning-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/ActivationPolicy.swift Sources/HoverPortal/SceneSafety.swift Sources/HoverPortal/GestureProfile.swift Tests/ActivationPolicyTests.swift -o .build/activation-policy-tests
.build/activation-policy-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/CaptureLifecycle.swift Tests/CaptureLifecycleTests.swift -o .build/capture-lifecycle-tests
.build/capture-lifecycle-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/ViewingAngles.swift Tests/ViewingAnglesTests.swift -o .build/viewing-angles-tests
.build/viewing-angles-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/PortalIcons.swift Sources/HoverPortal/StatusIcon.swift Tests/StatusIconTests.swift -o .build/status-icon-tests
.build/status-icon-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/ResourcePolicy.swift Sources/HoverPortal/SceneSafety.swift Sources/HoverPortal/GestureProfile.swift Tests/ResourcePolicyTests.swift -o .build/resource-policy-tests
.build/resource-policy-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/OpacityPolicy.swift Sources/HoverPortal/BackgroundClick.swift Sources/HoverPortal/PointerHitPolicy.swift Sources/HoverPortal/PointerEventFactory.swift Sources/HoverPortal/PointerRouter.swift Sources/HoverPortal/WindowSelection.swift Tests/OpacityPointerTests.swift -o .build/opacity-pointer-tests
.build/opacity-pointer-tests
xcrun swiftc -swift-version 5 Sources/HoverPortal/PointerEventFactory.swift Tests/PointerWindowTests.swift -o .build/pointer-window-tests
.build/pointer-window-tests

xcrun swiftc -swift-version 5 Sources/HoverPortal/SettingsTile.swift Tests/SettingsTileTests.swift -o .build/settings-tile-tests
.build/settings-tile-tests

xcrun swiftc Sources/HoverPortal/GuardianPolicy.swift Sources/HoverPortal/RevealStability.swift Tests/RevealStabilityTests.swift -o .build/reveal-stability-tests
.build/reveal-stability-tests

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
configuration="${1:-release}"
swift build -c "$configuration"
app="$PWD/视窗之门.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
binary_dir=$(swift build -c "$configuration" --show-bin-path)
cp "$binary_dir/HoverPortal" "$app/Contents/MacOS/HoverPortal"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/Models" "$app/Contents/Resources/Runtime" "$app/Contents/Resources/Licenses"
cp Resources/model-manifest.json "$app/Contents/Resources/"
cp Resources/Models/sface.onnx "$app/Contents/Resources/Models/"
cp Resources/Runtime/libonnxruntime.dylib "$app/Contents/Resources/Runtime/"
cp Resources/Licenses/* "$app/Contents/Resources/Licenses/"
codesign --force --sign - "$app/Contents/Resources/Runtime/libonnxruntime.dylib"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HoverPortal</string>
<key>CFBundleIdentifier</key><string>local.hoverportal.camera</string>
<key>CFBundleName</key><string>视窗之门</string>
<key>CFBundleDisplayName</key><string>视窗之门</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>CFBundleVersion</key><string>39</string>
<key>CFBundleShortVersionString</key><string>1.0.3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>在本机识别登记主人及其他面部，决定是否允许显示所选窗口。摄像头画面不保存、不上传。</string>
<key>NSScreenCaptureUsageDescription</key><string>在鼠标悬停的小矩形内显示您选择的下层窗口实时画面。画面仅在内存中处理，不录制、不上传。</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"

import AppKit

final class ToggleReceiver: NSObject {
    var count = 0
    @objc func changed(_ sender: NSSwitch) { count += 1 }
}
@main struct SettingsTileTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let receiver = ToggleReceiver(), control = NSSwitch()
        control.target = receiver; control.action = #selector(ToggleReceiver.changed(_:))
        let icon = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: nil)!
        var available = true, childCount = 0
        let main = TileButton(name: "摄像头守护", icon: icon,
            state: { TileState(on: control.state == .on) }, action: { control.performClick(nil) })
        let child = TileButton(name: "子设置", icon: icon, secondary: true,
            state: { TileState(enabled: available, help: available ? "设置" : "先开启主功能") }, action: { childCount += 1 })
        let tile = SettingsTile(main: main, children: [child])
        main.performClick(nil)
        precondition(control.state == .on && receiver.count == 1)
        tile.refresh(names: false)
        precondition(main.title.isEmpty && main.image != nil)
        let before = main.refreshCount
        for _ in 0..<100 { tile.refresh(names: false) }
        precondition(main.refreshCount == before)
        tile.refresh(names: true)
        precondition(main.title == "摄像头守护" && main.image == nil && control.state == .on)
        available = false; tile.refresh(names: true)
        child.performClick(nil)
        precondition(!child.isEnabled && childCount == 0 && child.toolTip!.contains("先开启主功能"))
        available = true; tile.refresh(names: true); child.performClick(nil)
        precondition(childCount == 1)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 84, height: 84), styleMask: .borderless, backing: .buffered, defer: false)
        let root = window.contentView!; root.addSubview(tile)
        NSLayoutConstraint.activate([tile.leadingAnchor.constraint(equalTo: root.leadingAnchor), tile.trailingAnchor.constraint(equalTo: root.trailingAnchor), tile.topAnchor.constraint(equalTo: root.topAnchor)])
        root.layoutSubtreeIfNeeded()
        precondition(abs(main.frame.height - 56) < 0.01 && abs(child.frame.height - 28) < 0.01)
        print("PASS: tile actions reuse native switch, disabled child does not fire, icon/name preserves state, rendering is cached and 2:1 layout fits")
    }
}

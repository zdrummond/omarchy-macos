// Read-only, time-bounded Dock click experiment. Not installed by refresh.
// Usage: swift scripts/dock_launch_probe.swift [seconds: 1...120]
//        swift scripts/dock_launch_probe.swift --self-test
// No keyboard monitor, AX actions, focus commands, or persistent output.
import AppKit
import ApplicationServices

struct ClickCandidate {
    let bundle: String
    let url: URL
    let point: CGPoint
    let timestamp: TimeInterval
}

func completedClick(_ down: ClickCandidate, _ up: ClickCandidate) -> Bool {
    down.bundle == up.bundle && down.url == up.url &&
    up.timestamp >= down.timestamp && up.timestamp - down.timestamp <= 3 &&
    hypot(up.point.x - down.point.x, up.point.y - down.point.y) <= 8
}

func applicationIcon(owner: pid_t, dock: pid_t, role: String?, subrole: String?) -> Bool {
    owner == dock && role == kAXDockItemRole && subrole == kAXApplicationDockItemSubrole
}

if CommandLine.arguments.dropFirst().first == "--self-test" {
    let url = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    let down = ClickCandidate(bundle: "com.google.Chrome", url: url, point: .zero, timestamp: 10)
    func up(_ bundle: String = "com.google.Chrome", _ seconds: Double = 11, _ x: Double = 0) -> ClickCandidate {
        ClickCandidate(bundle: bundle, url: url, point: CGPoint(x: x, y: 0), timestamp: seconds)
    }
    precondition(completedClick(down, up()))
    precondition(!completedClick(down, up("com.apple.TV")))
    precondition(!completedClick(down, up("com.google.Chrome", 14)))
    precondition(!completedClick(down, up("com.google.Chrome", 9)))
    precondition(!completedClick(down, up("com.google.Chrome", 11, 30)))
    precondition(applicationIcon(owner: 1, dock: 1, role: kAXDockItemRole, subrole: kAXApplicationDockItemSubrole))
    precondition(!applicationIcon(owner: 2, dock: 1, role: kAXDockItemRole, subrole: kAXApplicationDockItemSubrole))
    precondition(!applicationIcon(owner: 1, dock: 1, role: kAXDockItemRole, subrole: kAXMinimizedWindowDockItemSubrole))
    precondition(!applicationIcon(owner: 1, dock: 1, role: nil, subrole: nil))
    print("dock_launch_probe: 9 checks passed")
    exit(0)
}

guard CommandLine.arguments.count <= 2,
      let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60"),
      seconds.isFinite, (1...120).contains(seconds) else {
    fputs("Usage: swift scripts/dock_launch_probe.swift [seconds: 1...120] | --self-test\n", stderr)
    exit(2)
}

func emit(_ event: String, _ fields: [String: Any] = [:]) {
    var record = fields
    record["event"] = event
    record["time"] = ISO8601DateFormatter().string(from: Date())
    record["uptime"] = ProcessInfo.processInfo.systemUptime
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

// Do not request or change permission. A later standalone app needs its own
// verified permission identity; this probe's trust does not transfer to it.
guard AXIsProcessTrusted() else {
    emit("unavailable", ["reason": "Accessibility permission missing; no prompt requested"])
    exit(1)
}
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
    emit("unavailable", ["reason": "Dock not running"])
    exit(1)
}
let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
AXUIElementSetMessagingTimeout(dockElement, 0.1)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
}

func candidate(_ event: NSEvent) -> ClickCandidate? {
    let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    guard event.modifierFlags.intersection(modifiers).isEmpty,
          let point = event.cgEvent?.location else { return nil }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
          let element = hit else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.1)
    var owner: pid_t = 0
    guard AXUIElementGetPid(element, &owner) == .success,
          applicationIcon(owner: owner, dock: dock.processIdentifier,
                          role: value(element, kAXRoleAttribute) as? String,
                          subrole: value(element, kAXSubroleAttribute) as? String),
          let url = value(element, kAXURLAttribute) as? URL,
          url.isFileURL, url.pathExtension == "app",
          let bundle = Bundle(url: url)?.bundleIdentifier else { return nil }
    return ClickCandidate(bundle: bundle, url: url.standardizedFileURL,
                          point: point, timestamp: event.timestamp)
}

var pending: ClickCandidate?
var lastClick: ClickCandidate?
var mouseEvents = 0
var downs = 0
var clicks = 0
var activations = 0
let observer = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { notification in
    guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let click = pending ?? lastClick,
          ProcessInfo.processInfo.systemUptime - click.timestamp <= 3,
          activated.bundleIdentifier == click.bundle,
          activated.bundleURL?.standardizedFileURL == click.url else { return }
    activations += 1
    emit("matching-activation", ["bundle": click.bundle, "pid": activated.processIdentifier,
                                 "phase": pending == nil ? "after-click" : "during-click"])
}
guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { event in
    mouseEvents += 1
    let hit = candidate(event)
    if event.type == .leftMouseDown {
        pending = hit
        lastClick = nil
        if let hit = hit {
            downs += 1
            emit("dock-down", ["bundle": hit.bundle])
        }
    } else {
        defer { pending = nil }
        guard let down = pending else { return }
        guard let hit = hit, completedClick(down, hit) else {
            emit("candidate-cancelled", ["bundle": down.bundle, "reason": "release did not match app, time, or position"])
            return
        }
        clicks += 1
        lastClick = hit
        let front = NSWorkspace.shared.frontmostApplication
        emit("dock-click", ["bundle": hit.bundle,
                            "alreadyFrontmost": front?.bundleIdentifier == hit.bundle && front?.bundleURL?.standardizedFileURL == hit.url])
    }
}) else {
    NSWorkspace.shared.notificationCenter.removeObserver(observer)
    emit("unavailable", ["reason": "global mouse monitor could not be installed"])
    exit(1)
}
emit("listening", ["seconds": seconds, "readOnly": true])
// NSEvent monitors need AppKit's event dispatch, not just a Foundation run
// loop. The prohibited activation policy prevents this probe taking focus.
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    NSEvent.removeMonitor(monitor)
    NSWorkspace.shared.notificationCenter.removeObserver(observer)
    emit("finished", ["mouseEvents": mouseEvents, "dockDowns": downs,
                      "dockClicks": clicks, "matchingActivations": activations])
    exit(0)
}
app.run()

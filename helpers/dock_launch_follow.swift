// Dock launch intent broker. Explicit opt-in service; --observe never mutates.
// The private AX-to-CG window-ID bridge is dynamically checked and fail-closed.
import AppKit
import ApplicationServices
import Darwin
import CryptoKit

struct Request: Codable {
    let window: UInt32
    let source: String
    let target: String
    let bundle: String
    let deadline: Double
}

struct ChromeLaunchRequest: Codable {
    let token: UUID
    let started: Double
}

func freshLaunchRequest(_ started: Double, at time: Double) -> Bool {
    started.isFinite && time.isFinite && time >= started && time - started <= 0.75
}

struct Evidence {
    var age: Double = 0
    var coldLaunch = false
    var inputUnchanged = true
    var navigationUnchanged = true
    var sameProcess = true
    var newWindow = true
    var exactFocusedWindow = true
    var ordinary = true
    var restoreClear = true
    var sameSource = true
    var observerReady = true
}

func launchAllowance(coldLaunch: Bool) -> Double { coldLaunch ? 15 : 3 }

func launchPending(age: Double, coldLaunch: Bool) -> Bool {
    age >= 0 && age <= launchAllowance(coldLaunch: coldLaunch)
}

func permitted(_ e: Evidence) -> Bool {
    launchPending(age: e.age, coldLaunch: e.coldLaunch) && e.inputUnchanged && e.navigationUnchanged &&
    e.sameProcess && e.newWindow && e.exactFocusedWindow && e.ordinary &&
    e.restoreClear && e.sameSource && e.observerReady
}

func ordinary(role: String?, subrole: String?, modal: Bool?, children: [String]?) -> Bool {
    role == kAXWindowRole && subrole == kAXStandardWindowSubrole && modal == false &&
    children != nil && !children!.contains(kAXSheetRole)
}

// Runs only on the main loop. No delayed closures retain a cancelled intent.
// The retry clock starts at process binding, never at each failed attempt.
struct ObserverAttachment {
    let started: Double
    var nextAttempt: Double = 0
    var attempts = 0
    var ready = false
    var failed = false

    mutating func advance(at time: Double, contextValid: Bool,
                          attach: () -> AXError) -> AXError? {
        guard !failed else { return nil }
        guard contextValid, time.isFinite, time >= started else { failed = true; return nil }
        if ready { return nil }
        guard time < started + 2, attempts < 20 else { failed = true; return nil }
        guard time >= nextAttempt else { return nil }
        attempts += 1
        let error = attach()
        if error == .success { ready = true }
        else if [.cannotComplete, .failure, .notificationUnsupported,
                 .notImplemented, .invalidUIElement].contains(error) {
            nextAttempt = time + 0.1
        } else { failed = true }
        return error
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let service = args == ["--service"]
if args == ["--self-test"] {
    precondition(freshLaunchRequest(10, at: 10.75))
    for time in [9.0, 10.751, Double.infinity, Double.nan] {
        precondition(!freshLaunchRequest(10, at: time))
    }
    precondition(!freshLaunchRequest(Double.nan, at: 10))
    print("dock_launch_follow: 6 command freshness checks passed")
    precondition(permitted(Evidence()))
    for key in [\Evidence.inputUnchanged, \.navigationUnchanged, \.sameProcess,
                \.newWindow, \.exactFocusedWindow, \.ordinary, \.restoreClear, \.sameSource, \.observerReady] {
        var e = Evidence(); e[keyPath: key] = false; precondition(!permitted(e))
    }
    for age in [-1.0, 3.01, Double.infinity, Double.nan] {
        var e = Evidence(); e.age = age; precondition(!permitted(e))
    }
    // Cold startup may take longer, but never renews its original deadline or
    // relaxes any identity, focus, dialog, input, navigation, or restore gate.
    for (age, accepted) in [(0.0, true), (8.0, true), (15.0, true),
                            (15.001, false), (-1.0, false),
                            (Double.infinity, false), (Double.nan, false)] {
        var e = Evidence(); e.coldLaunch = true; e.age = age
        precondition(permitted(e) == accepted)
    }
    var warm = Evidence(); warm.age = 8; precondition(!permitted(warm))
    for key in [\Evidence.inputUnchanged, \.navigationUnchanged, \.sameProcess,
                \.newWindow, \.exactFocusedWindow, \.ordinary, \.restoreClear, \.sameSource, \.observerReady] {
        var e = Evidence(); e.coldLaunch = true; e.age = 8
        e[keyPath: key] = false; precondition(!permitted(e))
    }
    precondition(ordinary(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, modal: false, children: []))
    precondition(!ordinary(role: kAXWindowRole, subrole: kAXDialogSubrole, modal: false, children: []))
    precondition(!ordinary(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, modal: true, children: []))
    precondition(!ordinary(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, modal: nil, children: []))
    precondition(!ordinary(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, modal: false, children: [kAXSheetRole]))
    precondition(!ordinary(role: nil, subrole: nil, modal: nil, children: nil))
    print("dock_launch_follow: 37 policy checks passed")
    var checks = 0
    func check(_ condition: Bool) { precondition(condition); checks += 1 }
    var retry = ObserverAttachment(started: 10)
    check(retry.advance(at: 10, contextValid: true) { .cannotComplete } == .cannotComplete)
    check(!retry.ready && !retry.failed && retry.attempts == 1)
    check(retry.advance(at: 10.05, contextValid: true) { preconditionFailure("too early") } == nil)
    check(retry.advance(at: 10.11, contextValid: true) { .success } == .success)
    check(retry.ready && retry.attempts == 2)
    check(retry.advance(at: 10.5, contextValid: true) { preconditionFailure("already attached") } == nil)
    for error: AXError in [.cannotComplete, .failure, .notificationUnsupported, .notImplemented, .invalidUIElement] {
        var pending = ObserverAttachment(started: 0)
        check(pending.advance(at: 0, contextValid: true) { error } == error)
        check(!pending.failed && !pending.ready)
        check(pending.advance(at: 2, contextValid: true) { preconditionFailure("deadline") } == nil)
        check(pending.failed && !pending.ready)
    }
    for error: AXError in [.apiDisabled, .illegalArgument, .invalidUIElementObserver] {
        var pending = ObserverAttachment(started: 0)
        check(pending.advance(at: 0, contextValid: true) { error } == error)
        check(pending.failed && !pending.ready)
        check(pending.advance(at: 0.2, contextValid: true) { preconditionFailure("fatal failure") } == nil)
    }
    var cancelled = ObserverAttachment(started: 0)
    _ = cancelled.advance(at: 0, contextValid: true) { .cannotComplete }
    check(cancelled.advance(at: 0.2, contextValid: false) { preconditionFailure("cancelled context") } == nil)
    check(cancelled.failed && !cancelled.ready)
    check(cancelled.advance(at: 0.4, contextValid: true) { preconditionFailure("cannot revive") } == nil)
    var capped = ObserverAttachment(started: 0); capped.attempts = 20
    check(capped.advance(at: 1, contextValid: true) { preconditionFailure("attempt cap") } == nil)
    check(capped.failed)
    for time in [-1.0, Double.nan, Double.infinity] {
        var pending = ObserverAttachment(started: 0)
        check(pending.advance(at: time, contextValid: true) { preconditionFailure("invalid clock") } == nil)
        check(pending.failed)
    }
    // Permission/registration failure cannot become follow approval simply
    // because the exact window and other policy evidence are otherwise valid.
    var notReady = Evidence(); notReady.observerReady = cancelled.ready
    check(!permitted(notReady))
    print("dock_launch_follow: \(checks) observer attachment checks passed")
    exit(0)
}

let now = { ProcessInfo.processInfo.systemUptime }
let name = "com.omarchy-macos.dock-launch.\(getuid())" as CFString
let env = ProcessInfo.processInfo.environment
let temp = env["TMPDIR"] ?? "/tmp"
let navigationPath = env["OMARCHY_WORKSPACE_CHANGE_STATE"] ?? temp + "/omarchy_workspace_change_last"
let aerospace = env["OMARCHY_AEROSPACE_BIN"] ?? "/opt/homebrew/bin/aerospace"
let serviceMarker = (env["HOME"] ?? NSHomeDirectory()) + "/.omarchy-macos-backup/dock-launch-follow-enabled.sha256"
var serviceDigest: String?

// The existing Automator service calls this before creating its window. It
// remains the only shortcut owner and the only caller that launches Chrome.
if args.first == "--arm-chrome" || args.first == "--cancel-chrome" {
    guard args.count == 2, let token = UUID(uuidString: args[1]) else { exit(2) }
    let request = ChromeLaunchRequest(token: token, started: now())
    guard let port = CFMessagePortCreateRemote(nil, name) else { exit(1) }
    let data = try JSONEncoder().encode(request)
    var response: Unmanaged<CFData>?
    let arming = args[0] == "--arm-chrome"
    let status = CFMessagePortSendRequest(port, arming ? 4 : 5, data as CFData,
                                        0.2, 1, CFRunLoopMode.defaultMode.rawValue, &response)
    let reply = response?.takeRetainedValue() as Data?
    exit(status == kCFMessagePortSuccess && reply == Data((arming ? "armed" : "cancelled").utf8) ? 0 : 1)
}

func serviceAuthorized() -> Bool {
    guard let digest = serviceDigest,
          let recorded = try? String(contentsOfFile: serviceMarker, encoding: .utf8) else { return false }
    return recorded.trimmingCharacters(in: .whitespacesAndNewlines) == digest
}

if args == ["--stop"] || args == ["--status"] {
    guard let port = CFMessagePortCreateRemote(nil, name) else { print("dock-launch: not running"); exit(0) }
    var response: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(port, args == ["--stop"] ? 2 : 3, nil, 0.2, 0.5, CFRunLoopMode.defaultMode.rawValue, &response)
    guard status == kCFMessagePortSuccess, let data = response?.takeRetainedValue() else { exit(1) }
    print(String(decoding: data as Data, as: UTF8.self)); exit(0)
}

func log(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] dock-launch: \(message)\n"
    if service {
        // Reopen on each write so daily rotation does not strand a persistent
        // process's output in an old (eventually unlinked) file.
        let path = env["OMARCHY_WINDOW_STATE_LOG"] ?? "/tmp/omarchy_window_state.log"
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    } else { print(line, terminator: ""); fflush(stdout) }
}

func validWorkspace(_ value: String) -> Bool {
    value.utf8.count == 2 && value.utf8.allSatisfy { (48...57).contains($0) }
}

// The client never issues focus commands. Timeout, missing broker, bad response,
// or rejected evidence all leave normal no-follow rehome in control.
if args.first == "--move", args.count == 5, let window = UInt32(args[1]), window > 0,
   validWorkspace(args[2]), validWorkspace(args[3]), args[2] != args[3] {
    guard let port = CFMessagePortCreateRemote(nil, name) else { exit(1) }
    let request = Request(window: window, source: args[2], target: args[3], bundle: args[4], deadline: now() + 1)
    let data = try JSONEncoder().encode(request)
    var response: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(port, 1, data as CFData, 0.2, 1.5, CFRunLoopMode.defaultMode.rawValue, &response)
    let reply = response?.takeRetainedValue() as Data?
    exit(status == kCFMessagePortSuccess && reply == Data("handled".utf8) ? 0 : 1)
}

let observe = args.first == "--observe"
let seconds: Double?
if service {
    guard let binary = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0])) else { exit(6) }
    serviceDigest = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
    guard serviceAuthorized() else {
        log("service disabled: missing or stale executable authorization; run dock-launch-follow enable")
        exit(6)
    }
    seconds = nil
} else {
    guard (observe || args.first == "--serve"), args.count == 2, let duration = Double(args[1]),
          duration.isFinite, (1...3600).contains(duration) else {
        fputs("Usage: dock_launch_follow --observe|--serve seconds(1...3600) | --service | --move id source target bundle | --self-test\n", stderr)
        exit(2)
    }
    seconds = duration
}

typealias WindowBridge = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
guard AXIsProcessTrusted() else {
    log("unavailable: Accessibility permission missing; add ~/Applications/Omarchy Dock Launch.app in System Settings; no permission prompt")
    exit(3)
}
guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
    log("unavailable: window-ID bridge missing")
    exit(3)
}
guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
    log("unavailable: Dock not running")
    exit(3)
}
let bridge = unsafeBitCast(symbol, to: WindowBridge.self)
let dockAX = AXUIElementCreateApplication(dock.processIdentifier)
AXUIElementSetMessagingTimeout(dockAX, 0.05)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}

func windowID(_ element: AXUIElement) -> UInt32? {
    var id: CGWindowID = 0
    return bridge(element, &id) == .success && id > 0 ? id : nil
}

func focusedWindow(_ root: AXUIElement) -> AXUIElement? {
    guard let raw = attribute(root, kAXFocusedWindowAttribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(raw, to: AXUIElement.self)
}

func isOrdinary(_ element: AXUIElement) -> Bool {
    let deadline = now() + 0.2
    AXUIElementSetMessagingTimeout(element, 0.05)
    guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement], children.count <= 100 else { return false }
    var roles: [String] = []
    for child in children {
        guard now() < deadline else { return false }
        AXUIElementSetMessagingTimeout(child, 0.05)
        guard let role = attribute(child, kAXRoleAttribute) as? String else { return false }
        roles.append(role)
    }
    return now() < deadline && ordinary(role: attribute(element, kAXRoleAttribute) as? String,
                    subrole: attribute(element, kAXSubroleAttribute) as? String,
                    modal: attribute(element, kAXModalAttribute) as? Bool, children: roles)
}

// Small, bounded CLI results only. A timed-out command is never retried here.
func run(_ arguments: [String], timeout: Double = 0.25) -> String? {
    let p = Process(); let output = Pipe()
    p.executableURL = URL(fileURLWithPath: aerospace); p.arguments = arguments
    p.standardOutput = output; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let deadline = now() + timeout
    while p.isRunning && now() < deadline { Thread.sleep(forTimeInterval: 0.002) }
    if p.isRunning {
        p.terminate()
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        return nil
    }
    guard p.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func restoreClear() -> Bool {
    let paths = [env["OMARCHY_WINDOW_RESTORE_GUARD"] ?? temp + "/omarchy_window_state_restore_active",
                 env["OMARCHY_WINDOW_STARTUP_RESTORE_GUARD"] ?? temp + "/omarchy_window_state_startup_restore_active",
                 env["OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD"] ?? temp + "/omarchy_window_state_restore_incomplete",
                 temp + "/omarchy_native_input_active"]
    return paths.allSatisfy { !FileManager.default.fileExists(atPath: $0) }
}

struct Intent {
    let bundle: String
    let url: URL
    let point: CGPoint
    let down: Double
    let downDate: Date
    let coldLaunch: Bool
    let source: String
    let navigation: Data
    let existing: Set<UInt32>
    var clicked = false
    var pid: pid_t?
    var launched: Date?
    var window: UInt32?
    var commandToken: UUID?
}
var intent: Intent?
var axObserver: AXObserver?
var observerAttachment: ObserverAttachment?
func cancel(_ reason: String) {
    if let i = intent { log("cancelled reason=\(reason) age=\(now() - i.down) cold=\(i.coldLaunch)") }
    intent = nil
    if let observer = axObserver {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    axObserver = nil
    observerAttachment = nil
}

func focusEvent(_ element: AXUIElement) {
    guard var i = intent else { return }
    // A focused-window notification may identify the application rather than
    // the window. Resolve only that exact bound process, never by title.
    var pid: pid_t = 0
    AXUIElementSetMessagingTimeout(element, 0.05)
    guard AXUIElementGetPid(element, &pid) == .success, pid == i.pid else {
        cancel("different-process-focus"); return
    }
    let candidate: AXUIElement?
    if attribute(element, kAXRoleAttribute) as? String == kAXApplicationRole {
        candidate = focusedWindow(element)
    } else { candidate = element }
    guard let candidate = candidate, let id = windowID(candidate),
          !i.existing.contains(id), i.window == nil || i.window == id else {
        cancel("different-or-existing-window"); return
    }
    if i.window == nil { log("focused-window window=\(id) age=\(now() - i.down)") }
    i.window = id; intent = i
}
let axCallback: AXObserverCallback = { _, element, _, _ in focusEvent(element) }

func bind(_ app: NSRunningApplication) {
    guard var i = intent, app.bundleIdentifier == i.bundle,
          app.bundleURL?.standardizedFileURL == i.url, let launched = app.launchDate,
          !i.coldLaunch || launched >= i.downDate,
          !app.isTerminated,
          i.pid == nil || (i.pid == app.processIdentifier && i.launched == launched) else {
        cancel("different-application-or-process"); return
    }
    if i.pid == nil {
        i.pid = app.processIdentifier; i.launched = launched; intent = i
        observerAttachment = ObserverAttachment(started: now())
        log("bound-process bundle=\(i.bundle) pid=\(app.processIdentifier) age=\(now() - i.down) cold=\(i.coldLaunch)")
    }
    guard i.clicked else { return }
    guard let readiness = observerAttachment else { cancel("observer-state-missing"); return }
    var pending = readiness
    // Revalidate before every attempt, including requests that arrive before
    // the timer has processed intervening input or navigation.
    let valid = pendingCancellationReason(i) == nil && AXIsProcessTrusted() &&
        NSWorkspace.shared.frontmostApplication?.processIdentifier == i.pid
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.05)
    var attached: AXObserver?
    var stage = "create"
    let result = pending.advance(at: now(), contextValid: valid) {
        var candidate: AXObserver?
        let created = AXObserverCreate(app.processIdentifier, axCallback, &candidate)
        guard created == .success, let candidate = candidate else {
            return created == .success ? .failure : created
        }
        stage = "register"
        let registered = AXObserverAddNotification(candidate, root, kAXFocusedWindowChangedNotification as CFString, nil)
        if registered == .success { attached = candidate }
        return registered
    }
    observerAttachment = pending
    if let result = result {
        log("observer-attempt pid=\(app.processIdentifier) attempt=\(pending.attempts) stage=\(stage) axError=\(result.rawValue) age=\(now() - i.down)")
    }
    guard !pending.failed, pendingCancellationReason(i) == nil, AXIsProcessTrusted(),
          !app.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == i.pid else {
        cancel("observer-retry-cancelled-or-exhausted"); return
    }
    if let attached = attached {
        guard now() < pending.started + 2 else { cancel("observer-retry-expired"); return }
        axObserver = attached
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(attached), .commonModes)
        log("observer-ready pid=\(app.processIdentifier) attempts=\(pending.attempts) age=\(now() - i.down)")
        // Establish the current window immediately; attachment does not
        // guarantee a notification for an already-focused window.
        if let window = focusedWindow(root) { focusEvent(window) }
    }
}

func icon(_ event: NSEvent) -> (String, URL, CGPoint)? {
    guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
          let point = event.cgEvent?.location else { return nil }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(dockAX, Float(point.x), Float(point.y), &hit) == .success,
          let hit = hit else { return nil }
    AXUIElementSetMessagingTimeout(hit, 0.05)
    var pid: pid_t = 0
    guard AXUIElementGetPid(hit, &pid) == .success, pid == dock.processIdentifier,
          attribute(hit, kAXRoleAttribute) as? String == kAXDockItemRole,
          attribute(hit, kAXSubroleAttribute) as? String == kAXApplicationDockItemSubrole,
          let url = attribute(hit, kAXURLAttribute) as? URL, url.isFileURL, url.pathExtension == "app",
          let bundle = Bundle(url: url)?.bundleIdentifier else { return nil }
    return (bundle, url.standardizedFileURL, point)
}

func inputUnchanged(_ i: Intent) -> Bool {
    // Read only elapsed-time metadata, never key codes or typed content. This
    // catches navigation queued while AX/CLI checks temporarily occupy main.
    let current = now()
    return [CGEventType.keyDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .leftMouseDragged].allSatisfy {
        current - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) <= i.down
    } && current - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown) <= i.down + 0.01
}

func pendingCancellationReason(_ i: Intent) -> String? {
    if !launchPending(age: now() - i.down, coldLaunch: i.coldLaunch) { return "expired" }
    if !restoreClear() { return "restore-or-native-input" }
    if !inputUnchanged(i) { return "intervening-input" }
    if (try? Data(contentsOf: URL(fileURLWithPath: navigationPath))) != i.navigation { return "workspace-changed" }
    return nil
}

func armChrome(_ request: ChromeLaunchRequest) -> String {
    cancel("explicit-chrome-command")
    guard freshLaunchRequest(request.started, at: now()), restoreClear(), AXIsProcessTrusted(),
          !service || serviceAuthorized(),
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
          let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
          let navigation = try? Data(contentsOf: URL(fileURLWithPath: navigationPath)),
          let workspace = run(["list-workspaces", "--focused"]), validWorkspace(workspace) else { return "declined" }
    let cold = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
    let existing = Set(rows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    var candidate = Intent(bundle: "com.google.Chrome", url: url.standardizedFileURL, point: .zero,
                           down: request.started, downDate: Date(timeIntervalSinceNow: request.started - now()),
                           coldLaunch: cold, source: workspace, navigation: navigation, existing: existing)
    candidate.clicked = true
    candidate.commandToken = request.token
    guard freshLaunchRequest(request.started, at: now()), pendingCancellationReason(candidate) == nil else { return "declined" }
    intent = candidate
    // Do not bind the previously focused Chrome window here. The service has
    // not created the requested window yet; activation/placement does binding.
    log("command-armed app=Chrome source=\(workspace) cold=\(cold)")
    return "armed"
}

func handle(_ r: Request) -> String {
    log("placement-request window=\(r.window) source=\(r.source) target=\(r.target) pending=\(intent != nil)")
    guard var i = intent, i.clicked, i.bundle == r.bundle, i.source == r.source,
          validWorkspace(r.source), validWorkspace(r.target), r.source != r.target,
          now() <= r.deadline,
          launchPending(age: now() - i.down, coldLaunch: i.coldLaunch) else { return "declined" }
    // Validation is synchronous on the broker's serial main loop. Every
    // accepted candidate is consumed before any move, including failed moves.
    guard let front = NSWorkspace.shared.frontmostApplication else { cancel("no-front-app"); return "declined" }
    bind(front)
    guard let bound = intent, let pid = bound.pid else { return "declined" }
    guard axObserver != nil, observerAttachment?.ready == true else {
        // Do not queue a follow after normal placement has already continued.
        cancel("placement-before-observer-ready"); return "declined"
    }
    i = bound
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 0.05)
    guard let window = focusedWindow(root) else {
        cancel("focused-window-unavailable"); return "declined"
    }
    var e = Evidence()
    e.coldLaunch = i.coldLaunch
    e.observerReady = axObserver != nil && observerAttachment?.ready == true
    e.newWindow = !i.existing.contains(r.window) && (i.window == nil || i.window == r.window)
    e.exactFocusedWindow = windowID(window) == r.window
    e.sameProcess = front.processIdentifier == i.pid && front.launchDate == i.launched && !front.isTerminated
    e.sameSource = run(["list-windows", "--focused", "--format", "%{window-id}|%{workspace}|%{app-bundle-id}"]) == "\(r.window)|\(r.source)|\(r.bundle)"
    e.ordinary = isOrdinary(window)
    e.restoreClear = restoreClear()
    e.navigationUnchanged = (try? Data(contentsOf: URL(fileURLWithPath: navigationPath))) == i.navigation
    e.inputUnchanged = inputUnchanged(i)
    e.age = now() - i.down
    // Re-read focus after the potentially slow AX inspection: the original
    // element can remain valid even when another same-app window gains focus.
    let stillFocused = focusedWindow(root).flatMap(windowID) == r.window
    e.age = now() - i.down
    let allowed = permitted(e) && stillFocused && now() <= r.deadline && AXIsProcessTrusted() &&
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid &&
        inputUnchanged(i) && restoreClear() &&
        (try? Data(contentsOf: URL(fileURLWithPath: navigationPath))) == i.navigation
    if !allowed {
        log("rejected window=\(r.window) ordinary=\(e.ordinary) exactFocus=\(e.exactFocusedWindow) new=\(e.newWindow) source=\(e.sameSource) navigation=\(e.navigationUnchanged) input=\(e.inputUnchanged) age=\(e.age)")
    }
    cancel(allowed ? "consumed" : "validation-failed")
    guard allowed else { return "declined" }
    if observe { log("would-follow window=\(r.window) source=\(r.source) target=\(r.target)"); return "declined" }
    log("move-follow-request window=\(r.window) source=\(r.source) target=\(r.target)")
    let result = run(["move-node-to-workspace", "--window-id", String(r.window), "--focus-follows-window", r.target])
    log("move-follow-result window=\(r.window) success=\(result != nil); no retry")
    return result == nil ? "declined" : "handled"
}

let callback: CFMessagePortCallBack = { _, message, data, _ in
    if message == 2 {
        cancel("stop-request")
        DispatchQueue.main.async { exit(0) }
        return Unmanaged.passRetained(Data("dock-launch: stopped".utf8) as CFData)
    }
    if message == 3 {
        return Unmanaged.passRetained(Data("dock-launch: running mode=\(service ? "service" : (observe ? "observe" : "serve")) pid=\(getpid())".utf8) as CFData)
    }
    let reply: String
    if (message == 4 || message == 5), let data = data, CFDataGetLength(data) <= 4096,
       let request = try? JSONDecoder().decode(ChromeLaunchRequest.self, from: data as Data) {
        if message == 4 { reply = armChrome(request) }
        else {
            if intent?.commandToken == request.token { cancel("chrome-command-failed") }
            reply = "cancelled"
        }
    } else if message == 1, let data = data, CFDataGetLength(data) <= 4096,
       let request = try? JSONDecoder().decode(Request.self, from: data as Data) {
        reply = handle(request)
    } else { reply = "declined" }
    return Unmanaged.passRetained(Data(reply.utf8) as CFData)
}
var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
var freeInfo = DarwinBoolean(false)
guard let port = CFMessagePortCreateLocal(nil, name, callback, &context, &freeInfo),
      let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else {
    log("unavailable: another broker is running or IPC failed"); exit(4)
}
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
    guard intent != nil, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    bind(app)
}
guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown], handler: { event in
    // The invoking shortcut/click can be queued before IPC arming. Ignore only
    // events predating that command, and its harmless mouse-button release.
    if let i = intent, i.commandToken != nil,
       event.timestamp <= i.down || event.type == .leftMouseUp { return }
    if event.type == .leftMouseDown {
        cancel("new-click")
        guard let (bundle, url, point) = icon(event), restoreClear() else { return }
        // Snapshot before slow AX/CLI work. Any already-running instance with
        // this bundle keeps the short budget, even if it has no open windows.
        let coldLaunch = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
        let downDate = Date(timeIntervalSinceNow: event.timestamp - now())
        guard let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
              let navigation = try? Data(contentsOf: URL(fileURLWithPath: navigationPath)),
              let workspace = run(["list-workspaces", "--focused"]), validWorkspace(workspace) else { return }
        let existing = Set(rows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        intent = Intent(bundle: bundle, url: url, point: point, down: event.timestamp,
                        downDate: downDate, coldLaunch: coldLaunch,
                        source: workspace, navigation: navigation, existing: existing)
    } else if event.type == .leftMouseUp {
        guard var i = intent else { return }
        guard let (bundle, url, point) = icon(event), bundle == i.bundle, url == i.url,
              event.timestamp >= i.down, event.timestamp - i.down <= 3,
              hypot(point.x - i.point.x, point.y - i.point.y) <= 8 else { cancel("unmatched-release"); return }
        i.clicked = true; intent = i
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundle { bind(front) }
        log("click bundle=\(bundle) source=\(i.source) cold=\(i.coldLaunch) allowance=\(launchAllowance(coldLaunch: i.coldLaunch))s-from-down")
    } else { cancel("intervening-input") }
}) else { log("unavailable: input monitor failed"); exit(5) }
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    guard let i = intent else { return }
    if let reason = pendingCancellationReason(i) { cancel(reason); return }
    if !AXIsProcessTrusted() { cancel("permission-lost"); return }
    if i.clicked, let pid = i.pid {
        guard let process = NSRunningApplication(processIdentifier: pid), !process.isTerminated,
              process.launchDate == i.launched,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            cancel("process-exited-or-focus-changed"); return
        }
        if axObserver == nil { bind(process) }
    }
}
if let seconds = seconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        cancel("session-ended"); NSEvent.removeMonitor(monitor)
        NSWorkspace.shared.notificationCenter.removeObserver(activation)
        CFMessagePortInvalidate(port); log("stopped"); exit(0)
    }
} else {
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        if !serviceAuthorized() || !AXIsProcessTrusted() {
            cancel("service-authorization-or-permission-lost")
            log("service stopped: authorization or Accessibility permission lost; no automatic restart")
            exit(6)
        }
    }
}
log("listening mode=\(service ? "service" : (observe ? "observe" : "serve")) duration=\(seconds.map(String.init(describing:)) ?? "persistent")")
app.run()

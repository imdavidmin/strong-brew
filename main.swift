import AppKit
import IOKit.ps
import ServiceManagement

// Closing the lid on battery forces sleep regardless of power assertions;
// the only supported override is `pmset -a disablesleep 1`, which needs root.
enum Power {
    static let pmset = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/strongbrew"

    static func isSleepDisabled() -> Bool {
        let out = run(pmset, ["-g"]).output
        return out.split(separator: "\n").contains {
            let parts = $0.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return parts.first == "SleepDisabled" && parts.last == "1"
        }
    }

    /// `interactive: false` never prompts for a password, which matters for
    /// automatic turn-off: a prompt with the lid closed would hang forever.
    static func setSleepDisabled(_ disabled: Bool, interactive: Bool = true) -> Bool {
        let value = disabled ? "1" : "0"
        // Passwordless path, available once the sudoers helper is installed.
        if run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", value]).status == 0 {
            return true
        }
        return interactive && runAsAdmin("\(pmset) -a disablesleep \(value)")
    }

    static var helperInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    static func installHelper() -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
        let tmp = "/tmp/strongbrew.sudoers"
        let script = """
        printf '%s\\n' '\(rule)' > \(tmp) && \
        /usr/sbin/visudo -cf \(tmp) && \
        /usr/sbin/chown root:wheel \(tmp) && /bin/chmod 0440 \(tmp) && \
        /bin/mv \(tmp) \(sudoersPath)
        """
        return runAsAdmin(script)
    }

    /// Internal battery charge and whether the Mac is currently running from it.
    static func battery() -> (percent: Int, onBattery: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let onBattery = desc[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return (current * 100 / max, onBattery)
        }
        return nil
    }

    private static func runAsAdmin(_ command: String) -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var awake = false
    private var deadline: Date?
    private var checkTimer: Timer?

    private static let durations: [(String, TimeInterval)] = [
        ("15 min", 15 * 60), ("30 min", 30 * 60), ("1 hr", 3600),
        ("2 hr", 2 * 3600), ("4 hr", 4 * 3600), ("8 hr", 8 * 3600),
    ]
    private static let batteryLevels = [5, 10, 15, 20]
    private static let batteryKey = "batteryThreshold"

    /// 0 means "never".
    private var batteryThreshold: Int {
        get { UserDefaults.standard.integer(forKey: Self.batteryKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.batteryKey) }
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        awake = Power.isSleepDisabled()
        updateIcon()

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.checkAutoOff() }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer

        if !Power.helperInstalled { requestOneTimeApproval() }
    }

    /// Asked on launch until granted: installs the sudoers rule so every later
    /// toggle (including automatic turn-off) runs without a password.
    private func requestOneTimeApproval() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow Strong Brew to control sleep?"
        alert.informativeText = "One-time admin approval. Grants only `pmset -a disablesleep 0|1`."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = Power.installHelper()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if awake && !Power.setSleepDisabled(false) {
            let alert = NSAlert()
            alert.messageText = "Sleep still disabled"
            alert.informativeText = "Run: sudo pmset -a disablesleep 0"
            alert.runModal()
        }
        return .terminateNow
    }

    // Rebuild each time the menu opens so state reflects any external pmset changes.
    func menuNeedsUpdate(_ menu: NSMenu) {
        awake = Power.isSleepDisabled()
        if !awake { deadline = nil }
        updateIcon()
        menu.removeAllItems()

        addDisabled(statusText())
        if let battery = Power.battery() {
            addDisabled("Battery \(battery.percent)%\(battery.onBattery ? "" : " · AC")")
        }
        menu.addItem(.separator())

        if awake {
            addItem("Allow Sleep", #selector(allowSleep))
            if deadline != nil { addItem("Keep Awake", #selector(keepAwakeIndefinitely)) }
        } else {
            addItem("Keep Awake", #selector(keepAwakeIndefinitely))
        }

        let forMenu = NSMenu()
        for (index, (title, _)) in Self.durations.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(keepAwakeFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            forMenu.addItem(item)
        }
        addSubmenu("Awake For", forMenu)
        addItem("Awake Until…", #selector(keepAwakeUntil))

        let batteryMenu = NSMenu()
        for level in [0] + Self.batteryLevels {
            let item = NSMenuItem(title: level == 0 ? "Never" : "\(level)%", action: #selector(setBatteryThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level
            item.state = level == batteryThreshold ? .on : .off
            batteryMenu.addItem(item)
        }
        addSubmenu("Off at Battery", batteryMenu)
        menu.addItem(.separator())

        addItem("Launch at Login", #selector(toggleLaunchAtLogin))
        menu.items.last?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func statusText() -> String {
        guard awake else { return "Sleep allowed" }
        guard let deadline else { return "Awake" }
        let remaining = max(0, Int(deadline.timeIntervalSinceNow / 60))
        return "Awake until \(timeFormatter.string(from: deadline)) · \(remaining / 60)h \(remaining % 60)m"
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addItem(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func addSubmenu(_ title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func keepAwakeIndefinitely() {
        if turnOn() { deadline = nil }
        updateIcon()
    }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        guard ensureHelperForAutoOff(), turnOn() else { return }
        deadline = Date().addingTimeInterval(Self.durations[sender.tag].1)
        updateIcon()
    }

    @objc private func keepAwakeUntil() {
        guard let time = askForTime(), ensureHelperForAutoOff(), turnOn() else { return }
        deadline = time
        updateIcon()
    }

    @objc private func allowSleep() {
        turnOff(interactive: true)
    }

    @objc private func setBatteryThreshold(_ sender: NSMenuItem) {
        if sender.tag != 0 && !ensureHelperForAutoOff() { return }
        batteryThreshold = sender.tag
        checkAutoOff()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - State

    private func turnOn() -> Bool {
        if !awake { awake = Power.setSleepDisabled(true) }
        return awake
    }

    private func turnOff(interactive: Bool) {
        if Power.setSleepDisabled(false, interactive: interactive) {
            awake = false
            deadline = nil
        }
        updateIcon()
    }

    private func checkAutoOff() {
        guard awake else { return }
        if let deadline, deadline <= Date() {
            turnOff(interactive: false)
        } else if batteryThreshold > 0, let battery = Power.battery(),
                  battery.onBattery, battery.percent <= batteryThreshold {
            turnOff(interactive: false)
        }
    }

    /// Automatic turn-off can't show a password prompt (the lid may be closed),
    /// so it requires the sudoers helper.
    private func ensureHelperForAutoOff() -> Bool {
        if Power.helperInstalled { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Approval required"
        alert.informativeText = "Auto-off can't ask for a password. Grants only `pmset -a disablesleep 0|1`."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return Power.installHelper() && Power.helperInstalled
    }

    /// Returns the next occurrence of the chosen time of day.
    private func askForTime() -> Date? {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        picker.datePickerElements = .hourMinute
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = deadline ?? Date().addingTimeInterval(3600)

        let alert = NSAlert()
        alert.messageText = "Awake until"
        alert.accessoryView = picker
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: picker.dateValue)
        return calendar.nextDate(after: Date(), matching: parts, matchingPolicy: .nextTime)
    }

    private func updateIcon() {
        let image = awake ? MenuBarIcon.awake : MenuBarIcon.asleep
        image.accessibilityDescription = awake ? "Awake" : "Sleep allowed"
        statusItem.button?.image = image
        statusItem.button?.toolTip = statusText()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

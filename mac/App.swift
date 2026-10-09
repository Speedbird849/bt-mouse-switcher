import Cocoa
import Foundation
import IOBluetooth

class MainWindowController: NSWindowController {
    var statusLabel: NSTextField!
    var detailLabel: NSTextField!
    var switchButton: NSButton!
    var progressIndicator: NSProgressIndicator!
    var isSwitching = false
    var timer: Timer?

    let exactTargetName = "Bluetooth Mouse M336/M337/M535"
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/bt-mouse-switcher")
    var configFile: URL {
        return configDir.appendingPathComponent("config.json")
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Bluetooth Mouse Switcher"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let window = window else { return }
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView = contentView

        // Title Label
        let titleLabel = NSTextField(labelWithString: exactTargetName)
        titleLabel.frame = NSRect(x: 20, y: 195, width: 400, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        // Status Label
        statusLabel = NSTextField(labelWithString: "Status: Checking...")
        statusLabel.frame = NSRect(x: 20, y: 165, width: 400, height: 22)
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)

        // Switch Button
        switchButton = NSButton(frame: NSRect(x: 70, y: 100, width: 300, height: 48))
        switchButton.title = "Disconnect, Forget & Reconnect"
        switchButton.bezelStyle = .rounded
        switchButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        switchButton.target = self
        switchButton.action = #selector(onSwitchClicked)
        switchButton.keyEquivalent = "\r" // Enter key triggers it
        contentView.addSubview(switchButton)

        // Progress Spinner
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 208, y: 62, width: 24, height: 24))
        progressIndicator.style = .spinning
        progressIndicator.isDisplayedWhenStopped = false
        contentView.addSubview(progressIndicator)

        // Detail / Subtitle Label
        detailLabel = NSTextField(labelWithString: "Make sure the pairing button on the mouse is blinking.")
        detailLabel.frame = NSRect(x: 20, y: 25, width: 400, height: 32)
        detailLabel.font = NSFont.systemFont(ofSize: 12)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.alignment = .center
        detailLabel.cell?.wraps = true
        contentView.addSubview(detailLabel)

        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func findBlueutil() -> String {
        let locations = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
        for p in locations {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return "blueutil"
    }

    func runCmd(_ args: [String], timeout: TimeInterval = 15, input: String? = nil) -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: findBlueutil())
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        if let input = input, let data = input.data(using: .utf8) {
            let inPipe = Pipe()
            p.standardInput = inPipe
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.closeFile()
        }

        do {
            try p.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus, out, err)
        } catch {
            return (-1, "", "\(error)")
        }
    }

    func loadCachedAddress() -> String? {
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let addr = json["last_address"] as? String else {
            return nil
        }
        return addr
    }

    func saveCachedAddress(_ address: String) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let dict: [String: Any] = [
            "last_address": address,
            "target_names": [exactTargetName, "M336/M337/M535", "M337", "M336", "M535"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: configFile)
        }
    }

    func isTargetMouse(name: String, address: String) -> Bool {
        let lower = name.lowercased()
        let exactLower = exactTargetName.lowercased()
        if lower == exactLower || lower.contains("m336/m337/m535") || lower.contains("m337") || lower.contains("m336") || lower.contains("m535") {
            return true
        }
        if let cached = loadCachedAddress(), cached.lowercased() == address.lowercased() {
            return true
        }
        return false
    }

    func refreshStatus() {
        guard !isSwitching else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let (code, stdout, _) = self.runCmd(["--paired", "--format", "json"])
            var found = false
            var connected = false
            var devAddress = ""

            if code == 0, let data = stdout.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for dev in list {
                    let name = dev["name"] as? String ?? ""
                    let addr = dev["address"] as? String ?? ""
                    if self.isTargetMouse(name: name, address: addr) {
                        found = true
                        connected = dev["connected"] as? Bool ?? false
                        devAddress = addr
                        break
                    }
                }
            }

            DispatchQueue.main.async {
                guard !self.isSwitching else { return }
                if connected {
                    self.statusLabel.stringValue = "Status: Connected"
                    self.statusLabel.textColor = .systemGreen
                    self.detailLabel.stringValue = "Mouse is connected (\(devAddress))."
                } else if found {
                    self.statusLabel.stringValue = "Status: Paired (Disconnected)"
                    self.statusLabel.textColor = .systemOrange
                    self.detailLabel.stringValue = "Mouse is paired but not connected. Ready to switch."
                } else {
                    self.statusLabel.stringValue = "Status: Ready to Switch"
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.detailLabel.stringValue = "Make sure the pairing button on the mouse is blinking."
                }
            }
        }
    }

    @objc func onSwitchClicked() {
        guard !isSwitching else { return }
        isSwitching = true
        switchButton.isEnabled = false
        progressIndicator.startAnimation(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            func updateUI(status: String, detail: String, color: NSColor = .labelColor) {
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = status
                    self.statusLabel.textColor = color
                    self.detailLabel.stringValue = detail
                }
            }

            // Step 1: Disconnect & Forget
            updateUI(status: "Step 1/4: Disconnecting & Forgetting...", detail: "Removing stale pairing profile from settings...", color: .systemOrange)

            let cachedMac = self.loadCachedAddress()
            let (_, pairedOut, _) = self.runCmd(["--paired", "--format", "json"])
            var targetMac = cachedMac

            if let data = pairedOut.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for dev in list {
                    let name = dev["name"] as? String ?? ""
                    let addr = dev["address"] as? String ?? ""
                    if self.isTargetMouse(name: name, address: addr) {
                        targetMac = addr
                        break
                    }
                }
            }

            if let mac = targetMac {
                // Disconnect first
                _ = self.runCmd(["--disconnect", mac], timeout: 5)
                Thread.sleep(forTimeInterval: 0.5)

                // Clean link keys via IOBluetooth if available
                if let dev = IOBluetoothDevice(addressString: mac) {
                    _ = dev.perform(Selector(("removeLinkKey")))
                    _ = dev.perform(Selector(("forceRemove")))
                    _ = dev.perform(Selector(("remove")))
                }

                // Unpair via blueutil
                _ = self.runCmd(["--unpair", mac], timeout: 5)
            }

            // Step 2: Wait 1 second
            updateUI(status: "Step 2/4: Resetting Bluetooth state...", detail: "Waiting a second for Bluetooth subsystem...", color: .systemOrange)
            Thread.sleep(forTimeInterval: 1.0)

            // Step 3: Connect to mouse
            updateUI(status: "Step 3/4: Connecting to mouse...", detail: "Connecting to \(self.exactTargetName)...", color: .systemBlue)

            var targetMacToConnect: String? = nil

            // 3a. If we have a cached MAC, attempt direct connection first (fast path)
            if let cached = cachedMac, !cached.isEmpty {
                updateUI(status: "Step 3/4: Attempting direct connect...", detail: "Trying known device address...", color: .systemBlue)
                if let dev = IOBluetoothDevice(addressString: cached) {
                    let ret = dev.openConnection()
                    if ret == 0 || dev.isConnected() {
                        targetMacToConnect = cached
                    }
                }
                if targetMacToConnect == nil {
                    // Try blueutil quick connect
                    _ = self.runCmd(["--connect", cached], timeout: 4)
                    let (_, connCheck, _) = self.runCmd(["--is-connected", cached], timeout: 2)
                    if connCheck == "1" {
                        targetMacToConnect = cached
                    }
                }
            }

            // 3b. If direct connect didn't find it, search for the device in pairing mode
            if targetMacToConnect == nil {
                updateUI(status: "Step 3/4: Searching for mouse...", detail: "Make sure the pairing light under the mouse is blinking rapidly.", color: .systemBlue)
                let searchStart = Date()
                let timeout: TimeInterval = 20.0

                while Date().timeIntervalSince(searchStart) < timeout {
                    let (inqCode, inqOut, _) = self.runCmd(["--inquiry", "4", "--format", "json"], timeout: 8)
                    if inqCode == 0, let data = inqOut.data(using: .utf8),
                       let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        for dev in list {
                            let name = dev["name"] as? String ?? ""
                            let addr = dev["address"] as? String ?? ""
                            if self.isTargetMouse(name: name, address: addr) {
                                targetMacToConnect = addr
                                break
                            }
                        }
                    }
                    if targetMacToConnect != nil { break }
                    let elapsed = Int(Date().timeIntervalSince(searchStart))
                    updateUI(status: "Step 3/4: Searching (\(elapsed)s)...", detail: "Make sure the blue light under the mouse is blinking rapidly.", color: .systemBlue)
                }
            }

            guard let foundMac = targetMacToConnect else {
                updateUI(status: "Error: Mouse Not Found", detail: "Could not find \(self.exactTargetName). Press the pairing button and retry.", color: .systemRed)
                DispatchQueue.main.async {
                    self.isSwitching = false
                    self.switchButton.isEnabled = true
                    self.progressIndicator.stopAnimation(nil)
                }
                return
            }

            // Save found MAC
            self.saveCachedAddress(foundMac)

            // Step 4: Pair and Connect
            updateUI(status: "Step 4/4: Pairing & Connecting...", detail: "Found mouse at \(foundMac). Connecting...", color: .systemBlue)

            // Pair without PIN first
            var (pairCode, _, _) = self.runCmd(["--pair", foundMac], timeout: 15, input: "yes\n")
            if pairCode != 0 {
                // Retry with PIN 0000 fallback
                let (retryCode, _, _) = self.runCmd(["--pair", foundMac, "0000"], timeout: 15, input: "yes\n")
                pairCode = retryCode
            }

            // Connect
            Thread.sleep(forTimeInterval: 0.8)
            var connected = false
            for _ in 1...4 {
                _ = self.runCmd(["--connect", foundMac], timeout: 8)
                Thread.sleep(forTimeInterval: 1.0)
                let (_, connOut, _) = self.runCmd(["--is-connected", foundMac], timeout: 4)
                if connOut == "1" {
                    connected = true
                    break
                }
            }

            DispatchQueue.main.async {
                self.isSwitching = false
                self.switchButton.isEnabled = true
                self.progressIndicator.stopAnimation(nil)

                if connected {
                    updateUI(status: "Connected Successfully!", detail: "Mouse is ready to use.", color: .systemGreen)
                } else {
                    updateUI(status: "Pairing Completed", detail: "Paired! Click any mouse button to wake it up.", color: .systemOrange)
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowController = MainWindowController()
        windowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()


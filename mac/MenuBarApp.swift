import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var actionMenuItem: NSMenuItem!
    var isSwitching = false
    var timer: Timer?

    let exactDeviceName = "Bluetooth Mouse M336/M337/M535"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🖱️"
            button.toolTip = exactDeviceName + " Quick Switcher"
        }
        
        setupMenu()
        checkStatus()
        
        // Periodically refresh status every 4 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        actionMenuItem = NSMenuItem(title: "Switch to Mac (Pair & Connect)", action: #selector(performSwitch), keyEquivalent: "s")
        menu.addItem(actionMenuItem)
        
        let unpairItem = NSMenuItem(title: "Forget / Unpair " + exactDeviceName, action: #selector(performUnpair), keyEquivalent: "u")
        menu.addItem(unpairItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func findBlueutil() -> String? {
        let paths = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
        for p in paths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    func isTargetMouse(name: String) -> Bool {
        let lower = name.lowercased()
        let exactLower = exactDeviceName.lowercased()
        return lower == exactLower || lower.contains(exactLower) || lower.contains("m336/m337/m535") || lower.contains("m337") || lower.contains("m336") || lower.contains("m535")
    }

    func checkStatus() {
        guard !isSwitching else { return }
        guard let blueutil = findBlueutil() else {
            statusMenuItem.title = "Status: blueutil not found"
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: blueutil)
            task.arguments = ["--paired", "--format", "json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                var statusText = "Status: Disconnected / Not Paired"
                var icon = "🖱️"
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for dev in json {
                        let name = dev["name"] as? String ?? ""
                        if self.isTargetMouse(name: name) {
                            let connected = dev["connected"] as? Bool ?? false
                            if connected {
                                statusText = "Status: Connected"
                                icon = "🖱️ [ON]"
                            } else {
                                statusText = "Status: Paired (Disconnected)"
                                icon = "🖱️ [OFF]"
                            }
                            break
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.statusMenuItem.title = statusText
                    self.statusItem.button?.title = icon
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMenuItem.title = "Status: Bluetooth Error"
                }
            }
        }
    }
    
    func findScriptPath() -> String? {
        let bundleResources = Bundle.main.resourcePath ?? ""
        let bundledScript = (bundleResources as NSString).appendingPathComponent("switch_mouse.py")
        if FileManager.default.fileExists(atPath: bundledScript) {
            return bundledScript
        }
        
        let appPaths = [
            "/Applications/Switch Mouse to Mac.app/Contents/Resources/switch_mouse.py",
            "/Applications/Switch Mouse Menu Bar.app/Contents/Resources/switch_mouse.py",
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/bt-mouse-switch")
        ]
        for p in appPaths {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        
        let currentDir = FileManager.default.currentDirectoryPath
        let devPaths = [
            (currentDir as NSString).appendingPathComponent("mac/switch_mouse.py"),
            (currentDir as NSString).appendingPathComponent("switch_mouse.py")
        ]
        for p in devPaths {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        
        return nil
    }

    @objc func performSwitch() {
        guard !isSwitching else { return }
        isSwitching = true
        statusMenuItem.title = "Status: Searching for mouse..."
        statusItem.button?.title = "🖱️ [Searching...]"
        actionMenuItem.isEnabled = false
        
        guard let scriptPath = findScriptPath() else {
            statusMenuItem.title = "Status: switch_mouse.py not found"
            isSwitching = false
            actionMenuItem.isEnabled = true
            statusItem.button?.title = "🖱️ [OFF]"
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptPath]
            
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
            process.environment = env
            
            var outText = ""
            var errText = ""
            do {
                try process.run()
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                outText = String(data: outData, encoding: .utf8) ?? ""
                errText = String(data: errData, encoding: .utf8) ?? ""
            } catch {
                errText = "\(error)"
            }
            
            let exitCode = process.terminationStatus
            
            DispatchQueue.main.async {
                self?.isSwitching = false
                self?.actionMenuItem.isEnabled = true
                self?.checkStatus()
                
                if exitCode != 0 {
                    let alert = NSAlert()
                    alert.messageText = "Mouse Switch Failed"
                    alert.informativeText = errText.isEmpty ? (outText.isEmpty ? "Could not find Bluetooth Mouse M336/M337/M535.\n\nMake sure the pairing button underneath the mouse is blinking rapidly and try again." : outText) : errText
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func performUnpair() {
        guard let blueutil = findBlueutil() else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: blueutil)
            task.arguments = ["--paired", "--format", "json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for dev in json {
                        let name = dev["name"] as? String ?? ""
                        if self.isTargetMouse(name: name), let addr = dev["address"] as? String {
                            let unpairTask = Process()
                            unpairTask.executableURL = URL(fileURLWithPath: blueutil)
                            unpairTask.arguments = ["--unpair", addr]
                            try? unpairTask.run()
                            unpairTask.waitUntilExit()
                            break
                        }
                    }
                }
            } catch {}
            
            DispatchQueue.main.async {
                self.checkStatus()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var actionMenuItem: NSMenuItem!
    var isSwitching = false
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🖱️ M337"
            button.toolTip = "Logitech M337 Quick Switcher"
        }
        
        setupMenu()
        checkStatus()
        
        // Periodically refresh status every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        actionMenuItem = NSMenuItem(title: "⚡️ Switch to Mac (Pair & Connect)", action: #selector(performSwitch), keyEquivalent: "s")
        menu.addItem(actionMenuItem)
        
        let unpairItem = NSMenuItem(title: "Forget / Unpair M337", action: #selector(performUnpair), keyEquivalent: "u")
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

    func checkStatus() {
        guard !isSwitching else { return }
        guard let blueutil = findBlueutil() else {
            statusMenuItem.title = "Status: blueutil not found"
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
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
                var icon = "🖱️ M337"
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for dev in json {
                        let name = (dev["name"] as? String ?? "").lowercased()
                        if name.contains("m337") {
                            let connected = dev["connected"] as? Bool ?? false
                            if connected {
                                statusText = "Status: Connected 🟢"
                                icon = "🖱️ [ON]"
                            } else {
                                statusText = "Status: Paired (Disconnected) ⚪️"
                                icon = "🖱️ [OFF]"
                            }
                            break
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self?.statusMenuItem.title = statusText
                    self?.statusItem.button?.title = icon
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusMenuItem.title = "Status: Bluetooth Error"
                }
            }
        }
    }
    
    @objc func performSwitch() {
        guard !isSwitching else { return }
        isSwitching = true
        statusMenuItem.title = "Status: Switching... ⏳"
        statusItem.button?.title = "🖱️ ⏳"
        actionMenuItem.isEnabled = false
        
        // Find python script
        let scriptPath: String
        let bundleResources = Bundle.main.resourcePath ?? ""
        let bundledScript = (bundleResources as NSString).appendingPathComponent("switch_mouse.py")
        
        if FileManager.default.fileExists(atPath: bundledScript) {
            scriptPath = bundledScript
        } else {
            // Development path fallback
            let currentDir = FileManager.default.currentDirectoryPath
            let devScript = (currentDir as NSString).appendingPathComponent("switch_mouse.py")
            if FileManager.default.fileExists(atPath: devScript) {
                scriptPath = devScript
            } else {
                scriptPath = (currentDir as NSString).appendingPathComponent("mac/switch_mouse.py")
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptPath]
            
            // Set PATH environment
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
            process.environment = env
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to run script: \(error)")
            }
            
            DispatchQueue.main.async {
                self?.isSwitching = false
                self?.actionMenuItem.isEnabled = true
                self?.checkStatus()
            }
        }
    }
    
    @objc func performUnpair() {
        guard let blueutil = findBlueutil() else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                        let name = (dev["name"] as? String ?? "").lowercased()
                        if name.contains("m337"), let addr = dev["address"] as? String {
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
                self?.checkStatus()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

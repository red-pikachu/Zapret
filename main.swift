import Cocoa
import ServiceManagement
import UserNotifications

struct Strategy: Codable, Equatable {
    let id: String
    let name: String
    let args: String
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var isRunning = false
    var statusMenuItem: NSMenuItem!
    var toggleMenuItem: NSMenuItem!
    var strategyMenu: NSMenu!
    var strategies: [Strategy] = []
    
    // Default strategies if no file exists
    let defaultStrategies: [Strategy] = [
        Strategy(id: "fake_split", name: "Fake + Split (Default)", args: "--lua-desync=desync:desync=fake,split2;fake_type=tls_clienthello"),
        Strategy(id: "disorder", name: "Disorder", args: "--lua-desync=desync:desync=disorder2;fake_type=tls_clienthello"),
        Strategy(id: "syndata", name: "Syndata", args: "--lua-desync=desync:desync=syndata"),
        Strategy(id: "flowseal_general", name: "Flowseal General (v1.9.7)", args: "--lua-desync=desync:desync=multisplit;split_seqovl=568;split_pos=1;split_seqovl_pattern=@quic_initial_www_google_com.bin"),
        Strategy(id: "flowseal_discord", name: "Flowseal Discord", args: "--lua-desync=desync:desync=fake;repeats=6;fake_type=tls_clienthello"),
        Strategy(id: "flowseal_youtube", name: "Flowseal YouTube (Multisplit)", args: "--lua-desync=desync:desync=multisplit;split_seqovl=681;split_pos=1")
    ]
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Request Notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // Handle permission if needed
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(scale: .large)
            button.image = NSImage(systemSymbolName: "shield.slash", accessibilityDescription: "Zapret Stopped")?.withSymbolConfiguration(config)
        }
        
        loadStrategies()
        setupMenu()
        updateUI()
    }
    
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // Allow notifications to show even if app is active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func getStrategiesFileURL() -> URL {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let configDir = homeDir.appendingPathComponent(".zapret2")
        return configDir.appendingPathComponent("strategies.json")
    }
    
    func loadStrategies() {
        let fileURL = getStrategiesFileURL()
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Strategy].self, from: data) {
            self.strategies = decoded
        } else {
            self.strategies = defaultStrategies
            let configDir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: nil)
            if let encoded = try? JSONEncoder().encode(self.strategies) {
                try? encoded.write(to: fileURL)
            }
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        toggleMenuItem = NSMenuItem(title: "Start Zapret", action: #selector(toggleZapret), keyEquivalent: "s")
        menu.addItem(toggleMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // --- Strategy Submenu ---
        let strategyMenuItem = NSMenuItem(title: "Strategy", action: nil, keyEquivalent: "")
        strategyMenu = NSMenu()
        rebuildStrategyMenu()
        strategyMenuItem.submenu = strategyMenu
        menu.addItem(strategyMenuItem)
        
        // --- Settings Submenu ---
        let settingsMenuItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        
        settingsMenu.addItem(NSMenuItem(title: "Open Config Folder", action: #selector(openConfigFolder), keyEquivalent: ""))
        settingsMenu.addItem(NSMenuItem(title: "Add Custom Source URL...", action: #selector(promptForCustomURL), keyEquivalent: ""))
        
        settingsMenu.addItem(NSMenuItem.separator())
        
        let launchMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchMenuItem.state = .off
        settingsMenu.addItem(launchMenuItem)
        
        // Sudoers Setup
        settingsMenu.addItem(NSMenuItem.separator())
        settingsMenu.addItem(NSMenuItem(title: "Grant Passwordless Access...", action: #selector(setupSudoers), keyEquivalent: ""))
        
        settingsMenuItem.submenu = settingsMenu
        menu.addItem(settingsMenuItem)
        
        // --- Open Logs ---
        menu.addItem(NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    func rebuildStrategyMenu() {
        strategyMenu.removeAllItems()
        let savedStrategyId = UserDefaults.standard.string(forKey: "ZapretStrategyId") ?? "fake_split"
        
        for strategy in strategies {
            let item = NSMenuItem(title: strategy.name, action: #selector(selectStrategy(_:)), keyEquivalent: "")
            item.representedObject = strategy.id
            if strategy.id == savedStrategyId {
                item.state = .on
            }
            strategyMenu.addItem(item)
        }
    }
    
    @objc func setupSudoers() {
        guard let bundlePath = Bundle.main.resourcePath else { return }
        let wrapperPath = "\(bundlePath)/wrapper.sh"
        let userName = NSUserName()
        
        let sudoersContent = "\(userName) ALL=(ALL) NOPASSWD: \(wrapperPath)"
        
        let script = """
        do shell script "echo '\(sudoersContent)' > /private/etc/sudoers.d/zapret2_mac && chmod 440 /private/etc/sudoers.d/zapret2_mac" with administrator privileges
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if error != nil {
                print("Failed to setup sudoers: \(String(describing: error))")
                sendNotification(title: "Setup Failed", body: "Could not grant passwordless access.")
            } else {
                sendNotification(title: "Setup Successful", body: "Zapret can now start without asking for a password.")
            }
        }
    }
    
    @objc func promptForCustomURL() {
        // ... (existing prompt logic)
        let alert = NSAlert()
        alert.messageText = "Update Strategies from JSON"
        alert.informativeText = "Enter a direct URL to a raw strategies.json file:"
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        inputTextField.placeholderString = "https://raw.githubusercontent.com/.../strategies.json"
        
        if let savedURL = UserDefaults.standard.string(forKey: "ZapretCustomSourceURL") {
            inputTextField.stringValue = savedURL
        } else {
            inputTextField.stringValue = "https://raw.githubusercontent.com/red-pikachu/Zapret2Mac/main/strategies.json"
        }
        
        alert.accessoryView = inputTextField
        alert.addButton(withTitle: "Download & Update")
        alert.addButton(withTitle: "Cancel")
        
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        
        let customURLString = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: customURLString) else {
            sendNotification(title: "Update Failed", body: "Invalid URL provided.")
            return
        }
        
        UserDefaults.standard.set(customURLString, forKey: "ZapretCustomSourceURL")
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                self?.sendNotification(title: "Download Failed", body: "Could not reach the provided URL.")
                return
            }
            
            if let decoded = try? JSONDecoder().decode([Strategy].self, from: data) {
                DispatchQueue.main.async {
                    self?.strategies = decoded
                    if let fileURL = self?.getStrategiesFileURL() {
                        try? data.write(to: fileURL)
                    }
                    self?.rebuildStrategyMenu()
                    self?.sendNotification(title: "Update Successful", body: "Strategies updated from custom source!")
                }
            } else {
                 self?.sendNotification(title: "Parse Error", body: "The file is not a valid strategies.json array.")
            }
        }
        task.resume()
    }
    
    @objc func selectStrategy(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: "ZapretStrategyId")
        
        for item in strategyMenu.items {
            item.state = (item == sender) ? .on : .off
        }
        
        if isRunning {
            toggleZapret() // stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.toggleZapret() // start again
            }
        }
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        // Fallback for older compiler toolchain, or unimplemented for now
        print("Launch at login requires newer SDK")
    }
    
    @objc func openConfigFolder() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".zapret2")
        
        if !fileManager.fileExists(atPath: configURL.path) {
            do {
                try fileManager.createDirectory(at: configURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating config dir: \(error)")
            }
        }
        NSWorkspace.shared.open(configURL)
    }
    
    @objc func openLogs() {
        let logURL = URL(fileURLWithPath: "/tmp/zapret2.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(logURL)
    }
    
    func runCommandViaProcess(scriptPath: String, arguments: [String]) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments = [scriptPath] + arguments
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    @objc func toggleZapret() {
        guard let bundlePath = Bundle.main.resourcePath else { return }
        let scriptPath = "\(bundlePath)/wrapper.sh"
        let command = isRunning ? "stop" : "start"
        
        var args: [String] = [command]
        if command == "start" {
            let savedStrategyId = UserDefaults.standard.string(forKey: "ZapretStrategyId") ?? "fake_split"
            let strategy = strategies.first(where: { $0.id == savedStrategyId }) ?? defaultStrategies[0]
            args.append(strategy.args)
        }
        
        // First try to run silently using Process + sudo (relies on sudoers setup)
        if runCommandViaProcess(scriptPath: scriptPath, arguments: args) {
            isRunning.toggle()
            updateUI()
            return
        }
        
        // If it fails (probably needs password), fallback to AppleScript
        let argsString = args.dropFirst().joined(separator: " ")
        let appleScriptSource = """
        do shell script "\(scriptPath) \(command) \(argsString)" with administrator privileges
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScriptSource) {
            let output = scriptObject.executeAndReturnError(&error)
            if error != nil {
                print("Error: \(String(describing: error))")
                return
            } else {
                print("Success: \(output.stringValue ?? "no output")")
                isRunning.toggle()
                updateUI()
            }
        }
    }
    
    func updateUI() {
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(scale: .large)
            if isRunning {
                statusMenuItem.title = "Status: Running"
                toggleMenuItem.title = "Stop Zapret"
                button.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Zapret Running")?.withSymbolConfiguration(config)
            } else {
                statusMenuItem.title = "Status: Stopped"
                toggleMenuItem.title = "Start Zapret"
                button.image = NSImage(systemSymbolName: "shield.slash", accessibilityDescription: "Zapret Stopped")?.withSymbolConfiguration(config)
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        if isRunning {
            if let bundlePath = Bundle.main.resourcePath {
                let scriptPath = "\(bundlePath)/wrapper.sh"
                // Try silent process first
                if !runCommandViaProcess(scriptPath: scriptPath, arguments: ["stop"]) {
                    // Fallback to AppleScript
                    let appleScriptSource = """
                    do shell script "\(scriptPath) stop" with administrator privileges
                    """
                    if let scriptObject = NSAppleScript(source: appleScriptSource) {
                        scriptObject.executeAndReturnError(nil)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

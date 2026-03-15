import Cocoa
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

    let defaultStrategies: [Strategy] = [
        Strategy(id: "disorder_midsld", name: "Disorder midsld (рекомендуется)", args: "--filter-tcp=80 --methodeol --new --filter-tcp=443 --split-pos=1,midsld --disorder"),
        Strategy(id: "disorder_oob",    name: "Disorder + OOB",                  args: "--filter-tcp=443 --split-pos=1,midsld --disorder --oob"),
        Strategy(id: "tlsrec_sniext",   name: "TLS Record (sniext)",             args: "--filter-tcp=443 --tlsrec=sniext+1"),
        Strategy(id: "split_midsld",    name: "Split midsld",                    args: "--filter-tcp=443 --split-pos=midsld"),
        Strategy(id: "disorder_pos2",   name: "Disorder pos=2",                  args: "--filter-tcp=443 --split-pos=2 --disorder"),
        Strategy(id: "methodeol_only",  name: "HTTP MethodEOL (только port 80)", args: "--filter-tcp=80 --methodeol")
    ]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: — Strategies

    func getStrategiesFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zapret2")
            .appendingPathComponent("strategies.json")
    }

    func loadStrategies() {
        let fileURL = getStrategiesFileURL()
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Strategy].self, from: data) {
            strategies = decoded
        } else {
            strategies = defaultStrategies
            let configDir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(strategies) {
                try? encoded.write(to: fileURL)
            }
        }
    }

    // MARK: — Menu

    func setupMenu() {
        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Статус: Остановлен", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "Запустить Zapret", action: #selector(toggleZapret), keyEquivalent: "s")
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        // Strategy submenu
        let strategyMenuItem = NSMenuItem(title: "Стратегия", action: nil, keyEquivalent: "")
        strategyMenu = NSMenu()
        rebuildStrategyMenu()
        strategyMenuItem.submenu = strategyMenu
        menu.addItem(strategyMenuItem)

        // Settings submenu
        let settingsMenuItem = NSMenuItem(title: "Настройки", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(NSMenuItem(title: "Открыть папку конфигов",          action: #selector(openConfigFolder),          keyEquivalent: ""))
        settingsMenu.addItem(NSMenuItem(title: "Обновить стратегии",             action: #selector(fetchStrategies),           keyEquivalent: ""))
        settingsMenu.addItem(NSMenuItem(title: "Изменить источник стратегий...", action: #selector(updateStrategiesFromURL),   keyEquivalent: ""))
        settingsMenu.addItem(NSMenuItem(title: "Сбросить стратегии на дефолт",  action: #selector(resetStrategies),           keyEquivalent: ""))
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(NSMenuItem(title: "Разрешить запуск без пароля...", action: #selector(setupSudoers),            keyEquivalent: ""))
        settingsMenuItem.submenu = settingsMenu
        menu.addItem(settingsMenuItem)

        menu.addItem(NSMenuItem(title: "Открыть лог", action: #selector(openLogs), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func rebuildStrategyMenu() {
        strategyMenu.removeAllItems()
        let savedId = UserDefaults.standard.string(forKey: "ZapretStrategyId") ?? "disorder_midsld"
        for strategy in strategies {
            let item = NSMenuItem(title: strategy.name, action: #selector(selectStrategy(_:)), keyEquivalent: "")
            item.representedObject = strategy.id
            item.state = (strategy.id == savedId) ? .on : .off
            strategyMenu.addItem(item)
        }
    }

    // MARK: — Actions

    @objc func selectStrategy(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: "ZapretStrategyId")
        strategyMenu.items.forEach { $0.state = ($0 == sender) ? .on : .off }

        if isRunning {
            toggleZapret()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.toggleZapret() }
        }
    }

    private static let defaultStrategiesURL = "https://raw.githubusercontent.com/red-pikachu/Zapret2Mac/main/strategies.json"

    var strategiesSourceURL: String {
        UserDefaults.standard.string(forKey: "ZapretCustomSourceURL") ?? Self.defaultStrategiesURL
    }

    @objc func fetchStrategies() {
        guard let url = URL(string: strategiesSourceURL) else {
            sendNotification(title: "Ошибка", body: "Некорректный URL источника.")
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil else {
                self?.sendNotification(title: "Ошибка загрузки", body: "Не удалось подключиться к источнику.")
                return
            }
            guard let decoded = try? JSONDecoder().decode([Strategy].self, from: data) else {
                self?.sendNotification(title: "Ошибка формата", body: "Файл не является корректным strategies.json.")
                return
            }
            DispatchQueue.main.async {
                self?.strategies = decoded
                try? data.write(to: self!.getStrategiesFileURL())
                self?.rebuildStrategyMenu()
                self?.sendNotification(title: "Стратегии обновлены", body: "Загружено \(decoded.count) стратегий.")
            }
        }.resume()
    }

    @objc func updateStrategiesFromURL() {
        let alert = NSAlert()
        alert.messageText = "Источник стратегий"
        alert.informativeText = "Прямая ссылка на файл strategies.json в формате tpws:"

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.placeholderString = Self.defaultStrategiesURL
        field.stringValue = strategiesSourceURL
        alert.accessoryView = field
        alert.addButton(withTitle: "Сохранить и скачать")
        alert.addButton(withTitle: "Отмена")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let urlString = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, URL(string: urlString) != nil else {
            sendNotification(title: "Ошибка", body: "Некорректный URL.")
            return
        }
        UserDefaults.standard.set(urlString, forKey: "ZapretCustomSourceURL")
        fetchStrategies()
    }

    @objc func resetStrategies() {
        strategies = defaultStrategies
        if let encoded = try? JSONEncoder().encode(strategies) {
            try? encoded.write(to: getStrategiesFileURL())
        }
        rebuildStrategyMenu()
        sendNotification(title: "Сброс выполнен", body: "Стратегии восстановлены по умолчанию.")
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
                sendNotification(title: "Ошибка настройки", body: "Не удалось разрешить запуск без пароля.")
            } else {
                sendNotification(title: "Настройка выполнена", body: "Запret будет запускаться без запроса пароля.")
            }
        }
    }

    @objc func openConfigFolder() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zapret2")
        try? FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(configURL)
    }

    @objc func openLogs() {
        let logURL = URL(fileURLWithPath: "/tmp/zapret2.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(logURL)
    }

    // MARK: — Zapret control

    func runCommand(scriptPath: String, arguments: [String]) -> Bool {
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

        var args = [command]
        if command == "start" {
            let savedId = UserDefaults.standard.string(forKey: "ZapretStrategyId") ?? "disorder_midsld"
            let strategy = strategies.first(where: { $0.id == savedId }) ?? defaultStrategies[0]
            args.append(strategy.args)
        }

        // Тихий запуск через sudo (sudoers настроен)
        if runCommand(scriptPath: scriptPath, arguments: args) {
            isRunning.toggle()
            updateUI()
            return
        }

        // Фоллбек: AppleScript с запросом пароля
        let strategyArgs = args.dropFirst().joined(separator: " ")
        let appleScript = """
        do shell script "\(scriptPath) \(command) \(strategyArgs)" with administrator privileges
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            script.executeAndReturnError(&error)
            if error == nil {
                isRunning.toggle()
                updateUI()
            } else {
                sendNotification(title: "Ошибка", body: "Не удалось \(command == "start" ? "запустить" : "остановить") Zapret.")
            }
        }
    }

    func updateUI() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(scale: .large)
        if isRunning {
            statusMenuItem.title = "Статус: Работает"
            toggleMenuItem.title = "Остановить Zapret"
            button.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Zapret Running")?.withSymbolConfiguration(config)
        } else {
            statusMenuItem.title = "Статус: Остановлен"
            toggleMenuItem.title = "Запустить Zapret"
            button.image = NSImage(systemSymbolName: "shield.slash", accessibilityDescription: "Zapret Stopped")?.withSymbolConfiguration(config)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        guard isRunning, let bundlePath = Bundle.main.resourcePath else { return }
        let scriptPath = "\(bundlePath)/wrapper.sh"
        if !runCommand(scriptPath: scriptPath, arguments: ["stop"]) {
            if let script = NSAppleScript(source: "do shell script \"\(scriptPath) stop\" with administrator privileges") {
                script.executeAndReturnError(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

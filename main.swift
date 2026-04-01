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
    var autoCheckMenuItem: NSMenuItem!
    var socks5MenuItem: NSMenuItem!
    var socks5Process: Process?
    var strategies: [Strategy] = []

    private static let socks5Port = 9988

    let defaultStrategies: [Strategy] = [
        Strategy(id: "disorder_midsld",     name: "Disorder midsld (рекомендуется)", args: "--filter-tcp=80 --methodeol --new --filter-tcp=443 --split-pos=1,midsld --disorder"),
        Strategy(id: "disorder_oob_midsld", name: "Disorder + OOB midsld",           args: "--filter-tcp=443 --split-pos=1,midsld --disorder --oob"),
        Strategy(id: "disorder_oob_tlsrec", name: "Disorder + OOB + TLSRec",         args: "--filter-tcp=443 --split-pos=1,midsld --disorder --oob --tlsrec=sniext+1"),
        Strategy(id: "universal_heavy",     name: "Universal (Heavy)",               args: "--filter-tcp=443 --split-pos=1,midsld --disorder --oob --tlsrec=sniext+1 --new --filter-tcp=80 --methodeol"),
        Strategy(id: "tlsrec_sniext",       name: "TLS Record (sniext)",             args: "--filter-tcp=443 --tlsrec=sniext+1"),
        Strategy(id: "tlsrec_midsld",       name: "TLS Record (midsld)",             args: "--filter-tcp=443 --tlsrec=midsld"),
        Strategy(id: "split_midsld",        name: "Split midsld",                    args: "--filter-tcp=443 --split-pos=midsld"),
        Strategy(id: "split_sniext",        name: "Split sniext+1",                  args: "--filter-tcp=443 --split-pos=sniext+1"),
        Strategy(id: "split_2_sniext",      name: "Split pos=2,sniext+1",            args: "--filter-tcp=443 --split-pos=2,sniext+1"),
        Strategy(id: "disorder_pos2",       name: "Disorder pos=2",                  args: "--filter-tcp=443 --split-pos=2 --disorder"),
        Strategy(id: "disorder_pos2_oob",   name: "Disorder pos=2 + OOB",            args: "--filter-tcp=443 --split-pos=2 --disorder --oob"),
        Strategy(id: "disorder_sniext",     name: "Disorder sniext+1",               args: "--filter-tcp=443 --split-pos=sniext+1 --disorder"),
        Strategy(id: "oob_midsld",          name: "OOB midsld",                      args: "--filter-tcp=443 --split-pos=midsld --oob"),
        Strategy(id: "syndata_split",       name: "Syndata + Split",                 args: "--filter-tcp=443 --syndata --split-pos=1,midsld"),
        Strategy(id: "methodeol_only",      name: "HTTP MethodEOL only",             args: "--filter-tcp=80 --methodeol")
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
        autoUpdateStrategies()
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
        autoCheckMenuItem = NSMenuItem(title: "Подобрать лучшую стратегию...", action: #selector(autoSelectStrategy), keyEquivalent: "")
        strategyMenu.addItem(autoCheckMenuItem)
        strategyMenu.addItem(.separator())
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

        socks5MenuItem = NSMenuItem(title: "SOCKS5 для Telegram: выключен", action: #selector(toggleSocks5), keyEquivalent: "")
        menu.addItem(socks5MenuItem)
        menu.addItem(NSMenuItem(title: "Открыть лог", action: #selector(openLogs), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func rebuildStrategyMenu() {
        // Удаляем только стратегии, сохраняя первые 2 пункта (кнопка автовыбора + разделитель)
        while strategyMenu.numberOfItems > 2 {
            strategyMenu.removeItem(at: 2)
        }
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

    @objc func autoUpdateStrategies() {
        guard let url = URL(string: strategiesSourceURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            guard let decoded = try? JSONDecoder().decode([Strategy].self, from: data) else { return }
            
            DispatchQueue.main.async {
                if self.strategies != decoded {
                    self.strategies = decoded
                    try? data.write(to: self.getStrategiesFileURL())
                    self.rebuildStrategyMenu()
                    self.sendNotification(title: "Стратегии обновлены", body: "Список стратегий автоматически обновлен из сети (\(decoded.count) шт.)")
                }
            }
        }.resume()
    }

    // MARK: — Auto Strategy Detection

    private static let testURLs = [
        "https://www.youtube.com",
        "https://discord.com",
        "https://www.instagram.com"
    ]

    @objc func autoSelectStrategy() {
        guard let tpwsPath = Bundle.main.path(forResource: "tpws", ofType: nil) else {
            sendNotification(title: "Ошибка", body: "tpws не найден в бандле.")
            return
        }

        autoCheckMenuItem.title = "Тестирование..."
        autoCheckMenuItem.action = nil
        sendNotification(title: "Поиск стратегии", body: "Тестируем \(strategies.count) стратегий, это займёт ~\(strategies.count * 8) сек.")

        let strategiesToTest = strategies

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var results: [(Strategy, Bool, Double)] = []

            for (i, strategy) in strategiesToTest.enumerated() {
                let port = 19800 + i
                let process = self.startTpwsSOCKS(path: tpwsPath, port: port, args: strategy.args)
                Thread.sleep(forTimeInterval: 0.5)

                let start = Date()
                let ok = Self.testURLs.contains { self.testSOCKS5(port: port, urlString: $0) }
                let elapsed = Date().timeIntervalSince(start)

                process.terminate()
                process.waitUntilExit()

                results.append((strategy, ok, elapsed))
            }

            DispatchQueue.main.async {
                self.autoCheckMenuItem.title = "Подобрать лучшую стратегию..."
                self.autoCheckMenuItem.action = #selector(self.autoSelectStrategy)

                let working = results.filter { $0.1 }.sorted { $0.2 < $1.2 }

                if let best = working.first {
                    UserDefaults.standard.set(best.0.id, forKey: "ZapretStrategyId")
                    self.rebuildStrategyMenu()
                }

                self.showStrategyResults(results: results, best: working.first?.0)
            }
        }
    }

    private func showStrategyResults(results: [(Strategy, Bool, Double)], best: Strategy?) {
        let alert = NSAlert()

        if let best {
            alert.messageText = "Стратегия выбрана: \(best.name)"
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Ни одна стратегия не сработала"
            alert.alertStyle = .warning
        }

        let lines = results.map { (strategy, ok, elapsed) -> String in
            let icon   = ok ? "✅" : "❌"
            let time   = ok ? String(format: " (%.1f сек)", elapsed) : ""
            let marker = strategy.id == best?.id ? " ← выбрана" : ""
            return "\(icon) \(strategy.name)\(time)\(marker)"
        }

        let working = results.filter { $0.1 }.count
        let summary = best != nil
            ? "Работают \(working) из \(results.count). Активирована лучшая по скорости."
            : "Блокировок не обнаружено или интернет недоступен. Оставлена прежняя стратегия."

        alert.informativeText = lines.joined(separator: "\n") + "\n\n" + summary
        alert.addButton(withTitle: best != nil ? "Применить и закрыть" : "Закрыть")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func startTpwsSOCKS(path: String, port: Int, args: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        var arguments = ["--socks", "--port=\(port)", "--bind-addr=127.0.0.1"]
        arguments += args.components(separatedBy: " ").filter { !$0.isEmpty }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        return process
    }

    private func testSOCKS5(port: Int, urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable: 1,
            kCFNetworkProxiesSOCKSProxy: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort: port
        ]
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10

        let session = URLSession(configuration: config)
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                success = true
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 10)
        session.invalidateAndCancel()
        return success
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

    // MARK: — SOCKS5 proxy

    @objc func toggleSocks5() {
        if socks5Process != nil {
            stopSocks5()
        } else {
            startSocks5()
        }
    }

    private func startSocks5() {
        guard let tpwsPath = Bundle.main.path(forResource: "tpws", ofType: nil) else { return }

        let savedId = UserDefaults.standard.string(forKey: "ZapretStrategyId") ?? "disorder_midsld"
        let strategy = strategies.first(where: { $0.id == savedId }) ?? defaultStrategies[0]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tpwsPath)
        var args = ["--socks", "--port=\(Self.socks5Port)", "--bind-addr=127.0.0.1"]
        // midsld — TLS-специфичный маркер, не работает в SOCKS5 режиме, заменяем на фиксированную позицию
        let socks5Args = strategy.args
            .replacingOccurrences(of: "split-pos=1,midsld", with: "split-pos=2")
            .replacingOccurrences(of: "split-pos=midsld",   with: "split-pos=2")
        args += socks5Args.components(separatedBy: " ").filter { !$0.isEmpty }
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.socks5DidStop() }
        }

        do {
            try process.run()
            socks5Process = process
            socks5MenuItem.title = "SOCKS5 для Telegram: 127.0.0.1:\(Self.socks5Port) ●"
            socks5MenuItem.state = .on
            showSocks5Instructions()
        } catch {
            sendNotification(title: "Ошибка SOCKS5", body: "Не удалось запустить прокси.")
        }
    }

    private func stopSocks5() {
        guard let process = socks5Process else { return }
        socks5Process = nil
        socks5MenuItem.title = "SOCKS5 для Telegram: останавливается..."
        socks5MenuItem.action = nil
        process.terminate()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            process.waitUntilExit()
            DispatchQueue.main.async {
                self?.socks5DidStop()
            }
        }
    }

    private func socks5DidStop() {
        socks5Process = nil
        socks5MenuItem.title = "SOCKS5 для Telegram: выключен"
        socks5MenuItem.state = .off
        socks5MenuItem.action = #selector(toggleSocks5)
    }

    private func showSocks5Instructions() {
        let alert = NSAlert()
        alert.messageText = "SOCKS5 прокси запущен"
        alert.informativeText = """
            Настройки прокси для Telegram:

            Тип:    SOCKS5
            Сервер: 127.0.0.1
            Порт:   \(Self.socks5Port)

            Telegram → Settings → Privacy and Security → Proxy → Add Proxy → SOCKS5

            Прокси работает на текущей стратегии.
            Остановить: пункт "SOCKS5 для Telegram" в меню.
            """
        alert.addButton(withTitle: "Понятно")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: — Zapret control

    func runCommand(scriptPath: String, arguments: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/bin/sudo"
            task.arguments = [scriptPath] + arguments
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                DispatchQueue.main.async { completion(success) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
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

        // Блокируем кнопку на время выполнения
        toggleMenuItem.action = nil
        toggleMenuItem.title = isRunning ? "Останавливается..." : "Запускается..."

        // Тихий запуск через sudo (sudoers настроен)
        runCommand(scriptPath: scriptPath, arguments: args) { [weak self] success in
            guard let self else { return }
            if success {
                self.isRunning.toggle()
                self.updateUI()
                self.toggleMenuItem.action = #selector(self.toggleZapret)
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
                    self.isRunning.toggle()
                    self.updateUI()
                } else {
                    self.sendNotification(title: "Ошибка", body: "Не удалось \(command == "start" ? "запустить" : "остановить") Zapret.")
                }
            }
            self.toggleMenuItem.action = #selector(self.toggleZapret)
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
        socks5Process?.terminate()
        socks5Process?.waitUntilExit()

        guard isRunning, let bundlePath = Bundle.main.resourcePath else { return }
        let scriptPath = "\(bundlePath)/wrapper.sh"
        // При завершении приложения синхронный вызов допустим
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments = [scriptPath, "stop"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        if let _ = try? task.run() {
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                if let script = NSAppleScript(source: "do shell script \"\(scriptPath) stop\" with administrator privileges") {
                    script.executeAndReturnError(nil)
                }
            }
        } else {
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

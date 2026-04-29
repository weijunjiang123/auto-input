import AppKit
import AutoInputCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let inputSourceManager = InputSourceManager()

    private var config = AutoInputConfig.empty
    private var inputSources: [InputSourceDescriptor] = []
    private var statusItem: NSStatusItem!
    private var monitor: AppMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var statusMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadConfig()
        inputSources = inputSourceManager.enabledInputSources()
        seedInitialDefaults()
        setupStatusItem()
        startMonitoring()

        if !config.hasOpenedSettings {
            config.hasOpenedSettings = true
            saveConfig()
            openSettings(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    @objc private func openSettings(_ sender: Any?) {
        let controller = settingsWindowController ?? SettingsWindowController(
            inputSources: inputSources,
            getConfig: { [weak self] in self?.config ?? .empty },
            onChange: { [weak self] nextConfig in self?.updateConfig(nextConfig) },
            runningApplications: { [weak self] in self?.runningApplicationCandidates() ?? [] },
            onAddRunningApplication: { [weak self] application in self?.addRunningApplicationRule(application) },
            onAddApplication: { [weak self] appURL in self?.addApplicationRule(at: appURL) }
        )
        settingsWindowController = controller
        controller.statusMessage = statusMessage
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        config.isEnabled.toggle()
        saveConfig()
        refreshMenu()
        settingsWindowController?.reload(config: config)
    }

    @objc private func applyNow(_ sender: Any?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        applyRule(for: app)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func loadConfig() {
        do {
            config = try configStore.load()
        } catch {
            config = .empty
            statusMessage = "配置读取失败，已使用默认配置。"
        }
    }

    private func saveConfig() {
        do {
            try configStore.save(config)
        } catch {
            statusMessage = "配置保存失败：\(error.localizedDescription)"
            settingsWindowController?.statusMessage = statusMessage
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "AutoInput")
        statusItem.button?.image?.isTemplate = true
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let settings = makeMenuItem(
            title: "设置",
            symbolName: "gearshape",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        menu.addItem(settings)

        let enabled = makeMenuItem(
            title: config.isEnabled ? "暂停" : "启用",
            symbolName: config.isEnabled ? "pause.circle" : "play.circle",
            action: #selector(toggleEnabled(_:))
        )
        menu.addItem(enabled)

        let apply = makeMenuItem(
            title: "应用规则",
            symbolName: "checkmark.circle",
            action: #selector(applyNow(_:))
        )
        menu.addItem(apply)

        menu.addItem(.separator())

        let quit = makeMenuItem(
            title: "退出",
            symbolName: "power",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeMenuItem(
        title: String,
        symbolName: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        item.image?.isTemplate = true
        return item
    }

    private func startMonitoring() {
        let monitor = AppMonitor { [weak self] app in
            self?.applyRule(for: app)
        }
        self.monitor = monitor
        monitor.start()
    }

    private func applyRule(for app: NSRunningApplication) {
        guard let targetID = config.targetInputSourceID(for: app.bundleIdentifier) else { return }
        if inputSourceManager.selectInputSource(id: targetID) {
            statusMessage = ""
        } else {
            statusMessage = "未能切换到输入法：\(targetID)"
            settingsWindowController?.statusMessage = statusMessage
        }
    }

    private func updateConfig(_ nextConfig: AutoInputConfig) {
        config = nextConfig
        saveConfig()
        refreshMenu()
    }

    private func addApplicationRule(at appURL: URL) {
        guard appURL.pathExtension == "app" else {
            statusMessage = "请选择一个 .app 应用。"
            settingsWindowController?.statusMessage = statusMessage
            return
        }

        guard let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            statusMessage = "这个应用没有 bundle id，无法添加。"
            settingsWindowController?.statusMessage = statusMessage
            return
        }

        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        addRule(bundleID: bundleID, appName: appName, forceEnglishPunctuation: false)
    }

    private func runningApplicationCandidates() -> [RunningApplicationCandidate] {
        let rawApplications = NSWorkspace.shared.runningApplications.map { application in
            let bundle = application.bundleURL.flatMap { Bundle(url: $0) }
            let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String

            return RunningApplicationCandidate.RawApplication(
                bundleID: application.bundleIdentifier,
                localizedName: application.localizedName,
                bundleName: bundleName
            )
        }

        return RunningApplicationCandidate.candidates(
            from: rawApplications,
            excludingBundleID: Bundle.main.bundleIdentifier
        )
    }

    private func addRunningApplicationRule(_ application: RunningApplicationCandidate) {
        addRule(
            bundleID: application.bundleID,
            appName: application.appName,
            forceEnglishPunctuation: false
        )
    }

    private func addRule(bundleID: String, appName: String, forceEnglishPunctuation: Bool) {
        if let index = config.rules.firstIndex(where: { $0.bundleID == bundleID }) {
            config.rules[index].appName = appName
            statusMessage = "已更新：\(appName)"
            saveConfig()
            settingsWindowController?.selectRule(bundleID: bundleID)
            settingsWindowController?.reload(config: config)
            return
        }

        let fallback = inputSources.first { $0.id == config.defaultInputSourceID }
            ?? inputSourceManager.preferredEnglishSource(from: inputSources)
            ?? inputSources.first

        guard let source = fallback else {
            statusMessage = "没有找到可用输入法。"
            settingsWindowController?.statusMessage = statusMessage
            return
        }

        config.upsertRule(AppInputRule(
            bundleID: bundleID,
            appName: appName,
            inputSourceID: source.id,
            inputSourceName: source.name,
            forceEnglishPunctuation: forceEnglishPunctuation
        ))
        statusMessage = "已添加：\(appName)"
        saveConfig()
        settingsWindowController?.selectRule(bundleID: bundleID)
        settingsWindowController?.reload(config: config)
    }

    private func seedInitialDefaults() {
        guard let english = inputSourceManager.preferredEnglishSource(from: inputSources) else { return }
        if config.defaultInputSourceID == nil {
            config.defaultInputSourceID = english.id
            config.defaultInputSourceName = english.name
        }

        let developerApps: [(String, String)] = [
            ("com.apple.Terminal", "Terminal"),
            ("com.googlecode.iterm2", "iTerm2"),
            ("com.microsoft.VSCode", "Code"),
            ("com.todesktop.230313mzl4w4u92", "Cursor")
        ]

        for (bundleID, fallbackName) in developerApps {
            guard !config.rules.contains(where: { $0.bundleID == bundleID }) else { continue }
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { continue }
            config.rules.append(AppInputRule(
                bundleID: bundleID,
                appName: fallbackName,
                inputSourceID: english.id,
                inputSourceName: english.name,
                forceEnglishPunctuation: true
            ))
        }

        saveConfig()
    }
}

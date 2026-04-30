import AppKit
import AutoInputCore
import Carbon
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
    private var statusMenuPopover: NSPopover?
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?
    private var statusMessage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadConfig()
        applyAppearance()
        inputSources = inputSourceManager.enabledInputSources()
        seedInitialDefaults()
        setupStatusItem()
        startInputSourceChangeMonitoring()
        startMonitoring()

        if !config.hasOpenedSettings {
            config.hasOpenedSettings = true
            saveConfig()
            openSettings(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeStatusPopovers()
        stopInputSourceChangeMonitoring()
        monitor?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettings(nil)
        }
        return true
    }

    @objc private func openSettings(_ sender: Any?) {
        closeStatusPopovers()
        NSApp.setActivationPolicy(.regular)
        let controller = settingsWindowController ?? SettingsWindowController(
            inputSources: inputSources,
            getConfig: { [weak self] in self?.config ?? .empty },
            onChange: { [weak self] nextConfig in self?.updateConfig(nextConfig) },
            runningApplications: { [weak self] in self?.runningApplicationCandidates() ?? [] },
            onAddRunningApplication: { [weak self] application in self?.addRunningApplicationRule(application) },
            onAddApplication: { [weak self] appURL in self?.addApplicationRule(at: appURL) }
        )
        settingsWindowController = controller
        controller.onClose = { [weak self] in
            self?.settingsWindowDidClose()
        }
        controller.statusMessage = statusMessage
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func settingsWindowDidClose() {
        closeStatusPopovers()
        NSApp.setActivationPolicy(.accessory)
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
            statusMessage = backupInvalidConfigMessage(readError: error)
        }
    }

    private func backupInvalidConfigMessage(readError: Error) -> String {
        do {
            let backupURL = try configStore.backupInvalidConfig(suffix: invalidConfigBackupSuffix())
            return "配置读取失败，已备份为 \(backupURL.lastPathComponent)，并使用默认配置。"
        } catch {
            return "配置读取失败，且备份失败：\(error.localizedDescription)。已使用默认配置。原错误：\(readError.localizedDescription)"
        }
    }

    private func invalidConfigBackupSuffix() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleStatusMenu(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggleStatusMenu(_ sender: NSStatusBarButton) {
        if statusMenuPopover?.isShown == true {
            closeStatusPopovers()
            return
        }

        showStatusMenu(relativeTo: sender)
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        closeStatusPopovers()

        let view = makeStatusMenuView()
        let controller = NSViewController()
        controller.view = view

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = view.fittingSize
        popover.contentViewController = controller
        statusMenuPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startStatusMenuDismissMonitoring()
    }

    private func refreshStatusMenu() {
        guard let popover = statusMenuPopover, popover.isShown else { return }
        let view = makeStatusMenuView()
        popover.contentSize = view.fittingSize
        popover.contentViewController?.view = view
    }

    private func closeStatusPopovers() {
        statusMenuPopover?.close()
        statusMenuPopover = nil
        stopStatusMenuDismissMonitoring()
    }

    private func startStatusMenuDismissMonitoring() {
        stopStatusMenuDismissMonitoring()

        let popoverWindow = statusMenuPopover?.contentViewController?.view.window
        let statusButton = statusItem.button
        let statusButtonWindow = statusButton?.window

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                Task { @MainActor in
                    self.closeStatusPopovers()
                }
                return nil
            }

            guard event.type != .keyDown else { return event }
            guard event.window != popoverWindow else { return event }

            if let statusButton,
               event.window == statusButtonWindow {
                let location = statusButton.convert(event.locationInWindow, from: nil)
                if statusButton.bounds.contains(location) {
                    return event
                }
            }

            Task { @MainActor in
                self.closeStatusPopovers()
            }
            return event
        }

        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeStatusPopovers()
            }
        }
    }

    private func stopStatusMenuDismissMonitoring() {
        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }

        if let globalDismissMonitor {
            NSEvent.removeMonitor(globalDismissMonitor)
            self.globalDismissMonitor = nil
        }
    }

    private func makeStatusMenuView() -> StatusMenuPopoverView {
        StatusMenuPopoverView(
            model: StatusMenuModel(
                isEnabled: config.isEnabled,
                defaultInputSourceName: config.defaultInputSourceName ?? "不切换"
            ),
            onEnabledChange: { [weak self] enabled in
                self?.setServiceEnabled(enabled)
            },
            onAddCurrentApplication: { [weak self] in
                self?.addFrontmostApplicationRule()
            },
            onRefreshInputSources: { [weak self] in
                self?.refreshInputSources(showStatus: true)
            },
            onOpenRules: { [weak self] in
                self?.closeStatusPopovers()
                self?.openSettings(nil)
            },
            onOpenSettings: { [weak self] in
                self?.closeStatusPopovers()
                self?.openSettings(nil)
            },
            onQuit: { [weak self] in
                self?.quit(nil)
            }
        )
    }

    private func setServiceEnabled(_ enabled: Bool) {
        guard config.isEnabled != enabled else { return }
        config.isEnabled = enabled
        saveConfig()
        refreshStatusMenu()
        settingsWindowController?.reload(config: config)
    }

    private func startMonitoring() {
        let monitor = AppMonitor { [weak self] app in
            self?.applyRule(for: app)
        }
        self.monitor = monitor
        monitor.start()
    }

    private func startInputSourceChangeMonitoring() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourcesDidChange),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func stopInputSourceChangeMonitoring() {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    @objc private func inputSourcesDidChange() {
        refreshInputSources(showStatus: false)
    }

    private func refreshInputSources(showStatus: Bool) {
        inputSources = inputSourceManager.enabledInputSources()
        settingsWindowController?.reloadInputSources(inputSources)
        refreshStatusMenu()

        if showStatus {
            statusMessage = "已刷新输入法列表。"
            settingsWindowController?.statusMessage = statusMessage
        }
    }

    private func applyRule(for app: NSRunningApplication) {
        guard let target = config.targetInputSource(for: app.bundleIdentifier) else { return }
        if inputSourceManager.selectInputSource(
            id: target.id,
            forceEnglishPunctuation: target.forceEnglishPunctuation
        ) {
            statusMessage = ""
        } else {
            statusMessage = "未能切换到输入法：\(target.id)"
            settingsWindowController?.statusMessage = statusMessage
        }
    }

    private func updateConfig(_ nextConfig: AutoInputConfig) {
        config = nextConfig
        applyAppearance()
        saveConfig()
        refreshStatusMenu()
    }

    private func applyAppearance() {
        switch config.appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        settingsWindowController?.window?.appearance = NSApp.appearance
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
                bundleName: bundleName,
                bundlePath: application.bundleURL?.path,
                isRegularApplication: application.activationPolicy == .regular
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

    private func addFrontmostApplicationRule() {
        guard let application = frontmostApplicationCandidate() else {
            statusMessage = "没有可添加的当前应用。"
            settingsWindowController?.statusMessage = statusMessage
            refreshStatusMenu()
            return
        }

        addRunningApplicationRule(application)
        refreshStatusMenu()
    }

    private func frontmostApplicationCandidate() -> RunningApplicationCandidate? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundle = application.bundleURL.flatMap { Bundle(url: $0) }
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String

        return RunningApplicationCandidate.candidates(
            from: [
                RunningApplicationCandidate.RawApplication(
                    bundleID: application.bundleIdentifier,
                    localizedName: application.localizedName,
                    bundleName: bundleName,
                    bundlePath: application.bundleURL?.path,
                    isRegularApplication: application.activationPolicy == .regular
                )
            ],
            excludingBundleID: Bundle.main.bundleIdentifier
        ).first
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
        refreshStatusMenu()
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

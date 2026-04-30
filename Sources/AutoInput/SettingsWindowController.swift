import AppKit
import AutoInputCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSSearchFieldDelegate, NSWindowDelegate {
    private typealias Style = SettingsStyle

    private var inputSources: [InputSourceDescriptor]
    private let getConfig: () -> AutoInputConfig
    private let onChange: (AutoInputConfig) -> Void
    private let runningApplications: () -> [RunningApplicationCandidate]
    private let onAddRunningApplication: (RunningApplicationCandidate) -> Void
    private let onAddApplication: (URL) -> Void

    private enum Layout {
        static let windowWidth: CGFloat = 430
        static let windowHeight: CGFloat = 550
        static let windowMinWidth: CGFloat = 430
        static let windowMinHeight: CGFloat = 430
        static let contentInset: CGFloat = 22
        static let contentMaxWidth: CGFloat = 430
    }

    private let rootStack = NSStackView()
    private let defaultPopup = NSPopUpButton()
    private let enabledSwitch = NSSwitch()
    private let enabledBadge = BadgeView()
    private let rowsStack = NSStackView()
    private let searchField = NSSearchField()
    private let appearancePopup = NSPopUpButton()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var removeButton: NSButton!
    private var addApplicationPopover: NSPopover?
    private var styledCards: [NSView] = []

    private var selectedBundleID: String?
    private var config: AutoInputConfig
    private var searchQuery = ""
    var onClose: (() -> Void)?

    private var visibleRules: [AppInputRule] {
        config.rules.filter { $0.matchesSearch(searchQuery) }
    }

    var statusMessage: String = "" {
        didSet {
            updateStatus()
        }
    }

    init(
        inputSources: [InputSourceDescriptor],
        getConfig: @escaping () -> AutoInputConfig,
        onChange: @escaping (AutoInputConfig) -> Void,
        runningApplications: @escaping () -> [RunningApplicationCandidate],
        onAddRunningApplication: @escaping (RunningApplicationCandidate) -> Void,
        onAddApplication: @escaping (URL) -> Void
    ) {
        self.inputSources = inputSources
        self.getConfig = getConfig
        self.onChange = onChange
        self.runningApplications = runningApplications
        self.onAddRunningApplication = onAddRunningApplication
        self.onAddApplication = onAddApplication
        self.config = getConfig()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AutoInput"
        window.minSize = NSSize(width: Layout.windowMinWidth, height: Layout.windowMinHeight)
        window.center()

        super.init(window: window)
        window.delegate = self
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        buildUI()
        reload(config: config)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func reload(config: AutoInputConfig) {
        self.config = config

        if let selectedBundleID,
           !config.rules.contains(where: { $0.bundleID == selectedBundleID }) {
            self.selectedBundleID = visibleRules.first?.bundleID
        } else if selectedBundleID == nil {
            selectedBundleID = visibleRules.first?.bundleID
        }

        enabledSwitch.state = config.isEnabled ? .on : .off
        enabledBadge.setEnabled(config.isEnabled)
        removeButton?.isEnabled = selectedBundleID != nil
        reloadAppearancePopup()
        reloadDefaultPopup()
        rebuildRows()
        updateCount()
        updateStatus()
        applyTheme()
    }

    func selectRule(bundleID: String) {
        selectedBundleID = bundleID
        searchQuery = ""
        searchField.stringValue = ""
    }

    func reloadInputSources(_ inputSources: [InputSourceDescriptor]) {
        self.inputSources = inputSources
        reload(config: config)
    }

    func controlTextDidChange(_ notification: Notification) {
        searchQuery = searchField.stringValue
        if let selectedBundleID,
           !visibleRules.contains(where: { $0.bundleID == selectedBundleID }) {
            self.selectedBundleID = visibleRules.first?.bundleID
        }
        reload(config: config)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Style.background.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 18, left: 0, bottom: 14, right: 0)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        let horizontalInset = Layout.contentInset * 2
        let fillWidth = rootStack.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -horizontalInset)
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            rootStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rootStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: Layout.contentInset),
            rootStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -Layout.contentInset),
            rootStack.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.contentMaxWidth),
            fillWidth
        ])

        addRootArrangedSubview(makeHeader())
        addRootArrangedSubview(makeDefaultCard())
        addRootArrangedSubview(makeRulesCard())
        addRootArrangedSubview(makeStatusBar())
    }

    private func addRootArrangedSubview(_ view: NSView) {
        rootStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
    }

    private func rebuildUIForAppearanceChange() {
        styledCards.removeAll()
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rootStack.arrangedSubviews.forEach { view in
            rootStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rootStack.removeFromSuperview()
        buildUI()
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let title = NSTextField(labelWithString: "按应用切换")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.textColor = Style.text

        let titleStack = NSStackView(views: [title])
        titleStack.orientation = .horizontal
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)

        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)
        appearancePopup.controlSize = .large
        appearancePopup.toolTip = "外观"

        let switchStack = NSStackView(views: [appearancePopup, enabledBadge, enabledSwitch])
        switchStack.orientation = .horizontal
        switchStack.alignment = .centerY
        switchStack.spacing = 8
        switchStack.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleStack)
        header.addSubview(switchStack)

        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: switchStack.leadingAnchor, constant: -18),

            switchStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            switchStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            appearancePopup.widthAnchor.constraint(equalToConstant: 104)
        ])

        return header
    }

    private func makeDefaultCard() -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let title = NSTextField(labelWithString: "默认输入法")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = Style.text

        let hint = NSTextField(labelWithString: "未匹配时使用")
        hint.font = .systemFont(ofSize: 12, weight: .regular)
        hint.textColor = Style.secondaryText

        let textStack = NSStackView(views: [title, hint])
        textStack.orientation = .horizontal
        textStack.alignment = .firstBaseline
        textStack.spacing = 10
        textStack.translatesAutoresizingMaskIntoConstraints = false

        defaultPopup.target = self
        defaultPopup.action = #selector(defaultSourceChanged)
        defaultPopup.controlSize = .large
        defaultPopup.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(textStack)
        card.addSubview(defaultPopup)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: defaultPopup.leadingAnchor, constant: -16),

            defaultPopup.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            defaultPopup.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            defaultPopup.widthAnchor.constraint(equalToConstant: 205)
        ])

        return card
    }

    private func makeRulesCard() -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 278).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        stack.addArrangedSubview(makeRulesToolbar())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeRulesScrollArea())

        return card
    }

    private func makeRulesToolbar() -> NSView {
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let title = NSTextField(labelWithString: "规则")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = Style.text

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = Style.secondaryText

        let titleStack = NSStackView(views: [title, countLabel])
        titleStack.orientation = .horizontal
        titleStack.alignment = .firstBaseline
        titleStack.spacing = 6
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "搜索"
        searchField.delegate = self
        searchField.controlSize = .large
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "", target: self, action: #selector(showAddApplicationMenu(_:)))
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "添加应用")
        addButton.imagePosition = .imageOnly
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        addButton.contentTintColor = NSColor.controlAccentColor
        addButton.toolTip = "从正在运行的应用或应用文件添加输入法规则"

        removeButton = NSButton(title: "", target: self, action: #selector(removeSelectedRule))
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "移除所选")
        removeButton.imagePosition = .imageOnly
        removeButton.bezelStyle = .rounded
        removeButton.controlSize = .large
        removeButton.toolTip = "移除当前选中的应用规则"

        let toolbarViews: [NSView] = [titleStack, searchField, addButton, removeButton]
        for view in toolbarViews {
            toolbar.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            titleStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            removeButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            removeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -6),
            addButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            searchField.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 150),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: titleStack.trailingAnchor, constant: 12)
        ])

        return toolbar
    }

    private func makeRulesScrollArea() -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 4
        rowsStack.edgeInsets = NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rowsStack)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: document.topAnchor),
            rowsStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    private func makeStatusBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 18).isActive = true

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = Style.secondaryText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor)
        ])

        return bar
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let rules = visibleRules
        if rules.isEmpty {
            let empty = EmptyRulesView(isSearching: !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            rowsStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: rowsStack.widthAnchor, constant: -14).isActive = true
            empty.heightAnchor.constraint(equalToConstant: 108).isActive = true
            return
        }

        for rule in rules {
            let row = RuleRowView(
                rule: rule,
                inputSources: inputSources,
                isSelected: selectedBundleID == rule.bundleID,
                onSelect: { [weak self] in
                    self?.selectedBundleID = rule.bundleID
                    self?.reload(config: self?.config ?? .empty)
                },
                onInputSourceChange: { [weak self] source in
                    self?.updateRule(rule.bundleID, source: source)
                },
                onPunctuationChange: { [weak self] enabled in
                    self?.updateRule(rule.bundleID, forceEnglishPunctuation: enabled)
                }
            )
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor, constant: -14).isActive = true
        }
    }

    private func reloadDefaultPopup() {
        defaultPopup.removeAllItems()
        defaultPopup.addItem(withTitle: "不切换")
        defaultPopup.lastItem?.representedObject = ""
        for source in inputSources {
            defaultPopup.addItem(withTitle: source.name)
            defaultPopup.lastItem?.representedObject = source.id
        }

        if let id = config.defaultInputSourceID,
           let index = defaultPopup.itemArray.firstIndex(where: { $0.representedObject as? String == id }) {
            defaultPopup.selectItem(at: index)
        } else {
            defaultPopup.selectItem(at: 0)
        }
    }

    private func reloadAppearancePopup() {
        appearancePopup.removeAllItems()

        let items: [(String, AppAppearanceMode)] = [
            ("跟随系统", .system),
            ("浅色", .light),
            ("深色", .dark)
        ]

        for (title, mode) in items {
            appearancePopup.addItem(withTitle: title)
            appearancePopup.lastItem?.representedObject = mode.rawValue
        }

        if let index = appearancePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == config.appearanceMode.rawValue
        }) {
            appearancePopup.selectItem(at: index)
        }
    }

    private func updateRule(_ bundleID: String, source: InputSourceDescriptor) {
        guard let index = config.rules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        config.rules[index].inputSourceID = source.id
        config.rules[index].inputSourceName = source.name
        onChange(config)
        reload(config: config)
    }

    private func updateRule(_ bundleID: String, forceEnglishPunctuation: Bool) {
        guard let index = config.rules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        config.rules[index].forceEnglishPunctuation = forceEnglishPunctuation
        onChange(config)
    }

    private func updateCount() {
        let total = config.rules.count
        let visible = visibleRules.count
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            countLabel.stringValue = "· \(total) 条"
        } else {
            countLabel.stringValue = "· \(visible) / \(total) 条"
        }
    }

    @objc private func enabledChanged() {
        config.isEnabled = enabledSwitch.state == .on
        onChange(config)
        reload(config: config)
    }

    @objc private func appearanceChanged() {
        guard let rawValue = appearancePopup.selectedItem?.representedObject as? String,
              let mode = AppAppearanceMode(rawValue: rawValue) else {
            return
        }
        config.appearanceMode = mode
        onChange(config)
        rebuildUIForAppearanceChange()
        reload(config: config)
    }

    @objc private func systemAppearanceChanged() {
        guard config.appearanceMode == .system else { return }
        rebuildUIForAppearanceChange()
        reload(config: config)
    }

    @objc private func showAddApplicationMenu(_ sender: NSButton) {
        addApplicationPopover?.close()

        let picker = RunningApplicationsPickerView(
            applications: runningApplications(),
            onSelect: { [weak self] application in
                self?.addApplicationPopover?.close()
                self?.onAddRunningApplication(application)
            },
            onChooseFile: { [weak self] in
                self?.addApplicationPopover?.close()
                self?.chooseApplication()
            }
        )

        let controller = NSViewController()
        controller.view = picker

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = controller
        addApplicationPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "添加规则"
        panel.message = "选择一个 .app 应用，即使它现在没有运行也可以添加。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.applicationBundle]
        } else {
            panel.allowedFileTypes = ["app"]
        }

        guard let window else {
            if panel.runModal() == .OK, let url = panel.url {
                onAddApplication(url)
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.onAddApplication(url)
        }
    }

    @objc private func removeSelectedRule() {
        guard let selectedBundleID,
              let rule = config.rules.first(where: { $0.bundleID == selectedBundleID }) else { return }

        let alert = NSAlert()
        alert.messageText = "移除“\(rule.appName)”的输入法规则？"
        alert.informativeText = "移除后，这个应用会使用默认输入法。"
        alert.addButton(withTitle: "移除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        config.rules.removeAll { $0.bundleID == selectedBundleID }
        self.selectedBundleID = visibleRules.first?.bundleID
        onChange(config)
        reload(config: config)
    }

    @objc private func defaultSourceChanged() {
        let sourceID = defaultPopup.selectedItem?.representedObject as? String
        if let sourceID, !sourceID.isEmpty, let source = inputSources.first(where: { $0.id == sourceID }) {
            config.defaultInputSourceID = source.id
            config.defaultInputSourceName = source.name
        } else {
            config.defaultInputSourceID = nil
            config.defaultInputSourceName = nil
        }
        onChange(config)
    }

    private func updateStatus() {
        if statusMessage.isEmpty {
            statusLabel.stringValue = config.isEnabled ? "" : "已暂停"
            statusLabel.textColor = Style.secondaryText
        } else {
            statusLabel.stringValue = statusMessage
            statusLabel.textColor = .systemOrange
        }
    }

    private func makeCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Style.card.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = Style.stroke.cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        styledCards.append(card)
        return card
    }

    private func applyTheme() {
        window?.contentView?.layer?.backgroundColor = Style.background.cgColor
        for card in styledCards {
            card.layer?.backgroundColor = Style.card.cgColor
            card.layer?.borderColor = Style.stroke.cgColor
        }
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}

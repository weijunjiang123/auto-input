import AppKit
import AutoInputCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSSearchFieldDelegate {
    private enum Style {
        static let background = NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)
        static let card = NSColor(red: 0.15, green: 0.16, blue: 0.20, alpha: 1)
        static let row = NSColor(red: 0.20, green: 0.21, blue: 0.25, alpha: 1)
        static let rowSelected = NSColor(red: 0.22, green: 0.23, blue: 0.28, alpha: 1)
        static let field = NSColor(red: 0.22, green: 0.23, blue: 0.28, alpha: 1)
        static let stroke = NSColor(white: 1, alpha: 0.10)
        static let selectedStroke = NSColor.controlAccentColor.withAlphaComponent(0.70)
        static let text = NSColor(white: 0.96, alpha: 1)
        static let secondaryText = NSColor(white: 0.70, alpha: 1)
        static let tertiaryText = NSColor(white: 0.56, alpha: 1)
    }

    private let inputSources: [InputSourceDescriptor]
    private let getConfig: () -> AutoInputConfig
    private let onChange: (AutoInputConfig) -> Void
    private let runningApplications: () -> [RunningApplicationCandidate]
    private let onAddRunningApplication: (RunningApplicationCandidate) -> Void
    private let onAddApplication: (URL) -> Void

    private let rootStack = NSStackView()
    private let defaultPopup = NSPopUpButton()
    private let enabledSwitch = NSSwitch()
    private let enabledBadge = BadgeView()
    private let rowsStack = NSStackView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var removeButton: NSButton!
    private var addApplicationPopover: NSPopover?

    private var selectedBundleID: String?
    private var config: AutoInputConfig
    private var searchQuery = ""

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
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AutoInput"
        window.minSize = NSSize(width: 430, height: 430)
        window.center()

        super.init(window: window)
        buildUI()
        reload(config: config)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        reloadDefaultPopup()
        rebuildRows()
        updateCount()
        updateStatus()
    }

    func selectRule(bundleID: String) {
        selectedBundleID = bundleID
        searchQuery = ""
        searchField.stringValue = ""
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
        rootStack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 14, right: 22)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        let fillWidth = rootStack.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -44)
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            rootStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rootStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 22),
            rootStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -22),
            rootStack.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            fillWidth
        ])

        rootStack.addArrangedSubview(makeHeader())
        rootStack.addArrangedSubview(makeDefaultCard())
        rootStack.addArrangedSubview(makeRulesCard())
        rootStack.addArrangedSubview(makeStatusBar())
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let title = NSTextField(labelWithString: "按应用切换")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textColor = Style.text

        let titleStack = NSStackView(views: [title])
        titleStack.orientation = .horizontal
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)

        let switchStack = NSStackView(views: [enabledBadge, enabledSwitch])
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
            switchStack.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        return header
    }

    private func makeDefaultCard() -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let title = NSTextField(labelWithString: "默认输入法")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
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
        title.font = .systemFont(ofSize: 15, weight: .semibold)
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
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = Style.stroke.cgColor
        card.layer?.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEnabled(_ enabled: Bool) {
        label.stringValue = enabled ? "已启用" : "已暂停"
        label.textColor = enabled ? NSColor.systemGreen : NSColor.systemOrange
        layer?.backgroundColor = (enabled ? NSColor.systemGreen : NSColor.systemOrange)
            .withAlphaComponent(0.15)
            .cgColor
    }
}

private final class EmptyRulesView: NSView {
    private let isSearching: Bool

    init(isSearching: Bool) {
        self.isSearching = isSearching
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: isSearching ? "magnifyingglass" : "plus.app",
            accessibilityDescription: nil
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        icon.contentTintColor = NSColor(white: 0.66, alpha: 1)

        let title = NSTextField(labelWithString: isSearching ? "没有匹配的规则" : "还没有应用规则")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = NSColor(white: 0.92, alpha: 1)

        let subtitle = NSTextField(labelWithString: isSearching ? "换个关键词试试" : "点击 + 添加应用")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = NSColor(white: 0.66, alpha: 1)
        subtitle.alignment = .center

        let stack = NSStackView(views: [icon, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class RunningApplicationsPickerView: NSView {
    private enum Style {
        static let background = NSColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1)
        static let row = NSColor(white: 1, alpha: 0.06)
        static let rowHover = NSColor.controlAccentColor.withAlphaComponent(0.22)
        static let text = NSColor(white: 0.94, alpha: 1)
        static let secondaryText = NSColor(white: 0.62, alpha: 1)
        static let stroke = NSColor(white: 1, alpha: 0.10)
    }

    private let applications: [RunningApplicationCandidate]
    private let onSelect: (RunningApplicationCandidate) -> Void
    private let onChooseFile: () -> Void

    init(
        applications: [RunningApplicationCandidate],
        onSelect: @escaping (RunningApplicationCandidate) -> Void,
        onChooseFile: @escaping () -> Void
    ) {
        self.applications = applications
        self.onSelect = onSelect
        self.onChooseFile = onChooseFile
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = Style.background.cgColor

        let title = NSTextField(labelWithString: "正在运行的应用")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Style.text

        let count = NSTextField(labelWithString: "\(applications.count) 个")
        count.font = .systemFont(ofSize: 11, weight: .medium)
        count.textColor = Style.secondaryText

        let header = NSStackView(views: [title, count])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8

        let scrollView = makeApplicationsScrollView()
        let chooseFile = NSButton(title: "选择应用文件...", target: self, action: #selector(chooseFileClicked))
        chooseFile.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        chooseFile.imagePosition = .imageLeading
        chooseFile.bezelStyle = .rounded
        chooseFile.controlSize = .large

        let stack = NSStackView(views: [header, scrollView, chooseFile])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 278)
        ])
    }

    private func makeApplicationsScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 5
        list.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 4)
        list.translatesAutoresizingMaskIntoConstraints = false

        if applications.isEmpty {
            let empty = NSTextField(labelWithString: "没有可添加的前台应用")
            empty.font = .systemFont(ofSize: 12, weight: .medium)
            empty.textColor = Style.secondaryText
            empty.alignment = .center
            list.addArrangedSubview(empty)
            empty.heightAnchor.constraint(equalToConstant: 44).isActive = true
        } else {
            for application in applications {
                list.addArrangedSubview(RunningApplicationButton(application: application, onSelect: onSelect))
            }
        }

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    @objc private func chooseFileClicked() {
        onChooseFile()
    }
}

private final class RunningApplicationButton: NSButton {
    private let application: RunningApplicationCandidate
    private let onSelect: (RunningApplicationCandidate) -> Void

    init(application: RunningApplicationCandidate, onSelect: @escaping (RunningApplicationCandidate) -> Void) {
        self.application = application
        self.onSelect = onSelect
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        title = application.appName
        image = NSWorkspace.shared.icon(forFile: appPathForBundleID(application.bundleID) ?? "")
        imagePosition = .imageLeading
        alignment = .left
        isBordered = false
        bezelStyle = .regularSquare
        target = self
        action = #selector(clicked)
        toolTip = application.bundleID
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        attributedTitle = NSAttributedString(
            string: application.appName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(white: 0.94, alpha: 1),
                .paragraphStyle: paragraph
            ]
        )
    }

    @objc private func clicked() {
        onSelect(application)
    }
}

private func appPathForBundleID(_ bundleID: String) -> String? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
}

private final class RuleRowView: NSView {
    private enum Style {
        static let row = NSColor(red: 0.20, green: 0.21, blue: 0.25, alpha: 1)
        static let rowSelected = NSColor(red: 0.23, green: 0.24, blue: 0.29, alpha: 1)
        static let text = NSColor(white: 0.95, alpha: 1)
        static let secondaryText = NSColor(white: 0.68, alpha: 1)
    }

    private let rule: AppInputRule
    private let inputSources: [InputSourceDescriptor]
    private let onSelect: () -> Void
    private let onInputSourceChange: (InputSourceDescriptor) -> Void
    private let onPunctuationChange: (Bool) -> Void

    init(
        rule: AppInputRule,
        inputSources: [InputSourceDescriptor],
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onInputSourceChange: @escaping (InputSourceDescriptor) -> Void,
        onPunctuationChange: @escaping (Bool) -> Void
    ) {
        self.rule = rule
        self.inputSources = inputSources
        self.onSelect = onSelect
        self.onInputSourceChange = onInputSourceChange
        self.onPunctuationChange = onPunctuationChange
        super.init(frame: .zero)
        build(isSelected: isSelected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect()
    }

    private func build(isSelected: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = (isSelected ? Style.rowSelected : Style.row).cgColor
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.55) : NSColor(white: 1, alpha: 0.06)).cgColor
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true

        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        accent.layer?.cornerRadius = 2

        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: appPathForBundleID(rule.bundleID) ?? "")
        icon.imageScaling = .scaleProportionallyUpOrDown

        let name = NSTextField(labelWithString: rule.appName)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = Style.text
        name.lineBreakMode = .byTruncatingTail

        name.toolTip = rule.bundleID

        let appStack = NSStackView(views: [name])
        appStack.orientation = .horizontal
        appStack.spacing = 0
        appStack.alignment = .leading

        let popup = NSPopUpButton()
        popup.controlSize = .small
        popup.removeAllItems()
        for source in inputSources {
            popup.addItem(withTitle: source.name)
            popup.lastItem?.representedObject = source.id
        }
        if let index = popup.itemArray.firstIndex(where: { $0.representedObject as? String == rule.inputSourceID }) {
            popup.selectItem(at: index)
        }
        popup.target = self
        popup.action = #selector(inputSourceChanged(_:))

        let punctuation = NSSwitch()
        punctuation.controlSize = .small
        punctuation.state = rule.forceEnglishPunctuation ? .on : .off
        punctuation.target = self
        punctuation.action = #selector(punctuationChanged(_:))
        punctuation.toolTip = "英文标点"

        for view in [accent, icon, appStack, popup, punctuation] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: leadingAnchor),
            accent.centerYAnchor.constraint(equalTo: centerYAnchor),
            accent.widthAnchor.constraint(equalToConstant: 3),
            accent.heightAnchor.constraint(equalToConstant: 20),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            appStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            appStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            appStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            appStack.trailingAnchor.constraint(lessThanOrEqualTo: popup.leadingAnchor, constant: -8),

            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.trailingAnchor.constraint(equalTo: punctuation.leadingAnchor, constant: -14),
            popup.widthAnchor.constraint(equalToConstant: 154),

            punctuation.centerYAnchor.constraint(equalTo: centerYAnchor),
            punctuation.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }

    @objc private func inputSourceChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        guard let source = inputSources.first(where: { $0.id == id }) else { return }
        onInputSourceChange(source)
    }

    @objc private func punctuationChanged(_ sender: NSSwitch) {
        onPunctuationChange(sender.state == .on)
    }
}

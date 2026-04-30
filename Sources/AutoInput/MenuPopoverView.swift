import AppKit

@MainActor
struct StatusMenuModel {
    var isEnabled: Bool
    var defaultInputSourceName: String
}

@MainActor
final class StatusMenuPopoverView: NSView {
    private enum Layout {
        static let width: CGFloat = 260
        static let height: CGFloat = 259
        static let inset: CGFloat = 14
    }

    @MainActor
    private enum Style {
        static var background: NSColor {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.08, alpha: 0.40)
                : NSColor(white: 1, alpha: 0.18)
        }

        static var text: NSColor {
            NSColor.labelColor
        }

        static var secondaryText: NSColor {
            NSColor.secondaryLabelColor
        }
    }

    private let model: StatusMenuModel
    private let onEnabledChange: (Bool) -> Void
    private let onAddCurrentApplication: () -> Void
    private let onRefreshInputSources: () -> Void
    private let onOpenRules: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void
    private let enabledSwitch = NSSwitch()

    init(
        model: StatusMenuModel,
        onEnabledChange: @escaping (Bool) -> Void,
        onAddCurrentApplication: @escaping () -> Void,
        onRefreshInputSources: @escaping () -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.model = model
        self.onEnabledChange = onEnabledChange
        self.onAddCurrentApplication = onAddCurrentApplication
        self.onRefreshInputSources = onRefreshInputSources
        self.onOpenRules = onOpenRules
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Layout.width).isActive = true
        heightAnchor.constraint(equalToConstant: Layout.height).isActive = true

        addGlassBackground()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 20, left: Layout.inset, bottom: 10, right: Layout.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makeDefaultSourceRow())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(MenuActionRow(
            symbolName: "plus.circle",
            symbolColor: .controlAccentColor,
            title: "添加当前应用",
            action: onAddCurrentApplication
        ))
        stack.addArrangedSubview(MenuActionRow(
            symbolName: "arrow.clockwise.circle",
            symbolColor: .controlAccentColor,
            title: "刷新输入法",
            action: onRefreshInputSources
        ))
        stack.addArrangedSubview(MenuActionRow(
            symbolName: "list.bullet.rectangle",
            symbolColor: .controlAccentColor,
            title: "规则管理",
            action: onOpenRules
        ))
        stack.addArrangedSubview(MenuActionRow(
            symbolName: model.isEnabled ? "pause.circle" : "play.circle",
            symbolColor: .controlAccentColor,
            title: model.isEnabled ? "暂停服务" : "启用服务",
            action: { [weak self] in
                guard let self else { return }
                onEnabledChange(!model.isEnabled)
            }
        ))
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(MenuActionRow(
            symbolName: "gearshape",
            symbolColor: Style.secondaryText,
            title: "设置...",
            trailingText: "⌘,",
            action: onOpenSettings
        ))
        stack.addArrangedSubview(MenuActionRow(
            symbolName: "power",
            symbolColor: Style.secondaryText,
            title: "退出 AutoInput",
            trailingText: "⌘Q",
            action: onQuit
        ))
    }

    private func addGlassBackground() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = false
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Style.background.cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeHeader() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let title = NSTextField(labelWithString: "AutoInput")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = Style.text
        title.translatesAutoresizingMaskIntoConstraints = false

        let state = NSTextField(labelWithString: model.isEnabled ? "已启用" : "已暂停")
        state.font = .systemFont(ofSize: 12, weight: .medium)
        state.textColor = Style.secondaryText
        state.translatesAutoresizingMaskIntoConstraints = false

        enabledSwitch.controlSize = .small
        enabledSwitch.state = model.isEnabled ? .on : .off
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledSwitchChanged)
        enabledSwitch.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(state)
        view.addSubview(enabledSwitch)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            state.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 6),
            state.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            state.trailingAnchor.constraint(lessThanOrEqualTo: enabledSwitch.leadingAnchor, constant: -10),

            enabledSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            enabledSwitch.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func makeDefaultSourceRow() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let title = NSTextField(labelWithString: "默认输入法")
        title.font = .systemFont(ofSize: 11, weight: .regular)
        title.textColor = Style.secondaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let value = NSTextField(labelWithString: model.defaultInputSourceName)
        value.font = .systemFont(ofSize: 11, weight: .medium)
        value.textColor = Style.text
        value.lineBreakMode = .byTruncatingTail
        value.alignment = .right
        value.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(value)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            value.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            value.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            value.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 7).isActive = true
        return separator
    }

    @objc private func enabledSwitchChanged() {
        onEnabledChange(enabledSwitch.state == .on)
    }
}

@MainActor
private final class MenuActionRow: NSControl {
    @MainActor
    private enum Style {
        static var hover: NSColor {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.controlAccentColor.withAlphaComponent(0.24)
                : NSColor.controlAccentColor.withAlphaComponent(0.12)
        }

        static var pressed: NSColor {
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.controlAccentColor.withAlphaComponent(0.32)
                : NSColor.controlAccentColor.withAlphaComponent(0.18)
        }

        static var text: NSColor {
            NSColor.labelColor
        }

        static var secondaryText: NSColor {
            NSColor.secondaryLabelColor
        }
    }

    private let actionHandler: () -> Void
    private var trackingArea: NSTrackingArea?

    init(
        symbolName: String,
        symbolColor: NSColor,
        title: String,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) {
        self.actionHandler = action
        super.init(frame: .zero)
        build(symbolName: symbolName, symbolColor: symbolColor, title: title, trailingText: trailingText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(symbolName: String, symbolColor: NSColor, title: String, trailingText: String?) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.contentTintColor = symbolColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = Style.text
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if let trailingText {
            let trailing = NSTextField(labelWithString: trailingText)
            trailing.font = .systemFont(ofSize: 11, weight: .regular)
            trailing.textColor = Style.secondaryText
            trailing.translatesAutoresizingMaskIntoConstraints = false
            addSubview(trailing)

            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -8),
                trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                trailing.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -7).isActive = true
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let nextArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = nextArea
        addTrackingArea(nextArea)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Style.hover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Style.pressed.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        defer { layer?.backgroundColor = Style.hover.cgColor }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        actionHandler()
    }
}

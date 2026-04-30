import AppKit

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class BadgeView: NSView {
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

final class EmptyRulesView: NSView {
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
        icon.contentTintColor = SettingsStyle.emptyIcon

        let title = NSTextField(labelWithString: isSearching ? "没有匹配的规则" : "还没有应用规则")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = SettingsStyle.emptyText

        let subtitle = NSTextField(labelWithString: isSearching ? "换个关键词试试" : "点击 + 添加应用")
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = SettingsStyle.emptySecondaryText
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

func appPathForBundleID(_ bundleID: String) -> String? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
}

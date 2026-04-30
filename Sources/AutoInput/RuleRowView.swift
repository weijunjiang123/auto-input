import AppKit
import AutoInputCore

final class RuleRowView: NSView {
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
        layer?.cornerRadius = 8
        layer?.backgroundColor = (isSelected ? SettingsStyle.rowSelected : SettingsStyle.row).cgColor
        let idleBorder = SettingsStyle.isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.07)
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.45) : idleBorder).cgColor
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
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.textColor = SettingsStyle.text
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

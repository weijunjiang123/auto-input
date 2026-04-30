import AppKit
import AutoInputCore

final class RunningApplicationsPickerView: NSView {
    private let applications: [RunningApplicationCandidate]
    private let onSelect: (RunningApplicationCandidate) -> Void
    private let onChooseFile: () -> Void
    private var applicationRows: [RunningApplicationRow] = []

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
        layer?.backgroundColor = SettingsStyle.pickerBackground.cgColor

        let title = NSTextField(labelWithString: "正在运行的应用")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = SettingsStyle.pickerText
        title.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "\(applications.count) 个")
        count.font = .systemFont(ofSize: 11, weight: .medium)
        count.textColor = SettingsStyle.pickerSecondaryText
        count.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeApplicationsScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let chooseFile = NSButton(title: "选择应用文件...", target: self, action: #selector(chooseFileClicked))
        chooseFile.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        chooseFile.imagePosition = .imageLeading
        chooseFile.bezelStyle = .rounded
        chooseFile.controlSize = .large
        chooseFile.translatesAutoresizingMaskIntoConstraints = false

        addSubview(title)
        addSubview(count)
        addSubview(scrollView)
        addSubview(chooseFile)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            count.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            count.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: chooseFile.topAnchor, constant: -10),

            chooseFile.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chooseFile.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            chooseFile.widthAnchor.constraint(equalToConstant: 142),
            chooseFile.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func makeApplicationsScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        if applications.isEmpty {
            let empty = NSTextField(labelWithString: "没有可添加的前台应用")
            empty.font = .systemFont(ofSize: 12, weight: .medium)
            empty.textColor = SettingsStyle.pickerSecondaryText
            empty.alignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            document.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                empty.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                empty.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
                empty.heightAnchor.constraint(equalToConstant: 44),
                empty.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -12)
            ])
        } else {
            var previousBottom = document.topAnchor
            var isFirstRow = true
            for application in applications {
                let row = RunningApplicationRow(application: application, onSelect: onSelect)
                row.onHover = { [weak self] hoveredRow in
                    guard let self else { return }
                    for candidate in applicationRows where candidate !== hoveredRow {
                        candidate.setHighlighted(false)
                    }
                    hoveredRow.setHighlighted(true)
                }
                row.onHoverEnd = { endedRow in
                    endedRow.setHighlighted(false)
                }
                applicationRows.append(row)
                document.addSubview(row)
                NSLayoutConstraint.activate([
                    row.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                    row.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
                    row.topAnchor.constraint(equalTo: previousBottom, constant: isFirstRow ? 2 : 5)
                ])
                previousBottom = row.bottomAnchor
                isFirstRow = false
            }
            previousBottom.constraint(equalTo: document.bottomAnchor, constant: -2).isActive = true
        }

        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    @objc private func chooseFileClicked() {
        onChooseFile()
    }
}

final class RunningApplicationRow: NSView {
    private enum Style {
        static let background = NSColor.clear
        static let hoverBackground = NSColor.controlAccentColor.withAlphaComponent(0.16)
        static let pressedBackground = NSColor.controlAccentColor.withAlphaComponent(0.28)
    }

    private let application: RunningApplicationCandidate
    private let onSelect: (RunningApplicationCandidate) -> Void
    var onHover: ((RunningApplicationRow) -> Void)?
    var onHoverEnd: ((RunningApplicationRow) -> Void)?
    private var trackingArea: NSTrackingArea?

    init(application: RunningApplicationCandidate, onSelect: @escaping (RunningApplicationCandidate) -> Void) {
        self.application = application
        self.onSelect = onSelect
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = (highlighted ? Style.hoverBackground : Style.background).cgColor
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = Style.background.cgColor
        layer?.cornerRadius = 8
        toolTip = application.bundleID
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 38).isActive = true

        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: appPathForBundleID(application.bundleID) ?? "")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let label = NSTextField(labelWithAttributedString: NSAttributedString(
            string: application.appName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: SettingsStyle.runningRowText,
                .paragraphStyle: paragraph
            ]
        ))
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(self)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?(self)
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Style.pressedBackground.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            onHover?(self)
        }

        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect(application)
    }
}

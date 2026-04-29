import AppKit
import Foundation

@MainActor
final class AppMonitor {
    private var observer: NSObjectProtocol?
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let onActivate: (NSRunningApplication) -> Void

    private(set) var lastExternalApplication: NSRunningApplication?

    init(onActivate: @escaping (NSRunningApplication) -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self.handleActivation(app)
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            handleActivation(app)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func handleActivation(_ app: NSRunningApplication) {
        if app.bundleIdentifier != ownBundleID {
            lastExternalApplication = app
        }
        onActivate(app)
    }
}

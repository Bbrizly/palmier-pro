import AppKit
import SwiftUI

@MainActor
enum FilmStudioIntegration {
    static func installMenuItem() {
        guard let viewMenu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.title == L10n.string("View") })?
            .submenu
        else { return }

        let action = #selector(FilmStudioWindowController.showFromMenu(_:))
        guard !viewMenu.items.contains(where: { $0.action == action }) else { return }

        viewMenu.addItem(.separator())
        let item = NSMenuItem(title: "Film Studio…", action: action, keyEquivalent: "")
        item.target = FilmStudioWindowController.shared
        viewMenu.addItem(item)
    }
}

@MainActor
struct FilmStudioPalmierBridge {
    func importPlayableCut(using model: PalmierFilmStudioModel) {
        guard let editor = AppState.shared.activeProject?.editorViewModel else {
            model.errorMessage = PalmierFilmStudioModel.StudioError.noPalmierProject.localizedDescription
            return
        }
        model.importPlayableCut(into: editor)
    }
}

@MainActor
final class FilmStudioWindowController: NSWindowController {
    static let shared = FilmStudioWindowController(window: nil)

    private let model = PalmierFilmStudioModel()
    private let bridge = FilmStudioPalmierBridge()
    private var hostingController: NSHostingController<FilmStudioWorkspaceView>?

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func showFromMenu(_ sender: Any?) {
        show()
    }

    func show() {
        let rootView = FilmStudioWorkspaceView(model: model, bridge: bridge)

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Palmier Film Studio"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1_100, height: 760))
            window.minSize = NSSize(width: 980, height: 660)
            window.isReleasedWhenClosed = false
            window.center()
            self.hostingController = hostingController
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

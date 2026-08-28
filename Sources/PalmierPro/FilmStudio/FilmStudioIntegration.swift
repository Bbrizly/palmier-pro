import AppKit
import SwiftUI

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
    static let shared = FilmStudioWindowController()

    private let model: PalmierFilmStudioModel

    private init() {
        let model = PalmierFilmStudioModel()
        self.model = model
        let rootView = FilmStudioWorkspaceView(
            model: model,
            bridge: FilmStudioPalmierBridge()
        )
        .appLocalization()
        .tint(AppTheme.Accent.primary)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Palmier Film Studio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(AppTheme.Window.settingsDefault)
        window.minSize = AppTheme.Window.settingsMin
        window.backgroundColor = AppTheme.Background.base
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        model.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

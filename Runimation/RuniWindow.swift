import AuthenticationServices
import CoreUI
import RunKit
import RunUI
import RuniTransfer
import SwiftData
import SwiftUI
import VisualiserUI
#if os(iOS)
import UIKit
#endif

/// Per-window root view.
///
/// Owns the `NavigationModel` (navigation scope registry), `RunPlayer`, and
/// `NowPlayingModel`, and sets up the full environment chain for its subtree.
/// Platform-specific layout lives in `content`: `NavigationSplitView` on Mac/iPad,
/// `NavigationStack` + sheets on iPhone.
///
/// Two instances exist on macOS: the main persistent window (`autoRestore: true`)
/// and the runi-viewer window (`autoRestore: false`). On iOS there is only one.
///
struct RuniWindow: View {

    let library: RunLibrary

    let modelContainer: ModelContainer

    @State
    private var player: RunPlayer

    @State
    private var nowPlaying: NowPlayingModel

    @State
    private var navigationModel: NavigationModel

    @State
    private var visualiserPhoto = VisualiserPhotoHolder()

    #if os(macOS)
    @Environment(WindowCoordinator.self)
    private var windowCoordinator

    @Environment(\.controlActiveState)
    private var controlActiveState
    #endif

    #if os(iOS)
    @State
    private var presentationAnchor: ASPresentationAnchor? = nil
    #endif

    init(
        library: RunLibrary,
        modelContainer: ModelContainer,
        autoRestore: Bool
    ) {
        let player = RunPlayer(transformers: [GuassianRun()])
        let nowPlaying = NowPlayingModel(
            context: modelContainer.mainContext,
            markAsPlaying: { item in library.markAsPlaying(item) }
        )
        let navigation = NavigationModel(autoRestore: autoRestore)
        navigation.register(PlayerNavigation())
        navigation.register(LibraryNavigation())
        navigation.register(ExportNavigation())
        navigation.register(ImportNavigation())

        self.library = library
        self.modelContainer = modelContainer
        self._player = State(initialValue: player)
        self._nowPlaying = State(initialValue: nowPlaying)
        self._navigationModel = State(initialValue: navigation)
    }

    // MARK: - Body

    var body: some View {
        RuniView()
            .nowPlaying(nowPlaying)
            .library(library)
            .transfer(library: library)
            .player(player)
            .environment(navigationModel)
            .visualiserPhoto(visualiserPhoto)
            .modelContainer(modelContainer)
            #if os(macOS)
            .onChange(of: controlActiveState, initial: true) { _, state in
                if state == .key {
                    windowCoordinator.activeNavigationModel = navigationModel
                    windowCoordinator.activePlayer = player
                    windowCoordinator.activeNowPlaying = nowPlaying
                    windowCoordinator.activeVisualiserPhoto = visualiserPhoto
                }
            }
            #endif
            #if os(iOS)
            .background(WindowAnchorReader { anchor in presentationAnchor = anchor })
            .environment(\.presentationAnchor, presentationAnchor)
            #endif
    }
}

// MARK: - iOS Window Reader

#if os(iOS)
/// Captures the `UIWindow` containing this view and reports it via `onCapture`.
///
/// Used to inject the presentation anchor for `ASWebAuthenticationSession`
/// into the SwiftUI environment without UIKit dependencies in leaf views.
///
private struct WindowAnchorReader: UIViewRepresentable {

    let onCapture: @MainActor (UIWindow) -> Void

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let window = uiView.window else { return }
        Task { @MainActor in onCapture(window) }
    }
}
#endif

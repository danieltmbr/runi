import CoreUI
import RunKit
import SwiftUI
import VisualiserUI

/// App-level coordinator that tracks whichever `RuniWindow` is currently key.
///
/// Each `RuniWindow` writes its per-window state here when it becomes the key
/// window. The `CustomisationWindow` reads from it directly — bypassing the
/// `@FocusedValue` mechanism, which cannot cross SwiftUI scene boundaries.
///
/// Injected into all scenes via `.environment(windowCoordinator)` in `RuniApp`.
///
@MainActor
@Observable
final class WindowCoordinator {
    var activeNavigationModel: NavigationModel?
    var activePlayer: RunPlayer?
    var activeNowPlaying: NowPlayingModel?
    var activeVisualiserPhoto: VisualiserPhotoHolder?
}

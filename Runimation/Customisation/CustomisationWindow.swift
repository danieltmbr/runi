#if os(macOS)
import CoreUI
import RunKit
import RunUI
import SwiftUI
import VisualiserUI

/// macOS floating window that tracks whichever player window is currently key.
///
/// Reads the active window state from `WindowCoordinator`, which is updated
/// by `RuniWindow` whenever it becomes the key window. This bypasses `@FocusedValue`,
/// which cannot cross SwiftUI scene boundaries (the Customisation window lives in a
/// separate `Window` scene from the main `WindowGroup`).
///
struct CustomisationWindow: View {

    @Environment(WindowCoordinator.self)
    private var coordinator

    var body: some View {
        Group {
            if let nav = coordinator.activeNavigationModel,
               let player = coordinator.activePlayer,
               let nowPlaying = coordinator.activeNowPlaying,
               let visualiserPhoto = coordinator.activeVisualiserPhoto {
                VStack {
                    CustomisationPanel()
                        .padding()
                    Spacer()
                }
                .player(player)
                .environment(nowPlaying)
                .environment(nav)
                .visualiserPhoto(visualiserPhoto)
            } else {
                ContentUnavailableView(
                    "No Window Selected",
                    systemImage: "macwindow",
                    description: Text("Focus a run window to customise it.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.thinMaterial)
        .containerBackground(.clear, for: .window)
    }
}
#endif

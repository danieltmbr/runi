import RunKit
import RunUI
import SwiftUI
import VisualiserUI

struct VisualiserView: View {

    @NowPlaying
    private var nowPlaying

    var body: some View {
        PlayerDrivenView(visualisation: nowPlaying.visualisation)
            .ignoresSafeArea()
    }
}

// MARK: - Player-Driven View

/// Bridges `RunPlayer` state into `VisualiserCanvas` at 60 fps.
///
/// Kept as a separate named struct so only this view's body re-renders at the
/// animation frame rate — `VisualiserView` and the panel remain unaffected.
///
private struct PlayerDrivenView: View {

    @Player(\.segment.animation)
    private var segment

    @Player(\.progress.animation)
    private var progress

    @Player(\.run.animation)
    private var run

    @Player(\.duration)
    private var duration

    var visualisation: Binding<any Visualisation>

    var body: some View {
        VisualiserCanvas(
            state: VisualiserState(
                averageHeartRate: Float(run.averages.heartRate),
                averageSpeed: Float(run.averages.speed),
                coordinates: SIMD2(Float(segment.coordinate.x), Float(segment.coordinate.y)),
                direction: SIMD2(Float(segment.direction.x), Float(segment.direction.y)),
                elevation: Float(segment.elevation),
                heartRate: Float(segment.heartRate),
                path: run.coordinates.map { SIMD2(Float($0.x), Float($0.y)) },
                speed: Float(segment.speed),
                time: Float(progress * duration)
            ),
            visualisation: visualisation
        )
    }
}

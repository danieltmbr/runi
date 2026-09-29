import SwiftUI
import CoreUI

// MARK: - FormAdjustable Conformance

extension Voronoi: FormAdjustable {

    @MainActor
    public func form(for binding: Binding<Voronoi>) -> some View {
        VoronoiForm(value: binding)
    }
}

// MARK: - Form View

/// Configuration controls for `Voronoi` shown via `AdjustableForm`.
///
/// Photo selection delegated to `VisualiserPhotoPicker`, followed by sliders
/// for the grid size and the max / min radius of the density increase.
///
private struct VoronoiForm: View {

    @Binding
    var value: Voronoi

    var body: some View {
        VisualiserPhotoPicker()

        VStack(alignment: .leading) {
            Text("Grid Size")
                .font(.caption)
            Slider(value: $value.gridSize, in: 1...60, step: 1)
        }

        VStack(alignment: .leading) {
            Text("Max Radius")
                .font(.caption)
            Slider(value: $value.maxRadius, in: 0.1...1.5)
        }

        VStack(alignment: .leading) {
            Text("Min Radius")
                .font(.caption)
            Slider(value: $value.minRadius, in: 0.05...value.maxRadius)
        }
    }
}

import SwiftUI
import CoreUI

// MARK: - FormAdjustable Conformance

extension VoronoiPath: FormAdjustable {

    @MainActor
    public func form(for binding: Binding<VoronoiPath>) -> some View {
        VoronoiPathForm(value: binding)
    }
}

// MARK: - Form View

/// Configuration controls for `VoronoiPath` shown via `AdjustableForm`.
///
/// Photo selection delegated to `VisualiserPhotoPicker`, followed by sliders for
/// the grid size, a segmented density mode picker, the radius of the path band
/// and the max / min radius of the density increase around the runner.
///
private struct VoronoiPathForm: View {

    @Binding
    var value: VoronoiPath

    var body: some View {
        VisualiserPhotoPicker()

        VStack(alignment: .leading) {
            Text("Grid Size")
                .font(.caption)
            Slider(value: $value.gridSize, in: 1...60, step: 1)
        }

        Picker("Density", selection: $value.mode) {
            ForEach(Voronoi.Mode.allCases, id: \.self) { mode in
                Text(mode.formLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading) {
            Text("Path Radius")
                .font(.caption)
            Slider(value: $value.pathRadius, in: 0.02...0.5)
        }

        VStack(alignment: .leading) {
            Text("Runner Max Radius")
                .font(.caption)
            Slider(value: $value.maxRadius, in: 0.1...0.5)
        }

        VStack(alignment: .leading) {
            Text("Runner Min Radius")
                .font(.caption)
            Slider(value: $value.minRadius, in: 0.05...value.maxRadius)
        }
    }
}

// MARK: - Private Mode Labels

private extension Voronoi.Mode {

    var formLabel: String {
        switch self {
        case .fixed:   return "Fixed"
        case .dynamic: return "Dynamic"
        }
    }
}

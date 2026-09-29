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
/// Photo selection delegated to `VisualiserPhotoPicker`, followed by a slider
/// for the grid size, a segmented density mode picker, and sliders for the
/// max / min radius of the density increase. In dynamic mode the radii are
/// the baseline at average effort.
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

        Picker("Density", selection: $value.mode) {
            ForEach(Voronoi.Mode.allCases, id: \.self) { mode in
                Text(mode.formLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)

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

// MARK: - Private Mode Labels

private extension Voronoi.Mode {

    var formLabel: String {
        switch self {
        case .fixed:   return "Fixed"
        case .dynamic: return "Dynamic"
        }
    }
}

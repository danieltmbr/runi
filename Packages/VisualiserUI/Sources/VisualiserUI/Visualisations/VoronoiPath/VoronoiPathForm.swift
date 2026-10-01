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
            Text("Max Radius")
                .font(.caption)
            Slider(value: $value.maxRadius, in: 0.1...0.5)
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

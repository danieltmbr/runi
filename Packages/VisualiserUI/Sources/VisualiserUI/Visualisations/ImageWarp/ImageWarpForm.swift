import SwiftUI
import CoreUI

// MARK: - FormAdjustable Conformance

extension ImageWarp: FormAdjustable {

    @MainActor
    public func form(for binding: Binding<ImageWarp>) -> some View {
        ImageWarpForm(value: binding)
    }
}

// MARK: - Form View

/// Configuration controls for `ImageWarp` shown via `AdjustableForm`.
///
/// Photo selection delegated to `VisualiserPhotoPicker`, followed by a segmented
/// mode picker and sliders for smoothness, details, intensity, and radius.
/// The radius slider is hidden in full-image mode.
///
private struct ImageWarpForm: View {

    @Binding
    var value: ImageWarp

    var body: some View {
        VisualiserPhotoPicker()

        Picker("Mode", selection: $value.mode) {
            ForEach(ImageWarp.Mode.allCases, id: \.self) { mode in
                Text(mode.formLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading) {
            Text("Smoothing")
                .font(.caption)
            Slider(value: $value.smoothness, in: 0...1)
        }

        VStack(alignment: .leading) {
            Text("Details")
                .font(.caption)
            Slider(value: $value.details, in: 1...12, step: 1)
        }

        VStack(alignment: .leading) {
            Text("Intensity")
                .font(.caption)
            Slider(value: $value.intensity, in: 0...1)
        }

        if value.mode != .full {
            VStack(alignment: .leading) {
                Text("Radius")
                    .font(.caption)
                Slider(value: $value.radius, in: 0.05...1.0)
            }
        }
    }
}

// MARK: - Private Mode Labels

private extension ImageWarp.Mode {

    var formLabel: String {
        switch self {
        case .full:     return "Full"
        case .position: return "Position"
        case .path:     return "Path"
        }
    }
}

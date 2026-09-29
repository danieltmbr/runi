import SwiftUI

/// A control for selecting or removing the shared base-layer photo.
///
/// Designed to be embedded in the form of any photo-based visualisation.
/// Reads and writes the `VisualiserPhotoHolder` in the environment; picked
/// photos are downsampled before they are stored. The appearance and
/// interaction mechanism are controlled by `visualiserPhotoPickerStyle(_:)`:
/// - `.form` (default): a captioned form row with a `PhotosPicker` and a remove button
///
/// Requires a `VisualiserPhotoHolder` in the environment via `.visualiserPhoto(_:)`.
///
struct VisualiserPhotoPicker: View {

    @Environment(\.visualiserPhoto)
    private var photoHolder

    @Environment(\.visualiserPhotoPickerStyle)
    private var style

    private let downsampler = PhotoDownsampler()

    var body: some View {
        style.makeBody(configuration: configuration)
    }

    private var configuration: VisualiserPhotoPickerStyleConfiguration {
        VisualiserPhotoPickerStyleConfiguration(photo: photo)
    }

    private var photo: Binding<Data?> {
        Binding(
            get: { photoHolder.data },
            set: { photoHolder.setData($0.flatMap(downsampler.downsample)) }
        )
    }
}

// MARK: - Environment

private struct AnyVisualiserPhotoPickerStyle: @unchecked Sendable {
    private let _makeBody: @MainActor (VisualiserPhotoPickerStyleConfiguration) -> AnyView

    init<S: VisualiserPhotoPickerStyle>(_ style: S) {
        _makeBody = { AnyView(style.makeBody(configuration: $0)) }
    }

    @MainActor
    func makeBody(configuration: VisualiserPhotoPickerStyleConfiguration) -> some View {
        _makeBody(configuration)
    }
}

private struct VisualiserPhotoPickerStyleKey: EnvironmentKey {
    static let defaultValue = AnyVisualiserPhotoPickerStyle(FormVisualiserPhotoPickerStyle())
}

private extension EnvironmentValues {
    var visualiserPhotoPickerStyle: AnyVisualiserPhotoPickerStyle {
        get { self[VisualiserPhotoPickerStyleKey.self] }
        set { self[VisualiserPhotoPickerStyleKey.self] = newValue }
    }
}

extension View {
    func visualiserPhotoPickerStyle<S: VisualiserPhotoPickerStyle>(_ style: S) -> some View {
        environment(\.visualiserPhotoPickerStyle, AnyVisualiserPhotoPickerStyle(style))
    }
}

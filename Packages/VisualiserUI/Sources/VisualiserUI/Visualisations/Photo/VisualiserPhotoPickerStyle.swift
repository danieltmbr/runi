import SwiftUI

/// The data passed from `VisualiserPhotoPicker` to its active style.
///
@MainActor
struct VisualiserPhotoPickerStyleConfiguration {

    /// Raw bytes of the shared base-layer photo; `nil` when no photo is selected.
    /// Write the bytes of a newly picked photo to replace it, or `nil` to remove it.
    ///
    let photo: Binding<Data?>
}

// MARK: - Style Protocol

/// Defines the layout and interaction of a `VisualiserPhotoPicker`.
///
protocol VisualiserPhotoPickerStyle: Sendable {

    typealias Configuration = VisualiserPhotoPickerStyleConfiguration

    associatedtype Body: View

    @MainActor @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

// MARK: - Built-in Style Accessors

extension VisualiserPhotoPickerStyle where Self == FormVisualiserPhotoPickerStyle {
    static var form: FormVisualiserPhotoPickerStyle { .init() }
}

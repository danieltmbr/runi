import Foundation
import SwiftUI

/// Observable store for the transient base-layer photo shared by the
/// photo-based visualisations (`ImageWarp`, `Voronoi`).
///
/// Visualisation configs intentionally exclude photo bytes from their `Codable`
/// representation to keep persisted config small. This holder lives in the
/// environment so both the form (writer, via `VisualiserPhotoPicker`) and the
/// canvas (reader, via `VisualiserPhotoCanvas`) can share the same in-memory
/// photo without going through the JSON binding round-trip.
///
/// Inject one instance per window from `RuniWindow` using `.visualiserPhoto(_:)`.
///
@Observable
public final class VisualiserPhotoHolder {

    /// Raw image bytes of the currently selected photo. `nil` when no photo has been chosen.
    public private(set) var data: Data?

    /// Incremented whenever `data` changes; acts as an O(1) change token for `.task(id:)`.
    public private(set) var version: UUID = UUID()

    public init() {}

    /// Replaces the stored photo and bumps `version` so observers notice the change.
    public func setData(_ data: Data?) {
        self.data    = data
        self.version = UUID()
    }
}

// MARK: - Environment Key

private struct VisualiserPhotoHolderKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = VisualiserPhotoHolder()
}

public extension EnvironmentValues {
    var visualiserPhoto: VisualiserPhotoHolder {
        get { self[VisualiserPhotoHolderKey.self] }
        set { self[VisualiserPhotoHolderKey.self] = newValue }
    }
}

// MARK: - View Modifier

public extension View {
    /// Injects a `VisualiserPhotoHolder` into the environment.
    func visualiserPhoto(_ holder: VisualiserPhotoHolder) -> some View {
        environment(\.visualiserPhoto, holder)
    }
}

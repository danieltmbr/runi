import Foundation
import SwiftUI

/// Observable store for the transient photo selected by `ImageWarpForm`.
///
/// `ImageWarp.Codable` intentionally excludes photo bytes to keep persisted
/// config small. This holder lives in the environment so both the form (writer)
/// and the canvas view (reader) can share the same in-memory photo without going
/// through the JSON binding round-trip.
///
/// Inject one instance per window from `RuniWindow` using `.environment(imageWarpPhoto)`.
///
@Observable
public final class ImageWarpPhotoHolder {

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

private struct ImageWarpPhotoHolderKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = ImageWarpPhotoHolder()
}

public extension EnvironmentValues {
    var imageWarpPhoto: ImageWarpPhotoHolder {
        get { self[ImageWarpPhotoHolderKey.self] }
        set { self[ImageWarpPhotoHolderKey.self] = newValue }
    }
}

// MARK: - View Modifier

public extension View {
    /// Injects an `ImageWarpPhotoHolder` into the environment.
    func imageWarpPhoto(_ holder: ImageWarpPhotoHolder) -> some View {
        environment(\.imageWarpPhoto, holder)
    }
}

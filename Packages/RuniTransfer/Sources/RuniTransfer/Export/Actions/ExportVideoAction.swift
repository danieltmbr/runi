import Foundation
import RunKit
import VisualiserUI

/// Renders a run's animation to an `.mp4` file, fully independent of the player.
///
/// Loads track data and config from the library if not already present,
/// reconstructs the transformer + interpolator pipeline from stored config,
/// and renders via `VideoRenderer`. Safe to call for any run, including
/// tracker runs that have never been played.
///
/// Inject via `.transfer(library:)` and access in views with:
/// ```swift
/// @Environment(\.exportVideo) private var exportVideo
/// let url = try await exportVideo(item, config: config) { progress in ... }
/// ```
///
public struct ExportVideoAction {

    public typealias ProgressHandler = @Sendable (Double) -> Void

    private let body: @MainActor (RunItem, VideoExportConfig, @escaping ProgressHandler) async throws -> URL

    public init(_ body: @escaping @MainActor (RunItem, VideoExportConfig, @escaping ProgressHandler) async throws -> URL) {
        self.body = body
    }

    public init() {
        self.init { _, _, _ in throw UnboundError() }
    }

    @MainActor
    public init(library: RunLibrary) {
        self.init { item, config, onProgress in
            let loaded = try await library.load(item, with: [.run, .config])
            guard let rawRun = loaded.run else { throw ResolutionError() }

            let transformers = loaded.loadTransformersConfig()
            let interpolator = loaded.loadInterpolatorConfig() ?? LinearRunInterpolator()
            let duration = loaded.loadDurationConfig() ?? 30
            let visualisation = loaded.loadVisualisationConfig() ?? Warp()
            let timing = RunPlayer.Timing(duration: duration, fps: 30)

            let processed = transformers.reduce(rawRun) { $0.transform(by: $1) }
            let normalised = processed
                .transform(by: .normalised)
                .interpolate(by: interpolator, with: timing)

            return try await Task.detached(priority: .userInitiated) {
                try await VideoRenderer().render(
                    run: normalised,
                    duration: duration,
                    config: config,
                    visualisation: visualisation,
                    onProgress: onProgress
                )
            }.value
        }
    }

    @MainActor
    public func callAsFunction(
        _ item: RunItem,
        config: VideoExportConfig,
        onProgress: @escaping ProgressHandler
    ) async throws -> URL {
        try await body(item, config, onProgress)
    }

    // MARK: - Errors

    private struct UnboundError: LocalizedError {
        var errorDescription: String? { "No export action is available in the current environment." }
    }

    private struct ResolutionError: LocalizedError {
        var errorDescription: String? { "The run could not be found in the library." }
    }
}

import CoreTransferable
import RunKit
import SwiftUI
import UniformTypeIdentifiers
import VisualiserUI

/// Sheet presenting two export options for any run entry.
///
/// - **Runi file (.runi)** — loads track data if needed, encodes the run + config as
///   a few-kB JSON file, then opens the system share sheet.
/// - **Video (.mp4)** — loads + processes the run through its stored transformer /
///   interpolator pipeline, renders via `VideoRenderer`, shows a progress bar while
///   rendering, then opens the share sheet automatically when done.
///
/// Requires `@Environment(\.exportRuni)` and `@Environment(\.exportVideo)` (injected
/// by `.transfer(library:)`).
///
public struct ExportSheet: View {

    // MARK: - Environment

    @Environment(\.exportRuni)
    private var exportRuni

    @Environment(\.exportVideo)
    private var exportVideo

    @Environment(\.displayScale)
    private var displayScale

    @Environment(\.visualiserPhoto)
    private var photoHolder

    // MARK: - Runi Export State

    @State
    private var isLoadingRuni = false

    @State
    private var runiDocument: RuniDocument?

    @State
    private var runiError: Error?

    // MARK: - Video Export State

    @State
    private var isRenderingVideo = false

    @State
    private var videoProgress: Double = 0

    @State
    private var renderedVideoURL: URL?

    @State
    private var renderError: Error?

    // MARK: - Input

    let run: RunItem
    let viewportSize: CGSize

    public init(run: RunItem, viewportSize: CGSize) {
        self.run = run
        self.viewportSize = viewportSize
    }

    private var resolution: CGSize {
        CGSize(
            width: viewportSize.width * displayScale,
            height: viewportSize.height * displayScale
        )
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            title

            VStack(spacing: 12) {
                runiSection
                videoSection
            }
        }
        .padding(24)
        .frame(minWidth: 280)
        .presentationCompactAdaptation(.sheet)
    }

    // MARK: - Subviews

    private var title: some View {
        Text("Share as…")
            .font(.title2.bold())
    }

    @ViewBuilder
    private var runiSection: some View {
        if isLoadingRuni {
            loadingProgress(label: "Preparing Runi file…", icon: "doc.badge.arrow.up")
        } else if let doc = runiDocument {
            ShareLink(
                item: doc,
                preview: SharePreview(doc.name, image: Image(systemName: "figure.run"))
            ) {
                ExportOptionRow(icon: "doc.badge.checkmark", title: "Runi File", subtitle: "Tap to share")
            }
            .buttonStyle(.plain)
        } else {
            Button { startRuniExport() } label: {
                ExportOptionRow(
                    icon: "doc.badge.arrow.up",
                    title: "Runi File",
                    subtitle: runiError == nil ? "A few kB · plays back in Runimation" : "Export failed — tap to retry"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if isRenderingVideo {
            loadingProgress(label: "Rendering video…", icon: "video", progress: videoProgress)
        } else if let url = renderedVideoURL {
            ShareLink(
                item: RenderedVideo(url: url),
                preview: SharePreview(run.name, image: Image(systemName: "video"))
            ) {
                ExportOptionRow(icon: "video.badge.checkmark", title: "Video", subtitle: "Tap to share the rendered video")
            }
            .buttonStyle(.plain)
        } else {
            Button { startVideoExport() } label: {
                ExportOptionRow(
                    icon: "video",
                    title: "Video (.mp4)",
                    subtitle: renderError.map { "\($0.localizedDescription) Tap to retry." } ?? "Renders offline — takes a few seconds"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func loadingProgress(label: String, icon: String, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon).font(.headline)
            if let progress {
                ProgressView(value: progress).progressViewStyle(.linear)
                Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Runi Export

    private func startRuniExport() {
        isLoadingRuni = true
        runiDocument = nil
        runiError = nil
        Task {
            do {
                runiDocument = try await exportRuni(run)
                isLoadingRuni = false
            } catch {
                isLoadingRuni = false
                runiError = error
            }
        }
    }

    // MARK: - Video Export

    private func startVideoExport() {
        isRenderingVideo = true
        videoProgress = 0
        renderedVideoURL = nil
        renderError = nil
        let config = VideoExportConfig(resolution: resolution, logicalSize: viewportSize, photo: photoHolder.data)
        Task {
            do {
                let url = try await exportVideo(run, config: config) { @Sendable progress in
                    Task { @MainActor in videoProgress = progress }
                }
                isRenderingVideo = false
                renderedVideoURL = url
            } catch {
                isRenderingVideo = false
                renderError = error
            }
        }
    }
}

// MARK: - Rendered Video

private struct RenderedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { video in
            SentTransferredFile(video.url)
        }
    }
}

// MARK: - Export Option Row

private struct ExportOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

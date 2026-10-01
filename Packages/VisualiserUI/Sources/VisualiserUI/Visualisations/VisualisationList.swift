import SwiftUI
import CoreUI

/// Full-screen selection list of available visualisations.
///
/// Tapping an item updates the binding and dismisses back to the panel.
///
public struct VisualisationList: View {

    private let visualisation: Binding<any Visualisation>

    private static let catalog: [Item<any Visualisation>] = [
        Item(value: Warp() as any Visualisation),
        Item(value: ImageWarp() as any Visualisation),
        Item(value: RunPath() as any Visualisation),
        Item(value: Gradients() as any Visualisation),
        Item(value: Voronoi() as any Visualisation),
        Item(value: VoronoiPath() as any Visualisation),
    ]

    public init(visualisation: Binding<any Visualisation>) {
        self.visualisation = visualisation
    }

    public var body: some View {
        SelectionList(
            items: Self.catalog,
            selection: Binding(
                get: { Self.catalog.first { $0.value.label == visualisation.wrappedValue.label } ?? Self.catalog[0] },
                set: { visualisation.wrappedValue = $0.value }
            )
        )
        .navigationTitle("Visualisation")
    }
}

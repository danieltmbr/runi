import SwiftUI
import CoreUI

// MARK: - FormAdjustable Conformance

extension Warp: FormAdjustable {
    
    @MainActor
    public func form(for binding: Binding<Warp>) -> some View {
        WarpForm(value: binding)
    }
}

// MARK: - Form View

/// Configuration controls for `Warp` shown via `AdjustableForm`.
///
/// Sliders for smoothness and detail; palette editing delegated to `ColorPalettePicker`.
///
private struct WarpForm: View {
    
    @Binding
    var value: Warp
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Smoothing")
                .font(.caption)
            Slider(value: $value.smoothness, in: 0...1)
        }
        
        VStack(alignment: .leading) {
            Text("Details")
                .font(.caption)
            Slider(value: $value.details, in: 1...12)
        }
        
        ColorPalettePicker(palette: $value.palette)
    }
}

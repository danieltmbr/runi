import CoreUI
import SwiftUI
import RunUI

struct CustomisationToggle: View {

    @Environment(\.openWindow)
    private var openWindow

    @Navigation(\.player.showCustomisation)
    private var showCustomisation: Bool
    
    var body: some View {
        Button {
#if os(macOS)
            openWindow(id: "customisation")
#else
            showCustomisation.toggle()
#endif
        } label: {
            Label("Customise", systemImage: "slider.horizontal.3")
                .padding(10)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .foregroundStyle(.primary)
        .contentShape(Circle())
    }
}

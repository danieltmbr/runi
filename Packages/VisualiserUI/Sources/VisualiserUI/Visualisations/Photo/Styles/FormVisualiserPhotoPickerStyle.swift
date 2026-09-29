import PhotosUI
import SwiftUI

/// The default photo picker style — a captioned form row with a `PhotosPicker`
/// and a remove button that appears once a photo is selected.
///
struct FormVisualiserPhotoPickerStyle: VisualiserPhotoPickerStyle {

    func makeBody(configuration: Configuration) -> some View {
        FormVisualiserPhotoPickerView(configuration: configuration)
    }
}

private struct FormVisualiserPhotoPickerView: View {

    let configuration: VisualiserPhotoPickerStyleConfiguration

    @State
    private var selectedItem: PhotosPickerItem?

    var body: some View {
        let hasPhoto = configuration.photo.wrappedValue != nil

        VStack(alignment: .leading, spacing: 8) {
            Text("Photo")
                .font(.caption)

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        hasPhoto ? "Change Photo" : "Select Photo",
                        systemImage: "photo"
                    )
                    .font(.caption)
                }

                Spacer()

                if hasPhoto {
                    Button("Remove") {
                        selectedItem = nil
                        configuration.photo.wrappedValue = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: selectedItem) {
            guard let item = selectedItem,
                  let data = try? await item.loadTransferable(type: Data.self)
            else { return }
            configuration.photo.wrappedValue = data
        }
    }
}

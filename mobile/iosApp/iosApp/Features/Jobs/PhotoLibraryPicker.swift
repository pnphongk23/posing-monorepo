import PhotosUI
import SwiftUI

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedImageData: Data?
    @Binding var selectedFileName: String?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                return
            }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let self, let image = object as? UIImage else { return }
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                        // Downscale and prepare JPEG data (max side 2048px, q=0.85)
                        let downscaled = self.downscale(image: image, maxDimension: 2048)
                        let jpegData = downscaled.jpegData(compressionQuality: 0.85)
                        self.parent.selectedImageData = jpegData
                        self.parent.selectedFileName = "pose_\(UUID().uuidString).jpg"
                    }
                }
            }
        }

        private func downscale(image: UIImage, maxDimension: CGFloat) -> UIImage {
            let size = image.size
            if size.width <= maxDimension && size.height <= maxDimension {
                return image
            }
            let ratio = min(maxDimension / size.width, maxDimension / size.height)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
}

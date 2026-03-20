// BottleScannerView.swift
// BarrelBook
//
// Camera sheet that captures a bottle label photo, runs on-device OCR via Vision,
// and returns parsed ScannedBottleData. Photo is never saved to the camera roll.
// To remove this feature: delete this file + LabelParser.swift + the // MARK: Bottle Scanner
// block in AddWhiskeyView.swift.

import SwiftUI
import UIKit

// MARK: - Public sheet view

struct BottleScannerView: View {
    @Binding var isPresented: Bool
    let onResult: (ScannedBottleData) -> Void

    @State private var isProcessing = false

    var body: some View {
        if isProcessing {
            scanningOverlay
        } else {
            CameraPickerRepresentable(
                onCapture: { image in
                    isProcessing = true
                    LabelParser.parse(from: image) { data in
                        isPresented = false
                        onResult(data)
                    }
                },
                onCancel: {
                    isPresented = false
                }
            )
        }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Reading label…")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - UIImagePickerController wrapper

private struct CameraPickerRepresentable: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        // allowsEditing = false: we want the raw image, not a crop
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Use .originalImage — photo is held in memory only, never written to camera roll
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

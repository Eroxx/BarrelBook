// BottleScannerView.swift
// BarrelBook
//
// Photo-based label scanner.
// User takes a photo of the front label; Vision OCR + Apple Intelligence extracts bottle details.
// No photo is saved to the camera roll.
//
// To remove this feature: delete this file + LabelParser.swift + the
// MARK: Bottle Scanner blocks in AddWhiskeyView.swift.

import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

// MARK: - Scan state machine

private enum ScanState {
    case idle                           // tip screen or no-camera fallback
    case preview(UIImage)               // show captured photo before processing
    case processing                     // analyzing the photo
    case results(ScannedBottleData)
    case failed                         // OCR found nothing useful
}

// MARK: - Main view

struct BottleScannerView: View {
    @Binding var isPresented: Bool
    var onSaveAndScanNext: ((ScannedBottleData) -> Void)? = nil
    let onResult: (ScannedBottleData) -> Void

    @State private var scanState: ScanState = .idle
    @State private var showingCamera: Bool = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @AppStorage("bb_hasSeenScannerTip") private var hasSeenScannerTip = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack {
            // Solid backdrop — prevents AddWhiskeyView from ever showing through
            Color.black.ignoresSafeArea()

            switch scanState {
            case .idle:
                idleView
            case .preview(let image):
                photoPreviewView(image: image)
            case .processing:
                processingView
            case .results(let data):
                ScanResultView(
                    data: data,
                    onApply: { finalData in
                        isPresented = false
                        onResult(finalData)
                    },
                    onSaveAndScanNext: onSaveAndScanNext.map { callback in
                        { finalData in
                            callback(finalData)
                            scanState = .idle
                        }
                    },
                    onRetake: {
                        scanState = .idle
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
            case .failed:
                failedView
            }
        }
        // Camera is a fullScreenCover — dismisses cleanly without disturbing the sheet
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerRepresentable(
                onCapture: { image in
                    showingCamera = false
                    scanState = .preview(image)     // show preview before analyzing
                },
                onCancel: {
                    showingCamera = false
                    // Stay on Ready to Scan / tip so user can choose Take Photo or Library
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoPickerItem) { newItem in
            guard let newItem else { return }
            hasSeenScannerTip = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        photoPickerItem = nil
                        scanState = .preview(image)
                    }
                } else {
                    await MainActor.run {
                        photoPickerItem = nil
                    }
                }
            }
        }
    }

    // MARK: - Idle view

    @ViewBuilder
    private var idleView: some View {
        if !hasSeenScannerTip {
            tipView
        } else {
            // Simulator / no camera — library still works
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: cameraAvailable ? "camera.viewfinder" : "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.6))
                    Text(cameraAvailable ? "Ready to Scan" : "Camera not available")
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if cameraAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(14)
                        }
                    }
                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(14)
                    }
                    Button("Close") { isPresented = false }
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - First-use tip

    private var tipView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 20)
                    Spacer()
                }

                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundColor(.white)

                    Text("Scan a Bottle Label")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Take a photo of the **front label** in good light — or pick one from your library. BarrelBook will identify the name, type, proof, age, and cask finish.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    if cameraAvailable {
                        Button {
                            hasSeenScannerTip = true
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(14)
                        }
                    }

                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundColor(cameraAvailable ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(cameraAvailable ? Color.white.opacity(0.18) : Color.white)
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
    }

    // MARK: - Photo preview (confirm before analyzing)

    @ViewBuilder
    private func photoPreviewView(image: UIImage) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Gradient + buttons
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)

                HStack(spacing: 16) {
                    Button {
                        scanState = .idle
                    } label: {
                        Text(cameraAvailable ? "Retake" : "Choose Again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(14)
                    }

                    Button {
                        analyzePhoto(image)
                    } label: {
                        Text("Use Photo")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
                .background(Color.black.opacity(0.85))
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Processing view

    private var processingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.8)
                Group {
                    if #available(iOS 26.0, *) {
                        Text("Identifying with Apple Intelligence…")
                    } else {
                        Text("Analyzing label…")
                    }
                }
                .font(.callout)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Failed view

    private var failedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.45))

                VStack(spacing: 8) {
                    Text("Couldn't Read This Label")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    Text("Try moving closer, adjusting the angle,\nor shooting in better lighting.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    if cameraAvailable {
                        Button {
                            scanState = .idle
                            showingCamera = true
                        } label: {
                            Label("Try Again", systemImage: "camera.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(14)
                        }
                    }

                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundColor(cameraAvailable ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(cameraAvailable ? Color.white.opacity(0.18) : Color.white)
                            .cornerRadius(14)
                    }

                    Button("Cancel") { isPresented = false }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Analyze captured photo

    private func analyzePhoto(_ image: UIImage) {
        scanState = .processing
        LabelParser.parse(from: image) { data in
            if data.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                scanState = .failed
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                scanState = .results(data)
            }
        }
    }
}

// MARK: - Results view

private struct ScanResultView: View {
    let data: ScannedBottleData
    let onApply: (ScannedBottleData) -> Void
    var onSaveAndScanNext: ((ScannedBottleData) -> Void)? = nil
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var selectedName: String
    @State private var editedType: String
    @State private var editedProof: String
    @State private var editedAge: String
    @State private var editedFinish: String
    @State private var editedIsBiB: Bool
    @State private var editedIsSiB: Bool

    init(data: ScannedBottleData,
         onApply: @escaping (ScannedBottleData) -> Void,
         onSaveAndScanNext: ((ScannedBottleData) -> Void)? = nil,
         onRetake: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.data = data
        self.onApply = onApply
        self.onSaveAndScanNext = onSaveAndScanNext
        self.onRetake = onRetake
        self.onCancel = onCancel
        _selectedName  = State(initialValue: data.nameOptions.first ?? "")
        _editedType    = State(initialValue: data.type   ?? "")
        _editedProof   = State(initialValue: data.proof  ?? "")
        _editedAge     = State(initialValue: data.age    ?? "")
        _editedFinish  = State(initialValue: data.finish ?? "")
        _editedIsBiB   = State(initialValue: data.isBiB)
        _editedIsSiB   = State(initialValue: data.isSiB)
    }

    private var trimmedName: String {
        selectedName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Name — editable field; chips are suggestions that seed the field
                    VStack(alignment: .leading, spacing: 10) {
                        Label(data.nameOptions.count > 1 ? "Name — tap a suggestion or type" : "Name",
                              systemImage: "tag")
                            .font(.headline)

                        TextField("Bottle name", text: $selectedName)
                            .font(.subheadline)
                            .submitLabel(.done)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)

                        if !data.nameOptions.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(data.nameOptions, id: \.self) { option in
                                    Button {
                                        selectedName = option
                                    } label: {
                                        Text(option)
                                            .font(.subheadline)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(selectedName == option
                                                ? Color.blue
                                                : Color(UIColor.secondarySystemBackground))
                                            .foregroundColor(selectedName == option ? .white : .primary)
                                            .cornerRadius(20)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(selectedName == option
                                                            ? Color.blue
                                                            : Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Editable detail fields
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Details", systemImage: "square.and.pencil")
                            .font(.headline)

                        editableRow(label: "Type",   value: $editedType,   placeholder: "e.g. Kentucky Straight Bourbon")
                        editableRow(label: "Proof",  value: $editedProof,  placeholder: "e.g. 90")
                        editableRow(label: "Age",    value: $editedAge,    placeholder: "e.g. 10 Year")
                        editableRow(label: "Finish", value: $editedFinish, placeholder: "e.g. Port Wine Cask Finish")

                        Toggle("Bottled in Bond", isOn: $editedIsBiB)
                            .font(.subheadline)
                            .padding(.vertical, 4)
                        Toggle("Single Barrel", isOn: $editedIsSiB)
                            .font(.subheadline)
                            .padding(.vertical, 4)
                    }

                    Divider()

                    Text("Only empty fields in the form will be filled — anything you've already typed stays as-is.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let saveAndScanNext = onSaveAndScanNext {
                        Button {
                            saveAndScanNext(buildFinalData())
                        } label: {
                            Label("Save & Scan Another Bottle", systemImage: "camera.badge.plus")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(10)
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retake") { onRetake() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { onApply(buildFinalData()) }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty && data.nameOptions.isEmpty
                                  && editedType.isEmpty && editedProof.isEmpty
                                  && editedAge.isEmpty && editedFinish.isEmpty
                                  && !editedIsBiB && !editedIsSiB)
                }
                // Keyboard Done button — dismisses keyboard cleanly from any field
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
        }
    }

    private func buildFinalData() -> ScannedBottleData {
        var final = data
        let name = trimmedName
        final.nameOptions = name.isEmpty ? [] : [name]
        final.type   = editedType.trimmingCharacters(in: .whitespaces).isEmpty   ? nil : editedType.trimmingCharacters(in: .whitespaces)
        final.proof  = editedProof.trimmingCharacters(in: .whitespaces).isEmpty  ? nil : editedProof.trimmingCharacters(in: .whitespaces)
        final.age    = editedAge.trimmingCharacters(in: .whitespaces).isEmpty    ? nil : editedAge.trimmingCharacters(in: .whitespaces)
        final.finish = editedFinish.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editedFinish.trimmingCharacters(in: .whitespaces)
        final.isBiB = editedIsBiB
        final.isSiB = editedIsSiB
        return final
    }

    private func editableRow(label: String, value: Binding<String>, placeholder: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: value)
                .font(.subheadline)
                .submitLabel(.done)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// FlowLayout is defined in JournalEntryDetailView.swift and shared across the module.

// MARK: - Camera picker wrapper

private struct CameraPickerRepresentable: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator

        // Add torch toggle overlay if device has a torch
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            let overlay = TorchOverlayView()
            overlay.torchButton.addTarget(
                context.coordinator,
                action: #selector(Coordinator.toggleTorch(_:)),
                for: .touchUpInside
            )
            picker.cameraOverlayView = overlay
            context.coordinator.torchOverlay = overlay
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void
        var torchOverlay: TorchOverlayView?
        private var isTorchOn = false

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        @objc func toggleTorch(_ sender: UIButton) {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            try? device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            device.unlockForConfiguration()
            let icon = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            sender.setImage(UIImage(systemName: icon), for: .normal)
        }

        private func turnOffTorch() {
            guard let device = AVCaptureDevice.default(for: .video),
                  device.hasTorch, device.torchMode == .on else { return }
            try? device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            turnOffTorch()
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            turnOffTorch()
            onCancel()
        }
    }
}

// MARK: - Torch overlay view

private class TorchOverlayView: UIView {

    let torchButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        btn.layer.cornerRadius = 22
        return btn
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(torchButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGFloat = 44
        let margin: CGFloat = 16
        torchButton.frame = CGRect(
            x: bounds.width - size - margin,
            y: safeAreaInsets.top + margin,
            width: size,
            height: size
        )
    }

    // Pass touches through the transparent background to the camera controls underneath
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit == self ? nil : hit
    }
}

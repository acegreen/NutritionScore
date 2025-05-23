import SwiftUI
import AVFoundation
import UIKit
// import Inject

struct BarcodeScannerView: UIViewControllerRepresentable {
    // @ObserveInjection var inject
    @Binding var isScanning: Bool
    @Binding var scannedCode: String
    var onScan: ((String) -> Void)? = nil

    func makeUIViewController(context: Context) -> ScannerViewController {
        let viewController = ScannerViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.isScanning = isScanning
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        let parent: BarcodeScannerView

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func didFind(code: String) {
            parent.scannedCode = code
            parent.onScan?(code)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject {
    func didFind(code: String)
}

class ScannerViewController: UIViewController {
    weak var delegate: ScannerViewControllerDelegate?
    private var isStartingScanning = false
    private var hasInitializedCamera = false

    var isScanning: Bool = true {
        didSet {
            guard oldValue != isScanning else { return }
            if isScanning {
                startScanning()
            } else {
                stopScanning()
            }
        }
    }

    private let captureSession = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let scannerOverlay = UIView()
    private let instructionLabel = UILabel()
    private let controlsStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        checkCameraPermissions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasInitializedCamera {
            checkCameraPermissions()
        } else if !captureSession.isRunning {
            startScanning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            stopScanning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        setupOverlay()
        updateScanRect()
    }
    
    private func startScanning() {
        guard !captureSession.isRunning else { return }
        print("▶️ Starting scanning session")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                print("✅ Scanning session started")
            }
        }
    }

    private func stopScanning() {
        guard captureSession.isRunning else {
            print("⚠️ Scanner already stopped")
            return
        }
        print("⏹️ Stopping scanning session")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                print("✅ Scanning session stopped")
            }
        }
    }

    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("📸 Camera access already authorized")
            setupCamera()
        case .notDetermined:
            print("🔐 Requesting camera access")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        print("✅ Camera access granted")
                        self?.setupCamera()
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Camera access denied or restricted")
            // Optionally show an alert to direct user to Settings
        @unknown default:
            print("❓ Unknown camera authorization status")
        }
    }

    private func setupCamera() {
        guard !hasInitializedCamera else { return }
        hasInitializedCamera = true
        print("🎥 Setting up camera...")
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("❌ No video capture device found")
            return
        }

        // Configure preview layer first
        previewLayer.session = captureSession
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                print("✅ Video input added successfully")
            } else {
                print("❌ Could not add video input")
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                print("✅ Metadata output added successfully")

                // Configure scanning area AFTER adding output
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.ean8, .ean13]

                print("✅ Metadata delegate and types configured")
            } else {
                print("❌ Could not add metadata output")
            }

            print("🎥 Starting capture session...")
            startScanning()

        } catch {
            print("❌ Camera setup error: \(error.localizedDescription)")
        }
    }

    private func setupOverlay() {
        // Get the camera preview frame
        let previewFrame = previewLayer.frame
        
        let overlayHeight = previewFrame.height / 3
        let overlayWidth = previewFrame.width * 0.8

        let verticalOffset: CGFloat = 140

        scannerOverlay.frame = CGRect(
            x: (previewFrame.width - overlayWidth) / 2,
            y: (previewFrame.height - overlayHeight) / 2 - verticalOffset,
            width: overlayWidth,
            height: overlayHeight
        )
        
        // Ensure overlay is added to view
        if scannerOverlay.superview == nil {
            view.addSubview(scannerOverlay)
            
            // Create corner views
            let corners = [
                createCorner(position: .topLeft),
                createCorner(position: .topRight),
                createCorner(position: .bottomLeft),
                createCorner(position: .bottomRight)
            ]
            
            corners.forEach { scannerOverlay.addSubview($0) }
            
            // Add scan line
            let scanLine = UIView()
            scanLine.backgroundColor = UIColor.red
            let lineInset: CGFloat = 30
            scanLine.frame = CGRect(
                x: lineInset,
                y: overlayHeight / 2,
                width: overlayWidth - (lineInset * 2),
                height: 2
            )
            scannerOverlay.addSubview(scanLine)
        }
        
        // Update the scanning area
        if let metadataOutput = captureSession.outputs.first as? AVCaptureMetadataOutput {
            let scanRect = previewLayer.metadataOutputRectConverted(fromLayerRect: scannerOverlay.frame)
            metadataOutput.rectOfInterest = scanRect
        }
    }

    private func updateScanRect() {
        guard let metadataOutput = captureSession.outputs.first as? AVCaptureMetadataOutput else { return }
        let scanRect = previewLayer.metadataOutputRectConverted(
            fromLayerRect: CGRect(
                x: view.bounds.width * 0.1,
                y: view.bounds.height * 0.3,
                width: view.bounds.width * 0.8,
                height: view.bounds.height * 0.4
            )
        )
        guard scanRect.width > 0 && scanRect.height > 0 else {
            print("⚠️ Invalid scan rect dimensions: \(scanRect)")
            return
        }
        metadataOutput.rectOfInterest = scanRect
        print("📐 Scan rect set to: \(scanRect)")
    }

    private func createCorner(position: CornerPosition) -> UIView {
        let corner = UIView()
        let size: CGFloat = 40
        let thickness: CGFloat = 3
        let scanAreaHeight = scannerOverlay.bounds.height

        corner.frame = CGRect(x: 0, y: 0, width: size, height: size)
        corner.backgroundColor = .clear

        // Create the lines for each corner
        let vertical = UIView()
        vertical.backgroundColor = .white
        vertical.frame = CGRect(x: 0, y: 0, width: thickness, height: size)

        let horizontal = UIView()
        horizontal.backgroundColor = .white
        horizontal.frame = CGRect(x: 0, y: 0, width: size, height: thickness)

        switch position {
        case .topLeft:
            corner.frame.origin = CGPoint(x: 0, y: 0)
            // Position lines to create an L-shape pointing right and down
            vertical.frame.origin = CGPoint(x: 0, y: 0)
            horizontal.frame.origin = CGPoint(x: 0, y: 0)
            corner.addSubview(vertical)
            corner.addSubview(horizontal)

        case .topRight:
            corner.frame.origin = CGPoint(x: scannerOverlay.bounds.width - size, y: 0)
            // Position lines to create an L-shape pointing left and down
            vertical.frame.origin = CGPoint(x: size - thickness, y: 0)
            horizontal.frame.origin = CGPoint(x: 0, y: 0)
            corner.addSubview(vertical)
            corner.addSubview(horizontal)

        case .bottomLeft:
            corner.frame.origin = CGPoint(x: 0, y: scannerOverlay.bounds.height - size)
            // Position lines to create an L-shape pointing right and up
            vertical.frame.origin = CGPoint(x: 0, y: 0)
            horizontal.frame.origin = CGPoint(x: 0, y: size - thickness)
            corner.addSubview(vertical)
            corner.addSubview(horizontal)

        case .bottomRight:
            corner.frame.origin = CGPoint(x: scannerOverlay.bounds.width - size, y: scannerOverlay.bounds.height - size)
            // Position lines to create an L-shape pointing left and up
            vertical.frame.origin = CGPoint(x: size - thickness, y: 0)
            horizontal.frame.origin = CGPoint(x: 0, y: size - thickness)
            corner.addSubview(vertical)
            corner.addSubview(horizontal)
        }

        return corner
    }

    private enum CornerPosition {
        case topLeft, topRight, bottomLeft, bottomRight
    }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        print("🔍 Received metadata objects: \(metadataObjects.count)")

        guard isScanning else {
            print("❌ Scanner is not in scanning mode")
            return
        }

        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }

        print("✅ Found barcode: \(stringValue)")
        isScanning = false  // Stop scanning after finding a code
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        delegate?.didFind(code: stringValue)
    }
}

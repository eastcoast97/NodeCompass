import SwiftUI
import VisionKit
import AVFoundation

// MARK: - Barcode Scanner Sheet
//
// Wraps Apple's `DataScannerViewController` (VisionKit, iOS 16+). Recognizes
// EAN-8/13, UPC-A/E, and other 1D barcodes used on packaged foods.
//
// Flow: present as a sheet → user points camera at product → first valid
// barcode triggers OpenFoodFacts lookup → on success, returns BarcodeProduct
// to caller via `onProduct` closure. On failure (not found / network), shows
// inline error and lets user retry or dismiss.

struct BarcodeScannerSheet: View {
    let onProduct: (BarcodeProduct) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var status: Status = .scanning
    @State private var lastBarcode: String?

    enum Status: Equatable {
        case scanning
        case looking(String)        // looking up "<barcode>"
        case notFound(String)       // barcode "<x>" — no match
        case error(String)          // arbitrary error message
        case unavailable            // device or permissions unsupported
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScannerRepresentable(onScan: handleScan)
                        .ignoresSafeArea()

                    overlay
                } else {
                    unavailableState
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if !DataScannerViewController.isSupported {
                status = .unavailable
            }
        }
    }

    // MARK: - Overlay (status messaging on top of camera)

    private var overlay: some View {
        VStack {
            Spacer()

            // Crosshair guide
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.85), lineWidth: 3)
                .frame(width: 280, height: 120)
                .shadow(color: .black.opacity(0.4), radius: 6)

            Spacer()

            // Status pill
            statusPill
                .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch status {
        case .scanning:
            Label("Point at a barcode", systemImage: "barcode.viewfinder")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Capsule())

        case .looking(let code):
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Looking up \(code)…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

        case .notFound(let code):
            VStack(spacing: 8) {
                Label("No match for \(code)", systemImage: "questionmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Text("Try a different angle, or add manually.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Button("Try Again") { resumeScanning() }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(NC.teal, in: Capsule())
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

        case .error(let msg):
            VStack(spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Button("Retry") { resumeScanning() }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(NC.teal, in: Capsule())
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

        case .unavailable:
            EmptyView()
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Barcode scanning unavailable")
                .font(.headline)
            Text("This device doesn't support live barcode scanning. You can still add food manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
    }

    // MARK: - Scan handling

    private func handleScan(_ barcode: String) {
        // Debounce: ignore the same code while we're already looking it up.
        guard barcode != lastBarcode else { return }
        guard case .scanning = status else { return }
        lastBarcode = barcode
        status = .looking(barcode)
        Haptic.light()

        Task {
            do {
                if let product = try await OpenFoodFactsService.shared.lookup(barcode: barcode) {
                    await MainActor.run {
                        Haptic.selection()
                        onProduct(product)
                        dismiss()
                    }
                } else {
                    await MainActor.run { status = .notFound(barcode) }
                }
            } catch {
                await MainActor.run {
                    status = .error(error.localizedDescription)
                }
            }
        }
    }

    private func resumeScanning() {
        lastBarcode = nil
        status = .scanning
    }
}

// MARK: - DataScannerViewController wrapper

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}

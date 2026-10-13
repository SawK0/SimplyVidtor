import Photos

/// Saves exported movies to the photo library (add-only access).
nonisolated enum PhotoSaver {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            String(localized: "SimplyVidtor can’t add to your photo library. Allow it in Settings.")
        }
    }

    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

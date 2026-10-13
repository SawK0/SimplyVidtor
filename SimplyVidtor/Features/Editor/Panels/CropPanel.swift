import SwiftUI

/// Rotate and crop for the selected clip.
struct CropPanel: View {
    let session: EditorSession
    let store: MediaStore
    let onDone: () -> Void

    @State private var croppingClip: Clip?

    var body: some View {
        ToolPanel(title: "Crop", onDone: onDone) {
            if let clip = session.selectedClip {
                controls(for: clip)
            }
        }
        .fullScreenCover(item: $croppingClip) { clip in
            CropEditorView(clip: clip, store: store, onCancel: { croppingClip = nil }) { crop in
                croppingClip = nil
                session.edit { $0.setCrop(crop, ofClip: clip.id) }
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                ToolButton(title: "Rotate", systemImage: "rotate.right") {
                    session.edit { $0.rotateClip(clip.id) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("editor.crop.rotate")
                ToolButton(title: "Crop", systemImage: "crop") { croppingClip = clip }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor.crop.edit")
                ToolButton(title: "Reset", systemImage: "arrow.counterclockwise") {
                    session.edit { $0.resetFraming(ofClip: clip.id) }
                }
                .frame(maxWidth: .infinity)
                .disabled(clip.rotation == 0 && clip.crop == nil)
                .accessibilityIdentifier("editor.crop.reset")
            }
        }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return CropPanel(session: session, store: .temporary(), onDone: {})
        .preferredColorScheme(.dark)
}

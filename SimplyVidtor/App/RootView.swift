import SwiftUI

/// Top-level navigation. Hosts the Projects screen; the editor is presented
/// as a full-screen cover and the picker / export flows as sheets (M0 chunk 3).
struct RootView: View {
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-componentGallery") {
            ComponentGallery()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "SimplyVidtor",
            systemImage: "film.stack",
            description: Text("Projects screen lands in M1.")
        )
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}

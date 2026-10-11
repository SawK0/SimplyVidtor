import SwiftUI

struct RootView: View {
    var body: some View {
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

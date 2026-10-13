import SwiftData
import SwiftUI

@main
struct SimplyVidtorApp: App {
    private static let inMemory: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        #else
        false
        #endif
    }()

    private let container = makeContainer()
    /// A throwaway store with `-inMemoryStore`, so cleanup can't delete real media.
    private let mediaStore = inMemory ? MediaStore.temporary() : .standard
    @State private var motionLibrary = inMemory ? MotionLibrary.temporary() : MotionLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .environment(\.mediaStore, mediaStore)
        .environment(motionLibrary)
    }

    private static func makeContainer() -> ModelContainer {
        do {
            return try AppSchema.container(inMemory: inMemory)
        } catch {
            fatalError("Could not open the project store: \(error)")
        }
    }
}

import SwiftData
import SwiftUI

@main
struct SimplyVidtorApp: App {
    private let container = makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        #else
        let inMemory = false
        #endif
        do {
            return try ModelContainer(
                for: Project.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            fatalError("Could not open the project store: \(error)")
        }
    }
}

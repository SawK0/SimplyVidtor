import SwiftData

enum AppSchema {
    static let models: [any PersistentModel.Type] = [Project.self, AudioAsset.self]

    static func container(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}

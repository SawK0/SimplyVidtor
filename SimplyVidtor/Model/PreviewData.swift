#if DEBUG
import Foundation
import SwiftData

enum PreviewData {
    static func container(withSamples: Bool = true) -> ModelContainer {
        let container = try! AppSchema.container(inMemory: true)
        if withSamples {
            for project in sampleProjects() {
                container.mainContext.insert(project)
            }
        }
        return container
    }

    static func sampleProjects() -> [Project] {
        let samples: [(String, [Double], TimeInterval)] = [
            ("Beach Day", [12, 18, 12], -3_600),
            ("Tokyo Trip", [60, 65, 60], -86_400),
            ("Birthday", [30, 37], -3 * 86_400),
            ("Morning Run", [24], -7 * 86_400),
        ]
        return samples.map { name, durations, age in
            let timeline = Timeline(clips: durations.enumerated().map { index, duration in
                .video(mediaFile: "\(name)-\(index).mov", duration: duration)
            })
            return try! Project(name: name, timeline: timeline, now: .now.addingTimeInterval(age))
        }
    }
}
#endif

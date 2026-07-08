import Foundation
import SwiftData

final class PersistenceController {
    static let shared: PersistenceController = {
        let schema = Schema([
            UserProfile.self,
            Plan.self,
            DayLog.self,
            WorkoutLog.self,
            PhotoEntry.self,
            WorkoutPreset.self
        ])
        // New store file: the legacy 75 Hard store (default.store) is left
        // untouched on disk so old challenge data remains recoverable.
        let url = documentsURL().appendingPathComponent("Fitness.store")
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return PersistenceController(container: container)
    }()

    let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }
}

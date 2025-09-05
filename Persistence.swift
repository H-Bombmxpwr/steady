import Foundation
import SwiftData

final class PersistenceController {
    static let shared: PersistenceController = {
        // Define schema explicitly
        let schema = Schema([
            ChallengeState.self,
            DayEntry.self,
            PhotoEntry.self,
            WorkoutPreset.self
        ])
        // On-device storage
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return PersistenceController(container: container)
    }()

    let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }
}

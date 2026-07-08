import Foundation
import SwiftData

let appGroupID = "group.com.hunter.seventyfivehard"

final class PersistenceController {
    static let shared: PersistenceController = {
        let schema = Schema([
            UserProfile.self,
            Plan.self,
            DayLog.self,
            WorkoutLog.self,
            FoodLog.self,
            PhotoEntry.self,
            WorkoutPreset.self,
            WorkoutScheduleEntry.self,
            Supplement.self
        ])
        let config = ModelConfiguration(schema: schema, url: storeURL())
        let container = try! ModelContainer(for: schema, configurations: [config])
        return PersistenceController(container: container)
    }()

    let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
    }

    /// Store lives in the App Group container so widgets can read/write it.
    /// Falls back to Documents when the group isn't provisioned. A store
    /// already in Documents is migrated (copied) into the group once.
    static func storeURL() -> URL {
        let name = "Fitness.store"
        let documentsStore = documentsURL().appendingPathComponent(name)
        guard let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return documentsStore
        }
        let groupStore = group.appendingPathComponent(name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: groupStore.path), fm.fileExists(atPath: documentsStore.path) {
            for suffix in ["", "-shm", "-wal"] {
                let src = documentsURL().appendingPathComponent(name + suffix)
                let dst = group.appendingPathComponent(name + suffix)
                try? fm.copyItem(at: src, to: dst)
            }
        }
        return groupStore
    }
}

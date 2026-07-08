
import Foundation
import ZIPFoundation

enum ZipService {
    static func exportAll(state: ChallengeState) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportDir = docs.appendingPathComponent("Export_\(Int(Date().timeIntervalSince1970))")
        try? fm.removeItem(at: exportDir)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // JSON snapshot
        let jsonURL = exportDir.appendingPathComponent("challenge.json")
        try JSONExport.dumpJSON(state: state, to: jsonURL)

        // Photos
        let photosDir = docs.appendingPathComponent("Photos")
        if fm.fileExists(atPath: photosDir.path) {
            let dest = exportDir.appendingPathComponent("Photos")
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            let items = try fm.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            for u in items { try fm.copyItem(at: u, to: dest.appendingPathComponent(u.lastPathComponent)) }
        }

        // Zip
        let zipURL = docs.appendingPathComponent("75Hard_Export_\(Int(Date().timeIntervalSince1970)).zip")
        try? fm.removeItem(at: zipURL)
        guard let archive = Archive(url: zipURL, accessMode: .create) else { throw NSError(domain: "zip", code: -1) }
        try archive.addEntry(with: exportDir.lastPathComponent, relativeTo: exportDir.deletingLastPathComponent())
        return zipURL
    }
}

enum JSONExport {
    static func dumpJSON(state: ChallengeState, to url: URL) throws {
        struct DTO: Codable {
            struct DayDTO: Codable {
                let date: Date
                let workout1Minutes: Int
                let workout1Outdoor: Bool
                let workout2Minutes: Int
                let workout2Outdoor: Bool
                let waterOunces: Int
                let pagesRead: Int
                let dietCompliant: Bool
                let alcoholUsed: Bool
                let photos: [String]
            }
            struct PresetDTO: Codable { let name: String; let defaultMinutes: Int; let outdoor: Bool; let notes: String? }
            let createdAt: Date
            let startDate: Date
            let dietName: String
            let totalDays: Int
            let days: [DayDTO]
            let presets: [PresetDTO]
        }
        let dto = DTO(
            createdAt: state.createdAt,
            startDate: state.startDate,
            dietName: state.dietName,
            totalDays: state.totalDays,
            days: state.days.sorted(by: { $0.date < $1.date }).map { d in
                DTO.DayDTO(
                    date: d.date,
                    workout1Minutes: d.workout1Minutes,
                    workout1Outdoor: d.workout1Outdoor,
                    workout2Minutes: d.workout2Minutes,
                    workout2Outdoor: d.workout2Outdoor,
                    waterOunces: d.waterOunces,
                    pagesRead: d.pagesRead,
                    dietCompliant: d.dietCompliant,
                    alcoholUsed: d.alcoholUsed,
                    photos: d.photos.map { $0.filename }
                )
            },
            presets: state.presets.map { DTO.PresetDTO(name: $0.name, defaultMinutes: $0.defaultMinutes, outdoor: $0.outdoor, notes: $0.notes) }
        )
        let data = try JSONEncoder().encode(dto)
        try data.write(to: url)
    }
}

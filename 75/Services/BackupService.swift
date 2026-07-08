//
//  BackupService.swift
//  75
//
//  Created by Hunter Baisden on 9/5/25.
//

import Foundation
import SwiftUI

// Plain codable forms (avoid encoding SwiftData @Model types directly)
struct BackupPayload: Codable {
    struct BPhoto: Codable {
        let filename: String
        let createdAt: Date
        let base64JPEG: String   // embedded photo
    }
    struct BDay: Codable {
        let date: Date
        let workout1Minutes: Int
        let workout1Outdoor: Bool
        let workout2Minutes: Int
        let workout2Outdoor: Bool
        let waterOunces: Int
        let pagesRead: Int
        let dietCompliant: Bool
        let alcoholUsed: Bool
        let weight: Double?
        let photos: [BPhoto]
    }
    struct BPreset: Codable {
        let name: String
        let defaultMinutes: Int
        let outdoor: Bool
        let notes: String?
    }

    // ChallengeState-level
    let createdAt: Date
    let startDate: Date
    let dietName: String
    let dietDescription: String
    let totalDays: Int
    let allowAlcoholMonthly: Bool
    let startingWeight: Double?
    let waterStepOunces: Int

    let days: [BDay]
    let presets: [BPreset]
}

enum BackupService {
    /// Builds a single JSON file containing state, days, presets, and embedded photos.
    static func exportJSON(state: ChallengeState) throws -> URL {
        // Build codable payload
        let sortedDays = state.days.sorted { $0.date < $1.date }

        let bDays: [BackupPayload.BDay] = sortedDays.map { d in
            let photos: [BackupPayload.BPhoto] = d.photos.compactMap { p in
                let url = photosDir().appendingPathComponent(p.filename)
                guard let data = try? Data(contentsOf: url) else { return nil }
                let base64 = data.base64EncodedString()
                return .init(filename: p.filename, createdAt: p.createdAt, base64JPEG: base64)
            }
            return .init(
                date: d.date,
                workout1Minutes: d.workout1Minutes,
                workout1Outdoor: d.workout1Outdoor,
                workout2Minutes: d.workout2Minutes,
                workout2Outdoor: d.workout2Outdoor,
                waterOunces: d.waterOunces,
                pagesRead: d.pagesRead,
                dietCompliant: d.dietCompliant,
                alcoholUsed: d.alcoholUsed,
                weight: d.weight,
                photos: photos
            )
        }

        let bPresets: [BackupPayload.BPreset] = state.presets.map {
            .init(name: $0.name, defaultMinutes: $0.defaultMinutes, outdoor: $0.outdoor, notes: $0.notes)
        }

        let payload = BackupPayload(
            createdAt: state.createdAt,
            startDate: state.startDate,
            dietName: state.dietName,
            dietDescription: state.dietDescription,
            totalDays: state.totalDays,
            allowAlcoholMonthly: state.allowAlcoholMonthly,
            startingWeight: state.startingWeight,
            waterStepOunces: state.waterStepOunces,
            days: bDays,
            presets: bPresets
        )

        // Encode JSON
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(payload)

        // Write to a temp file
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("75hard-\(Int(Date().timeIntervalSince1970)).75hard-backup.json")
        try data.write(to: outURL, options: .atomic)
        return outURL
    }
}

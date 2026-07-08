
import Foundation
import SwiftUI

extension Date {
    func startOfDay() -> Date { Calendar.current.startOfDay(for: self) }
    func days(to other: Date) -> Int { Calendar.current.dateComponents([.day], from: self.startOfDay(), to: other.startOfDay()).day ?? 0 }
}

func ensureDay(plan: Plan, date: Date) -> DayLog {
    if let d = plan.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) { return d }
    let d = DayLog(date: date)
    plan.days.append(d)
    return d
}

func documentsURL() -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! }

func photosDir() -> URL {
    let dir = documentsURL().appendingPathComponent("Photos")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

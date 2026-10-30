import Foundation

/// A saved rate applies only after it was observed. Settling a rate change
/// preserves both the accrued notes and the original offline-cap deadline.
struct RoyaltyJar: Codable, Equatable {
    var since: Date
    var updatedAt: Date
    var accrued: Double = 0
    var rate: Double
    var overnightRate: Double
    var midnight: Date
    var capacityHours: Double = 24

    init(at date: Date, rate: Double, overnightRate: Double, capacityHours: Double = 24) {
        since = date
        updatedAt = date
        self.rate = rate
        self.overnightRate = overnightRate
        self.capacityHours = capacityHours
        midnight = Calendar.current.date(byAdding: .day, value: 1,
                                         to: Calendar.current.startOfDay(for: date))!
    }

    var fullAt: Date { since.addingTimeInterval(capacityHours * 3600) }

    func currentRate(at date: Date) -> Double {
        date < midnight ? rate : overnightRate
    }

    func amount(at date: Date) -> Double {
        let end = min(date, fullAt)
        guard end > updatedAt else { return accrued }
        let daytime = max(0, min(end, midnight).timeIntervalSince(updatedAt))
        let overnight = max(0, end.timeIntervalSince(max(updatedAt, midnight)))
        return accrued + daytime * rate + overnight * overnightRate
    }

    mutating func update(at date: Date, rate: Double, overnightRate: Double) {
        guard date >= updatedAt else { return }
        accrued = amount(at: date)
        updatedAt = date
        self.rate = rate
        self.overnightRate = overnightRate
        midnight = Calendar.current.date(byAdding: .day, value: 1,
                                         to: Calendar.current.startOfDay(for: date))!
    }
}

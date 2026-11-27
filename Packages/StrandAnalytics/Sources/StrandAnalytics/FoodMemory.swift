import Foundation

/// A food as the person corrected it: what the portion they were shown holds, by their own figures. Kept on the device.
public struct LearnedFood: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    /// The portion the figures are for ("150 g", "2 potong"); nil when the estimate named none.
    public var amount: String?
    public var kcal: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var updatedAt: Int
    public var id: String { FoodMemory.key(name) + "|" + FoodMemory.unit(of: amount) }

    public init(name: String, amount: String?, kcal: Double, proteinG: Double?, carbsG: Double?, fatG: Double?, updatedAt: Int) {
        self.name = name; self.amount = amount; self.kcal = kcal; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG; self.updatedAt = updatedAt
    }
}

/// What the app learns from the person's corrections to a food estimate, and how it uses them on the next one. No model is trained and nothing is
/// sent anywhere: a later estimate of the same food has its figures replaced by the person's, scaled to the portion where the two can be compared.
/// It is strict on purpose: a figure is only reused for the same name and the same unit, because a wrong reuse is worse than a fresh estimate. Pure.
public enum FoodMemory {
    /// The most foods kept; the oldest correction goes first.
    public static let limit = 200
    /// How far a learned portion is stretched: past this the two are not the same kind of serving.
    private static let scales = 0.1...10.0

    /// A food's name as compared: lower case, words and numbers only.
    public static func key(_ name: String) -> String {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    /// A portion read as a count and a unit ("150 gram" is 150 and "g", "1/2 piring" is 0.5 and "piring"); nil when it does not open with a number.
    /// A remark in brackets and a leading "about" are not part of it.
    public static func portion(_ amount: String?) -> (count: Double, unit: String)? {
        var s = (amount ?? "").lowercased()
        while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")") { s.removeSubrange(open...close) }
        s = s.trimmingCharacters(in: .whitespaces)
        for lead in ["±", "~", "sekitar ", "kira-kira ", "about ", "approx. ", "approximately "] where s.hasPrefix(lead) {
            s = String(s.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        let number = s.prefix { $0.isNumber || $0 == "." || $0 == "," || $0 == "/" }
        let parts = number.replacingOccurrences(of: ",", with: ".").split(separator: "/", omittingEmptySubsequences: false).map { Double($0) }
        let count: Double?
        switch parts.count {
        case 1: count = parts[0]
        case 2: if let a = parts[0], let b = parts[1], b > 0 { count = a / b } else { count = nil }
        default: count = nil
        }
        guard let count, count > 0, count.isFinite else { return nil }
        let rest = key(String(s.dropFirst(number.count)))
        let same = ["gr": "g", "gram": "g", "grams": "g", "mililiter": "ml", "milliliter": "ml", "millilitre": "ml"]
        return (count, same[rest] ?? rest)
    }

    /// What a portion is measured in, or the whole phrase when it states no number.
    public static func unit(of amount: String?) -> String { portion(amount)?.unit ?? key(amount ?? "") }

    /// The list with a correction in it: one figure per food and unit, the newest first.
    public static func remember(_ food: LearnedFood, in list: [LearnedFood]) -> [LearnedFood] {
        guard !key(food.name).isEmpty, food.kcal >= 0, food.kcal <= 6000 else { return list }
        return Array(([food] + list.filter { $0.id != food.id }).prefix(limit))
    }

    /// The person's figures for an item that was just estimated, scaled to the portion named now; nil when they set none that fits. The name and
    /// the portion stay the new item's.
    public static func figures(for item: AnyaFoodItem, in list: [LearnedFood]) -> AnyaFoodItem? {
        let name = key(item.name), unit = unit(of: item.amount)
        guard let known = list.first(where: { key($0.name) == name && self.unit(of: $0.amount) == unit }) else { return nil }
        var factor = 1.0
        switch (portion(item.amount), portion(known.amount)) {
        case let (now?, then?): factor = now.count / then.count
        case (nil, nil): break
        default: return nil
        }
        guard scales.contains(factor), known.kcal * factor <= 6000 else { return nil }
        func scaled(_ v: Double?) -> Double? { v.map { ($0 * factor * 10).rounded() / 10 } }
        return AnyaFoodItem(name: item.name, amount: item.amount, kcal: (known.kcal * factor).rounded(),
                            proteinG: scaled(known.proteinG), carbsG: scaled(known.carbsG), fatG: scaled(known.fatG))
    }
}

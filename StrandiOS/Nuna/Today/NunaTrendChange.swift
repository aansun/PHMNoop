#if os(iOS)
import SwiftUI
import StrandDesign

/// How a Trend view's average compares with the period before it, for the chip under the average.
enum NunaTrendChange {
    /// The average of the `range` days that end the day before `start` (the window just before the one on show), nil when none of them has a reading.
    static func prior(start: Date, range: Int, _ value: (Date) -> Double?) -> Double? {
        let cal = Calendar.current
        let values = (1...max(range, 1)).compactMap { i in cal.date(byAdding: .day, value: -i, to: start).flatMap(value) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// "vs. prior week" for a week, "vs. prior month" for a month and "vs. prior six months" for six months: the period the switch is on.
    static func label(range: Int) -> String {
        range <= 7 ? String(localized: "vs. prior week") : (range <= 31 ? String(localized: "vs. prior month") : String(localized: "vs. prior six months"))
    }
}

/// "▲ 7% vs. prior month" under the average of a Trend view: the change of the average against the period before, in the period the switch is on.
/// Green when the change is the better way (`upIsGood` says which way that is); grey when it is the other way, when it is the same, and for a
/// figure with no better direction (`upIsGood` nil). Nothing while either period has no readings or the earlier one is zero.
struct NunaChangeChip: View {
    let average: Double?
    let prior: Double?
    let range: Int
    /// Whether a rise is the better way (HRV, sleep), a fall is (resting heart rate, stress), or neither is.
    var upIsGood: Bool?

    var body: some View {
        if let average, let prior, abs(prior) > 0.000_001 {
            let change = (average - prior) / abs(prior) * 100
            let whole = Int(abs(change).rounded())
            let better = whole > 0 && upIsGood.map { (change > 0) == $0 } == true
            let tint = better ? NunaPalette.charge : NunaPalette.textPrimary
            HStack(spacing: 5) {
                Image(systemName: whole == 0 ? "minus" : (change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")).font(.system(size: 9, weight: .heavy))
                Text(verbatim: "\(whole)% " + NunaTrendChange.label(range: range)).font(.nuna(size: 12, weight: .bold)).textCase(nil)
            }
            .foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 4)
            .background(better ? NunaPalette.charge.opacity(0.18) : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(whole)% " + NunaTrendChange.label(range: range)))
        }
    }
}
#endif

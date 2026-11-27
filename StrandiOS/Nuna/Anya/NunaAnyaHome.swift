#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What Anya's button on Home shows: the day's figures, worked out on this iPhone and dated, and above them a few words from Anya when she is
/// connected and the greeting is on. The words are kept until the figures change, so opening the button again asks nothing of the provider.
@MainActor
enum NunaAnyaHome {
    static let greetingKey = "anya.homeGreeting"
    private static let cacheKey = "anya.homeGreeting.cache"
    /// Raised when what she is asked for changes, so a greeting kept under the old wording is not shown again.
    private static let wording = "2"

    /// On unless the person turned it off in Anya settings.
    static var greets: Bool { UserDefaults.standard.object(forKey: greetingKey) as? Bool ?? true }

    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let value: String
        var note: String?
    }

    struct Summary: Equatable {
        /// Set when today has no readings yet: which day the latest are from.
        var stale: String?
        var rows: [Row] = []
        /// The same figures as the provider is told them.
        var told: String = ""
    }

    private static func day(_ key: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    static func summary(repo: Repository, profile: ProfileStore, now: Date = Date()) async -> Summary {
        let model = NunaTodayModel()
        await model.load(repo: repo, profile: profile)
        let today = Repository.localDayKey(now)
        let days = repo.days
        let scale = AICoachEngine.strainScale()
        var out = Summary()
        var told: [String] = []

        let scored = days.last { $0.recovery != nil }
        let todayRow = days.last { $0.day == today }
        let hasToday = todayRow.map { $0.recovery != nil || $0.totalSleepMin != nil } ?? false
        if !hasToday, let newest = days.last(where: { $0.recovery != nil || $0.totalSleepMin != nil }) {
            out.stale = String(localized: "No readings for today yet. The latest are from \(day(newest.day)).")
            told.append("There are no readings for today (\(today)) yet; the newest are from \(newest.day).")
        }

        // Recovery, with its own date when it is not today's, beside the 30-day average the rest of the app and Anya's data quote.
        if let scored, let value = scored.recovery {
            let month = days.suffix(30).compactMap(\.recovery)
            let usual = month.isEmpty ? nil : Int((month.reduce(0, +) / Double(month.count)).rounded())
            var note: [String] = []
            if scored.day != today { note.append(day(scored.day)) }
            if let usual { note.append(String(localized: "30-day average \(usual)%")) }
            out.rows.append(Row(id: "recovery", title: "Recovery", value: "\(Int(value.rounded()))%", note: note.joined(separator: " · ")))
            told.append("Recovery \(Int(value.rounded()))% on \(scored.day)" + (usual.map { ", 30-day average \($0)%" } ?? "") + ".")
        }

        if let night = days.last(where: { $0.totalSleepMin != nil }), let minutes = night.totalSleepMin {
            var note = night.day == today ? nil : day(night.day)
            if let hrv = night.avgHrv { note = [note, "HRV \(Int(hrv.rounded())) ms"].compactMap { $0 }.joined(separator: " · ") }
            out.rows.append(Row(id: "sleep", title: "Sleep", value: NunaAnyaReader.hm(minutes), note: note))
            told.append(String(format: "Last night with a reading: %@, slept %.1f hours", night.day, minutes / 60)
                        + (night.avgHrv.map { ", HRV \(Int($0.rounded())) ms" } ?? "") + (night.restingHr.map { ", resting HR \($0)" } ?? "") + ".")
        }

        // Strain is today's own: nothing is carried over from another day.
        let plan = await NunaDayPlanResult.load(repo: repo, profile: profile)
        let band = CoupledView.optimalStrainRange(recovery: hasToday ? plan.map { Double($0.charge) } : nil)
        let strain = hasToday ? model.effort : nil
        let range = band.map { "\(UnitFormatter.effortDisplay(Double($0.lowerBound), scale: scale))–\(UnitFormatter.effortDisplay(Double($0.upperBound), scale: scale))" }
        out.rows.append(Row(id: "strain", title: "Strain", value: strain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–",
                            note: range.map { String(localized: "Aim for \($0) today") }))
        told.append("Strain so far today " + (strain.map { AICoachEngine.strainText($0) } ?? "none recorded") + (range.map { ", range for today \($0)" } ?? "") + ".")

        if let plan {
            let from = hasToday ? nil : scored.map { String(localized: "From Recovery on \(day($0.day))") }
            out.rows.append(Row(id: "session", title: String(localized: "Suggested session"), value: plan.title, note: from))
            told.append("Suggested session: \(plan.plan.kind.rawValue), \(plan.plan.totalMinutes) minutes" + (hasToday ? "." : " (worked out from older readings)."))
        }

        let need = SleepModel.debtNeedMin(days: days)
        let ledger = SleepDebt.ledger(series: days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: need / 60)
        if need > 0, let mid = await repo.habitualMidsleepSec() {
            let bed = AnyaDayContext.clock(seconds: AnyaDayContext.asleepBySec(midsleepSec: mid, needMin: need))
            let debt = ledger.nightCount > 0 && ledger.magnitudeMin >= 10 ? String(localized: "Sleep debt \(NunaAnyaReader.hm(ledger.magnitudeMin))") : nil
            out.rows.append(Row(id: "bed", title: String(localized: "Asleep tonight by"), value: bed, note: debt))
            told.append("To be asleep tonight by \(bed); sleep need about \(Int((need / 60).rounded())) hours.")
        }
        out.told = told.joined(separator: "\n")
        return out
    }

    // MARK: The greeting

    private struct Cached: Codable { let signature: String; let text: String }

    /// Changes when the figures, the part of the day or who is asked changes.
    private static func signature(_ summary: Summary, coach: AICoachEngine, now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 11 ? "morning" : (hour < 16 ? "midday" : (hour < 20 ? "afternoon" : "night"))
        return [wording, Repository.localDayKey(now), part, coach.provider.rawValue, coach.model,
                UserDefaults.standard.string(forKey: AICoachEngine.responseLanguageKey) ?? "app", AppLanguage.activeLocale.identifier, summary.told].joined(separator: "|")
    }

    static func cachedGreeting(_ summary: Summary, coach: AICoachEngine, now: Date = Date()) -> String? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey), let kept = try? JSONDecoder().decode(Cached.self, from: data),
              kept.signature == signature(summary, coach: coach, now: now) else { return nil }
        return kept.text
    }

    /// The greeting for these figures: the kept one, or a new one from the provider. nil when greeting is off or nothing came back.
    static func greeting(_ summary: Summary, coach: AICoachEngine, now: Date = Date()) async -> String? {
        guard greets, coach.isConfigured, coach.dataConsent, !summary.rows.isEmpty else { return nil }
        if let kept = cachedGreeting(summary, coach: coach, now: now) { return kept }
        let asked = signature(summary, coach: coach, now: now)
        guard let text = await coach.homeGreeting(summary: summary.told) else { return nil }
        if let data = try? JSONEncoder().encode(Cached(signature: asked, text: text)) { UserDefaults.standard.set(data, forKey: cacheKey) }
        return text
    }
}

/// The day's figures as rows, on the dark ground of Anya's sheet.
struct NunaAnyaHomeCard: View {
    let summary: NunaAnyaHome.Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stale = summary.stale {
                Text(verbatim: stale).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.warning)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.vertical, 12)
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            ForEach(Array(summary.rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row.title).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75)).textCase(nil)
                        if let note = row.note, !note.isEmpty {
                            Text(verbatim: note).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5)).textCase(nil).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 10)
                    Text(verbatim: row.value).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(.white)
                        .multilineTextAlignment(.trailing).textCase(nil)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif

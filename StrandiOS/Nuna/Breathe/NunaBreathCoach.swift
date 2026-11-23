#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Anya after a breathing session: she reads the session's own numbers (heart rate, HRV and, when the strap read enough, stress) and says
/// what they mean in a warm, supportive way, and she notices when the same exercise keeps coming back and offers to keep it as a favourite.
enum NunaBreathCoach {
    struct Insight: Equatable {
        let headline: String
        let detail: String?
    }

    /// The saved session behind a "Breathwork" activity row: the one that started at the same second.
    static func record(for row: WorkoutRow) -> NunaBreathRecord? {
        guard row.sport == NunaBreathRecovery.sport else { return nil }
        return NunaBreathLog.all().first { $0.startTs == row.startTs }
    }

    // MARK: The reading

    /// How far stress moved through the session (the last readings against the first, on the 0 to 3 scale); nil without enough readings.
    static func stressChange(_ points: [NunaWorkoutStress.Point]) -> Double? {
        guard points.count >= 3 else { return nil }
        let edge = max(1, min(3, points.count / 3))
        func mean(_ p: ArraySlice<NunaWorkoutStress.Point>) -> Double { p.map(\.level).reduce(0, +) / Double(p.count) }
        return mean(points.suffix(edge)) - mean(points.prefix(edge))
    }

    /// What the session did, in Anya's voice. `stress` is the stress series of the session when it has one.
    static func insight(for r: NunaBreathRecord, stress: [NunaWorkoutStress.Point] = [], heartRate: [Double] = [], all: [NunaBreathRecord] = NunaBreathLog.all(), now: Date = Date()) -> Insight {
        // Resonance and Calm me keep no heart-rate series of their own: the strap's readings over the session stand in for them.
        func mean(_ v: ArraySlice<Double>) -> Double { v.reduce(0, +) / Double(v.count) }
        let fromStrap = heartRate.count >= 6
        let hrFirst = r.hrStart ?? (fromStrap ? mean(heartRate.prefix(3)) : nil)
        let hrLast = r.hrEnd ?? (fromStrap ? mean(heartRate.suffix(3)) : nil)
        let hrDrop: (Int, Int)? = {
            guard let a = hrFirst, let b = hrLast, a - b >= 3 else { return nil }
            return (Int(a.rounded()), Int(b.rounded()))
        }()
        let pct = r.rmssdChangePct
        let hrvUp = (pct ?? 0) >= 10
        let calmer = (stressChange(stress) ?? 0) <= -0.2
        let hasHeart = hrFirst != nil || r.rmssdStart != nil || !stress.isEmpty

        var detail: [String] = []
        let headline: String
        if hrvUp || calmer || hrDrop != nil {
            headline = String(localized: "Nice breathing today. It helped you relax.")
            if calmer { detail.append(String(localized: "Your stress went down through the session.")) }
            if let (a, b) = hrDrop { detail.append(String(localized: "Your heart rate came down from \(a) to \(b) bpm.")) }
            if hrvUp, let p = pct { detail.append(String(localized: "Your HRV rose \(Int(p.rounded()))%.")) }
            detail.append(String(localized: "Keep it up regularly: a few calm minutes a day add up."))
        } else if let p = pct, p <= -10 {
            headline = String(localized: "Good effort. Your HRV dipped a little this time.")
            detail.append(String(localized: "That can happen with focus or energising techniques, or when you were already calm. A longer out-breath tends to lift it. Nothing to worry about."))
        } else if hasHeart {
            headline = String(localized: "Well done for making time to breathe.")
            detail.append(String(localized: "Your numbers stayed close to where they began. Short sessions often change little. Try a slower out-breath next time, and keep at it regularly."))
        } else {
            headline = String(localized: "Well done for pausing to breathe.")
            detail.append(String(localized: "I did not get heart readings this time, so I cannot say how much it helped. Wear the strap snug next time and I will read it with you."))
        }
        // A rhythm worth naming: the second session or more inside the week.
        let weekStart = Int(now.timeIntervalSince1970) - 7 * 86_400
        let thisWeek = Set(all.filter { $0.startTs >= weekStart }.map(\.id)).union([r.id]).count
        if thisWeek >= 2 { detail.append(String(localized: "That is your \(thisWeek) breathing session this week. A lovely rhythm.")) }
        return Insight(headline: headline, detail: detail.joined(separator: " "))
    }

    // MARK: Favourites

    private static let dismissedKey = "nuna.breath.favoriteOfferDismissed.v1"
    /// How many times the same exercise has to come back, in the last 30 days, before Anya offers to keep it.
    static let repeatsForOffer = 3

    /// The Explore item a session was of: a ready exercise, Resonance or Calm me. An exercise Anya made is already kept, so it has none.
    static func itemId(for r: NunaBreathRecord) -> String? {
        if let t = r.templateId { return "t-" + t }
        switch r.protocolId {
        case NunaBreathKind.resonanceId: return "k-" + NunaBreathTool.resonance.rawValue
        case NunaBreathKind.calmMeId: return "k-" + NunaBreathTool.calmMe.rawValue
        default: return nil
        }
    }

    private static func dismissed() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }

    static func dismissOffer(_ id: String) {
        var d = dismissed(); d.insert(id)
        UserDefaults.standard.set(Array(d), forKey: dismissedKey)
    }

    struct Offer: Equatable {
        let item: NunaBreathItem
        let times: Int
    }

    /// The exercise of this session, when it has been done `repeatsForOffer` times or more in 30 days and is not a favourite yet nor was turned down.
    static func offer(for r: NunaBreathRecord, all: [NunaBreathRecord] = NunaBreathLog.all()) -> Offer? {
        guard let id = itemId(for: r), !NunaBreathFavorites.contains(id), !dismissed().contains(id),
              let item = NunaBreathGroup.allItems.first(where: { $0.id == id }) else { return nil }
        let from = r.startTs - 30 * 86_400
        let same = Set(all.filter { $0.startTs >= from && itemId(for: $0) == id }.map(\.id)).union([r.id])
        return same.count >= repeatsForOffer ? Offer(item: item, times: same.count) : nil
    }
}

/// Anya's line after a session, kept as simple as on every other page: one slim row with her short reading. Her fuller words (what the heart rate, HRV
/// and stress did, and the encouragement) are in the sheet the row opens.
struct NunaBreathInsightCard: View {
    let insight: NunaBreathCoach.Insight
    let onAnya: () -> Void

    var body: some View {
        NunaAnyaCard(verbatim: insight.headline, detail: insight.detail, action: onAnya)
            .environment(\.nunaAnyaRow, true)
            .environment(\.nunaAnyaCardContext, "Breathing")
    }
}

/// Anya offering to keep an exercise the wearer keeps coming back to: one tap adds it to the favourites (My Exercises); "Not now" is remembered so she asks once.
struct NunaBreathFavoriteOffer: View {
    let offer: NunaBreathCoach.Offer
    @State private var added = false
    @State private var gone = false

    private static let wing = [Color(red: 0.44, green: 0.90, blue: 0.83), Color(red: 0.15, green: 0.65, blue: 0.62), Color(red: 0.11, green: 0.56, blue: 0.53)]

    var body: some View {
        if !gone {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(LinearGradient(colors: Self.wing, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                        AnyaMark(size: 19)
                    }
                    .frame(width: 34, height: 34).accessibilityHidden(true)
                    Text(verbatim: added
                         ? String(localized: "Added to your favorites. Find it under My Exercises.")
                         : String(localized: "You have done \(offer.item.title) \(offer.times) times lately. Want to keep it as a favorite? It will sit under My Exercises, one tap away."))
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                if !added {
                    HStack(spacing: 10) {
                        Button {
                            if !NunaBreathFavorites.contains(offer.item.id) { NunaBreathFavorites.toggle(offer.item.id) }
                            withAnimation(.easeInOut(duration: 0.2)) { added = true }
                        } label: {
                            Label("Add to favorites", systemImage: "heart.fill")
                                .font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                                .padding(.horizontal, 18).frame(height: 42)
                                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain)
                        Button {
                            NunaBreathCoach.dismissOffer(offer.item.id)
                            withAnimation(.easeInOut(duration: 0.2)) { gone = true }
                        } label: {
                            Text("Not now").font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                                .padding(.horizontal, 14).frame(height: 42)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: Self.wing, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
        }
    }
}
#endif

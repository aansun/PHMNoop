#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Daily Outlook: a card under "My Day" that opens Anya on a fuller version of the daily brief (how the night and Recovery set the
/// day, and three things worth doing about it, picked from what the person actually logs). It only appears once there are enough days
/// of data to know the person's habits.
enum NunaOutlookGate {
    /// Days with something recorded before the Outlook opens. Ten days is the earliest it can tell habits from chance.
    static let minDays = 10
    static let openedKey = "nuna.outlook.opened"
    /// The day the Outlook was last opened: the card is in colour until then, and grey for the rest of that day.
    static let seenDayKey = "nuna.outlook.seenDay"
    /// The ideas committed to, as JSON, so a screen that reads it through `@AppStorage` follows the changes.
    static let plannedKey = "nuna.outlook.planned"

    static func dataDays(_ days: [DailyMetric]) -> Int {
        days.filter { $0.recovery != nil || ($0.totalSleepMin ?? 0) > 0 || ($0.strain ?? 0) > 0 }.count
    }

    static func ready(_ days: [DailyMetric]) -> Bool {
#if DEBUG
        // `--demo-outlook=off` / `=on` forces the Outlook shut or open, since the demo year always has enough days.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-outlook=") }) { return arg.hasSuffix("on") }
#endif
        return dataDays(days) >= minDays
    }

    static func decode(_ raw: String) -> [NunaPlannedActivity] {
        (try? JSONDecoder().decode([NunaPlannedActivity].self, from: Data(raw.utf8))) ?? []
    }

    /// What was committed to on a day (today by default).
    static func planned(_ raw: String? = nil, on day: String = Repository.localDayKey(Date())) -> [NunaPlannedActivity] {
        decode(raw ?? UserDefaults.standard.string(forKey: plannedKey) ?? "").filter { $0.day == day }
    }

    static func committed(on day: String = Repository.localDayKey(Date())) -> Set<String> { Set(planned(on: day).map(\.ideaID)) }

    private static func save(_ items: [NunaPlannedActivity]) {
        let data = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        UserDefaults.standard.set(data, forKey: plannedKey)
    }

    /// Commits to an idea for today. Earlier days are dropped on the way, so the list never grows.
    static func commit(_ idea: NunaOutlookIdea, on day: String = Repository.localDayKey(Date())) {
        var items = planned(on: day)
        guard !items.contains(where: { $0.ideaID == idea.id }) else { return }
        items.append(NunaPlannedActivity(day: day, ideaID: idea.id, sport: idea.sport, title: idea.title, card: idea.card, minutes: idea.minutes, strain: idea.strain))
        save(items)
    }

    static func remove(_ item: NunaPlannedActivity) { save(planned(on: item.day).filter { $0.ideaID != item.ideaID }) }
}

/// An idea the person committed to: it shows in today's activities until it is added, started or removed.
struct NunaPlannedActivity: Codable, Identifiable, Equatable {
    let day: String
    let ideaID: String
    let sport: String
    let title: String
    let card: String
    let minutes: Int
    /// The Strain it should add, on the 0 to 21 scale (shown through `effortDisplay` after turning it into the stored 0 to 100).
    let strain: Double
    var id: String { day + "|" + ideaID }

    var intensity: String { strain < 7 ? String(localized: "Low") : (strain < 12 ? String(localized: "Moderate") : String(localized: "High")) }
}

/// One thing the Outlook suggests for today.
struct NunaOutlookIdea: Identifiable, Equatable {
    let id: String
    /// The sport label the icon is picked by.
    let sport: String
    let title: String
    let emoji: String
    /// After the dash in the list.
    let line: String
    /// The body of its card.
    let card: String
    let minutes: Int
    /// The Strain it should add, on the raw 0 to 21 scale.
    let strain: Double
}

struct NunaOutlook: Equatable {
    var greeting: String
    /// Light markdown (bold figures).
    var paragraph: String
    var ideas: [NunaOutlookIdea]
    var closing: String
}

struct NunaOutlookInputs {
    var charge: Double?
    var hrv: Double?
    var sleepMinutes: Double?
    var sleepNeedMin: Double
    /// How many times each idea's activity was logged lately, by idea id.
    var logged: [String: Int] = [:]
}

/// The words and the picks, from plain numbers so the rules read (and test) without the app around them.
enum NunaOutlookEngine {
    private struct Spec {
        let id: String, sport: String, title: String, emoji: String
        /// Recovery bands it suits: 0 red, 1 yellow, 2 green.
        let fits: Set<Int>
        let line: [String]
        let logged: String
        /// How long it is suggested for, and the Strain that adds at each band.
        let minutes: Int
        let strain: [Double]
        static func pick(_ a: [String], _ band: Int) -> String { a[min(max(band, 0), a.count - 1)] }
        static func pickValue(_ a: [Double], _ band: Int) -> Double { a[min(max(band, 0), a.count - 1)] }
    }

    private static let specs: [Spec] = [
        .init(id: "walking", sport: "Walking", title: String(localized: "Walking"), emoji: "🚶", fits: [0, 1, 2],
              line: [String(localized: "A slow, easy route keeps you moving without taxing your recovery."),
                     String(localized: "An easy route keeps your overall fitness moving while you keep today's effort comfortable."),
                     String(localized: "A brisk walk adds steady volume at little cost to tomorrow.")],
              logged: String(localized: "an easy route keeps your overall fitness moving."), minutes: 30, strain: [4.5, 5.8, 6.8]),
        .init(id: "yoga", sport: "Yoga", title: String(localized: "Yoga"), emoji: "🧘", fits: [0, 1],
              line: [String(localized: "Gentle yoga loosens you up and eases tension while you recover."),
                     String(localized: "Gentle yoga fits a yellow Recovery and helps you stay loose."),
                     String(localized: "A flowing session keeps you mobile between harder days.")],
              logged: String(localized: "gentle yoga keeps your movement varied."), minutes: 30, strain: [3.0, 3.5, 3.5]),
        .init(id: "strength", sport: "Strength Trainer", title: String(localized: "Strength Trainer"), emoji: "💪", fits: [1, 2],
              line: [String(localized: "Keep it to light mobility work today."),
                     String(localized: "A moderate session builds strength for overall fitness if you're feeling steady."),
                     String(localized: "Your body is ready for a harder session; put your effort into the main lifts.")],
              logged: String(localized: "a session at the right weight builds strength for overall fitness."), minutes: 45, strain: [5.0, 10.5, 13.5]),
        .init(id: "running", sport: "Running", title: String(localized: "Running"), emoji: "🏃", fits: [2],
              line: [String(localized: "Skip the run today."), String(localized: "Keep any run short and easy."),
                     String(localized: "A controlled run in zones 2 to 3 builds your aerobic base while Recovery is high.")],
              logged: String(localized: "a controlled run builds your aerobic base."), minutes: 35, strain: [6.0, 9.0, 12.5]),
        .init(id: "cycling", sport: "Cycling", title: String(localized: "Cycling"), emoji: "🚴", fits: [1, 2],
              line: [String(localized: "Skip the ride today."), String(localized: "An easy spin keeps your legs moving at a low cost."),
                     String(localized: "A steady ride builds endurance with little impact on your joints.")],
              logged: String(localized: "an easy spin keeps your legs moving."), minutes: 40, strain: [6.0, 8.5, 11.0]),
        .init(id: "breathwork", sport: "Meditation", title: String(localized: "Breathwork"), emoji: "🌬️", fits: [0],
              line: [String(localized: "A few minutes of slow breathing helps your body settle after a hard stretch."),
                     String(localized: "Slow breathing takes the edge off the day."), String(localized: "A short session helps you switch off after training.")],
              logged: String(localized: "slow breathing helps your body settle."), minutes: 10, strain: [2.0, 2.0, 2.0]),
    ]

    /// Which idea a logged activity counts toward.
    static func ideaID(forSport sport: String) -> String? {
        let s = sport.lowercased()
        if s.contains("walk") || s.contains("hik") { return "walking" }
        if s.contains("yoga") || s.contains("stretch") || s.contains("pilates") { return "yoga" }
        if s.contains("strength") || s.contains("weight") || s.contains("lift") || s.contains("gym") || s.contains("functional") { return "strength" }
        if s.contains("run") { return "running" }
        if s.contains("cycl") || s.contains("bike") || s.contains("spin") { return "cycling" }
        if s.contains("breath") || s.contains("meditat") { return "breathwork" }
        return nil
    }

    static func band(_ charge: Double?) -> Int? { charge.map { $0 >= 67 ? 2 : ($0 >= 34 ? 1 : 0) } }

    /// Every idea that suits the day, best first: what suits the Recovery band, then what the person logs most.
    private static func ranked(_ i: NunaOutlookInputs) -> [Spec] {
        let b = band(i.charge) ?? 1
        let order = i.logged.sorted { $0.value > $1.value }.map(\.key)
        func score(_ s: Spec) -> Double {
            var v = s.fits.contains(b) ? 10.0 : 0
            if let r = order.firstIndex(of: s.id) { v += max(6 - Double(r), 2) }
            return v
        }
        return specs.enumerated().sorted { a, c in
            let x = score(a.element), y = score(c.element)
            return x != y ? x > y : a.offset < c.offset
        }.map(\.element)
    }

    /// `offset` moves on through the ranking, for "Generate alternatives".
    static func build(_ i: NunaOutlookInputs, offset: Int = 0) -> NunaOutlook {
        let b = band(i.charge)
        let all = ranked(i)
        let n = all.count
        let topLogged = Set(i.logged.sorted { $0.value > $1.value }.prefix(3).map(\.key))
        let picks = (0..<min(3, n)).map { all[((offset % n) + $0) % n] }
        let ideas = picks.map { s -> NunaOutlookIdea in
            let band = b ?? 1
            let card = topLogged.contains(s.id)
                ? String(localized: "\(s.title) is one of your most-logged activities; \(s.logged)")
                : Spec.pick(s.line, band)
            return NunaOutlookIdea(id: s.id, sport: s.sport, title: s.title, emoji: s.emoji, line: Spec.pick(s.line, band), card: card,
                                   minutes: s.minutes, strain: Spec.pickValue(s.strain, band))
        }

        let greeting: String
        switch b {
        case 0: greeting = String(localized: "Easy does it 🌿")
        case 1: greeting = String(localized: "Steady effort 👏")
        case 2: greeting = String(localized: "Strong start 💪")
        default: greeting = String(localized: "Good to see you ☀️")
        }

        var parts: [String] = []
        if let c = i.charge, let b {
            let colour = b == 2 ? String(localized: "green") : (b == 1 ? String(localized: "yellow") : String(localized: "red"))
            let pct = Int(c.rounded())
            let figure = i.hrv.map { String(localized: "**\(pct)% \(colour) Recovery with HRV at \(Int($0.rounded())) ms**") }
                ?? String(localized: "**\(pct)% \(colour) Recovery**")
            let night: String
            if let s = i.sleepMinutes, i.sleepNeedMin > 0 {
                let r = s / i.sleepNeedMin
                night = r >= 0.95 ? String(localized: "after a night of solid sleep")
                    : (r >= 0.8 ? String(localized: "after a night where sleep was decent but not fully topped off")
                       : String(localized: "after a short night of sleep"))
            } else { night = "" }
            parts.append(String(localized: "You woke up to a \(figure)") + (night.isEmpty ? "." : " \(night)."))
            switch b {
            case 0: parts.append(String(localized: "That's a clear signal to keep today light and let your body rebuild."))
            case 1: parts.append(String(localized: "That's a real signal to keep today moderate, and it's good that you're starting with awareness."))
            default: parts.append(String(localized: "That's a strong signal: your body is ready to take on more today."))
            }
        } else {
            parts.append(String(localized: "Recovery isn't scored yet today, so these ideas follow your usual routine and last night's sleep."))
        }
        if let top = i.logged.max(by: { $0.value < $1.value })?.key, let s = specs.first(where: { $0.id == top }) {
            parts.append(String(localized: "\(s.title) is a regular part of your routine, so the ideas below build on it."))
        }
        return NunaOutlook(greeting: greeting, paragraph: parts.joined(separator: " "), ideas: ideas,
                           closing: String(localized: "Let me know what you end up choosing, and I'll help you shape the rest of the day."))
    }

    /// The same read as text, for the provider to build on.
    static func summary(_ o: NunaOutlook) -> String {
        "DAILY OUTLOOK\n" + NunaMark.plain(o.paragraph) + "\nIdeas: " + o.ideas.map { "\($0.title) (\($0.line))" }.joined(separator: "; ")
    }
}

/// Reads what the Outlook is made from, on this iPhone.
enum NunaOutlookLoader {
    @MainActor static func inputs(repo: Repository, profile: ProfileStore) async -> NunaOutlookInputs {
        let m = NunaTodayModel()
        await m.load(repo: repo, profile: profile)
        var logged: [String: Int] = [:]
        for r in await repo.workoutRows(days: 60) {
            if let id = NunaOutlookEngine.ideaID(forSport: r.sport) { logged[id, default: 0] += 1 }
        }
#if DEBUG
        // `--demo-outlook=on` has no logged walks or yoga in the demo year to speak of, so give the habits something to show.
        if CommandLine.arguments.contains("--demo-outlook=on"), logged.isEmpty { logged = ["walking": 9, "strength": 7, "yoga": 4] }
#endif
        return NunaOutlookInputs(charge: m.charge.pct, hrv: m.hrv, sleepMinutes: m.sleepMinutes,
                                 sleepNeedMin: SleepModel.debtNeedMin(days: repo.days), logged: logged)
    }
}

// MARK: - The card under "My Day"

struct NunaDailyOutlookCard: View {
    let action: () -> Void
    @AppStorage(NunaOutlookGate.seenDayKey) private var seenDay = ""

    var body: some View {
        // New today: the brown to blue wash. Once it was opened, it settles into a plain card.
        let seen = seenDay == Repository.localDayKey(Date())
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max").font(.system(size: 22, weight: .light)).foregroundStyle(seen ? NunaPalette.textSecondary : .white.opacity(0.9)).frame(width: 26)
                Text("Daily Outlook").font(.nuna(size: 17, weight: .medium)).foregroundStyle(seen ? NunaPalette.textPrimary : .white).textCase(nil)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(seen ? NunaPalette.textSecondary : .white.opacity(0.9))
            }
            .padding(.horizontal, 18).frame(height: 47).frame(maxWidth: .infinity)
            .background(seen ? AnyShapeStyle(NunaPalette.cardSurface)
                             : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.62, green: 0.54, blue: 0.45), Color(red: 0.38, green: 0.41, blue: 0.47), Color(red: 0.22, green: 0.32, blue: 0.45)],
                                                            startPoint: .leading, endPoint: .trailing)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Daily Outlook"))
    }
}

// MARK: - The Outlook inside Anya's sheet

/// The greeting, the read, the ideas, and the cards to commit to.
struct NunaOutlookContent: View {
    let outlook: NunaOutlook
    /// The provider's own words for the read, when it wrote some; the local paragraph otherwise.
    let provider: String?
    let committed: Set<String>
    let onCommit: (NunaOutlookIdea) -> Void
    let onAlternatives: () -> Void
    @State private var page: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: outlook.greeting).font(.nunaStrong(size: 18))
            if let provider {
                Text(Self.body(provider)).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
            } else {
                Text(Self.body(outlook.paragraph)).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
            }
            Text("Today's activity ideas").font(.nunaStrong(size: 16))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(outlook.ideas) { idea in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: "•").font(.nunaStrong(size: 16))
                        (Text(verbatim: idea.title + " ").font(.nunaStrong(size: 16)) + Text(verbatim: idea.emoji + " – ").font(.nuna(size: 16, weight: .regular))
                            + Text(verbatim: idea.line).font(.nuna(size: 16, weight: .regular)))
                            .lineSpacing(7)
                    }
                }
            }
            Text(verbatim: outlook.closing).font(.nuna(size: 16, weight: .regular)).lineSpacing(7)
            carousel
            Button(action: onAlternatives) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .regular))
                    Text("Generate alternatives").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The markdown of the read, with its bold figures set in the app's own bold (a plain `.font` would flatten them).
    private static func body(_ markdown: String) -> AttributedString {
        var a = NunaAnyaSheet.markdown(markdown)
        for run in a.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            a[run.range].font = .nunaStrong(size: 16)
        }
        return a
    }

    private var carousel: some View {
        VStack(spacing: 18) {
            ScrollView(.horizontal) {
                // Every card as tall as the tallest, so a longer line in one does not leave the others short.
                HStack(spacing: 12) {
                    ForEach(outlook.ideas) { idea in
                        ideaCard(idea).containerRelativeFrame(.horizontal) { w, _ in w - 82 }.id(idea.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned).scrollPosition(id: $page).scrollIndicators(.hidden)
            .onChange(of: outlook.ideas.map(\.id)) { _, _ in page = nil }
            // Bleeds out of the sheet's side margin, as the cards do on the reference.
            .padding(.horizontal, -20)
            HStack(spacing: 14) {
                ForEach(outlook.ideas) { idea in
                    Circle().fill(idea.id == (page ?? outlook.ideas.first?.id) ? Color.white : Color.white.opacity(0.35)).frame(width: 8, height: 8)
                }
            }
        }
    }

    private func ideaCard(_ idea: NunaOutlookIdea) -> some View {
        let done = committed.contains(idea.id)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: sportSymbol(idea.sport)).font(.system(size: 19, weight: .regular)).foregroundStyle(.white)
                    .frame(width: 39, height: 39).background(Color(red: 0.19, green: 0.21, blue: 0.40), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(verbatim: idea.title).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).lineLimit(1)
                Spacer(minLength: 0)
            }
            ZStack(alignment: .topLeading) {
                Text(verbatim: "A\nA\nA").font(.nuna(size: 14, weight: .regular)).lineSpacing(3).hidden().accessibilityHidden(true)
                Text(verbatim: idea.card).font(.nuna(size: 14, weight: .regular)).foregroundStyle(.white.opacity(0.78)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { onCommit(idea) } label: {
                HStack(spacing: 8) {
                    Image(systemName: done ? "checkmark" : "plus").font(.system(size: 15, weight: .semibold))
                    Text(done ? "Committed" : "Commit").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                }
                .foregroundStyle(done ? Color.white : Color(red: 0.03, green: 0.04, blue: 0.07))
                .frame(maxWidth: .infinity).frame(height: 39)
                .background(done ? AnyShapeStyle(NunaOutlookStyle.gradient) : AnyShapeStyle(Color.white), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain).allowsHitTesting(!done)
        }
        .padding(16).frame(maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.27), Color(red: 0.06, green: 0.09, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color(red: 0.30, green: 0.45, blue: 0.72).opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
    }
}

/// The violet to sky blue the Outlook uses for what is committed.
enum NunaOutlookStyle {
    static let violet = Color(red: 0.55, green: 0.38, blue: 0.98)
    static let sky = Color(red: 0.34, green: 0.80, blue: 1.0)
    static var gradient: LinearGradient { LinearGradient(colors: [violet, sky], startPoint: .leading, endPoint: .trailing) }
    static let tile = LinearGradient(colors: [Color(red: 0.31, green: 0.24, blue: 0.55), Color(red: 0.20, green: 0.29, blue: 0.52)], startPoint: .leading, endPoint: .trailing)
}

// MARK: - A committed idea, in today's activities

/// The row of a committed idea: a dashed frame in the Outlook's colours, a tile with the Strain it should add, and what is recommended.
struct NunaPlannedRow: View {
    let plan: NunaPlannedActivity
    let effortScale: EffortScale

    var body: some View {
        HStack(spacing: 12) {
            NunaPlannedTile(plan: plan, effortScale: effortScale)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: plan.title).font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Text(verbatim: String(localized: "Recommended: \(plan.minutes) min")).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).padding(.trailing, 8)
        }
        .padding(.horizontal, 7).padding(.vertical, 8)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.29), Color(red: 0.12, green: 0.25, blue: 0.36)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Color(red: 0.42, green: 0.34, blue: 0.78), Color(red: 0.27, green: 0.55, blue: 0.85)], startPoint: .leading, endPoint: .trailing),
                          style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .contentShape(Rectangle())
    }
}

/// The tile: the activity's icon and the Strain it should add.
struct NunaPlannedTile: View {
    let plan: NunaPlannedActivity
    let effortScale: EffortScale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: sportSymbol(plan.sport)).font(.system(size: 18, weight: .regular)).frame(width: 22)
            Text(verbatim: UnitFormatter.effortDisplay(plan.strain / UnitFormatter.effortScaleFactor, scale: effortScale)).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).foregroundStyle(.white).frame(width: 100, height: 39)
        .background(NunaOutlookStyle.tile, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// What a committed idea opens: its reason, the plan (Strain, duration, intensity), and Add / Start.
struct NunaPlannedSheet: View {
    let plan: NunaPlannedActivity
    let effortScale: EffortScale
    let onAdd: (() -> Void)?
    let onStart: (() -> Void)?
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    private static let ink = Color(red: 0.03, green: 0.04, blue: 0.07)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { onRemove(); dismiss() } label: { Image(systemName: "trash").font(.system(size: 19, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Remove"))
            }
            Text(verbatim: plan.title).font(.nuna(size: 26, weight: .medium)).padding(.top, 8)
            HStack(alignment: .top, spacing: 12) {
                NunaAnyaRing(size: 28).padding(.top, 2)
                Text(verbatim: plan.card).font(.nuna(size: 16, weight: .regular)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 12) {
                    NunaPlannedTile(plan: plan, effortScale: effortScale)
                    Text(verbatim: plan.title).font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).textCase(.uppercase).lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 18) {
                    figure(value: "\(plan.minutes)", unit: String(localized: "min"), label: String(localized: "Duration"), tint: nil)
                    figure(value: plan.intensity, unit: nil, label: String(localized: "Intensity level"), tint: Color(red: 0.35, green: 0.66, blue: 0.90))
                    Spacer(minLength: 0)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NunaOutlookStyle.gradient, lineWidth: 2))
            .padding(.top, 18).padding(.horizontal, 16)
            Spacer(minLength: 16)
            HStack(spacing: 12) {
                if let onAdd {
                    Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onAdd() } } label: {
                        Text("Add").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                            .frame(maxWidth: .infinity).frame(height: 45)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                if let onStart {
                    Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onStart() } } label: {
                        Text("Start").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(Self.ink)
                            .frame(maxWidth: .infinity).frame(height: 45).background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white).textCase(nil)
        .background(LinearGradient(colors: [Color(red: 0.19, green: 0.15, blue: 0.36), Color(red: 0.10, green: 0.25, blue: 0.34), Color(red: 0.06, green: 0.10, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.height(420)]).presentationDragIndicator(.visible)
    }

    private func figure(value: String, unit: String?, label: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold)).foregroundStyle(tint ?? .white)
                if let unit { Text(verbatim: unit).font(.nuna(size: 15, weight: .regular)) }
            }
            Text(verbatim: label).font(.nuna(size: 12.5, weight: .heavy)).tracking(1.1).textCase(.uppercase)
        }
    }
}
#endif

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
    static let committedKey = "nuna.outlook.committed"

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

    /// Ideas the person committed to, as "day|id" entries, read back for today only.
    static func committed(on day: String = Repository.localDayKey(Date())) -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: committedKey) ?? ""
        return Set(raw.split(separator: ",").compactMap { e -> String? in
            let p = e.split(separator: "|", maxSplits: 1)
            return p.count == 2 && String(p[0]) == day ? String(p[1]) : nil
        })
    }

    static func commit(_ id: String, on day: String = Repository.localDayKey(Date())) {
        var entries = (UserDefaults.standard.string(forKey: committedKey) ?? "").split(separator: ",").map(String.init).filter { $0.hasPrefix(day + "|") }
        if !entries.contains("\(day)|\(id)") { entries.append("\(day)|\(id)") }
        UserDefaults.standard.set(entries.joined(separator: ","), forKey: committedKey)
    }
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
        static func pick(_ a: [String], _ band: Int) -> String { a[min(max(band, 0), a.count - 1)] }
    }

    private static let specs: [Spec] = [
        .init(id: "walking", sport: "Walking", title: String(localized: "Walking"), emoji: "🚶", fits: [0, 1, 2],
              line: [String(localized: "A slow, easy route keeps you moving without taxing your recovery."),
                     String(localized: "An easy route keeps your overall fitness moving while you keep today's effort comfortable."),
                     String(localized: "A brisk walk adds steady volume at little cost to tomorrow.")],
              logged: String(localized: "an easy route keeps your overall fitness moving.")),
        .init(id: "yoga", sport: "Yoga", title: String(localized: "Yoga"), emoji: "🧘", fits: [0, 1],
              line: [String(localized: "Gentle yoga loosens you up and eases tension while you recover."),
                     String(localized: "Gentle yoga fits a yellow Recovery and helps you stay loose."),
                     String(localized: "A flowing session keeps you mobile between harder days.")],
              logged: String(localized: "gentle yoga keeps your movement varied.")),
        .init(id: "strength", sport: "Strength Trainer", title: String(localized: "Strength Trainer"), emoji: "💪", fits: [1, 2],
              line: [String(localized: "Keep it to light mobility work today."),
                     String(localized: "A moderate session builds strength for overall fitness if you're feeling steady."),
                     String(localized: "Your body is ready for a harder session; put your effort into the main lifts.")],
              logged: String(localized: "a session at the right weight builds strength for overall fitness.")),
        .init(id: "running", sport: "Running", title: String(localized: "Running"), emoji: "🏃", fits: [2],
              line: [String(localized: "Skip the run today."), String(localized: "Keep any run short and easy."),
                     String(localized: "A controlled run in zones 2 to 3 builds your aerobic base while Recovery is high.")],
              logged: String(localized: "a controlled run builds your aerobic base.")),
        .init(id: "cycling", sport: "Cycling", title: String(localized: "Cycling"), emoji: "🚴", fits: [1, 2],
              line: [String(localized: "Skip the ride today."), String(localized: "An easy spin keeps your legs moving at a low cost."),
                     String(localized: "A steady ride builds endurance with little impact on your joints.")],
              logged: String(localized: "an easy spin keeps your legs moving.")),
        .init(id: "breathwork", sport: "Meditation", title: String(localized: "Breathwork"), emoji: "🌬️", fits: [0],
              line: [String(localized: "A few minutes of slow breathing helps your body settle after a hard stretch."),
                     String(localized: "Slow breathing takes the edge off the day."), String(localized: "A short session helps you switch off after training.")],
              logged: String(localized: "slow breathing helps your body settle.")),
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
            return NunaOutlookIdea(id: s.id, sport: s.sport, title: s.title, emoji: s.emoji, line: Spec.pick(s.line, band), card: card)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "sun.max").font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.9)).frame(width: 26)
                Text("Daily Outlook").font(.nuna(size: 17, weight: .medium)).foregroundStyle(.white).textCase(nil)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18).frame(height: 47).frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color(red: 0.62, green: 0.54, blue: 0.45), Color(red: 0.38, green: 0.41, blue: 0.47), Color(red: 0.22, green: 0.32, blue: 0.45)],
                               startPoint: .leading, endPoint: .trailing),
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
        VStack(alignment: .leading, spacing: 22) {
            Text(verbatim: outlook.greeting).font(.nuna(size: 22, weight: .bold))
            if let provider {
                Text(Self.body(provider)).font(.nuna(size: 20, weight: .regular)).lineSpacing(9)
            } else {
                Text(Self.body(outlook.paragraph)).font(.nuna(size: 20, weight: .regular)).lineSpacing(9)
            }
            Text("Today's activity ideas").font(.nuna(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(outlook.ideas) { idea in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(verbatim: "•").font(.nuna(size: 20, weight: .bold))
                        (Text(verbatim: idea.title + " ").font(.nuna(size: 20, weight: .bold)) + Text(verbatim: idea.emoji + " – ").font(.nuna(size: 20, weight: .regular))
                            + Text(verbatim: idea.line).font(.nuna(size: 20, weight: .regular)))
                            .lineSpacing(9)
                    }
                }
            }
            Text(verbatim: outlook.closing).font(.nuna(size: 20, weight: .regular)).lineSpacing(9)
            carousel
            Button(action: onAlternatives) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 19, weight: .regular))
                    Text("Generate alternatives").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
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
            a[run.range].font = .nuna(size: 20, weight: .bold)
        }
        return a
    }

    private var carousel: some View {
        VStack(spacing: 18) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(outlook.ideas) { idea in
                        ideaCard(idea).containerRelativeFrame(.horizontal) { w, _ in w - 82 }.id(idea.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned).scrollPosition(id: $page).scrollIndicators(.hidden)
            .onChange(of: outlook.ideas.map(\.id)) { _, _ in page = nil }
            // Bleeds out of the sheet's side margin, as the cards do on the reference.
            .padding(.horizontal, -20)
            HStack(spacing: 14) {
                ForEach(outlook.ideas) { idea in
                    Circle().fill(idea.id == (page ?? outlook.ideas.first?.id) ? Color.white : Color.white.opacity(0.35)).frame(width: 9, height: 9)
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
                Text(verbatim: idea.title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).lineLimit(1)
                Spacer(minLength: 0)
            }
            ZStack(alignment: .topLeading) {
                Text(verbatim: "A\nA\nA\nA").font(.nuna(size: 16.5, weight: .regular)).lineSpacing(3).hidden().accessibilityHidden(true)
                Text(verbatim: idea.card).font(.nuna(size: 16.5, weight: .regular)).foregroundStyle(.white.opacity(0.78)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { onCommit(idea) } label: {
                HStack(spacing: 8) {
                    Image(systemName: done ? "checkmark" : "plus").font(.system(size: 16, weight: .semibold))
                    Text(done ? "Committed" : "Commit").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                }
                .foregroundStyle(done ? Color.white : Color(red: 0.03, green: 0.04, blue: 0.07))
                .frame(maxWidth: .infinity).frame(height: 39)
                .background(done ? Color.white.opacity(0.16) : Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain).disabled(done)
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.27), Color(red: 0.06, green: 0.09, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color(red: 0.30, green: 0.45, blue: 0.72).opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What the person asks Anya for when she builds a program: the target, how often and how long, the equipment, the level and their own words.
struct NunaProgramBrief: Equatable {
    enum Goal: String, CaseIterable, Identifiable {
        case muscle, strength, fatLoss, fitness, endurance
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self { case .muscle: "Build muscle"; case .strength: "Get stronger"; case .fatLoss: "Lose fat"; case .fitness: "General fitness"; case .endurance: "Muscular endurance" }
        }
        /// The goal in the words the model is given.
        var words: String {
            switch self {
            case .muscle: return "build muscle (hypertrophy)"
            case .strength: return "get stronger (strength)"
            case .fatLoss: return "lose fat while keeping muscle"
            case .fitness: return "general fitness"
            case .endurance: return "muscular endurance"
            }
        }
    }
    enum Gear: String, CaseIterable, Identifiable {
        case fullGym, dumbbells, bodyweight, homeBarbell
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self { case .fullGym: "Full gym"; case .dumbbells: "Dumbbells only"; case .bodyweight: "Bodyweight only"; case .homeBarbell: "Home: barbell and dumbbells" }
        }
        var words: String {
            switch self {
            case .fullGym: return "a full gym (barbells, dumbbells, cables, machines)"
            case .dumbbells: return "dumbbells and a bench only"
            case .bodyweight: return "no equipment, bodyweight only (a pull-up bar is not available)"
            case .homeBarbell: return "a barbell, a rack, dumbbells and a bench at home; no machines or cables"
            }
        }
    }
    enum Level: String, CaseIterable, Identifiable {
        case beginner, intermediate, advanced
        var id: String { rawValue }
        var title: LocalizedStringKey { switch self { case .beginner: "Beginner"; case .intermediate: "Intermediate"; case .advanced: "Advanced" } }
    }

    var goal: Goal = .muscle
    var days = 4
    var minutes = 60
    var gear: Gear = .fullGym
    var level: Level = .intermediate
    var words = ""

    /// The brief as the model reads it.
    var text: String {
        var s = "Goal: \(goal.words)\nTraining days per week: \(days)\nSession length: \(minutes) minutes\nEquipment: \(gear.words)\nLevel: \(level.rawValue)"
        let extra = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { s += "\nTheir own instructions: \(extra)" }
        return s
    }
}

/// The names Anya gives are put into the library's own, so a program made by her has demos, muscles and history from its first session.
enum NunaAnyaProgramNames {
    /// The library entry for a name: the same words, or the closest exercise when the words overlap enough.
    static func library(for name: String) -> NunaLibraryExercise? {
        NunaExerciseLibrary.matchBundled(name) ?? NunaCustomExercises.closestLibraryExercise(to: name)
    }

    /// The program with each exercise renamed to the library's where there is one. A name the library does not have stays as Anya wrote it,
    /// and is then treated as the person's own exercise (muscles filled in, a page and history like any other).
    static func resolve(_ spec: AnyaProgramSpec) -> AnyaProgramSpec {
        var out = spec
        for d in out.days.indices {
            for i in out.days[d].items.indices {
                if let lib = library(for: out.days[d].items[i].exercise) { out.days[d].items[i].exercise = lib.name }
            }
        }
        return out
    }

    /// The program as plain text, for asking Anya to change it.
    static func text(_ spec: AnyaProgramSpec) -> String {
        var lines = ["Name: \(spec.name)"]
        if let n = spec.note { lines.append("Note: \(n)") }
        for d in spec.days {
            lines.append("\(d.title):")
            for it in d.items {
                let reps = it.repsLow.map { lo in it.repsHigh.map { $0 == lo ? "\(lo)" : "\(lo)-\($0)" } ?? "\(lo)" } ?? "?"
                lines.append("- \(it.exercise): \(it.sets ?? 3) x \(reps), rest \(it.restSec ?? 90) s")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// "Program with Anya": fill in the target and the instructions, Anya builds the program (from the person's own training, the equipment and the
/// time they have), the person checks it, asks for changes in their own words, and saves each day as a program under "Anya special".
struct NunaAnyaProgramBuilder: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var brief = NunaProgramBrief()
    @State private var making = false
    @State private var spec: AnyaProgramSpec?
    @State private var explanation: String?
    @State private var problem: String?
    @State private var change = ""
    @FocusState private var focused: Bool

    private var coach: AICoachEngine { model.coach }
    private var ready: Bool { coach.isConfigured && coach.dataConsent && CoachBriefScheduler.coachMasterEnabled }

    var body: some View {
        NavigationStack {
            NunaDetailScreen("Program with Anya") {
                if !ready {
                    NunaCard(small: true) {
                        Text("Anya is not connected. Connect her in More › Anya, then come back.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
                if let spec {
                    result(spec)
                } else {
                    form
                }
                if let problem {
                    Text(verbatim: problem).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                nunaFootnote("Anya sees only what you fill in here and a summary of your recent training, never your other health data. A suggestion, not a prescription.")
            }
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    // MARK: The form

    private var form: some View {
        VStack(alignment: .leading, spacing: NunaSpacing.section) {
            section("Target") {
                NunaFlowChips(items: NunaProgramBrief.Goal.allCases.map(\.rawValue)) { id in
                    chip(NunaProgramBrief.Goal(rawValue: id)?.title ?? "", on: brief.goal.rawValue == id) { brief.goal = NunaProgramBrief.Goal(rawValue: id) ?? .muscle }
                }
            }
            section("Days per week") {
                NunaSegmented((2...6).map { (value: $0, title: LocalizedStringKey("\($0)")) }, selection: $brief.days)
            }
            section("Minutes per session") {
                NunaSegmented([30, 45, 60, 75, 90].map { (value: $0, title: LocalizedStringKey("\($0)")) }, selection: $brief.minutes)
            }
            section("Equipment") {
                NunaFlowChips(items: NunaProgramBrief.Gear.allCases.map(\.rawValue)) { id in
                    chip(NunaProgramBrief.Gear(rawValue: id)?.title ?? "", on: brief.gear.rawValue == id) { brief.gear = NunaProgramBrief.Gear(rawValue: id) ?? .fullGym }
                }
            }
            section("Level") {
                NunaFlowChips(items: NunaProgramBrief.Level.allCases.map(\.rawValue)) { id in
                    chip(NunaProgramBrief.Level(rawValue: id)?.title ?? "", on: brief.level.rawValue == id) { brief.level = NunaProgramBrief.Level(rawValue: id) ?? .intermediate }
                }
            }
            section("Your instructions") {
                TextField("", text: $brief.words, prompt: Text("Wider shoulders, no squats because of my knee, 20 minutes of cardio at the end…").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                    .lineLimit(3...6).focused($focused).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .padding(14).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            }
            primaryButton(making ? "Anya is building it…" : "Build the program", icon: "sparkles") { Task { await make(previous: nil) } }
                .disabled(making || !ready).opacity(making || !ready ? 0.5 : 1)
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { nunaRuledHeader(title); content() }
    }

    private func chip(_ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 14, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 38).background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func primaryButton(_ title: LocalizedStringKey, icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if making { ProgressView().tint(NunaPalette.onAccent) } else { Image(systemName: icon).font(.nuna(size: 15, weight: .bold)) }
                Text(title).font(.nuna(size: 17, weight: .bold))
            }
            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: The result

    private func result(_ spec: AnyaProgramSpec) -> some View {
        VStack(alignment: .leading, spacing: NunaSpacing.section) {
            if let explanation, !explanation.isEmpty {
                Text(verbatim: explanation).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            NunaAnyaProgramCard(spec: spec)
            section("Change something") {
                TextField("", text: $change, prompt: Text("Swap the leg day for a lighter one, add arms…").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                    .lineLimit(2...4).focused($focused).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .padding(14).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                primaryButton(making ? "Anya is building it…" : "Update the program", icon: "arrow.triangle.2.circlepath") { Task { await make(previous: spec) } }
                    .disabled(making || change.trimmingCharacters(in: .whitespaces).isEmpty || !ready)
                    .opacity(making || change.trimmingCharacters(in: .whitespaces).isEmpty || !ready ? 0.5 : 1)
            }
            Button { self.spec = nil; explanation = nil; problem = nil } label: {
                Text("Start over").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Asking Anya

    private func make(previous: AnyaProgramSpec?) async {
        focused = false; making = true; problem = nil
        defer { making = false }
        var text = brief.text
        if previous != nil { text += "\nWhat to change now: \(change.trimmingCharacters(in: .whitespacesAndNewlines))" }
        let summary = await trainingSummary()
        // A small on-device model now and then answers in prose without the block; one more try with the same words is usually enough.
        var found: AnyaProgramSpec?
        var reply: String?
        for _ in 0..<2 {
            guard let r = await coach.suggestProgram(brief: text, trainingSummary: summary, previous: previous.map(NunaAnyaProgramNames.text)) else { continue }
            reply = r
            if let p = AnyaActions.parseProgram(from: r) { found = p; break }
        }
        if let found {
            spec = NunaAnyaProgramNames.resolve(found)
            explanation = reply.map(AnyaActions.proseOnly)
            change = ""
        } else if let reply {
            // Anya asked a question or explained what is missing.
            let prose = AnyaActions.proseOnly(reply)
            problem = prose.isEmpty ? String(localized: "Anya couldn't make a program from that. Say a little more about what you want.") : prose
        } else {
            problem = String(localized: "Anya couldn't answer. Check her connection in More, then try again.")
        }
    }

    /// A few lines on what the person already does, from their own sessions of the last four weeks: how often, sets a week for each muscle,
    /// the exercises they use with the last weight, and which muscles are still tired. Nothing else about them goes with it.
    private func trainingSummary() async -> String {
        guard let store = await repo.storeHandle() else { return "No training logged yet." }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - 28 * 86_400
        let sessions = ((try? await store.liftSessions(deviceId: repo.deviceId, fromTs: from, toTs: now + 86_400)) ?? []).filter { $0.endTs != nil }
        guard !sessions.isEmpty else { return "No training logged in the last four weeks: treat the person as starting out." }
        var perMuscle: [LiftMuscle: Double] = [:]
        var uses: [String: (count: Int, kg: Double?, reps: Int?, at: Int)] = [:]
        var tagged: [(set: LiftSetRow, at: Int)] = []
        for s in sessions {
            for set in (try? await store.liftSets(sessionId: s.id)) ?? [] where !set.isWarmup {
                tagged.append((set, s.startTs))
                if let p = set.primaryMuscle { perMuscle[p, default: 0] += 1 }
                for m in set.secondaryMuscles where m != set.primaryMuscle { perMuscle[m, default: 0] += 0.5 }
                var u = uses[set.exercise] ?? (0, nil, nil, 0)
                u.count += 1
                if s.startTs >= u.at, set.weightKg != nil || set.reps != nil { u.kg = set.weightKg ?? u.kg; u.reps = set.reps ?? u.reps; u.at = s.startTs }
                uses[set.exercise] = u
            }
        }
        var lines = ["Sessions in the last 4 weeks: \(sessions.count) (about \(String(format: "%.1f", Double(sessions.count) / 4)) a week)."]
        let weekly = perMuscle.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key.displayName) \(String(format: "%.0f", $0.value / 4))" }
        if !weekly.isEmpty { lines.append("Working sets per week by muscle: " + weekly.joined(separator: ", ") + ".") }
        let top = uses.sorted { $0.value.count > $1.value.count }.prefix(8).map { name, u -> String in
            var s = name
            if let kg = u.kg, kg > 0 { s += " (\(LiftFormat.trim(kg)) kg" + (u.reps.map { " x \($0)" } ?? "") + ")" }
            return s
        }
        if !top.isEmpty { lines.append("Exercises they use most: " + top.joined(separator: "; ") + ".") }
        let tired = NunaMuscleReadiness.readings(sets: tagged.filter { now - $0.at <= NunaMuscleReadiness.horizonDays * 86_400 }, now: now)
            .filter { NunaMuscleReadiness.state($0.value) == .fatigued }.map { $0.key.displayName }
        if !tired.isEmpty { lines.append("Still tired today: " + tired.sorted().joined(separator: ", ") + ".") }
        return lines.joined(separator: "\n")
    }
}
#endif

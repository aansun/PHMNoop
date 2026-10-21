#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// A breathing exercise made to the person's request, kept on this phone. Started or saved, it stays findable by its id, so its sessions in the
/// history and their reports still know what it was.
struct NunaSavedBreath: Codable, Identifiable, Equatable {
    struct Stage: Codable, Equatable { var phase: String; var seconds: Double }
    var id: String
    var title: String
    var goal: String
    var minutes: Int
    var stages: [Stage]
    var note: String?
}

enum NunaCustomBreath {
    private static let key = "nuna.breath.custom.v1"
    private static let maxSaved = 30

    static func all() -> [NunaSavedBreath] {
        guard let data = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([NunaSavedBreath].self, from: data) else { return [] }
        return list
    }

    private static func store(_ list: [NunaSavedBreath]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// A stable id from what the exercise is, so asking for the same one twice is one entry (FNV-1a over the title and the stages).
    static func id(for spec: AnyaBreathSpec) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        let text = spec.title.lowercased() + "|" + spec.stages.map { "\($0.phase):\($0.seconds)" }.joined(separator: ",")
        for u in text.utf16 { h = (h ^ UInt64(u)) &* 0x100000001b3 }
        return "custom-breath-" + String(h, radix: 16)
    }

    /// Keeps the exercise (newest first, at most 30) and makes it playable.
    @discardableResult
    static func save(_ spec: AnyaBreathSpec) -> NunaSavedBreath {
        let saved = NunaSavedBreath(id: id(for: spec), title: spec.title, goal: spec.goal, minutes: spec.minutes,
                                    stages: spec.stages.map { .init(phase: $0.phase, seconds: $0.seconds) }, note: spec.note)
        var list = all().filter { $0.id != saved.id }
        list.insert(saved, at: 0)
        store(Array(list.prefix(maxSaved)))
        BreathProtocolCatalog.registerCustom(proto(for: saved))
        return saved
    }

    static func delete(id: String) {
        store(all().filter { $0.id != id })
        BreathProtocolCatalog.unregisterCustom(id: id)
    }

    /// Makes every kept exercise playable again after a launch.
    static func registerAll() {
        for s in all() { BreathProtocolCatalog.registerCustom(proto(for: s)) }
    }

    static func phase(_ name: String) -> BreathPhase { name == "inhale" ? .inhale : (name == "exhale" ? .exhale : .hold) }

    static func proto(for s: NunaSavedBreath) -> BreathProtocol {
        BreathProtocol(id: s.id, title: s.title, subtitle: summary(s.stages),
                       edu: s.note ?? String(localized: "An exercise Anya made for you."), caution: nil, sessionHint: nil,
                       mode: .playable, category: .ans, recommendedDurationMs: s.minutes * 60_000,
                       stages: s.stages.map { BreathStage(type: phase($0.phase), durationMs: Int(($0.seconds * 1000).rounded())) })
    }

    static func request(for s: NunaSavedBreath) -> NunaBreathRequest {
        NunaBreathRequest(goal: BreathGoal(rawValue: s.goal) ?? .calm, templateId: nil, protocolId: s.id, seconds: s.minutes * 60)
    }

    static func word(_ phase: String) -> String {
        switch phase { case "inhale": return String(localized: "Inhale"); case "exhale": return String(localized: "Exhale"); default: return String(localized: "Hold") }
    }

    /// "Inhale 4 · Hold 2 · Exhale 6 s".
    static func summary(_ stages: [NunaSavedBreath.Stage]) -> String {
        let parts = stages.map { "\(word($0.phase)) \(trim($0.seconds))" }
        return parts.joined(separator: " · ") + " " + String(localized: "s")
    }

    private static func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", locale: AppLanguage.activeLocale, v) }
}

/// An exercise Anya made, to start now or keep. In the chat and in Breathing it is the same card.
struct NunaAnyaBreathCard: View {
    let spec: AnyaBreathSpec
    @State private var saved: Bool
    @State private var request: NunaBreathRequest?

    init(spec: AnyaBreathSpec) {
        self.spec = spec
        _saved = State(initialValue: NunaCustomBreath.all().contains { $0.id == NunaCustomBreath.id(for: spec) })
    }

    private var goal: BreathGoal { BreathGoal(rawValue: spec.goal) ?? .calm }

    var body: some View {
        let summary = NunaCustomBreath.summary(spec.stages.map { .init(phase: $0.phase, seconds: $0.seconds) })
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NunaIconTile(goal.icon, tint: goal.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: spec.title).font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        Text(verbatim: "\(spec.minutes) min · \(goal.shortTitle)").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: summary).font(.nuna(size: 14, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                if let n = spec.note { Text(verbatim: n).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil) }
                HStack(spacing: 10) {
                    Button {
                        let s = NunaCustomBreath.save(spec); saved = true
                        request = NunaCustomBreath.request(for: s)
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill").font(.nuna(size: 13, weight: .bold)); Text("Start") }
                            .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 44)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { NunaCustomBreath.save(spec); saved = true } label: {
                        Label(saved ? String(localized: "Saved") : String(localized: "Save"), systemImage: saved ? "checkmark" : "plus")
                            .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 18).frame(height: 44)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(saved).opacity(saved ? 0.6 : 1)
                }
            }
        }
        .fullScreenCover(item: $request) { req in NunaBreathFlow(first: req) { request = nil } }
    }
}

/// Breathing screen: "Your own exercise". Say what is needed in your own words and Anya makes it, from how you are right now; keep it, or start it.
struct NunaBreathAskAnya: View {
    var inputs: BreathAdvisorInput?
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var making = false
    @State private var spec: AnyaBreathSpec?
    @State private var explanation: String?
    @State private var problem: String?
    @State private var mine = NunaCustomBreath.all()
    @State private var starting: NunaBreathRequest?
    @FocusState private var focused: Bool

    private var coach: AICoachEngine { model.coach }
    private var ready: Bool { coach.isConfigured && coach.dataConsent && CoachBriefScheduler.coachMasterEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NunaTitleRow(title: "Your own exercise") { EmptyView() }
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if ready {
                        TextField("", text: $text, prompt: Text("Something slow to fall asleep, no holds, 6 minutes…").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                            .lineLimit(2...4).focused($focused).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                            .padding(14).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                        Button { Task { await make() } } label: {
                            HStack(spacing: 8) {
                                if making { ProgressView().tint(NunaPalette.onAccent) } else { Image(systemName: NunaGlyph.anya).font(.nuna(size: 14, weight: .bold)) }
                                Text(making ? "Anya is making it…" : "Make it with Anya").font(.nuna(size: 15.5, weight: .bold))
                            }
                            .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 48)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                        }.buttonStyle(.plain).disabled(making || text.trimmingCharacters(in: .whitespaces).isEmpty).opacity(making || text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    } else {
                        Text("Connect Anya in More › Anya to ask for an exercise of your own.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                    if let problem { Text(verbatim: problem).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.alertText).fixedSize(horizontal: false, vertical: true).textCase(nil) }
                }
            }
            if let spec {
                if let explanation, !explanation.isEmpty {
                    Text(verbatim: explanation).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                NunaAnyaBreathCard(spec: spec).id(NunaCustomBreath.id(for: spec))
            }
            if !mine.isEmpty { saved }
        }
        .onAppear { mine = NunaCustomBreath.all() }
        .fullScreenCover(item: $starting, onDismiss: { mine = NunaCustomBreath.all() }) { req in NunaBreathFlow(first: req) { starting = nil } }
    }

    private var saved: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)) {
            VStack(spacing: 0) {
                ForEach(Array(mine.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { NunaDivider() }
                    HStack(spacing: 12) {
                        Button { starting = NunaCustomBreath.request(for: s) } label: {
                            HStack(spacing: 12) {
                                NunaIconTile((BreathGoal(rawValue: s.goal) ?? .calm).icon, tint: (BreathGoal(rawValue: s.goal) ?? .calm).tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: s.title).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).textCase(nil)
                                    Text(verbatim: "\(s.minutes) min · " + NunaCustomBreath.summary(s.stages)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(2).textCase(nil)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "play.circle.fill").font(.nuna(size: 28, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { NunaCustomBreath.delete(id: s.id); mine = NunaCustomBreath.all() } label: {
                            Image(systemName: "trash").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(width: 36, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                    }.padding(.vertical, 10)
                }
            }
        }
    }

    private func make() async {
        focused = false; making = true; problem = nil
        defer { making = false }
        var context = ""
        if let i = inputs {
            var bits: [String] = []
            if let b = i.bpm { bits.append("heart rate \(b) bpm") }
            if let r = i.liveRmssd { bits.append("HRV \(Int(r.rounded())) ms") }
            if let s = i.stress { bits.append("stress \(String(format: "%.1f", s)) of 3") }
            if let c = i.charge { bits.append("Charge \(Int(c.rounded()))%") }
            bits.append("hour \(i.hour)")
            context = "Right now: " + bits.joined(separator: ", ")
        }
        // A small on-device model now and then answers in prose without the block; one more try with the same words is usually enough.
        var reply: String?
        var found: AnyaBreathSpec?
        for _ in 0..<2 {
            guard let r = await coach.suggestBreath(request: text, context: context) else { continue }
            reply = r
            if let s = AnyaActions.parseBreath(from: r) { found = s; break }
        }
        if let found {
            spec = found
            explanation = reply.map(AnyaActions.proseOnly)
        } else if let reply {
            let prose = AnyaActions.proseOnly(reply)
            problem = prose.isEmpty ? String(localized: "Anya couldn't make an exercise from that. Say a little more about what you need.") : prose
        } else {
            problem = String(localized: "Anya couldn't answer. Check her connection in More, then try again.")
        }
    }
}
#endif

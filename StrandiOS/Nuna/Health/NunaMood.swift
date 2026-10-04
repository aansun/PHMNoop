#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What the mood check-in keeps besides the 1 to 5 value: the factors, the energy level and the note.
/// Local to this phone, one entry per day, like the mood value itself.
struct NunaMoodExtras: Codable, Equatable {
    var factors: [String] = []
    var energy: Double = 0.5
    var note: String = ""

    private static let key = "nuna.mood.extras.v1"

    static func load(day: String) -> NunaMoodExtras? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: NunaMoodExtras].self, from: data) else { return nil }
        return all[day]
    }

    static func save(_ extras: NunaMoodExtras, day: String) {
        var all: [String: NunaMoodExtras] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let old = try? JSONDecoder().decode([String: NunaMoodExtras].self, from: data) { all = old }
        all[day] = extras
        if all.count > 400 { for k in all.keys.sorted().prefix(all.count - 400) { all[k] = nil } }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Mood check-in (HealthMind): five faces, what affected the day, energy, a note, today's stress, the week
/// and, once there are 7 check-ins, what tends to move with mood. Self-tracking, not a clinical assessment.
struct NunaMoodView: View {
    @EnvironmentObject private var repo: Repository
    @State private var mood: Int?
    @State private var saved: Int?
    @State private var extras = NunaMoodExtras()
    @State private var week: [(date: Date, value: Int?)] = []
    @State private var stress: Double?
    @State private var lines: [(text: String, caption: String)] = []
    @State private var savedFlash = false

    private let factorKeys: [(id: String, title: LocalizedStringKey)] = [
        ("work", "Work"), ("family", "Family"), ("exercise", "Exercise"), ("sleep", "Enough sleep"),
        ("caffeine", "Caffeine"), ("social", "Social"), ("travel", "Trips"),
    ]
    private var dirty: Bool { mood != nil && (mood != saved || extras != (NunaMoodExtras.load(day: Repository.localDayKey(Date())) ?? NunaMoodExtras())) }

    var body: some View {
        NunaDetailScreen("Mood check-in") {
            askCard
            factorsCard
            energyCard
            TextField("", text: $extras.note, prompt: Text("Note (optional)").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            if let stress {
                NunaCard(small: true) {
                    NunaListRow(LocalizedStringKey(String(localized: "Stress today \(String(format: "%.1f", locale: AppLanguage.activeLocale, stress)) · \(stress < 1 ? String(localized: "low") : (stress < 2 ? String(localized: "medium") : String(localized: "high")))")),
                                subtitle: "Saved together with your mood", systemImage: "wind")
                }
            }
            Button { Task { await save() } } label: {
                Text(savedFlash ? "Saved" : "Save").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(NunaPalette.textPrimary.opacity(mood == nil ? 0.35 : 1), in: Capsule())
            }
            .buttonStyle(.plain).disabled(mood == nil)
            weekCard
            if !lines.isEmpty { insightsCard }
            Text("Self-tracking, not a clinical assessment. If low mood persists, talk to a professional. You deserve support.")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private var askCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                Text(verbatim: Self.stamp.string(from: Date())).font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text("How are you feeling right now?").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(MoodStore.scale), id: \.self) { v in
                        let on = mood == v
                        Button { mood = v } label: {
                            VStack(spacing: 8) {
                                Text(verbatim: MoodStore.face(for: v)).font(.system(size: 26))
                                    .frame(width: 52, height: 52)
                                    .background(on ? NunaPalette.textPrimary : Color.white.opacity(0.07), in: Circle())
                                    .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: on ? 0 : 1))
                                Text(verbatim: MoodStore.label(for: v)).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                                    .multilineTextAlignment(.center).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: "\(MoodStore.label(for: v)), \(v) / 5"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var factorsCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("What affects it").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                NunaFlowChips(items: factorKeys.map { $0.id }) { id in
                    let on = extras.factors.contains(id)
                    Button {
                        if on { extras.factors.removeAll { $0 == id } } else { extras.factors.append(id) }
                    } label: {
                        Text(factorKeys.first { $0.id == id }!.title).font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background(on ? NunaPalette.textPrimary : NunaPalette.glassStrong, in: Capsule())
                            .overlay(Capsule().strokeBorder(NunaPalette.hairline, lineWidth: on ? 0 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var energyCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Energy").font(.system(size: 11.5, weight: .heavy)).tracking(1.15).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text(extras.energy < 0.34 ? "Low" : (extras.energy < 0.67 ? "Medium" : "High"))
                        .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(NunaPalette.textPrimary)
                }
                Slider(value: $extras.energy, in: 0...1).tint(NunaPalette.charge)
                HStack { Text("Tired"); Spacer(); Text("Energetic") }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "This week") { EmptyView() }
            NunaCard {
                HStack {
                    ForEach(0..<week.count, id: \.self) { i in
                        let d = week[i]
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(d.value == nil ? Color.white.opacity(0.12) : Color.white.opacity(0.14 + 0.16 * Double(d.value ?? 0)))
                                if let v = d.value { Text(verbatim: MoodStore.face(for: v)).font(.system(size: 14)) }
                            }
                            .frame(width: 30, height: 30)
                            Text(verbatim: Self.weekday.string(from: d.date)).font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "What tracks your mood") { EmptyView() }
            ForEach(0..<lines.count, id: \.self) { i in
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: lines[i].text).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: lines[i].caption).font(.system(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEEE d MMMM jj:mm"); return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE"); return f
    }()

    private func save() async {
        guard let mood else { return }
        let key = Repository.localDayKey(Date())
        await repo.saveMood(day: key, value: mood)
        NunaMoodExtras.save(extras, day: key)
        saved = mood
        savedFlash = true
        await load()
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        savedFlash = false
    }

    private func load() async {
        let series = await repo.moodSeries()
        let key = Repository.localDayKey(Date())
        let byDay = Dictionary(series.map { ($0.day, Int($0.value.rounded())) }, uniquingKeysWith: { _, l in l })
        if saved == nil, let v = byDay[key] { saved = v; mood = v }
        if let e = NunaMoodExtras.load(day: key), !dirty { extras = e }
        let cal = Calendar.current
        week = (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return (d, byDay[Repository.localDayKey(d)])
        }
        let stored = await repo.series(key: "stress", source: "my-whoop")
        let days = repo.days
        stress = await Task.detached(priority: .utility) { StressModel(days: days, stored: stored)?.score }.value

        func body(_ pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
            days.compactMap { d in pick(d).map { (day: d.day, value: $0) } }
        }
        let candidates: [(name: String, series: [(day: String, value: Double)])] = [
            ("HRV", body { $0.avgHrv }), (String(localized: "recovery"), body { $0.recovery }),
            (String(localized: "sleep duration"), body { $0.totalSleepMin }),
        ]
        var built: [(r: Double, text: String, caption: String)] = []
        if series.count >= 7 {
            for c in candidates {
                guard let corr = CorrelationEngine.pearson(CorrelationEngine.alignByDay(c.series, series)),
                      corr.n >= 7, abs(corr.r) >= 0.3 else { continue }
                let strength = abs(corr.r) < 0.5 ? String(localized: "Moderate") : (abs(corr.r) < 0.7 ? String(localized: "Strong") : String(localized: "Very strong"))
                let text = corr.r > 0 ? String(localized: "Days with higher \(c.name) tend to be your better-mood days.")
                                      : String(localized: "Days with higher \(c.name) tend to be your lower-mood days.")
                built.append((abs(corr.r), text, String(localized: "\(strength) link · r = \(String(format: "%+.2f", corr.r)) · n = \(corr.n) days")))
            }
        }
        lines = built.sorted { $0.r > $1.r }.prefix(3).map { ($0.text, $0.caption) }
    }
}

/// Wraps chips onto as many lines as they need.
struct NunaFlowChips<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}
#endif

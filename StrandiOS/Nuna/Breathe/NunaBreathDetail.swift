#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What a touch on the Breathe tab opens: a goal ("What is it for?") or one ready exercise ("Ready to start").
enum NunaBreathRoute: Identifiable, Equatable {
    case goal(BreathGoal)
    case template(BreathTemplate)
    case tool(NunaBreathTool)
    var id: String {
        switch self { case .goal(let g): return "goal-" + g.rawValue; case .template(let t): return "template-" + t.id; case .tool(let t): return "tool-" + t.rawValue }
    }
}

extension BreathGoal {
    /// A few plain lines on what the goal is for, in the app's own words.
    var about: String {
        switch self {
        case .calm: return String(localized: "For the moments your heart is racing or your mind will not stop. Slow, even breathing tells your body it is safe, and the rest follows.")
        case .sleep: return String(localized: "For the last minutes before bed, or when you wake in the night. Long, easy exhales help your body move from busy to ready to rest.")
        case .focus: return String(localized: "For the minutes before a task, a meeting or a study block. Counted breaths give a scattered mind one simple thing to follow.")
        case .energize: return String(localized: "For a slow morning or a flat afternoon. Fuller, brisker breathing wakes you up without a coffee.")
        case .recover: return String(localized: "For after hard effort or a poor night. Unhurried breathing helps your heart rate settle and gives recovery a head start.")
        }
    }
    var benefits: [String] {
        switch self {
        case .calm: return [String(localized: "Slows a racing heart within a few minutes"), String(localized: "Takes the edge off tension and worry"), String(localized: "Raises your HRV while you breathe, which the strap can show")]
        case .sleep: return [String(localized: "Moves you from busy to ready for bed"), String(localized: "Long exhales turn down the stress response"), String(localized: "Makes it easier to drift off, or to settle again after waking")]
        case .focus: return [String(localized: "Steadies your attention before you start"), String(localized: "Counted breaths quiet a scattered mind"), String(localized: "Keeps you alert without the jitters")]
        case .energize: return [String(localized: "Wakes you up without caffeine"), String(localized: "Raises alertness and the depth of your breath"), String(localized: "Works well in the morning or in an afternoon slump")]
        case .recover: return [String(localized: "Helps your heart rate settle after effort or a short night"), String(localized: "Supports the HRV your strap reads next morning"), String(localized: "Counts as a recovery activity in your day")]
        }
    }
}

/// A flat card for one exercise, as a Personal Record on the Strength Trainer: a tinted tile, the name and a line under it, the minutes at the right.
struct NunaBreathPickRow: View {
    let glyph: String
    let tint: Color
    let title: String
    let line: String
    var figure: String?
    var unit: String = String(localized: "min")
    var chip: LocalizedStringKey?

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)).frame(width: 72, height: 54)
                    .overlay(NunaActivityGlyph(name: glyph, size: 28).foregroundStyle(tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).textCase(nil)
                    Text(verbatim: line).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                    if let chip { NunaChip(chip, color: NunaPalette.charge) }
                }
                Spacer(minLength: 8)
                if let figure {
                    Text(verbatim: figure).font(.nuna(size: 26, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(minWidth: 30, alignment: .trailing)
                    Text(verbatim: unit).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                }
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The shell both detail pages share: a title row with Close, the content, and the Start button pinned to the bottom.
private struct NunaBreathDetailShell<Content: View>: View {
    let kicker: String
    let title: String
    let startLabel: LocalizedStringKey
    var startNote: String?
    let onStart: () -> Void
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NunaSpacing.section) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: kicker).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: title).font(.nuna(size: NunaTypeSize.h1, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Text("Close").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                content
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 22).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if let startNote { Text(verbatim: startNote).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                Button(action: onStart) {
                    Text(startLabel).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                        .background(NunaPalette.textPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 8)
            .background(NunaBackdrop().ignoresSafeArea())
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}

private func nunaBreathFact(_ label: LocalizedStringKey, _ value: String, _ unit: String = "") -> some View {
    NunaCard(small: true, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(verbatim: unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func nunaBreathSection(_ title: LocalizedStringKey, @ViewBuilder _ body: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        body()
    }
}

private func nunaBreathBenefits(_ items: [String], tint: Color) -> some View {
    NunaCard(small: true) {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark").font(.nuna(size: 12, weight: .heavy)).foregroundStyle(tint).padding(.top, 3)
                    Text(verbatim: line).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Aura

/// A soft glow that breathes at the pace of a technique: it swells while you breathe in, rests while you hold, and settles while you breathe out.
/// Without stages (a guided technique) it rises and falls slowly. With `pulse` it beats once every so many seconds, as Calm me's buzz does.
struct NunaBreathAura: View {
    let stages: [BreathStage]
    var tint: Color = NunaPalette.rest
    var pulse: Double?
    var guidance: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cycle: Double { max(0.5, stages.reduce(0) { $0 + Double($1.durationMs) / 1000 }) }

    /// 0...1 (how full the breath is) and the stage in force, at a moment in time.
    private func state(_ t: Double) -> (p: Double, stage: BreathStage?, left: Double) {
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if let pulse {
            let x = (t.truncatingRemainder(dividingBy: pulse)) / pulse
            return (x < 0.3 ? ease(x / 0.3) : ease(1 - (x - 0.3) / 0.7), nil, 0)
        }
        guard !stages.isEmpty else {
            let x = (t.truncatingRemainder(dividingBy: 8)) / 8
            return (0.5 - 0.5 * cos(x * 2 * .pi), nil, 0)
        }
        var pos = t.truncatingRemainder(dividingBy: cycle)
        var fullness = 0.0
        for st in stages {
            let d = Double(st.durationMs) / 1000
            if pos < d {
                let x = d > 0 ? pos / d : 1
                switch st.type {
                case .inhale: return (ease(x), st, d - pos)
                case .exhale: return (1 - ease(x), st, d - pos)
                default: return (fullness, st, d - pos)
                }
            }
            pos -= d
            switch st.type { case .inhale: fullness = 1; case .exhale: fullness = 0; default: break }
        }
        return (fullness, stages.last, 0)
    }

    private func word(_ st: BreathStage?) -> String {
        guard let st else { return "" }
        if let label = st.label { return String(localized: String.LocalizationValue(label)) }
        switch st.type {
        case .inhale: return String(localized: "Inhale"); case .exhale: return String(localized: "Exhale"); default: return String(localized: "Hold")
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let s = reduceMotion ? (p: 0.6, stage: stages.first, left: 0.0) : state(ctx.date.timeIntervalSinceReferenceDate)
            ZStack {
                // The aura: three soft layers that swell a little apart from each other.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.55 - Double(i) * 0.12), tint.opacity(0)], center: .center, startRadius: 4, endRadius: 120))
                        .scaleEffect(0.7 + 0.55 * s.p * (1 + Double(i) * 0.16))
                        .blur(radius: 10 + CGFloat(i) * 8)
                }
                Circle().fill(tint.opacity(0.22)).scaleEffect(0.32 + 0.38 * s.p)
                Circle().strokeBorder(tint.opacity(0.9), lineWidth: 2).scaleEffect(0.32 + 0.38 * s.p)
                if guidance, s.stage != nil {
                    VStack(spacing: 2) {
                        Text(verbatim: word(s.stage)).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: String(Int(ceil(s.left)))).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    }
                }
            }
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 240)
        .accessibilityHidden(true)
    }
}

// MARK: Steps

/// "Step 1, Step 2, …": one card each with a picture, the way a technique is explained on a poster.
private struct NunaBreathStepCards: View {
    let steps: [NunaBreathStep]
    let tint: Color
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(steps) { st in
                    NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                        VStack(spacing: 14) {
                            Text("Step \(st.id + 1)").font(.nuna(size: 15, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Image(systemName: st.icon).font(.system(size: 40, weight: .light)).foregroundStyle(tint).frame(height: 56)
                            Text(verbatim: st.text).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 190, alignment: .top).frame(minHeight: 205, alignment: .top)
                    }
                    .frame(width: 222)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
        }
        .padding(.horizontal, -NunaSpacing.screenH)
    }
}

/// What the Resonance and Calm me tabs of the older screen are, as pages of their own: the same layout as any technique.
enum NunaBreathTool: String, Identifiable {
    case resonance, calmMe
    var id: String { rawValue }
    var title: String { self == .resonance ? String(localized: "Resonance") : String(localized: "Calm me") }
    var subtitle: String {
        self == .resonance ? String(localized: "Find the slow pace that suits your body") : String(localized: "A buzz just under your heart rate, slowing down")
    }
    var mode: String { self == .resonance ? "resonance" : "calm" }
    var glyph: String { "Breathwork" }
    var tint: Color { self == .resonance ? NunaPalette.charge : NunaPalette.recoveryBlue }
    var stages: [BreathStage] {
        self == .resonance ? [BreathStage(type: .inhale, durationMs: 4_400), BreathStage(type: .exhale, durationMs: 6_500)] : []
    }
    var pulse: Double? { self == .calmMe ? 1.1 : nil }
    var about: String {
        self == .resonance
            ? String(localized: "Your heart rate speeds up as you breathe in and slows as you breathe out. At one slow pace those swings are biggest. Resonance tries a few paces while the strap reads your heart, keeps the best one, and paces your sessions at it.")
            : String(localized: "When you are wound up, a steady beat to follow helps. Calm me buzzes the strap just under your heart rate and eases the beat slower as you settle, so your breathing and your heart can follow it down together.")
    }
    var benefits: [String] {
        self == .resonance
            ? [String(localized: "Finds the slow pace that suits your body"), String(localized: "Trains a steadier heart rhythm (HRV)"), String(localized: "Gives your sessions a pace of your own instead of a general one")]
            : [String(localized: "Gives a restless mind one steady thing to follow"), String(localized: "Slows the beat gradually and never forces it"), String(localized: "Works best with the strap's buzz; without it you get a visual cue only")]
    }
    var steps: [NunaBreathStep] {
        let sit = ("figure.mind.and.body", String(localized: "Sit upright and comfortable, and relax your neck and shoulders."))
        let list: [(String, String)] = self == .resonance
            ? [sit,
               ("applewatch.watchface", String(localized: "Wear the strap snugly so it can read your heart.")),
               ("waveform.path.ecg", String(localized: "Start the sweep. You breathe at a few slow paces, about a minute each.")),
               ("circle.dotted", String(localized: "Follow the glow: breathe in as it grows, breathe out as it shrinks.")),
               ("checkmark.circle", String(localized: "The pace where your heart swings most is kept for your sessions."))]
            : [sit,
               ("applewatch.watchface", String(localized: "Wear the strap snugly. It buzzes a beat just under your heart rate.")),
               ("waveform", String(localized: "Breathe slowly in time with the buzz.")),
               ("tortoise", String(localized: "As you settle, the buzz slows down. Stop whenever you want."))]
        return list.enumerated().map { NunaBreathStep(id: $0.offset, icon: $0.element.0, text: $0.element.1) }
    }
    var duration: String { self == .resonance ? "5–15" : "3–10" }
}

// MARK: Pages

/// The shared body of a technique page: the aura, the three facts, the steps, what it is, what it does for you, and cautions.
private struct NunaBreathTechniquePage: View {
    let kicker: String
    let title: String
    let subtitle: String
    let tint: Color
    let stages: [BreathStage]
    var pulse: Double?
    let duration: String
    let pace: String
    let paceUnit: String
    let level: String
    let steps: [NunaBreathStep]
    let about: String
    var hint: String?
    let benefits: [String]
    var caution: String?
    var startNote: String?
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        NunaBreathDetailShell(kicker: kicker, title: title, startLabel: "Start", startNote: startNote, onStart: onStart, onClose: onClose) {
            Text(verbatim: subtitle).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            NunaBreathAura(stages: stages, tint: tint, pulse: pulse)
            HStack(spacing: 10) {
                nunaBreathFact("Duration", duration, String(localized: "min"))
                nunaBreathFact("Pace", pace, paceUnit)
                nunaBreathFact("Level", level)
            }
            nunaBreathSection("How to do it") { NunaBreathStepCards(steps: steps, tint: tint) }
            nunaBreathSection("About this exercise") {
                Text(verbatim: about).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(verbatim: String(localized: "Suggested length: \(hint)")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            nunaBreathSection("What it does for you") { nunaBreathBenefits(benefits, tint: tint) }
            if let caution {
                Text(verbatim: caution).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One ready exercise: its aura at its own pace, how to do it step by step, what it is, what it does for you, how long it takes, and then Start.
struct NunaBreathTemplateDetail: View {
    let template: BreathTemplate
    let minutes: Int
    let onStart: () -> Void
    let onClose: () -> Void

    private var proto: BreathProtocol? { BreathProtocolCatalog.protocolById(template.protocolId) }
    private var pattern: (value: String, unit: String) {
        let stages = proto?.stages ?? []
        guard !stages.isEmpty else { return (String(localized: "Guided"), "") }
        return (stages.map { String(format: "%g", Double($0.durationMs) / 1000) }.joined(separator: "-"), String(localized: "s"))
    }

    var body: some View {
        let p = proto
        NunaBreathTechniquePage(
            kicker: template.goal.shortTitle, title: template.title, subtitle: template.blurb, tint: template.goal.tint, stages: p?.stages ?? [],
            duration: "\(minutes)", pace: pattern.value, paceUnit: pattern.unit, level: NunaBreathLevel.of(template.protocolId).title,
            steps: p.map { NunaBreathGuide.steps(for: $0) } ?? [],
            about: p.map { String(localized: String.LocalizationValue($0.edu)) } ?? template.goal.about,
            hint: p?.sessionHint.map { String(localized: String.LocalizationValue($0)) },
            benefits: template.goal.benefits, caution: p?.caution.map { String(localized: String.LocalizationValue($0)) },
            onStart: onStart, onClose: onClose)
    }
}

/// Resonance or Calm me: a page like any technique's, and Start opens the older screen on that tab.
struct NunaBreathToolDetail: View {
    let tool: NunaBreathTool
    let onStart: () -> Void
    let onClose: () -> Void
    var body: some View {
        NunaBreathTechniquePage(
            kicker: String(localized: "Biofeedback"), title: tool.title, subtitle: tool.subtitle, tint: tool.tint, stages: tool.stages, pulse: tool.pulse,
            duration: tool.duration, pace: tool == .resonance ? "5.5" : String(localized: "Below HR"), paceUnit: tool == .resonance ? String(localized: "br/min") : "",
            level: NunaBreathLevel.gentle.title, steps: tool.steps, about: tool.about, hint: nil, benefits: tool.benefits,
            caution: String(localized: "Wear the strap for the best result. Without it you still get the visual cue."),
            onStart: onStart, onClose: onClose)
    }
}

/// One goal: what it is for, what it does, how long its exercises run, the exercises themselves, and Start on the one suggested.
struct NunaBreathGoalDetail: View {
    let goal: BreathGoal
    let recommended: BreathTemplate
    let lengthPref: Int
    let onStart: (BreathTemplate) -> Void
    let onOpen: (BreathTemplate) -> Void
    let onClose: () -> Void

    private var templates: [BreathTemplate] { NunaBreathLibrary.templates(for: goal) }
    private func mins(_ t: BreathTemplate) -> Int { lengthPref > 0 ? lengthPref : t.minutes }
    private var range: String {
        let m = templates.map(mins)
        guard let lo = m.min(), let hi = m.max() else { return "–" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        NunaBreathDetailShell(kicker: String(localized: "What is it for?"), title: goal.shortTitle, startLabel: "Start",
                              startNote: "\(recommended.title) · \(mins(recommended)) \(String(localized: "min"))", onStart: { onStart(recommended) }, onClose: onClose) {
            Text(goal.blurb).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            NunaBreathAura(stages: BreathProtocolCatalog.protocolById(recommended.protocolId)?.stages ?? [], tint: goal.tint)
            HStack(spacing: 10) {
                nunaBreathFact("Duration", range, String(localized: "min"))
                nunaBreathFact("Exercises", "\(templates.count)")
            }
            nunaBreathSection("About") {
                Text(verbatim: goal.about).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            nunaBreathSection("What it does for you") { nunaBreathBenefits(goal.benefits, tint: goal.tint) }
            nunaBreathSection("Exercises") {
                VStack(spacing: 10) {
                    ForEach(templates) { t in
                        Button { onOpen(t) } label: {
                            NunaBreathPickRow(glyph: goal.activity, tint: goal.tint, title: t.title, line: t.blurb, figure: "\(mins(t))")
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
#endif

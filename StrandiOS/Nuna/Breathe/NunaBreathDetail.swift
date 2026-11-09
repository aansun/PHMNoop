#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What a touch on the Breathe tab opens: a goal ("What is it for?") or one ready exercise ("Ready to start").
enum NunaBreathRoute: Identifiable, Equatable {
    case group(NunaBreathGroup)
    case template(BreathTemplate)
    case tool(NunaBreathTool)
    var id: String {
        switch self { case .group(let g): return "group-" + g.rawValue; case .template(let t): return "template-" + t.id; case .tool(let t): return "tool-" + t.rawValue }
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

// MARK: Icons

/// Every technique is drawn like any other activity: a thin one-colour picture from the WHOOP set, white on the dark card.
enum NunaBreathIcon {
    static func name(for protocolId: String, goal: BreathGoal) -> String {
        switch protocolId {
        case "relax_4_6": return "Restorative Yoga"
        case "coherence_5_5", "coherent_6_6", "okinaga", "presence_regular", "presence_mid": return "Meditation"
        case "deep_4_2_6", "extended_4_8": return "Non-sleep, deep rest"
        case "nadi_shodhana", "ujjayi": return "Yoga"
        case "four_seven_eight": return "Sleep"
        case "tummo": return "Ice Bath"
        case "wim_hof", "sitali": return "Cold Shower"
        case "bhastrika", "presence_punching": return "HIIT"
        case "qigong", "kiko_kokyuho": return "QiGong"
        case "soma", "bhramari", "holotropic", "shamanic": return "Sound Healing"
        case "kapalabhati": return "Hot Yoga"
        case "misogi_kokyuho", "nogare": return "Martial Arts"
        case "torifune_kokyuho": return "Judo"
        case "ibuki": return "Boxing"
        case "kiai": return "Kickboxing"
        case "kokyuho": return "Jiu-Jitsu"
        default: return "Breathwork"
        }
    }
    static func name(for t: BreathTemplate) -> String { name(for: t.protocolId, goal: t.goal) }
}

// MARK: Rows of a goal page

/// A flat card for one exercise inside a goal page: the picture, the name and a line under it, the minutes at the right.
struct NunaBreathPickRow: View {
    let glyph: String
    let title: String
    let line: String
    var figure: String?
    var unit: String = String(localized: "min")

    var body: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 14)) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NunaPalette.glassStrong).frame(width: 64, height: 50)
                    .overlay(NunaActivityGlyph(name: glyph, size: 28).foregroundStyle(NunaPalette.textPrimary))
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).font(.nunaWords(size: 14.5, semibold: true)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading).textCase(nil)
                    Text(verbatim: line).font(.nunaWords(size: 12.5)).tracking(0).foregroundStyle(NunaPalette.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                }
                Spacer(minLength: 8)
                if let figure {
                    Text(verbatim: figure).font(.nuna(size: 24, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: unit).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                }
                Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: Detail page

/// The page of a technique, laid out like WHOOP's workout details: a photograph behind a close button, the page name, the name of the technique and three
/// plain figures; under it the text, the steps and one outlined Start button. Nothing moves here: the animation begins with the session.
private struct NunaBreathDetailShell<Content: View>: View {
    let icon: String
    var background: String?
    let title: String
    let subtitle: String
    let stats: [(value: String, unit: String, label: LocalizedStringKey)]
    let startNote: String?
    let onStart: () -> Void
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                top
                VStack(alignment: .leading, spacing: 22) { content }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if let startNote { Text(verbatim: startNote).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                Button(action: onStart) {
                    Text("Start").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.charge).frame(maxWidth: .infinity).frame(height: 56)
                        .overlay(Capsule().strokeBorder(NunaPalette.charge, lineWidth: 2.5))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH + 8).padding(.top, 10).padding(.bottom, 8)
            .background(NunaBackdrop().ignoresSafeArea())
        }
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    /// The top of the page: the photograph (a dark gradient where there is none) with the close button, the page name, the title and the figures over it.
    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("Breathing details").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(.white)
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.nuna(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(Text("Close"))
                    Spacer()
                }
            }
            Spacer(minLength: 150)
            Text(verbatim: title).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(.white)
                .lineLimit(3).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: subtitle).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(.white.opacity(0.8)).lineSpacing(3).textCase(nil)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, st in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: st.value).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                            if !st.unit.isEmpty { Text(verbatim: st.unit).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(.white).textCase(nil) }
                        }
                        Text(st.label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(.white.opacity(0.65))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 18).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { photo }
    }

    @ViewBuilder private var photo: some View {
        ZStack {
            if let background, UIImage(named: background) != nil {
                GeometryReader { geo in
                    Image(background).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            } else {
                LinearGradient(colors: [NunaPalette.glassStrong, NunaPalette.cardSurface], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
            // A little dark over the whole photograph so the white text reads, then the photograph fades into the page below.
            Color.black.opacity(0.32)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }
}

private func nunaBreathBlock(_ title: LocalizedStringKey, @ViewBuilder _ body: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
        body()
    }
}

/// A heading with a line running out to the right, as "EXERCISES" has in WHOOP's workout details.
private func nunaBreathRuled(_ title: LocalizedStringKey) -> some View {
    HStack(spacing: 12) {
        Text(title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
        Rectangle().fill(NunaPalette.hairline).frame(height: 1)
    }
}

private func nunaBreathBenefits(_ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.charge)
                Text(verbatim: line).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The steps as one compact list that fits a screen: a number, a small picture and one or two lines each.
private struct NunaBreathSteps: View {
    let steps: [NunaBreathStep]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaBreathRuled("How to do it")
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, st in
                    if i > 0 { NunaDivider() }
                    HStack(spacing: 12) {
                        Text(verbatim: "\(st.id + 1)").font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(width: 24, height: 24).background(NunaPalette.glassStrong, in: Circle())
                        Image(systemName: st.icon).font(.system(size: 18, weight: .light)).foregroundStyle(NunaPalette.textPrimary).frame(width: 26)
                        Text(verbatim: st.text).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: Steps

/// What the Resonance and Calm me tabs of the older screen are, as pages of their own: the same layout as any technique.
enum NunaBreathTool: String, Identifiable {
    case resonance, calmMe
    var id: String { rawValue }
    var title: String { self == .resonance ? String(localized: "Resonance") : String(localized: "Calm me") }
    var subtitle: String {
        self == .resonance ? String(localized: "Find the slow pace that suits your body") : String(localized: "A buzz just under your heart rate, slowing down")
    }
    var mode: String { self == .resonance ? "resonance" : "calm" }
    var glyph: String { self == .resonance ? "Breathwork" : "Meditation" }
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
               ("arrow.down.right", String(localized: "As you settle, the buzz slows down. Stop whenever you want."))]
        return list.enumerated().map { NunaBreathStep(id: $0.offset, icon: $0.element.0, text: $0.element.1) }
    }
    var duration: String { self == .resonance ? "5–15" : "3–10" }
}

// MARK: Pages

/// One ready exercise: what it is, how long it takes, how to do it, what it does for you, and then Start.
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
        NunaBreathDetailShell(
            icon: NunaBreathIcon.name(for: template), background: NunaBreathGroup.containing(templateId: template.id).background,
            title: template.title, subtitle: template.blurb,
            stats: [("\(minutes)", String(localized: "min"), "Duration"), (pattern.value, pattern.unit, "Pace"), (NunaBreathLevel.of(template.protocolId).title, "", "Level")],
            startNote: nil, onStart: onStart, onClose: onClose) {
            if let p { NunaBreathSteps(steps: NunaBreathGuide.steps(for: p)) }
            Text(verbatim: p.map { String(localized: String.LocalizationValue($0.edu)) } ?? template.goal.about)
                .font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            NunaDivider()
            nunaBreathBlock("Best for") {
                Text(verbatim: template.goal.shortTitle).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            if let hint = p?.sessionHint {
                nunaBreathBlock("Suggested length") {
                    Text(verbatim: String(localized: String.LocalizationValue(hint))).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            nunaBreathBlock("What it does for you") { nunaBreathBenefits(template.goal.benefits) }
            if let caution = p?.caution {
                Text(verbatim: String(localized: String.LocalizationValue(caution))).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.warning).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Resonance or Calm me: a page like any technique's, and Start opens the older screen on that tab.
struct NunaBreathToolDetail: View {
    let tool: NunaBreathTool
    let onStart: () -> Void
    let onClose: () -> Void
    var body: some View {
        NunaBreathDetailShell(
            icon: tool.glyph, background: NunaBreathGroup.biofeedback.background, title: tool.title, subtitle: tool.subtitle,
            stats: [(tool.duration, String(localized: "min"), "Duration"),
                    (tool == .resonance ? "5.5" : String(localized: "Below HR"), tool == .resonance ? String(localized: "br/min") : "", "Pace"),
                    (NunaBreathLevel.gentle.title, "", "Level")],
            startNote: nil, onStart: onStart, onClose: onClose) {
            NunaBreathSteps(steps: tool.steps)
            Text(verbatim: tool.about).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            NunaDivider()
            nunaBreathBlock("What it does for you") { nunaBreathBenefits(tool.benefits) }
            Text(verbatim: String(localized: "Wear the strap for the best result. Without it you still get the visual cue.")).font(.nunaWords(size: 14)).tracking(0).foregroundStyle(NunaPalette.warning).lineSpacing(3).textCase(nil)
        }
    }
}

/// One group of techniques: what it is for, what it does, how long its exercises run, the exercises themselves, and Start on the one suggested.
struct NunaBreathGroupDetail: View {
    let group: NunaBreathGroup
    let recommended: NunaBreathItem?
    let lengthPref: Int
    let onStart: (NunaBreathItem) -> Void
    let onOpen: (NunaBreathItem) -> Void
    let onClose: () -> Void

    private var items: [NunaBreathItem] { group.items }
    private func mins(_ i: NunaBreathItem) -> String { i.minutesText(lengthPref: lengthPref) }
    private var range: String {
        let m = items.map { mins($0) }
        let nums = m.flatMap { $0.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } }
        guard let lo = nums.min(), let hi = nums.max() else { return "–" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        NunaBreathDetailShell(
            icon: group.icon, background: group.background, title: group.title, subtitle: group.blurb,
            stats: [(range, String(localized: "min"), "Duration"), ("\(items.count)", "", "Exercises"), (group.level.title, "", "Level")],
            startNote: recommended.map { "\($0.title) · \(mins($0)) \(String(localized: "min"))" }, onStart: { if let recommended { onStart(recommended) } }, onClose: onClose) {
            Text(verbatim: group.about).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
            NunaDivider()
            nunaBreathBlock("What it does for you") { nunaBreathBenefits(group.benefits) }
            nunaBreathRuled("Exercises")
            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button { onOpen(item) } label: {
                        NunaBreathPickRow(glyph: item.icon, title: item.title, line: item.blurb, figure: mins(item))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
#endif

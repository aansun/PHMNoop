#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// What a touch on the Breathe tab opens: a goal ("What is it for?") or one ready exercise ("Ready to start").
enum NunaBreathRoute: Identifiable, Equatable {
    case goal(BreathGoal)
    case template(BreathTemplate)
    var id: String {
        switch self { case .goal(let g): return "goal-" + g.rawValue; case .template(let t): return "template-" + t.id }
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

/// One ready exercise: what it is, what it does for you, how long it takes, and then Start.
struct NunaBreathTemplateDetail: View {
    let template: BreathTemplate
    let minutes: Int
    let onStart: () -> Void
    let onClose: () -> Void

    private var proto: BreathProtocol? { BreathProtocolCatalog.protocolById(template.protocolId) }
    private var pattern: String {
        let stages = proto?.stages ?? []
        guard !stages.isEmpty else { return String(localized: "Guided") }
        return stages.map { String(format: "%g", Double($0.durationMs) / 1000) }.joined(separator: "-")
    }

    var body: some View {
        NunaBreathDetailShell(kicker: template.goal.shortTitle, title: template.title, startLabel: "Start",
                              onStart: onStart, onClose: onClose) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(template.goal.tint.opacity(0.16)).frame(width: 88, height: 66)
                    .overlay(NunaActivityGlyph(name: template.goal.activity, size: 36).foregroundStyle(template.goal.tint))
                Text(verbatim: template.blurb).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                nunaBreathFact("Duration", "\(minutes)", String(localized: "min"))
                nunaBreathFact("Pace", pattern, pattern == String(localized: "Guided") ? "" : String(localized: "s"))
                nunaBreathFact("For", template.goal.shortTitle)
            }
            if let edu = proto?.edu {
                nunaBreathSection("About this exercise") {
                    Text(verbatim: String(localized: String.LocalizationValue(edu))).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    if let hint = proto?.sessionHint {
                        Text(verbatim: String(localized: "Suggested length: \(String(localized: String.LocalizationValue(hint)))")).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
            nunaBreathSection("What it does for you") { nunaBreathBenefits(template.goal.benefits, tint: template.goal.tint) }
            if let caution = proto?.caution {
                Text(verbatim: String(localized: String.LocalizationValue(caution))).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
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

    private var templates: [BreathTemplate] { BreathTemplates.templates(for: goal) }
    private func mins(_ t: BreathTemplate) -> Int { lengthPref > 0 ? lengthPref : t.minutes }
    private var range: String {
        let m = templates.map(mins)
        guard let lo = m.min(), let hi = m.max() else { return "–" }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        NunaBreathDetailShell(kicker: String(localized: "What is it for?"), title: goal.shortTitle, startLabel: "Start",
                              startNote: "\(recommended.title) · \(mins(recommended)) min", onStart: { onStart(recommended) }, onClose: onClose) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(goal.tint.opacity(0.16)).frame(width: 88, height: 66)
                    .overlay(NunaActivityGlyph(name: goal.activity, size: 36).foregroundStyle(goal.tint))
                Text(goal.blurb).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
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

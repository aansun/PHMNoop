#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - The plan being edited

/// What the wearer is building: the metric goals with their targets, the behaviors and the activities. Nothing is stored until the plan is started (or
/// saved), so backing out of any screen of the editor leaves the current plan alone.
@MainActor
final class NunaPlanDraft: ObservableObject {
    @Published var template: NunaPlanTemplate?
    @Published var metrics: [NunaPlanKind: Int] = [:]
    @Published var order: [NunaPlanKind] = []
    @Published var behaviors: [NunaPlanBehavior] = []
    @Published var activities: [NunaPlanActivity] = []
    /// 30-day steps and four-week minutes, read once for the cards.
    @Published var averages: [NunaPlanKind: Double] = [:]
    /// Whether the targets are still the ones a template suggested (they follow the averages until the wearer sets one).
    private var edited = Set<NunaPlanKind>()
    private var suggesting = false

    /// A template, with its own metrics, behaviors and activities.
    init(starting template: NunaPlanTemplate) {
        self.template = template
        suggesting = true
        for kind in template.metrics { metrics[kind] = kind.suggested(average: nil); order.append(kind) }
        behaviors = template.behaviors
        activities = template.activities
    }

    /// A custom plan with nothing chosen yet.
    init() { template = nil }

    var isEmpty: Bool { metrics.isEmpty && behaviors.isEmpty && activities.isEmpty }

    /// The plan as it is now, to change it; `asCustom` drops the template it came from.
    init(current spec: NunaPlanSpec, asCustom: Bool) {
        template = asCustom ? nil : NunaPlanStore.template(spec)
        for kind in NunaPlanStore.orderedKinds(spec) { metrics[kind] = kind.goal; order.append(kind) }
        behaviors = spec.behaviors
        activities = spec.activities
    }

    var selectedKinds: [NunaPlanKind] { order.filter { metrics[$0] != nil } }
    var unselectedKinds: [NunaPlanKind] { NunaPlanKind.allCases.filter { metrics[$0] == nil } }

    func target(_ kind: NunaPlanKind) -> Int { metrics[kind] ?? kind.suggested(average: averages[kind]) }

    func setTarget(_ kind: NunaPlanKind, _ value: Int) { metrics[kind] = value; edited.insert(kind) }

    func add(_ kind: NunaPlanKind) {
        metrics[kind] = kind.suggested(average: averages[kind])
        order.removeAll { $0 == kind }; order.append(kind)
    }

    func remove(_ kind: NunaPlanKind) { metrics[kind] = nil; order.removeAll { $0 == kind }; edited.remove(kind) }

    func isOn(_ activity: String) -> Bool { activities.contains { $0.id == activity } }
    func days(_ activity: String) -> Int { activities.first { $0.id == activity }?.days ?? 1 }
    func setActivity(_ item: NunaPlanActivity, on: Bool) {
        if on { if !isOn(item.id) { activities.append(item) } } else { activities.removeAll { $0.id == item.id } }
    }
    func setDays(_ activity: String, _ days: Int) {
        if let i = activities.firstIndex(where: { $0.id == activity }) { activities[i].days = days }
    }

    private var loadedAverages = false
    func loadAverages(repo: Repository, age: Int) async {
        guard !loadedAverages else { return }
        loadedAverages = true
        // Steps: the mean of the last thirty days that have a count, today left out.
        var st: [String: Double] = [:]
        for source in ["my-whoop", MetricCatalog.combinedStepsSource] {
            for p in await repo.exploreSeries(key: "steps", source: source, days: 60) where p.value > 0 { st[p.day] = p.value }
        }
        for p in await repo.exploreSeries(key: "steps_est", source: "my-whoop", days: 60) where p.value > 0 && st[p.day] == nil { st[p.day] = p.value }
        let cal = Calendar.current
        let recent = (1...30).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }.compactMap { st[Repository.localDayKey($0)] }
        if !recent.isEmpty { averages[.steps] = recent.reduce(0, +) / Double(recent.count) }
        resuggest()
        // The cheap reads first, so a template of sleep scores or steps shows its figures before the heart-rate zones are scanned.
        for kind in [NunaPlanKind.sleepConsistency, .sleepPerformance, .strength, .zonesEasy, .zonesHard] {
            averages[kind] = await NunaPlanModel.fourWeekAverage(kind, repo: repo, age: age) ?? 0
            resuggest()
        }
    }

    private func resuggest() {
        guard suggesting else { return }
        for kind in metrics.keys where !edited.contains(kind) { metrics[kind] = kind.suggested(average: averages[kind]) }
    }

    /// Writes the plan: the metric goals (those left out are cleared), the order, the behaviors and the activities. A behavior the journal does not have yet
    /// is added to it, so it can be logged there.
    func apply(repo: Repository) async {
        for kind in NunaPlanKind.allCases { UserDefaults.standard.set(metrics[kind] ?? 0, forKey: kind.storageKey) }
        NunaPlanStore.save(NunaPlanSpec(template: template?.rawValue, order: selectedKinds.map(\.rawValue), behaviors: behaviors, activities: activities))
        let catalog = JournalCatalogStore()
        let imported = Array(Set((await repo.importedJournalEntries()).map(\.question)))
        let known = catalog.resolvedItems(imported: imported, includeHidden: true).map { $0.canonical.lowercased() }
        for b in behaviors where !known.contains(b.id.lowercased()) {
            catalog.addCustom(b.id, group: b.id == NunaPlanBehavior.glp1Question ? .health : (b.id == NunaPlanBehavior.proteinQuestion || b.id == NunaPlanBehavior.hydrationQuestion ? .nutrition : .other))
            if b.title != b.id { catalog.rename(b.id, to: b.title) }
        }
    }
}

// MARK: - Shared pieces

private func planH1(_ key: LocalizedStringKey) -> some View {
    Text(key).font(.nuna(size: 22.5, weight: .semibold, design: NunaType.design)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
}

private func planLead(_ key: LocalizedStringKey) -> some View {
    Text(key).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
}

private func planSection(_ text: String, count: Int? = nil) -> some View {
    Text(verbatim: count.map { "\(text) (\($0))" } ?? text).font(.nuna(size: 18, weight: .semibold, design: NunaType.design)).tracking(0).textCase(nil)
        .foregroundStyle(NunaPalette.textPrimary)
}

/// A figure in the plan's number type; a trailing "%" is set smaller beside it.
@ViewBuilder private func planFigure(_ text: String, size: CGFloat, color: Color) -> some View {
    if text.hasSuffix("%") {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: String(text.dropLast())).font(.nuna(size: size, weight: .semibold, design: NunaType.design)).textCase(nil)
            Text(verbatim: "%").font(.nuna(size: size * 0.62, weight: .semibold, design: NunaType.design)).textCase(nil)
        }
        .foregroundStyle(color)
    } else {
        Text(verbatim: text).font(.nuna(size: size, weight: .semibold, design: NunaType.design)).textCase(nil).foregroundStyle(color)
    }
}

private func planCaps(_ s: String, size: CGFloat = 12.5, color: Color = NunaPalette.textPrimary) -> some View {
    Text(verbatim: s).font(.nuna(size: size, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
}

/// A metric or activity picture at the width every row keeps for it.
@ViewBuilder private func planIcon(_ name: String, size: CGFloat = 16.5) -> some View {
    Group {
        if name.hasPrefix("act:") { NunaGlyph(name, pointSize: size * 1.3) } else { NunaIcon(name: name, size: size) }
    }
    .foregroundStyle(NunaPalette.textSecondary).frame(width: 22, height: 26)
}

/// A switch in the plan's own look: a grey track and thumb when off, the accent and a white thumb when on.
private struct NunaPlanToggleStyle: ToggleStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? tint : Color(hex: "#4A4D52")).frame(width: 62, height: 32)
                Circle().fill(configuration.isOn ? Color.white : Color(hex: "#8E8F94")).frame(width: 26, height: 26).padding(3)
            }
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain).accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
    }
}

/// The white bar at the foot of a page.
private struct NunaPlanPrimaryButton: View {
    let title: LocalizedStringKey
    var outlined = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase)
                .foregroundStyle(outlined ? NunaPalette.textPrimary : (enabled ? NunaPalette.onAccent : NunaPalette.textMuted))
                .frame(maxWidth: .infinity).frame(height: 49)
                .background(outlined ? AnyShapeStyle(Color.clear) : (enabled ? AnyShapeStyle(NunaPalette.accent) : AnyShapeStyle(NunaPalette.cardHighlight)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(outlined ? NunaPalette.textPrimary : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled || !outlined ? 1 : 0.4)
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14).padding(.bottom, 12)
        .background(LinearGradient(colors: [NunaPalette.canvas.opacity(0), NunaPalette.canvas.opacity(0.92), NunaPalette.canvas], startPoint: .top, endPoint: .init(x: 0.5, y: 0.45)).ignoresSafeArea())
    }
}

/// The pencil beside "Edit".
private struct NunaPlanEditLabel: View {
    var body: some View {
        HStack(spacing: 8) {
            planCaps(String(localized: "Edit"), size: 11)
            Image(systemName: "pencil").font(.nuna(size: 15, weight: .regular))
        }
        .foregroundStyle(NunaPalette.textPrimary).frame(height: 36).contentShape(Rectangle())
    }
}

private struct NunaPlanBandBars: View {
    let band: NunaPlanBand
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i == band.index ? band.color : NunaPalette.ringTrack).frame(width: 21, height: 4)
            }
        }
    }
}

private struct NunaPlanLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(NunaPlanBand.poor.color, String(localized: "Poor"))
            item(NunaPlanBand.sufficient.color, String(localized: "Sufficient"))
            item(NunaPlanBand.optimal.color, String(localized: "Optimal"))
            Spacer(minLength: 0)
        }
    }
    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(verbatim: text).font(.nuna(size: 12.5, weight: .semibold)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
        }
    }
}

private struct NunaPlanChevrons: View {
    var body: some View {
        HStack(spacing: -7) {
            ForEach(0..<3, id: \.self) { _ in Image(systemName: "chevron.right").font(.system(size: 17, weight: .heavy)) }
        }
        .foregroundStyle(NunaPalette.textMuted)
    }
}

private struct NunaPlanDaysPicker: View {
    let days: Int
    let tint: Color
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                planCaps(String(localized: "Days per week"), size: 12.5)
                Spacer()
                planCaps(days == 1 ? String(localized: "1 day") : String(localized: "\(days) days"), size: 12.5, color: tint)
            }
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    Button { onPick(d) } label: {
                        Text(verbatim: "\(d)").font(.nuna(size: 15, weight: .semibold, design: NunaType.design)).textCase(nil)
                            .foregroundStyle(d == days ? Color(red: 0.03, green: 0.04, blue: 0.07) : NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(d == days ? AnyShapeStyle(tint) : AnyShapeStyle(NunaPalette.glassStrong), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct NunaPlanRowCard<Content: View>: View {
    var highlight = false
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 16).frame(maxWidth: .infinity)
            .background(highlight ? NunaPalette.cardHighlight : NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }
}

/// A metric goal: its name, the average it starts from and the target it asks for; with `editable`, the X that takes it out and the pencil that changes the target.
private struct NunaPlanMetricCard: View {
    @ObservedObject var draft: NunaPlanDraft
    let kind: NunaPlanKind
    var editable = false
    var onTarget: () -> Void = {}

    var body: some View {
        let average = draft.averages[kind]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                planIcon(kind.editIcon)
                planCaps(kind.editTitle)
                Spacer(minLength: 8)
                if editable {
                    if let average { NunaPlanBandBars(band: kind.band(average)) }
                    Button { withAnimation(.easeInOut(duration: 0.2)) { draft.remove(kind) } } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text("Remove"))
                }
            }
            HStack(alignment: .center) {
                VStack(spacing: 3) {
                    planFigure(average.map(kind.averageText) ?? "–", size: 23, color: average.map { kind.band($0).color } ?? NunaPalette.textSecondary)
                    planCaps(kind.averageLabel, size: 11, color: NunaPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                NunaPlanChevrons()
                VStack(spacing: 3) {
                    Button(action: onTarget) {
                        HStack(spacing: 8) {
                            planFigure(kind.targetText(draft.target(kind)), size: 26, color: NunaPalette.textPrimary)
                            if editable { Image(systemName: "pencil").font(.system(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textPrimary) }
                        }
                    }
                    .buttonStyle(.plain).allowsHitTesting(editable)
                    planCaps(String(localized: "This week's target"), size: 11, color: NunaPalette.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }
            if editable, let text = kind.recommendation {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lightbulb").font(.system(size: 20, weight: .light)).foregroundStyle(NunaPalette.recoveryBlue).padding(.top, 2)
                    Text(verbatim: text).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.recoveryBlue).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(NunaPalette.recoveryBlue.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
        .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }
}

/// A face in outline: the circle, two closed eyes and a smile.
private struct NunaSmileOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        let w = r.width, h = r.height
        for cx in [0.35, 0.65] {
            p.addArc(center: CGPoint(x: r.minX + w * cx, y: r.minY + h * 0.40), radius: w * 0.055, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: true)
        }
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + h * 0.50), radius: w * 0.21, startAngle: .degrees(35), endAngle: .degrees(145), clockwise: false)
        return p
    }
}

// MARK: - Edit your weekly plan

/// The editor: it opens over the plan page and has its own stack, so Start plan can close all of it at once.
struct NunaPlanEditFlow: View {
    /// Open straight on the current plan's details instead of the list of plans.
    var opensDetails = false
    let onClose: () -> Void
    @State private var draft = NunaPlanDraft(current: NunaPlanStore.load(), asCustom: false)

    var body: some View {
        NavigationStack {
            Group {
                if opensDetails { NunaPlanDetailsView(draft: draft, startsTemplate: false, onClose: onClose) }
                else { NunaPlanEditList(onClose: onClose) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}

private struct NunaPlanEditList: View {
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let spec = NunaPlanStore.load()

    var body: some View {
        NunaDetailScreen("Edit plan", centersTitle: true) {
            VStack(alignment: .leading, spacing: 12) {
                planH1("Edit your Weekly Plan")
                planLead("Choose from the list of personalized plans below or create your own. Starting a plan will customize your daily recommendations for the week ahead.")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            VStack(alignment: .leading, spacing: 12) {
                nunaRuledHeader("Current plan")
                NavigationLink { NunaPlanDetailsView(draft: NunaPlanDraft(current: spec, asCustom: false), startsTemplate: false, onClose: onClose).toolbar(.hidden, for: .navigationBar) } label: {
                    if let t = NunaPlanStore.template(spec) { templateCard(t) } else { customCard }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 12) {
                nunaRuledHeader("Choose a plan")
                ForEach(NunaPlanTemplate.allCases.filter { $0 != NunaPlanStore.template(spec) }) { t in
                    NavigationLink {
                        // The GLP-1 plan starts with a few questions about the medication, unless they were answered before.
                        if t == .glp1Companion, NunaGLP1Setup.load() == nil {
                            NunaGLP1Flow(onClose: onClose).toolbar(.hidden, for: .navigationBar)
                        } else if t == .glp1Companion, let setup = NunaGLP1Setup.load() {
                            NunaPlanDetailsView(draft: NunaPlanDraft(glp1: setup), startsTemplate: true, onClose: onClose).toolbar(.hidden, for: .navigationBar)
                        } else {
                            NunaPlanDetailsView(draft: NunaPlanDraft(starting: t), startsTemplate: true, onClose: onClose).toolbar(.hidden, for: .navigationBar)
                        }
                    } label: { templateCard(t) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            // A plan of your own, from nothing (shown while a ready-made plan is the current one).
            if NunaPlanStore.template(spec) != nil {
                VStack(alignment: .leading, spacing: 12) {
                    nunaRuledHeader("Custom")
                    NavigationLink { NunaPlanDetailsView(draft: NunaPlanDraft(), startsTemplate: true, onClose: onClose).toolbar(.hidden, for: .navigationBar) } label: { customCard }
                        .buttonStyle(.plain)
                }
                .padding(.top, 14)
            }
        }
        .environment(\.nunaDetailSwitch, nil)
    }

    private var customCard: some View {
        planCard(icon: AnyView(Image(systemName: "square.and.pencil").font(.nuna(size: 21, weight: .light)).foregroundStyle(NunaPalette.textPrimary)),
                 title: String(localized: "Custom Plan"), blurb: String(localized: "Build your personalized plan by selecting weekly metric, behavior and activity goals."),
                 titleColor: NunaPalette.textPrimary, fill: AnyShapeStyle(NunaPalette.glassStrong))
    }

    /// The picture on a plan card, in the plan's colour. A smile is drawn as an outline, as the symbol set only offers it filled here.
    @ViewBuilder private func templateIcon(_ t: NunaPlanTemplate) -> some View {
        if t == .feelBetter {
            NunaSmileOutline().stroke(t.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 24, height: 24)
        } else {
            NunaIcon(name: t.symbol, size: 17).foregroundStyle(t.accent)
        }
    }

    private func templateCard(_ t: NunaPlanTemplate) -> some View {
        planCard(icon: AnyView(templateIcon(t)), title: t.name, blurb: t.blurb, titleColor: t.accent,
                 fill: AnyShapeStyle(LinearGradient(colors: [t.wash, NunaPalette.cardSurface], startPoint: .topLeading, endPoint: .trailing)))
    }

    private func planCard(icon: AnyView, title: String, blurb: String, titleColor: Color, fill: AnyShapeStyle) -> some View {
        HStack(alignment: .center, spacing: 17) {
            icon.frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title).font(.nuna(size: 15, weight: .semibold)).tracking(0).textCase(nil).foregroundStyle(titleColor)
                Text(verbatim: blurb).font(.nunaWords(size: 12.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17).padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }
}

// MARK: - Plan details

struct NunaPlanDetailsView: View {
    @ObservedObject var draft: NunaPlanDraft
    /// A template being started (the button says Start plan) or a plan being changed (Save plan).
    let startsTemplate: Bool
    let onClose: () -> Void
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    private var title: String { draft.template?.name ?? String(localized: "Custom Plan") }
    private var blurb: String { draft.template?.blurb ?? String(localized: "Build your personalized plan by selecting weekly metric, behavior and activity goals.") }

    var body: some View {
        NunaDetailScreen("Plan details", centersTitle: true) {
            VStack(alignment: .leading, spacing: 12) {
                planH1(LocalizedStringKey(title))
                planLead(LocalizedStringKey(blurb))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            section(String(localized: "Metrics"), count: draft.selectedKinds.count, destination: NunaPlanMetricsPage(draft: draft),
                    empty: String(localized: "Select your metrics"), add: String(localized: "Add metrics")) {
                if !draft.selectedKinds.isEmpty { NunaPlanLegend() }
                ForEach(draft.selectedKinds) { kind in NunaPlanMetricCard(draft: draft, kind: kind) }
            }
            section(String(localized: "Behaviors"), count: draft.behaviors.count, destination: NunaPlanBehaviorPage(draft: draft),
                    empty: String(localized: "Select your behaviors"), add: String(localized: "Add behaviors")) {
                ForEach(draft.behaviors) { b in
                    NunaPlanRowCard {
                        HStack {
                            planCaps(b.title)
                            Image(systemName: "info.circle").font(.system(size: 16, weight: .regular)).foregroundStyle(NunaPalette.recoveryBlue)
                            Spacer(minLength: 8)
                            planCaps(b.avoid ? avoidText(b.days) : daysText(b.days), size: 12.5, color: NunaPalette.textSecondary)
                        }
                        .frame(height: 56)
                    }
                }
            }
            section(String(localized: "Activities"), count: draft.activities.count, destination: NunaPlanActivityPage(draft: draft),
                    empty: String(localized: "Select your activities"), add: String(localized: "Add activities")) {
                ForEach(draft.activities) { a in
                    NunaPlanRowCard {
                        HStack(spacing: 14) {
                            activityGlyph(a).frame(width: 22)
                            planCaps(a.title)
                            Spacer(minLength: 8)
                            planCaps(daysText(a.days), size: 12.5, color: NunaPalette.textSecondary)
                        }
                        .frame(height: 56)
                    }
                }
            }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task { await draft.loadAverages(repo: repo, age: profile.age) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NunaPlanPrimaryButton(title: startsTemplate ? "Start plan" : "Save plan", enabled: !draft.isEmpty) {
                Task { await draft.apply(repo: repo); onClose() }
            }
        }
    }

    private func daysText(_ d: Int) -> String { d == 1 ? String(localized: "1 day") : String(localized: "\(d) days") }
    private func avoidText(_ d: Int) -> String { d == 1 ? String(localized: "Avoid 1 day") : String(localized: "Avoid \(d) days") }

    /// A section: its name and Edit, then its cards. While nothing is chosen in it, a card asks for the choice, with the button that adds one.
    @ViewBuilder private func section<D: View, C: View>(_ name: String, count: Int, destination: D, empty: String, add: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                planSection(name, count: count)
                Spacer()
                if count > 0 {
                    NavigationLink { destination.toolbar(.hidden, for: .navigationBar) } label: { NunaPlanEditLabel() }.buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            if count == 0 {
                VStack(alignment: .leading, spacing: 16) {
                    planCaps(empty, size: 12.5)
                    NavigationLink { destination.toolbar(.hidden, for: .navigationBar) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                            planCaps(add, size: 12.5)
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 40)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
            }
            content()
        }
    }
}

@ViewBuilder private func activityGlyph(_ a: NunaPlanActivity) -> some View {
    switch a.id {
    case NunaPlanActivity.strain: NunaGlyph("figure.arms.open", pointSize: 20).foregroundStyle(NunaPalette.textSecondary)
    case NunaPlanActivity.strength: NunaGlyph("act:strength-trainer", pointSize: 21).foregroundStyle(NunaPalette.textSecondary)
    case NunaPlanActivity.recovery: NunaGlyph("figure.mind.and.body", pointSize: 20).foregroundStyle(NunaPalette.textSecondary)
    default: NunaActivityGlyph(name: a.sportName ?? a.title, size: 24).foregroundStyle(NunaPalette.textSecondary)
    }
}

// MARK: - Metrics

private struct NunaPlanMetricsPage: View {
    @ObservedObject var draft: NunaPlanDraft
    @Environment(\.dismiss) private var dismiss
    @State private var editing: NunaPlanKind?

    var body: some View {
        NunaDetailScreen("Metrics", centersTitle: true) {
            VStack(alignment: .leading, spacing: 12) {
                planH1("Select Your Metric Goals")
                planLead("Improve your health and fitness by selecting 1-2 metric goals for the week.")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            if !draft.selectedKinds.isEmpty {
                planSection(String(localized: "Selected"), count: draft.selectedKinds.count).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                ForEach(draft.selectedKinds) { kind in
                    NunaPlanMetricCard(draft: draft, kind: kind, editable: true) { editing = kind }
                }
            }
            if !draft.unselectedKinds.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    planSection(String(localized: "All Metrics"))
                    Spacer()
                    Text("30 Day avg.").font(.nuna(size: 13.5, weight: .regular)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
                }
                .padding(.top, 14)
                NunaPlanLegend()
                ForEach(draft.unselectedKinds) { kind in row(kind) }
            }
        }
        .environment(\.nunaDetailSwitch, nil)
        .animation(.easeInOut(duration: 0.2), value: draft.selectedKinds)
        .sheet(item: $editing) { kind in
            NunaNumberSheet(title: LocalizedStringKey(kind.editTitle), unit: kind.unit, initial: Double(draft.target(kind)), range: kind.targetRange, step: kind.targetStep, decimals: 0) {
                draft.setTarget(kind, Int($0))
            }
            .presentationDetents([.medium])
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { NunaPlanPrimaryButton(title: "Save metrics") { dismiss() } }
    }

    private func row(_ kind: NunaPlanKind) -> some View {
        let average = draft.averages[kind]
        return Button { withAnimation(.easeInOut(duration: 0.2)) { draft.add(kind) } } label: {
            NunaPlanRowCard {
                HStack(spacing: 10) {
                    planIcon(kind.editIcon)
                    VStack(alignment: .leading, spacing: 4) {
                        planCaps(kind.editTitle, size: 13)
                        Text(verbatim: average.map(kind.valueText) ?? "–").font(.nuna(size: 14, weight: .semibold)).tracking(0).textCase(nil)
                            .foregroundStyle(average.map { kind.band($0).color } ?? NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if let average { NunaPlanBandBars(band: kind.band(average)) }
                    Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(NunaPalette.textPrimary).frame(width: 34)
                }
                .frame(height: 72)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Behaviors

private struct NunaPlanBehaviorPage: View {
    @ObservedObject var draft: NunaPlanDraft
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var info: NunaPlanBehavior?

    var body: some View {
        NunaDetailScreen("Behavior goal", centersTitle: true) {
            VStack(alignment: .leading, spacing: 12) {
                planH1("Set Your Weekly Behavior Goals")
                planLead("Behavior goals will be added to your journal. Record progress daily to earn credit toward your plan.")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            if !draft.behaviors.isEmpty {
                planCaps(String(localized: "Recommended behaviors"), size: 11.5, color: NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            }
            ForEach($draft.behaviors) { $b in card($b) }
            Button { picking = true } label: {
                NunaPlanRowCard(highlight: true) {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
                        planCaps(String(localized: "Add behaviors"), size: 13.5)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 64)
                }
            }
            .buttonStyle(.plain)
            Text("New behaviors will also be added to your Journal for daily tracking.")
                .font(.nunaWords(size: 14.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.top, 18)
        }
        .environment(\.nunaDetailSwitch, nil)
        .animation(.easeInOut(duration: 0.2), value: draft.behaviors)
        .sheet(isPresented: $picking) { NunaPlanBehaviorPicker(draft: draft) }
        .alert(info.map { Text(verbatim: $0.title) } ?? Text(verbatim: ""), isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: info?.id ?? "") }
        .safeAreaInset(edge: .bottom, spacing: 0) { NunaPlanPrimaryButton(title: "Save behaviors") { dismiss() } }
    }

    private func card(_ b: Binding<NunaPlanBehavior>) -> some View {
        let value = b.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        planCaps(value.title, size: 13)
                        Button { info = value } label: { Image(systemName: "info.circle").font(.system(size: 17, weight: .regular)).foregroundStyle(NunaPalette.recoveryBlue) }
                            .buttonStyle(.plain).accessibilityLabel(Text("About this behavior"))
                    }
                    Text(verbatim: value.subtitle).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { true }, set: { if !$0 { withAnimation { draft.behaviors.removeAll { $0.id == value.id } } } }))
                    .labelsHidden().toggleStyle(NunaPlanToggleStyle(tint: NunaPalette.recoveryBlue))
            }
            Button { b.wrappedValue.avoid.toggle() } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: 2).frame(width: 30, height: 30)
                        if value.avoid { Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary) }
                    }
                    planCaps(String(localized: "Avoid \(value.title.lowercased())"), size: 13)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            NunaPlanDaysPicker(days: value.days, tint: NunaPalette.recoveryBlue) { b.wrappedValue.days = $0 }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(NunaPalette.cardHighlight, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }
}

/// "Select behaviors": every journal question, searchable and sorted into its journal group; a tick puts it in the plan.
private struct NunaPlanBehaviorPicker: View {
    @ObservedObject var draft: NunaPlanDraft
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var group: JournalGroup?
    @State private var items: [NunaPlanBehavior] = []
    @State private var groups: [String: JournalGroup] = [:]
    @State private var chosen: [String: NunaPlanBehavior] = [:]
    @FocusState private var focused: Bool

    private func matches(_ b: NunaPlanBehavior) -> Bool {
        (query.isEmpty || b.title.localizedCaseInsensitiveContains(query) || b.subtitle.localizedCaseInsensitiveContains(query))
            && (group == nil || groups[b.id] == group)
    }
    private var selected: [NunaPlanBehavior] { items.filter { chosen[$0.id] != nil && matches($0) } }
    private var rest: [NunaPlanBehavior] { items.filter { chosen[$0.id] == nil && matches($0) } }

    var body: some View {
        ZStack {
            NunaBackdrop()
            VStack(spacing: 0) {
                ZStack {
                    planCaps(String(localized: "Select behaviors"), size: 14)
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel(Text("Close"))
                        Spacer()
                    }
                }
                .padding(.horizontal, 12).padding(.top, 14)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                    TextField("Search for Behaviors", text: $query).focused($focused).font(.nuna(size: 16, weight: .regular)).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 14)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        chip(String(localized: "All"), on: group == nil) { group = nil }
                        ForEach(JournalGroup.displayOrder, id: \.self) { g in chip(g.title, on: group == g) { group = g } }
                    }
                    .padding(.horizontal, NunaSpacing.screenH)
                }
                .scrollIndicators(.hidden).padding(.top, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !selected.isEmpty {
                            nunaRuledHeader("Currently selected").padding(.vertical, 12)
                            ForEach(selected) { row($0) }
                        }
                        if !rest.isEmpty {
                            nunaRuledHeader("Not selected").padding(.vertical, 12)
                            ForEach(rest) { row($0) }
                        }
                    }
                    .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                NunaPlanPrimaryButton(title: "Save behaviors", outlined: true) { save() }
            }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await load() }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.nuna(size: 16, weight: .semibold)).tracking(0).textCase(nil)
                .foregroundStyle(on ? Color(red: 0.03, green: 0.04, blue: 0.07) : NunaPalette.textPrimary)
                .padding(.horizontal, 16).frame(height: 46)
                .background(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(NunaPalette.glassStrong), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row(_ b: NunaPlanBehavior) -> some View {
        let on = chosen[b.id] != nil
        return Button { if on { chosen[b.id] = nil } else { chosen[b.id] = draft.behaviors.first { $0.id == b.id } ?? b } } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: b.title).font(.nuna(size: 18, weight: .semibold)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading)
                    Text(verbatim: b.subtitle).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? AnyShapeStyle(NunaPalette.recoveryBlue) : AnyShapeStyle(Color.clear))
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Color.clear : NunaPalette.textPrimary, lineWidth: 2)
                    if on { Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color(red: 0.03, green: 0.04, blue: 0.07)) }
                }
                .frame(width: 30, height: 30)
            }
            .padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        let imported = Array(Set((await repo.importedJournalEntries()).map(\.question)))
        let catalog = JournalCatalogStore()
        var out: [NunaPlanBehavior] = []
        var map: [String: JournalGroup] = [:]
        for item in catalog.resolvedItems(imported: imported, includeHidden: false) {
            let title = item.displayName ?? NunaPlanBehavior.shortTitle(item.canonical)
            out.append(NunaPlanBehavior(id: item.canonical, title: title, subtitle: item.canonical, days: 3))
            map[item.canonical] = item.group
        }
        // Protein is the plan's own suggestion, until the journal has it.
        if !out.contains(where: { $0.id.lowercased() == NunaPlanBehavior.proteinQuestion.lowercased() }) {
            out.append(NunaPlanBehavior.protein(days: 4)); map[NunaPlanBehavior.proteinQuestion] = .nutrition
        }
        if !out.contains(where: { $0.id.lowercased() == NunaPlanBehavior.hydrationQuestion.lowercased() }) {
            out.append(NunaPlanBehavior.hydration(days: 4)); map[NunaPlanBehavior.hydrationQuestion] = .nutrition
        }
        // A behavior already in the plan keeps the name the plan gave it ("Late meal").
        out = out.map { o in draft.behaviors.first { $0.id == o.id } ?? o }
        // The ones already in the plan come first, with the days they have.
        for b in draft.behaviors where !out.contains(where: { $0.id == b.id }) { out.append(b) }
        out.sort { l, r in
            let a = draft.behaviors.contains { $0.id == l.id }, b = draft.behaviors.contains { $0.id == r.id }
            return a != b ? a : l.title.localizedCaseInsensitiveCompare(r.title) == .orderedAscending
        }
        items = out; groups = map
        chosen = Dictionary(uniqueKeysWithValues: draft.behaviors.map { ($0.id, $0) })
    }

    private func save() {
        // Keep the plan's own order for what stays, then the new ones as they come.
        let kept = draft.behaviors.compactMap { chosen[$0.id] }
        let added = items.filter { item in chosen[item.id] != nil && !draft.behaviors.contains(where: { $0.id == item.id }) }.compactMap { chosen[$0.id] }
        draft.behaviors = kept + added
        dismiss()
    }
}

// MARK: - Activities

private struct NunaPlanActivityPage: View {
    @ObservedObject var draft: NunaPlanDraft
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var recent: [String] = []
    @State private var picking = false
    @State private var pick = ""

    private let tint = NunaPalette.effortModerate

    var body: some View {
        NunaDetailScreen("Activity goal", centersTitle: true) {
            VStack(alignment: .leading, spacing: 12) {
                planH1("Set Your Weekly Activities")
                planLead("Add activities to your plan that will help support your goals.")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            planCaps(String(localized: "Generic activity"), size: 11.5, color: NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
            ForEach([NunaPlanActivity.strain, NunaPlanActivity.strength, NunaPlanActivity.recovery], id: \.self) { id in toggleCard(NunaPlanActivity.generic(id)) }
            if !recent.isEmpty {
                planCaps(String(localized: "Recent activities"), size: 11.5, color: NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14)
                ForEach(recent, id: \.self) { name in toggleCard(NunaPlanActivity.sport(name)) }
            }
            Button { picking = true } label: {
                NunaPlanRowCard(highlight: true) {
                    HStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(NunaPalette.textSecondary).frame(width: 34)
                        planCaps(String(localized: "Add activities"), size: 13.5)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 64)
                }
            }
            .buttonStyle(.plain)
            tips.padding(.top, 20)
        }
        .environment(\.nunaDetailSwitch, nil)
        .animation(.easeInOut(duration: 0.2), value: draft.activities)
        .task { await loadRecent() }
        .sheet(isPresented: $picking, onDismiss: addPicked) {
            NunaSportPicker(selection: $pick, allowsCustom: false, includesRest: false) { picking = false }
                .background(NunaBackdrop()).preferredColorScheme(NunaTheme.colorScheme)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { NunaPlanPrimaryButton(title: "Save activities") { dismiss() } }
    }

    private func toggleCard(_ a: NunaPlanActivity) -> some View {
        let on = draft.isOn(a.id)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                activityGlyph(a).frame(width: 22)
                planCaps(a.title, size: 12.5)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { on }, set: { draft.setActivity(a, on: $0) })).labelsHidden().toggleStyle(NunaPlanToggleStyle(tint: tint))
            }
            if on {
                NunaPlanDaysPicker(days: draft.days(a.id), tint: tint) { draft.setDays(a.id, $0) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "lightbulb").font(.system(size: 22, weight: .light))
                Text("Tips to set Activity Goals").font(.nuna(size: 18, weight: .semibold)).tracking(0).textCase(nil)
            }
            .foregroundStyle(NunaPalette.recoveryBlue)
            bullet("If you're adding an activity that's new to your routine, start slow by choosing 1 or 2 days a week and increase each week from there")
            bullet("Not sure which activities to choose? You can choose general goals around Cardio, Recovery, or Strength activities!")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.recoveryBlue.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bullet(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle().fill(NunaPalette.textPrimary).frame(width: 5, height: 5).offset(y: -3)
            Text(key).font(.nunaWords(size: 15)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The sports done lately, most-done first, then any the plan already holds.
    private func loadRecent() async {
        var counts: [String: Int] = [:]
        for r in await repo.workoutRows(days: 60) {
            let name = WorkoutSource.displaySport(r.sport)
            if NunaActivityKind.isRest(name) { continue }
            counts[name, default: 0] += 1
        }
        var names = counts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        for a in draft.activities { if let s = a.sportName, !names.contains(s) { names.append(s) } }
        recent = names
    }

    /// A sport chosen in Add activities joins the list, switched on.
    private func addPicked() {
        guard !pick.isEmpty else { return }
        if !recent.contains(pick) { recent.append(pick) }
        draft.setActivity(NunaPlanActivity.sport(pick), on: true)
        pick = ""
    }
}
#endif

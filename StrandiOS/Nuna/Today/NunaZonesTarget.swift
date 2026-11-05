#if os(iOS)
import SwiftUI
import StrandDesign

/// Under a heart-rate zones trend page (zones 1–3 or zones 4–5): the way to add an activity, the weekly target, and two cards on what zone training is
/// and why intensity matters. The cards are the same on both pages; the target and its advice differ.
struct NunaZonesFooter: View {
    /// Zones 4–5 when true, zones 1–3 when false.
    let high: Bool
    /// The weekly minutes of the last four weeks, averaged; read only when the target screen opens.
    let fourWeekAverage: () async -> Double?
    /// An activity was saved: the page reads its figures again.
    let onAdded: () async -> Void

    @AppStorage(NunaGoals.zonesEasyMinutes) private var easy = 0
    @AppStorage(NunaGoals.zonesHardMinutes) private var hard = 0
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var showTarget = false
    @State private var showAdd = false

    private var stored: Int { high ? hard : easy }

    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            Button { showAdd = true } label: { NunaFooterLinkRow(icon: "plus", title: "Add activity") }.buttonStyle(.plain)
            Button { showTarget = true } label: {
                NunaFooterLinkRow(icon: "checklist", title: stored > 0 ? "Update your HR zones goal" : "Set a HR zones goal",
                                  subtitle: stored > 0 ? LocalizedStringKey(String(localized: "Now \(NunaZonesTargetView.text(stored)) a week")) : nil)
            }.buttonStyle(.plain)
            NunaZonesExplainer()
        }
        .fullScreenCover(isPresented: $showTarget) {
            NunaZonesTargetView(high: high, fourWeekAverage: fourWeekAverage) { showTarget = false }
        }
        .sheet(isPresented: $showAdd) {
            NunaManualWorkoutSheet(editing: nil) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await onAdded()
                }
            }
            .nunaSheetChrome(detents: [.large])
        }
    }
}

/// "Set your target" for the weekly time in a group of zones.
struct NunaZonesTargetView: View {
    let high: Bool
    let fourWeekAverage: () async -> Double?
    let onClose: () -> Void

    @AppStorage(NunaGoals.zonesEasyMinutes) private var easy = 0
    @AppStorage(NunaGoals.zonesHardMinutes) private var hard = 0
    @State private var goal = 0
    @State private var average: Int?

    private var stored: Int { high ? hard : easy }
    /// The scale in minutes, what a drag rounds to, and the goal shown before one is set.
    private var low: Int { high ? 1 : 10 }
    private var top: Int { high ? 60 : 300 }
    private var step: Int { high ? 1 : 5 }
    private var fallback: Int { high ? 20 : 150 }
    private var tint: Color { NunaZoneWeeklyCard.color(high ? 3 : 1) }

    /// "50 min", or "2:30 hr" from an hour up.
    static func text(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60):\(String(format: "%02d", minutes % 60)) hr")
    }

    var body: some View {
        ZStack(alignment: .top) {
            NunaBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    Color.clear.frame(height: 56)
                    Text(high ? "Set your weekly HR zones 4–5 target for the coming week" : "Set your weekly HR zones 1–3 target for the coming week")
                        .font(.nuna(size: 22, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
                        .textCase(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    NunaTargetGauge(goal: $goal, low: low, high: top, step: step, nudge: high ? 5 : 30, tint: tint,
                                    average: average, averageLabel: "4 week avg.", text: Self.text).padding(.top, 8)
                    advice
                    VStack(spacing: 12) {
                        Button(action: save) {
                            Text("Save target").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity).frame(height: 54).background(Color.white, in: Capsule())
                        }.buttonStyle(.plain)
                        if stored > 0 {
                            Button { if high { hard = 0 } else { easy = 0 }; onClose() } label: {
                                Text("Remove").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                    .frame(maxWidth: .infinity).frame(height: 40)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 50)
            }
            .scrollIndicators(.hidden)
            header
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .onAppear { goal = min(max(stored > 0 ? stored : fallback, low), top) }
        .task { if let a = await fourWeekAverage() { average = Int(a.rounded()) } }
    }

    private var header: some View {
        ZStack {
            Text("Set your target").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1.2)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(Text("Close"))
                Spacer()
            }
        }
        .padding(.horizontal, 8).padding(.top, 4).frame(height: 52).frame(maxWidth: .infinity).background(NunaPalette.canvas)
    }

    /// What each group of zones is for, and about how much of it to aim for in a week (the guideline of 150 minutes of moderate activity, or 75 of hard).
    private var advice: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(high ? "High intensity" : "Aerobic base").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(tint)
                Text(high ? "Aim for about 20 minutes in zones 4–5 each week, in short hard efforts, to raise your VO₂ max and your ability to hold intense effort. Follow hard days with easy ones."
                          : "Aim for 150 minutes or more in zones 1–3 each week to build endurance and your body's ability to use oxygen during exercise.")
                    .font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        if high { hard = goal } else { easy = goal }
        onClose()
    }
}

/// What heart-rate zone training is and why intensity matters, for both zone pages.
struct NunaZonesExplainer: View {
    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    title("What is heart-rate zone training?")
                    paragraph("Zone training means watching how hard your heart works while you exercise and spending time in chosen ranges. Each zone trains something different, so mixing them is how fitness builds without wearing you out.")
                    paragraph("Here a zone is a share of your heart-rate reserve, the gap between your maximum and your resting heart rate. As your fitness changes, your resting heart rate changes and the zones move with it.")
                    Text("Heart-rate reserve = Max HR − resting HR").font(.nunaWords(size: 15, semibold: true)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    VStack(alignment: .leading, spacing: 8) {
                        zoneLine("Zone 5 (90–100%): all out")
                        zoneLine("Zone 4 (80–90%): hard")
                        zoneLine("Zone 3 (70–80%): moderate")
                        zoneLine("Zone 2 (60–70%): light")
                        zoneLine("Zone 1 (50–60%): very light")
                    }
                    pyramid.padding(.top, 6).frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    title("Why does intensity matter?")
                    paragraph("Balancing time across the zones is what builds lasting fitness: easy work lays the base, hard work raises the ceiling, and rest lets both settle in.")
                    paragraph("Zones 1–3 build your aerobic base, the body's ability to use oxygen steadily while you run, cycle or walk for a long time. Most of your training time belongs here. It improves endurance and long-term health and leaves you fresh for the next session.")
                    paragraph("Zones 4–5 push your heart close to its limit. They make it a more efficient pump, train the short hard efforts of a sprint, and raise your VO₂ max, a key measure of fitness and long-term health. They cost more recovery, so a little goes a long way.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nuna(size: 20, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }

    private func zoneLine(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(NunaPalette.textSecondary).frame(width: 4, height: 4).offset(y: -3)
            Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    /// Five layers, zone 5 at the top and narrowest, zone 1 at the foot and widest, each in the colour of its zone.
    private var pyramid: some View {
        let width: CGFloat = 250, layer: CGFloat = 40, gap: CGFloat = 3
        func foot(_ zone: Int) -> CGFloat { width * CGFloat(6 - zone) / 5 + 30 }
        return VStack(spacing: gap) {
            ForEach((1...5).reversed(), id: \.self) { zone in
                ZStack {
                    NunaZonePyramidLayer(topWidth: zone == 5 ? 22 : foot(zone + 1), bottomWidth: foot(zone))
                        .fill(NunaZoneWeeklyCard.color(zone - 1).opacity(0.55))
                    Text(verbatim: "\(zone)").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaZoneWeeklyCard.color(zone - 1))
                }
                .frame(width: foot(zone), height: layer)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A band of the pyramid: narrower at the top than at the foot, with the corners softened a little.
private struct NunaZonePyramidLayer: Shape {
    let topWidth: CGFloat
    let bottomWidth: CGFloat
    func path(in r: CGRect) -> Path {
        let cx = r.midX, top = r.minY, bottom = r.maxY
        var p = Path()
        p.move(to: CGPoint(x: cx - topWidth / 2, y: top))
        p.addLine(to: CGPoint(x: cx + topWidth / 2, y: top))
        p.addLine(to: CGPoint(x: cx + bottomWidth / 2, y: bottom))
        p.addLine(to: CGPoint(x: cx - bottomWidth / 2, y: bottom))
        p.closeSubpath()
        return p
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign

/// Under the Steps trend page: the way into the daily step target, and a short explanation of what steps are and how this app counts them.
struct NunaStepsFooter: View {
    @AppStorage(NunaGoals.steps) private var stored = 0
    @State private var showTarget = false

    private var goal: Int { NunaGoals.stepTarget(stored) }

    var body: some View {
        VStack(spacing: NunaSpacing.section) {
            Button { showTarget = true } label: {
                NunaCard(small: true) {
                    NunaListRow(stored > 0 ? "Update your daily step goal" : "Set a daily step goal",
                                subtitle: LocalizedStringKey(String(localized: "Now \(nunaThousands(Double(goal))) a day")),
                                systemImage: "checklist", showsChevron: true)
                }
            }
            .buttonStyle(.plain)
            about
        }
        .fullScreenCover(isPresented: $showTarget) { NunaStepsTargetView { showTarget = false } }
    }

    private var about: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("About steps").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).tracking(0)
                paragraph("Steps count the walking and moving that fills your day outside workouts. They are the simplest measure of how much you move, and they catch what heart-rate zones leave out.")
                paragraph("In large studies of adults, more daily steps go with a lower risk of heart disease and early death. Most of the gain comes by about 7,000 to 10,000 steps a day, and every extra thousand still helps if you are below that.")
                paragraph("Steps come from Apple Health when it is connected, otherwise from your strap's motion. If the strap's count runs high or low, adjust Step calibration in Persona. Today is left out of the average because the day is not over.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func paragraph(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3).textCase(nil).fixedSize(horizontal: false, vertical: true)
    }
}

/// "Set your target": a tall bar to drag to the daily step goal, the 30-day average marked beside it, and how long it takes to reach the optimal
/// level at 500 more steps a week.
struct NunaStepsTargetView: View {
    let onClose: () -> Void

    @AppStorage(NunaGoals.steps) private var stored = 0
    @EnvironmentObject private var repo: Repository
    @StateObject private var history = NunaSleepHistory()
    @State private var goal = NunaGoals.defaultSteps
    @State private var low = 1_000
    @State private var high = 11_000
    @State private var scaled = false

    /// Where the benefit levels off for most adults; the goal is led there by 500 a week.
    private static let optimal = 10_000
    private static let weeklyStep = 500
    private let barHeight: CGFloat = 300, barWidth: CGFloat = 92

    /// The 30 days before today, which is not finished.
    private var average: Int? {
        let cal = Calendar.current
        let values = (1...30).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }.compactMap { history.steps[Repository.localDayKey($0)] }
        return values.isEmpty ? nil : Int((values.reduce(0, +) / Double(values.count)).rounded())
    }

    private var weeksToOptimal: Int { goal >= Self.optimal ? 0 : Int((Double(Self.optimal - goal) / Double(Self.weeklyStep)).rounded(.up)) }
    private func fraction(_ v: Int) -> CGFloat { CGFloat(min(max(Double(v - low) / Double(max(high - low, 1)), 0), 1)) }
    private func text(_ v: Int) -> String { nunaThousands(Double(v)) }

    var body: some View {
        ZStack(alignment: .top) {
            NunaBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    Color.clear.frame(height: 56)
                    Text("Set your daily step target for the coming week").font(.nuna(size: 22, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textPrimary)
                        .textCase(nil).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    gauge.padding(.top, 8)
                    plan
                    VStack(spacing: 12) {
                        Button(action: save) {
                            Text("Save target").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingHead(1)).textCase(.uppercase).foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity).frame(height: 54).background(Color.white, in: Capsule())
                        }.buttonStyle(.plain)
                        if stored > 0 {
                            Button { stored = 0; onClose() } label: {
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
        .task { await history.load(repo: repo) }
        .onChange(of: history.loaded) { _, _ in setScale() }
        .onAppear { goal = NunaGoals.stepTarget(stored); setScale() }
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

    /// The scale is ten thousand steps tall and sits around the 30-day average (or the goal when there is no history); it is fixed once chosen so the
    /// bar does not move under the finger.
    private func setScale() {
        let centre = average ?? goal
        var lo = max(1_000, (centre - 5_000) / 100 * 100)
        lo = min(lo, max(1_000, goal - 1_000))
        low = lo
        high = max(lo + 10_000, (goal + 1_000 + 99) / 100 * 100)
        scaled = true
    }

    // MARK: Gauge

    private var gauge: some View {
        GeometryReader { g in
            let cx = g.size.width / 2
            let top = barHeight * (1 - fraction(goal))
            ZStack(alignment: .topLeading) {
                // The bar: a dark track and the blue fill up to the goal, with a grip at the top of it.
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(NunaPalette.effortModerate)
                        .frame(height: max(24, barHeight * fraction(goal)))
                        .overlay(alignment: .top) {
                            VStack(spacing: 3) { Capsule().fill(Color.black.opacity(0.25)).frame(width: 28, height: 2.5); Capsule().fill(Color.black.opacity(0.25)).frame(width: 28, height: 2.5) }.padding(.top, 14)
                        }
                }
                .frame(width: barWidth, height: barHeight)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                    let f = 1 - min(max(d.location.y / barHeight, 0), 1)
                    let raw = Double(low) + Double(f) * Double(high - low)
                    goal = min(max(Int((raw / 100).rounded()) * 100, low), high)
                })
                .position(x: cx, y: barHeight / 2)
                .accessibilityElement().accessibilityLabel(Text("Your goal")).accessibilityValue(Text(verbatim: text(goal)))
                .accessibilityAdjustableAction { d in goal = min(max(goal + (d == .increment ? 500 : -500), low), high) }
                // The goal, beside the top of the fill.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: text(goal)).font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortModerate).monospacedDigit()
                    Text("Your goal").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(width: 110, alignment: .trailing).position(x: cx - barWidth / 2 - 14 - 55, y: min(max(top + 24, 30), barHeight - 30))
                // The ends of the scale.
                Text(verbatim: text(high)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortModerate).position(x: cx, y: -16)
                Text(verbatim: text(low)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effortModerate).position(x: cx, y: barHeight + 18)
                // The 30-day average: a dashed line out to the right with its figure.
                if let avg = average, avg >= low, avg <= high {
                    let y = barHeight * (1 - fraction(avg))
                    Path { p in p.move(to: CGPoint(x: cx + barWidth / 2 - 6, y: y)); p.addLine(to: CGPoint(x: cx + barWidth / 2 + 70, y: y)) }
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: text(avg)).font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text("30-day average").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(width: 130, alignment: .leading).position(x: cx + barWidth / 2 + 12 + 65, y: y + 28)
                }
            }
        }
        .frame(height: barHeight + 40).padding(.top, 20)
    }

    // MARK: Plan

    private var plan: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                if weeksToOptimal > 0 {
                    Text(verbatim: String(localized: "Reach optimal in \(weeksToOptimal) weeks")).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "Raise your goal by \(Self.weeklyStep) steps each week until your average reaches \(text(Self.optimal)) or more."))
                        .font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    ramp
                } else {
                    Text("You are in the optimal range").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "Your goal is already \(text(Self.optimal)) or more, the range where most of the benefit is."))
                        .font(.nunaWords(size: 15)).tracking(0).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Today's goal on the left, the optimal on the right, and the rise between them.
    private var ramp: some View {
        let h: CGFloat = 96
        let a = h * CGFloat(Double(goal) / Double(Self.optimal)), b = h
        return VStack(spacing: 8) {
            GeometryReader { g in
                let w = g.size.width, bar: CGFloat = 20
                ZStack(alignment: .bottomLeading) {
                    Path { p in
                        p.move(to: CGPoint(x: bar, y: h)); p.addLine(to: CGPoint(x: bar, y: h - a)); p.addLine(to: CGPoint(x: w - bar, y: h - b)); p.addLine(to: CGPoint(x: w - bar, y: h)); p.closeSubpath()
                    }.fill(LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(NunaPalette.effortModerate).frame(width: bar, height: a)
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white).frame(width: bar, height: b).offset(x: w - bar)
                }
            }.frame(height: h)
            HStack {
                Text("Your goal").foregroundStyle(NunaPalette.effortModerate)
                Spacer()
                Text("Weekly increase").foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Text("Optimal").foregroundStyle(NunaPalette.textPrimary)
            }
            .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
        }
    }

    private func save() {
        stored = goal
        onClose()
    }
}
#endif

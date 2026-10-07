#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Water, in the Nuna look. The same data and the same rules as the Default screen (the day total and the drinks are the local hydration
/// store, the goal is `HydrationGoal` from sex and today's Effort); only the drawing is new: the same W / M / 6M trend card as the Steps
/// detail, with the goal as a dashed line, and the quick log buttons below it.
struct NunaHydrationView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(HydrationStore.customSizeKey) private var customSizeML = HydrationGoal.cupML
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var totalML: Double = 0
    @StateObject private var series = NunaSeriesModel()
    @State private var range = 7
    @State private var page = 0
    @State private var reloadTick = 0
    @State private var settingCustom = false

    private var goalML: Int { repo.hydrationGoalML(profileSex: profile.sex) }
    private var fraction: Double { HydrationGoal.fraction(totalML: totalML, goalML: goalML) }
    private var percent: Int { min(100, Int((fraction * 100).rounded(.towardZero))) }
    private func litres(_ ml: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, HydrationGoal.litres(fromML: ml)) }

    var body: some View {
        NunaDetailScreen("Water") {
            trendCard
            logCard
            NunaExpandRow(title: "How the goal is set", subtitle: "Your sex and today's Effort", systemImage: "drop",
                          text: "A simple goal that starts from your sex and rises with the Effort you add during the day. It is a guide, not a prescription.")
        }
        .task(id: reloadTick) { await reload() }
        .sheet(isPresented: $settingCustom) {
            NunaHydrationAmountSheet(title: "Custom size", initialML: customSizeML) { ml in
                customSizeML = ml; settingCustom = false
            } onCancel: { settingCustom = false }
        }
    }

    // MARK: Trend (the same card as the Steps detail)

    /// Litres today with the way the week or month went, as columns, and the goal as a dashed line across them.
    private var trendCard: some View {
        let togo = max(goalML - Int(totalML.rounded()), 0)
        return NunaTrendDetailCard(
            caption: "Today", valueText: litres(totalML), unit: "L",
            chip: percent >= 100 ? (text: "Goal reached", color: NunaPalette.charge) : (text: LocalizedStringKey("\(percent)% of today's goal"), color: NunaPalette.restText),
            note: percent >= 100 ? nil : String(localized: "\(litres(Double(togo))) L to go"),
            series: series, showsBand: false, reference: Double(goalML) / 1000, referenceLabel: "Goal",
            lineColor: NunaPalette.rest, decimals: 1, higherIsBetter: true, directional: false, bars: true, range: $range, page: $page)
    }

    // MARK: Quick log

    private var logCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Log a drink")
                HStack(spacing: 10) {
                    logButton("Sip", "drop", HydrationGoal.sipML)
                    logButton("Cup", "cup.and.saucer.fill", HydrationGoal.cupML)
                    logButton("Bottle", "waterbottle.fill", HydrationGoal.bottleML)
                }
                HStack(spacing: 10) {
                    Button { Task { await add(customSizeML) } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "drop.circle").font(.nuna(size: 15, weight: .semibold))
                            Text(verbatim: String(localized: "Custom \(customSizeML) ml")).font(.nuna(size: 14.5, weight: .bold))
                        }
                        .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 48)
                        .background(NunaPalette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { settingCustom = true } label: { NunaBareIcon("pencil", target: 48) }
                        .buttonStyle(.plain).accessibilityLabel(Text("Set custom container size"))
                }
                Text(verbatim: "\(String(localized: "Sip")) \(HydrationGoal.sipML) ml · \(String(localized: "Cup")) \(HydrationGoal.cupML) ml · \(String(localized: "Bottle")) \(HydrationGoal.bottleML) ml")
                    .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
            }
        }
    }

    private func logButton(_ title: LocalizedStringKey, _ icon: String, _ ml: Int) -> some View {
        Button { Task { await add(ml) } } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.nuna(size: 18, weight: .semibold)).frame(height: 24)
                Text(title).font(.nuna(size: 13.5, weight: .bold))
            }
            .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 66)
            .background(NunaPalette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Data

    private func add(_ ml: Int) async {
        guard ml > 0 else { return }
        _ = await repo.logHydration(amountMl: ml)
        repo.noteHydrationChanged()
        reloadTick &+= 1
    }

    private func reload() async {
        let key = Repository.localDayKey(Date())
        totalML = await repo.hydrationTotal(day: key)
        // Litres per day over the last six months (a day nothing was logged on has no reading, so it stays empty rather than 0), for the same W / M / 6M card the Steps detail uses.
        series.set((await repo.hydrationHistory(days: 190)).filter { $0.value > 0 }.map { ($0.day, $0.value / 1000) })
    }
}

/// A stepper in a sheet for an amount in ml: setting the custom size.
private struct NunaHydrationAmountSheet: View {
    let title: LocalizedStringKey
    let initialML: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void
    @State private var ml: Int

    private static let minML = 10, maxML = 3000, stepML = 10
    init(title: LocalizedStringKey, initialML: Int, onSave: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.title = title; self.initialML = initialML; self.onSave = onSave; self.onCancel = onCancel
        _ml = State(initialValue: min(Self.maxML, max(Self.minML, initialML)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            HStack {
                Text("Amount").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Text(verbatim: "\(ml) ml").font(.nuna(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
            }
            Stepper("", value: $ml, in: Self.minML...Self.maxML, step: Self.stepML).labelsHidden()
                .accessibilityLabel(Text("Amount in millilitres")).accessibilityValue(Text(verbatim: "\(ml) ml"))
            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }.buttonStyle(.nuna(.ghost, height: 50, fullWidth: true))
                Button("Save") { onSave(ml) }.buttonStyle(.nuna(.primary, height: 50, fullWidth: true))
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .presentationDetents([.height(300)]).presentationDragIndicator(.visible)
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Water, in the Nuna look. The same data and the same rules as the Default screen (the day total and the drinks are the local hydration
/// store, the goal is `HydrationGoal` from sex and today's Effort); only the drawing is new: a hero with the litres against the goal,
/// quick log buttons, today's drinks, and the last seven days as columns.
struct NunaHydrationView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(HydrationStore.customSizeKey) private var customSizeML = HydrationGoal.cupML
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var totalML: Double = 0
    @State private var importedML: Double = 0
    @State private var history: [(day: String, value: Double)] = []
    @State private var entries: [HydrationEntry] = []
    @State private var reloadTick = 0
    @State private var editing: HydrationEntry?
    @State private var settingCustom = false

    private var goalML: Int { repo.hydrationGoalML(profileSex: profile.sex) }
    private var fraction: Double { HydrationGoal.fraction(totalML: totalML, goalML: goalML) }
    private var percent: Int { min(100, Int((fraction * 100).rounded(.towardZero))) }
    private func litres(_ ml: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, HydrationGoal.litres(fromML: ml)) }

    var body: some View {
        NunaDetailScreen("Water") {
            hero
            logCard
            drinksCard
            weekCard
            nunaFootnote("A simple goal that adjusts to your effort. General wellness guidance, not medical advice.")
        }
        .task(id: reloadTick) { await reload() }
        .sheet(item: $editing) { entry in
            NunaHydrationAmountSheet(title: "Edit drink", initialML: entry.amountMl) { ml in
                editing = nil
                Task { _ = await repo.updateHydrationEntry(id: entry.id, amountMl: ml); repo.noteHydrationChanged(); reloadTick &+= 1 }
            } onCancel: { editing = nil }
        }
        .sheet(isPresented: $settingCustom) {
            NunaHydrationAmountSheet(title: "Custom size", initialML: customSizeML) { ml in
                customSizeML = ml; settingCustom = false
            } onCancel: { settingCustom = false }
        }
    }

    // MARK: Hero

    private var hero: some View {
        NunaCard(padding: EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Today").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(verbatim: "\(percent)%", color: percent >= 100 ? NunaPalette.charge : nil)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: litres(totalML)).font(.nuna(size: 56, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(56))
                        .foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: "/ \(litres(Double(goalML))) L").font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaProgressBar(fraction: fraction, color: NunaPalette.rest)
                Text(verbatim: String(localized: "\(percent)% of today's goal")).font(.nuna(size: 13, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
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

    // MARK: Today's drinks

    @ViewBuilder private var drinksCard: some View {
        if !entries.isEmpty || importedML > 0 {
            NunaCard(small: true, padding: EdgeInsets(top: 12, leading: 18, bottom: 6, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaTitleRow(title: "Today's drinks") { EmptyView() }.padding(.bottom, 6)
                    if importedML > 0 {
                        HStack(spacing: 12) {
                            NunaIconTile("heart.text.square")
                            Text("From Apple Health").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer(minLength: 8)
                            Text(verbatim: "\(Int(importedML.rounded())) ml").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                        .frame(minHeight: 56)
                        if !entries.isEmpty { NunaDivider() }
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        if idx > 0 { NunaDivider() }
                        HStack(spacing: 4) {
                            Button { editing = entry } label: {
                                HStack(spacing: 12) {
                                    NunaIconTile("drop.fill", tint: NunaPalette.restText)
                                    Text(verbatim: AppClock.hourMinuteFormatter().string(from: entry.loggedAt))
                                        .font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    Spacer(minLength: 8)
                                    Text(verbatim: "\(entry.amountMl) ml").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }
                                .frame(minHeight: 56).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button(role: .destructive) { Task { _ = await repo.deleteHydrationEntry(id: entry.id); repo.noteHydrationChanged(); reloadTick &+= 1 } } label: {
                                Image(systemName: "trash").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                                    .frame(width: 40, height: 40).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                        }
                    }
                    if !entries.isEmpty {
                        Text("Tap a drink to edit it, or use the trash to delete.").font(.nuna(size: 12, weight: .semibold))
                            .foregroundStyle(NunaPalette.textMuted).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: Last 7 days

    private var weekCard: some View {
        let cal = Calendar.current
        let top = max(Double(max(goalML, 1)), history.map(\.value).max() ?? 0, 1)
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        let wd = DateFormatter(); wd.locale = AppLanguage.activeLocale; wd.setLocalizedDateFormatFromTemplate("EEE")
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Last 7 days")
                if history.isEmpty {
                    Text("No history yet.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                } else {
                    NunaColumns(items: history.compactMap { bar in
                        guard let d = parser.date(from: bar.day) else { return nil }
                        return NunaColumns.Item(weekday: wd.string(from: d), date: d, fraction: bar.value > 0 ? bar.value / top : nil,
                                                valueText: bar.value > 0 ? litres(bar.value) : nil, highlight: cal.isDateInToday(d))
                    }, color: NunaPalette.rest, highlightColor: NunaPalette.restText, showsDates: false)
                }
            }
        }
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
        history = await repo.hydrationHistory(days: 7)
        entries = repo.hydrationEntries()
        importedML = await repo.hydrationImportedTotal(day: key)
    }
}

/// A stepper in a sheet for an amount in ml: editing a drink, or setting the custom size.
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

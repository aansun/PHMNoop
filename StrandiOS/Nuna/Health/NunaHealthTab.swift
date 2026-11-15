#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// The Health tab: fitness age, the Lab Book, the health monitor (the five vital signs against their usual range) and the stress monitor, one under the other.
struct NunaHealthTabView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @StateObject private var day = NunaTodayModel()

    var body: some View {
        ScrollView {
            VStack(spacing: NunaSpacing.section) {
                NunaFitnessAgeSummary()
                NunaLabBookCard()
                NunaHealthMonitorCard(hrv: day.hrv, restingHr: day.restingHr, spo2: day.spo2, respiratory: day.respiratory, skinTemp: day.extras["skin_temp"])
                if !day.stressStatus.isReady {
                    // Still learning the person: no stress figure, only how far along it is.
                    if day.loaded { NunaStressCalibrationCard(nights: day.stressStatus.nights) }
                } else if day.loaded {
                    // Shown even before the day has a reading, so the card does not come and go: it then reads "–" over an empty chart.
                    NunaStressSummaryCard(curve: day.stressCurve, typicalMin: day.stressTypicalMin, isToday: day.isToday)
                }
                Text("Fitness age, the health monitor and the stress monitor are not medical devices and cannot diagnose or manage medical conditions. They do not give medical advice. Always consult your doctor about health concerns, and never delay or change medical care because of what they show.")
                    .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(NunaPalette.hairline).frame(height: 1) }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(NunaBackdrop())
        .nunaTodayDestinations()
        .task(id: repo.refreshSeq) { await day.load(repo: repo, profile: profile) }
    }
}

/// "5 years younger", "1 year older": the gap between fitness age and calendar age, in the singular for one year. Positive is younger.
func nunaYearsGap(_ diff: Int) -> LocalizedStringKey {
    switch diff {
    case 1: return "1 year younger"
    case -1: return "1 year older"
    case let d where d > 0: return "\(d) years younger"
    default: return "\(-diff) years older"
    }
}

/// Fitness age as the orb, with the pace of aging under it and the way into the full page. The card has no edge at the top: its tint fades into the
/// page, and it is darkest at the bottom.
struct NunaFitnessAgeSummary: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("nuna.fitnessAgeCalibratingHidden") private var calibratingHidden = false
    /// The Body Age stored each week, which the pace is read from.
    @State private var series: [(day: String, value: Double)] = []
    /// The age of the latest 7 days, the figure on the orb: the one the fitness age page shows.
    @State private var live: NunaHealthspanResult?
    @State private var loaded = false

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var readings: [PaceOfAging.Reading] {
        series.compactMap { r in Self.dayParser.date(from: r.day).map { PaceOfAging.Reading(time: $0.timeIntervalSince1970, fitnessAge: r.value) } }
    }

    /// Calibrating for the first 90 days of readings, and while the pace is still firming up.
    private var isCalibrating: Bool {
        let all = readings
        guard let first = all.first?.time, let last = all.last?.time else { return false }
        return (last - first) / 86_400 < 90 || (PaceOfAging.compute(all)?.confidence ?? .early) != .solid
    }

    private var tint: Color {
        guard let age = live?.bodyAge, profile.age > 0 else { return NunaFitnessAgeTone.tint(gap: nil) }
        return NunaFitnessAgeTone.tint(gap: Int((Double(profile.age) - age).rounded()))
    }

    var body: some View {
        VStack(spacing: 14) {
            if let age = live?.bodyAge {
                orb(age)
                if isCalibrating, !calibratingHidden { calibrating }
                pace
            } else {
                empty
            }
            NavigationLink(value: NunaTodayRoute.fitnessAge) {
                Text("Go to fitness age").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52)
                    .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 16, trailing: 16))
        .background {
            // Clear at the top (so the card melts into the page), the card colour at the bottom, with the tint of the orb in between.
            RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous)
                .fill(LinearGradient(stops: [
                    .init(color: NunaPalette.canvas.opacity(0), location: 0),
                    .init(color: tint.opacity(0.07), location: 0.4),
                    .init(color: NunaPalette.card, location: 0.8),
                ], startPoint: .top, endPoint: .bottom))
        }
        .background(alignment: .top) {
            // A soft glow above the card, so there is no line where the card starts.
            RadialGradient(colors: [tint.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 420).offset(y: -140).allowsHitTesting(false)
        }
        .task(id: repo.refreshSeq) {
            series = await repo.exploreSeries(key: "body_age", source: "my-whoop", days: 200)
            live = await NunaHealthspan.latest(repo: repo, profile: profile)
            loaded = true
        }
    }

    private func orb(_ age: Double) -> some View {
        let gap: Int? = profile.age > 0 ? Int((Double(profile.age) - age).rounded()) : nil
        // Over a room as wide as the card, so an orb a little wider than the card does not widen it.
        return Color.clear.frame(maxWidth: .infinity).frame(height: 320)
            .overlay { NunaFitnessOrb(tint: tint, size: 360, irregularity: NunaFitnessAgeTone.irregularity(pace: PaceOfAging.compute(readings)?.pace)) { NunaFitnessOrbCenter(value: age, gap: gap, numberSize: 48) } }
    }

    /// The note while the pace is still firming up; it can be closed and stays closed.
    private var calibrating: some View {
        let blue = NunaPalette.effortModerate
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hourglass").font(.nuna(size: 16, weight: .regular)).foregroundStyle(blue).padding(.top, 2)
            Text("Your fitness age is calibrating for its first 90 days, so fluctuations are normal. As more weeks of readings come in, it will stabilize.")
                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(blue).textCase(nil).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation(.easeOut(duration: 0.2)) { calibratingHidden = true } } label: {
                Image(systemName: "xmark").font(.nuna(size: 13, weight: .bold)).foregroundStyle(blue.opacity(0.8)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Close"))
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 14)
        .background(blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Pace of aging

    private var pace: some View {
        let all = readings
        let now = PaceOfAging.compute(all)
        let before = PaceOfAging.compute(Array(all.dropLast()))
        let move: Double? = now.flatMap { n in before.map { n.pace - $0.pace } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pace of aging").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                if let move, abs(move) >= 0.05 {
                    let good = move < 0
                    HStack(spacing: 5) {
                        Image(systemName: good ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.nuna(size: 8))
                        Text(good ? "slower vs. last week" : "faster vs. last week").font(.nuna(size: 12, weight: .bold)).textCase(nil)
                    }
                    .foregroundStyle(good ? NunaPalette.charge : NunaPalette.warning)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background((good ? NunaPalette.charge : NunaPalette.warning).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            NunaPaceRuler(value: now?.pace)
            if now == nil {
                Text(verbatim: all.isEmpty ? String(localized: "Pace of aging appears after 6 weekly readings.")
                     : String(localized: "Pace of aging appears after 6 weekly readings. You have \(all.count) so far."))
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fitness age").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Text(loaded ? "Not ready yet" : " ").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Text("Fitness age needs your age in your profile and at least 3 of its 9 inputs from the last 7 days.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}

/// The pace of aging on a ruler from -1.0x to 3.0x: fine ticks, a longer one at every half step, and a white mark with the figure above it.
struct NunaPaceRuler: View {
    let value: Double?
    private static let lo = -1.0, hi = 3.0

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                // The word at an end is left out while the figure sits over it.
                let f = value.map { (min(max($0, Self.lo), Self.hi) - Self.lo) / (Self.hi - Self.lo) } ?? 0.5
                HStack {
                    HStack(spacing: 6) {
                        Circle().strokeBorder(NunaPalette.textSecondary, lineWidth: 5).frame(width: 18, height: 18)
                        Text("Slow").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    .opacity(f < 0.3 ? 0 : 1)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("Fast").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        NunaPaceGlyph(fast: true)
                    }
                    .opacity(f > 0.7 ? 0 : 1)
                }
                .padding(.top, 14)
                GeometryReader { geo in
                    let f = value.map { (min(max($0, Self.lo), Self.hi) - Self.lo) / (Self.hi - Self.lo) } ?? 0.5
                    Text(verbatim: value.map { String(format: "%.1fx", locale: AppLanguage.activeLocale, $0) } ?? "–")
                        .font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .position(x: min(max(geo.size.width * f, 34), geo.size.width - 34), y: 14)
                }
                .frame(height: 30)
            }
            .frame(height: 32)
            Canvas { ctx, size in
                let steps = 80
                let f = value.map { (min(max($0, Self.lo), Self.hi) - Self.lo) / (Self.hi - Self.lo) }
                for i in 0...steps {
                    let x = size.width * CGFloat(i) / CGFloat(steps)
                    let major = i % 10 == 0
                    let h: CGFloat = major ? 40 : 30
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: (size.height - h) / 2)); path.addLine(to: CGPoint(x: x, y: (size.height + h) / 2))
                    ctx.stroke(path, with: .color(NunaPalette.textSecondary.opacity(major ? 0.75 : 0.4)), lineWidth: major ? 1.6 : 1)
                }
                if let f {
                    let x = size.width * CGFloat(f)
                    var mark = Path()
                    mark.move(to: CGPoint(x: x, y: 0)); mark.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(mark, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            .frame(height: 48)
            HStack {
                Text(verbatim: "-1.0x"); Spacer(); Text(verbatim: "1.0x"); Spacer(); Text(verbatim: "3.0x")
            }
            .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }
}

/// The five vital signs side by side, each with a mark for in range, out of range or no reading, and a line with how many are in range.
struct NunaHealthMonitorCard: View {
    let hrv: Double?
    let restingHr: Double?
    let spo2: Double?
    let respiratory: Double?
    let skinTemp: Double?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var hrvS = NunaSeriesModel()
    @StateObject private var rhrS = NunaSeriesModel()
    @StateObject private var respS = NunaSeriesModel()
    @StateObject private var skinS = NunaSeriesModel()

    private struct Vital: Identifiable {
        let id: String
        let icon: String
        let label: String
        /// nil with no reading (or no range yet), otherwise whether it sits in its usual range.
        let ok: Bool?
    }

    /// Nights with a sleep reading, which the range and the early warning go by.
    private var phase: VitalRange.Phase { VitalRange.phase(nights: max(hrvS.nights, rhrS.nights)) }
    private var loaded: Bool { hrvS.loaded && rhrS.loaded }

    private var vitals: [Vital] {
        let hasRange = phase.hasRange
        return [
            Vital(id: "resp", icon: "met:respiratory-rate", label: "RESP", ok: respiratory.flatMap { v in respS.verdict(v, floor: VitalRange.respiratoryFloor).map { $0 == .inRange } }),
            Vital(id: "spo2", icon: "vital:spo2", label: "SpO₂", ok: hasRange ? spo2.map { $0 >= 95 } : nil),
            Vital(id: "rhr", icon: "met:resting-heart-rate", label: "RHR", ok: restingHr.flatMap { v in rhrS.verdict(v, floor: 1).map { $0 == .inRange } }),
            Vital(id: "hrv", icon: "met:heart-rate-variability", label: "HRV", ok: hrv.flatMap { v in hrvS.verdict(v, floor: 1).map { $0 == .inRange } }),
            Vital(id: "temp", icon: "vital:temp", label: "TEMP", ok: skinTemp.flatMap { v in skinS.skinVerdict(v).map { $0 == .inRange } }),
        ]
    }

    var body: some View {
        let all = vitals
        let known = all.filter { $0.ok != nil }.count
        let within = all.filter { $0.ok == true }.count
        NavigationLink(value: NunaTodayRoute.vitalSigns) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Health monitor").font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    if case .calibrating(let n) = phase, loaded {
                        // Still learning the person: nothing about their vitals is judged, only how far along it is.
                        NunaLockedColumns(items: all.map { ($0.icon, LocalizedStringKey($0.label)) }, accessibility: "The health monitor is locked")
                        let left = VitalRange.calibrationNights - n
                        NunaNightsPanel(message: left == 1 ? "Wear your strap to sleep for 1 more night to unlock."
                                        : "Wear your strap to sleep for \(left) more nights to unlock.",
                                        nights: n, needed: VitalRange.calibrationNights)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(Array(all.enumerated()), id: \.element.id) { idx, v in
                                if idx > 0 { Rectangle().fill(NunaPalette.textMuted.opacity(0.4)).frame(width: 1, height: 78) }
                                column(v)
                            }
                        }
                        if loaded { summary(within: within, known: known) }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: repo.refreshSeq) {
            await hrvS.load(repo: repo, key: "hrv", source: "my-whoop", days: 400)
            await rhrS.load(repo: repo, key: "rhr", source: "my-whoop", days: 400)
            await respS.load(repo: repo, key: "resp_rate", source: "my-whoop")
            await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop")
        }
    }

    private func column(_ v: Vital) -> some View {
        let tint = v.ok == nil ? NunaPalette.textMuted : (v.ok == true ? NunaPalette.charge : NunaPalette.warning)
        return VStack(spacing: 6) {
            NunaIcon(name: v.icon, size: 23, weight: .medium).foregroundStyle(NunaPalette.textSecondary).frame(height: 28)
            Text(verbatim: v.label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).foregroundStyle(NunaPalette.textPrimary)
            badge(tint: tint, symbol: v.ok == nil ? "minus" : (v.ok == true ? "checkmark" : "exclamationmark"), side: 22)
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(tint: Color, symbol: String, side: CGFloat = 26) -> some View {
        Image(systemName: symbol).font(.nuna(size: side < 26 ? 10 : 11, weight: .heavy)).foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: side < 26 ? 5 : 6, style: .continuous))
    }

    /// The count in range and, under it, the early warning: it speaks only once there are fourteen nights, and until then says how many are left.
    private func summary(within: Int, known: Int) -> some View {
        let allIn = known > 0 && within == known
        let raised = phase.isTrusted && (appModel.illnessSignal.map { $0.level != .quiet } ?? false)
        let tint = known == 0 ? NunaPalette.textMuted : (raised || !allIn ? NunaPalette.warning : NunaPalette.charge)
        let title: String = raised ? String(localized: "Signals are up")
            : (known == 0 ? String(localized: "No data") : String(localized: "\(within)/5 metrics within range"))
        let detail: String? = {
            if raised { return String(localized: "Some signals are away from your range. Take it easy and watch how you feel.") }
            if case .learning(let n) = phase {
                let left = VitalRange.trustedNights - n
                return left == 1 ? String(localized: "Early warning starts after 14 nights: 1 more night.")
                    : String(localized: "Early warning starts after 14 nights: \(left) more nights.")
            }
            return known == 0 ? nil : String(localized: "No vital-sign warning.")
        }()
        return HStack(spacing: 12) {
            badge(tint: tint, symbol: known == 0 ? "minus" : (raised || !allIn ? "exclamationmark" : "checkmark"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                if let detail {
                    Text(verbatim: detail).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 9).frame(minHeight: 44)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The stress monitor of the Health tab: the time spent in high stress today with how it compares to a typical day of this weekday, and the day's
/// curve beside it, ending in a dot on the latest reading.
struct NunaStressSummaryCard: View {
    let curve: DaytimeStress.Result?
    /// High-stress minutes of a typical day of this weekday; nil until there are earlier days to average.
    let typicalMin: Int?
    var isToday = true

    private var scored: Bool { curve?.hours.contains { $0.level != nil } ?? false }
    private var highMin: Int? { scored ? curve.map(StressDayCurve.highMinutes) : nil }

    private var weekday: String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: Date())
    }

    private var stressRoute: NunaTodayRoute {
        MetricCatalog.metric(key: "stress", source: "my-whoop").map { .metric($0) } ?? .allMetrics
    }

    var body: some View {
        NavigationLink(value: stressRoute) {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Stress monitor").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isToday ? "Today's high stress" : "High stress")
                                .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, -8)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: highMin.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "–")
                                    .font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                                if highMin != nil { Text("hrs").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                            }
                            comparison
                        }
                        .frame(width: 150, alignment: .leading)
                        NunaStressDayChart(points: curve?.timeline ?? []).frame(height: 120)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The pill under the figure: green with a down arrow when today is below a typical day of this weekday, amber with an up arrow above it.
    @ViewBuilder private var comparison: some View {
        if isToday, let highMin, let typicalMin {
            let diff = highMin - typicalMin
            let flat = abs(diff) < 5
            let tint: Color = flat ? NunaPalette.textSecondary : (diff < 0 ? NunaPalette.charge : NunaPalette.warning)
            HStack(spacing: 5) {
                Image(systemName: flat ? "equal" : (diff < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")).font(.nuna(size: 9, weight: .bold))
                Text(verbatim: String(format: String(localized: "vs. typical %@"), weekday)).font(.nuna(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7).textCase(nil)
            }
            .foregroundStyle(tint).padding(.horizontal, 10).frame(height: 28)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
#endif

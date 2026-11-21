#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Words and symbols

extension NunaEnvironmentFormat {
    /// The US AQI band in words short enough for a chip.
    static func bandName(_ band: AirQuality.Band) -> String {
        switch band {
        case .good: return String(localized: "Good")
        case .moderate: return String(localized: "Moderate")
        case .unhealthyForSensitive: return String(localized: "Sensitive groups")
        case .unhealthy: return String(localized: "Unhealthy")
        case .veryUnhealthy: return String(localized: "Very unhealthy")
        case .hazardous: return String(localized: "Hazardous")
        }
    }

    /// An icon for a sky by its OpenWeather code; a clear sky at night is the moon.
    static func symbol(conditionId: Int?, feelsLikeC: Double?, night: Bool = false) -> String {
        switch conditionId ?? 800 {
        case 200..<300: return "cloud.bolt.rain"
        case 300..<400: return "cloud.drizzle"
        case 500..<600: return "cloud.rain"
        case 600..<700: return "cloud.snow"
        case 700..<800: return "cloud.fog"
        case 801...802: return night ? "cloud.moon" : "cloud.sun"
        case 803...: return "cloud"
        default: return night ? "moon.stars" : ((feelsLikeC ?? 0) >= 33 ? "sun.max" : "sun.min")
        }
    }

    static func isNight(_ ts: Int) -> Bool {
        let h = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return h >= 19 || h < 5
    }

    /// "06:00 – 09:00", with the day in front of it when it is not today ("Tomorrow 06:00 – 09:00").
    static func window(_ w: EnvironmentOutlook.Window) -> String {
        let cal = Calendar.current
        let start = Date(timeIntervalSince1970: TimeInterval(w.start))
        let day = cal.isDateInToday(start) ? "" : (cal.isDateInTomorrow(start) ? String(localized: "Tomorrow") + " " : start.formatted(.dateTime.weekday(.abbreviated)) + " ")
        return day + NunaInsightText.clockHour(w.start) + " – " + NunaInsightText.clockHour(w.end)
    }

    static func percent(_ chance: Double) -> String { "\(Int((chance * 100).rounded()))%" }

    /// Green for a stretch that suits time outdoors, yellow for one to adjust to, red for one to spend indoors.
    static func fitColor(_ fit: OutdoorFit) -> Color {
        switch fit { case .good: return NunaPalette.charge; case .adjust: return NunaPalette.warning; case .indoors: return NunaPalette.alert }
    }

    /// The verdict in the words of the card: short, capital, a call to action rather than a forecast.
    static func verdictWord(_ level: EnvironmentAdvice.Level) -> String {
        switch level {
        case .good: return String(localized: "Good to go")
        case .adjust: return String(localized: "Ease it")
        case .indoors: return String(localized: "Train indoors")
        }
    }
}

// MARK: - Strain room

/// How much the day has room for: the Strain band today's Recovery supports (the one the Strain page and the plan judge by) and the Strain done so far.
struct NunaStrainRoom: Equatable {
    let load: TrainingLoad
    /// The band on the 0-21 axis.
    let band: ClosedRange<Int>?
    /// Strain so far, on the 0-21 axis.
    let soFar: Double?

    static func make(chargePct: Double?, effort: Double?) -> NunaStrainRoom {
        let band = CoupledView.optimalStrainRange(recovery: chargePct)
        let done = effort.map { UnitFormatter.effortValue($0, scale: .whoop) }
        return NunaStrainRoom(load: TrainingLoad.of(recoveryPct: chargePct, targetHigh: band.map { Double($0.upperBound) }, soFar: done), band: band, soFar: done)
    }

    /// "14–18", on the scale the person chose.
    func bandText(_ scale: EffortScale) -> String? {
        guard let band else { return nil }
        func shown(_ v: Int) -> Int { Int(UnitFormatter.effortValue(Double(v) / UnitFormatter.effortScaleFactor, scale: scale).rounded()) }
        return "\(shown(band.lowerBound))–\(shown(band.upperBound))"
    }

    func soFarText(_ scale: EffortScale) -> String? {
        soFar.map { UnitFormatter.effortDisplay($0 / UnitFormatter.effortScaleFactor, scale: scale) }
    }

    var loadWord: String {
        switch load {
        case .recover: return String(localized: "Target reached")
        case .easy: return String(localized: "Keep it easy")
        case .moderate: return String(localized: "Room for a steady session")
        case .hard: return String(localized: "Room for a hard session")
        }
    }
}

// MARK: - What each pick is called, and why

extension ActivityPick {
    var title: String {
        switch kind {
        case .easyWalk: return String(localized: "Easy walk")
        case .run: return String(localized: "Zone 2 run")
        case .intervalRun: return String(localized: "Interval run")
        case .ride: return String(localized: "Steady ride")
        case .strength: return String(localized: "Strength")
        case .treadmill: return String(localized: "Treadmill run")
        case .indoorRide: return String(localized: "Indoor ride")
        case .mobility: return String(localized: "Mobility")
        case .breathwork: return String(localized: "Breathwork")
        }
    }

    var symbol: String {
        switch kind {
        case .easyWalk: return "figure.walk"
        case .run, .intervalRun: return "figure.run"
        case .ride, .indoorRide: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .treadmill: return "figure.run.treadmill"
        case .mobility: return "figure.cooldown"
        case .breathwork: return "wind"
        }
    }

    var intensity: String {
        switch kind {
        case .easyWalk: return String(localized: "Zone 1")
        case .run, .ride, .treadmill, .indoorRide: return String(localized: "Zone 2")
        case .intervalRun: return String(localized: "Zone 4–5 intervals")
        case .strength: return String(localized: "Moderate")
        case .mobility: return String(localized: "Light")
        case .breathwork: return String(localized: "Calm")
        }
    }

    /// "40 MIN · ZONE 2 · OUTDOORS": the facts of the session in one line.
    var meta: String {
        [String(localized: "\(minutes) min"), intensity, outdoors ? String(localized: "Outdoors") : String(localized: "Indoors")].joined(separator: " · ")
    }

    /// The reasons as sentences, the Strain one first: what it fits, then what the sky and the air allow.
    func reason(strainBand: String?) -> String {
        var parts: [String] = []
        for why in whys.prefix(3) {
            switch why {
            case .fitsTarget:
                parts.append(strainBand.map { String(localized: "Fits the Strain of \($0) your Recovery supports") } ?? String(localized: "Fits the Strain your Recovery supports"))
            case .targetReached: parts.append(String(localized: "You have already reached today's Strain target"))
            case .recoveryLow: parts.append(String(localized: "Your Recovery is low, so keep it light"))
            case .coolWindow(let t): parts.append(String(localized: "the kindest stretch of the day, feels like \(NunaInsightText.degrees(t))"))
            case .cleanAir(let aqi): parts.append(String(localized: "the air is clean (AQI \(aqi))"))
            case .airTooPoor(let aqi): parts.append(String(localized: "AQI \(aqi) is too high to train outside"))
            case .tooHot(let t): parts.append(String(localized: "it feels like \(NunaInsightText.degrees(t)), too hot outside"))
            case .rainLikely(let c): parts.append(String(localized: "rain is likely (\(NunaEnvironmentFormat.percent(c)))"))
            case .storm: parts.append(String(localized: "a storm is around"))
            case .windStrong: parts.append(String(localized: "the wind is strong"))
            case .shortenedForHeat: parts.append(String(localized: "a little shorter because of the heat"))
            }
        }
        guard let first = parts.first else { return "" }
        let rest = parts.dropFirst().joined(separator: ", ")
        let sentence = rest.isEmpty ? first : first + ": " + rest
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }
}

// MARK: - The timeline

/// The next 24 hours as one bar of 3-hour blocks, each in the colour of how well it suits time outdoors (green, yellow, red), the kindest stretch ringed in white.
/// It reads like the zone bar of a session: the day at a glance, then the times under it.
struct NunaConditionsTimeline: View {
    let outlook: EnvironmentOutlook
    let now: EnvironmentSnapshot
    var height: CGFloat = 22
    var showsLabels = true

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                // The reading now, then every step of the forecast.
                cell(color: NunaEnvironmentFormat.fitColor(currentFit), best: false, now: true)
                ForEach(outlook.steps) { step in
                    cell(color: NunaEnvironmentFormat.fitColor(step.fit), best: isBest(step), now: false)
                }
            }
            .frame(height: height)
            if showsLabels {
                HStack(spacing: 3) {
                    label(String(localized: "Now"), strong: true)
                    ForEach(Array(outlook.steps.enumerated()), id: \.element.id) { i, step in
                        label(i % 2 == 1 ? NunaInsightText.clockHour(step.ts) : "", strong: isBest(step))
                    }
                }
            }
        }
    }

    private var currentFit: OutdoorFit {
        OutdoorFit.of(feelsLikeC: now.effectiveC, humidityPct: now.humidityPct, usAqi: now.usAqi, rainChance: 0, windMps: now.windMps, conditionId: now.conditionId)
    }

    private func isBest(_ step: EnvironmentOutlook.Step) -> Bool { outlook.best?.start == step.ts }

    private func cell(color: Color, best: Bool, now: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.opacity(now ? 1 : 0.78))
            .overlay {
                if best { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: 2.5) }
            }
            .frame(maxWidth: .infinity)
    }

    private func label(_ text: String, strong: Bool) -> some View {
        Text(verbatim: text).font(.nuna(size: 10.5, weight: strong ? .heavy : .semibold)).foregroundStyle(strong ? NunaPalette.textPrimary : NunaPalette.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity)
    }
}

// MARK: - The card on Today

/// Conditions as a card of Today: a verdict on training outdoors, the day as a bar of green, yellow and red, and the one activity that fits both the sky and the
/// Strain the day has room for. It draws nothing until Weather and air is on and has a key, and opens the page with the whole day.
struct NunaWeatherAirCard: View {
    let chargePct: Double?
    let effort: Double?
    @ObservedObject private var store = EnvironmentStore.shared
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        Group {
            if store.isActive {
                if let s = store.snapshot {
                    NavigationLink(value: NunaTodayRoute.weatherAir) { NunaCard(small: true) { content(s) } }
                        .buttonStyle(.plain)
                } else {
                    NunaCard(small: true) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Reading the weather and the air…").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task { await store.refreshIfNeeded() }
    }

    private func content(_ s: EnvironmentSnapshot) -> some View {
        let outlook = EnvironmentOutlook.make(s, now: Int(Date().timeIntervalSince1970))
        let room = NunaStrainRoom.make(chargePct: chargePct, effort: effort)
        let level = store.advice?.level ?? .good
        let pick = EnvironmentTraining.picks(s, outlook: outlook, load: room.load).first
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                nunaTrendsCap("Conditions")
                Spacer()
                if let place = s.place { Text(verbatim: place).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: NunaEnvironmentFormat.verdictWord(level)).font(.nuna(size: 28, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaEnvironmentFormat.levelColor(level)).lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: summary(s)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            if let outlook, !outlook.steps.isEmpty { NunaConditionsTimeline(outlook: outlook, now: s) }
            if let pick { pickRow(pick, room: room, outlook: outlook) }
        }
    }

    /// "Feels like 38° · AQI 132": what the verdict rests on.
    private func summary(_ s: EnvironmentSnapshot) -> String {
        var bits: [String] = []
        if let f = s.effectiveC { bits.append(String(localized: "Feels like \(NunaInsightText.degrees(f))")) }
        if let aqi = s.usAqi { bits.append("AQI \(aqi)") }
        if let c = s.forecast.first(where: { $0.rainChance >= 0.5 }) { bits.append(String(localized: "Rain \(NunaEnvironmentFormat.percent(c.rainChance)) at \(NunaInsightText.clockHour(c.ts))")) }
        return bits.joined(separator: " · ")
    }

    private func pickRow(_ pick: ActivityPick, room: NunaStrainRoom, outlook: EnvironmentOutlook?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pick.symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 38, height: 38).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pick.title).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: pick.window.map { NunaEnvironmentFormat.window($0) + " · " + String(localized: "\(pick.minutes) min") } ?? pick.meta)
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Strain").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: room.bandText(scale) ?? "–").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effort)
            }
        }
    }
}

// MARK: - The page

/// The whole day for training: the verdict, the day as a bar, what the Strain has room for, the activities that fit, and the hours with their heat, rain and air.
struct NunaWeatherAirView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    @StateObject private var today = NunaTodayModel()
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        NunaDetailScreen("Conditions", trailing: AnyView(settingsButton), centersTitle: true) {
            if let s = store.snapshot {
                let outlook = EnvironmentOutlook.make(s, now: Int(Date().timeIntervalSince1970))
                let room = NunaStrainRoom.make(chargePct: today.charge.pct, effort: today.effort)
                let picks = EnvironmentTraining.picks(s, outlook: outlook, load: room.load)
                heroCard(s, outlook: outlook)
                strainCard(room)
                if !picks.isEmpty { picksSection(picks, room: room) }
                if let o = outlook, !o.steps.isEmpty { hoursCard(o, s: s) }
                nowCard(s)
                nunaFootnote("Weather and the forecast from OpenWeather; the air now from IQAir, or from OpenWeather without an IQAir key. General guidance for a healthy adult, not medical advice.")
            } else if store.isActive {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                NunaCard { Text("Turn on Weather and air in settings to see the conditions here.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .task {
            await today.load(repo: repo, profile: profile)
            await store.refreshIfNeeded()
        }
        .refreshable { await store.refreshIfNeeded(maxAge: 0) }
        // Her line is the one the Today suggestion already gives: what the sky and the air mean for training now.
        .nunaAnyaFloating(context: "weather and air", line: anyaLine, analyses: false)
    }

    private var anyaLine: String? {
        guard let s = store.snapshot, let a = store.advice else { return nil }
        return NunaInsightText.environment(a, s)
    }

    private var settingsButton: some View {
        NavigationLink { NunaEnvironmentView() } label: {
            Image(systemName: "gearshape").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Weather and air settings"))
    }

    // MARK: Verdict

    private func heroCard(_ s: EnvironmentSnapshot, outlook: EnvironmentOutlook?) -> some View {
        let level = store.advice?.level ?? .good
        return NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    nunaTrendsCap("Training conditions")
                    Spacer()
                    if let place = s.place { Text(verbatim: place).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                }
                Text(verbatim: NunaEnvironmentFormat.verdictWord(level)).font(.nuna(size: 38, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaEnvironmentFormat.levelColor(level)).lineLimit(1).minimumScaleFactor(0.6)
                if let a = store.advice {
                    Text(verbatim: NunaMark.plain(NunaInsightText.environment(a, s, maxReasons: 2))).font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                if let outlook, !outlook.steps.isEmpty {
                    NunaConditionsTimeline(outlook: outlook, now: s, height: 30)
                    HStack(spacing: 14) {
                        legend(.good, String(localized: "Good")); legend(.adjust, String(localized: "Adjust")); legend(.indoors, String(localized: "Indoors"))
                        Spacer(minLength: 0)
                    }
                    if let best = outlook.best {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(NunaPalette.textPrimary, lineWidth: 2).frame(width: 16, height: 11)
                            Text("Best time to train").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer(minLength: 6)
                            Text(verbatim: NunaEnvironmentFormat.window(best)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private func legend(_ fit: OutdoorFit, _ name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(NunaEnvironmentFormat.fitColor(fit)).frame(width: 8, height: 8)
            Text(verbatim: name).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }
    }

    // MARK: Strain

    private func strainCard(_ room: NunaStrainRoom) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    nunaTrendsCap("Your Strain today")
                    Spacer()
                    Text(verbatim: room.loadWord).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.effort).textCase(nil)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: room.soFarText(scale) ?? "–").font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("so far").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Spacer()
                    if let band = room.bandText(scale) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Target").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: band).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.effort)
                        }
                    }
                }
                strainBar(room)
            }
        }
    }

    /// The day's Strain against the band Recovery supports: the band lit, a marker where the day stands.
    private func strainBar(_ room: NunaStrainRoom) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let axis = 21.0
            ZStack(alignment: .leading) {
                Capsule().fill(NunaPalette.glassStrong)
                if let band = room.band {
                    Capsule().fill(NunaPalette.effort.opacity(0.3))
                        .frame(width: w * CGFloat(Double(band.upperBound - band.lowerBound) / axis))
                        .offset(x: w * CGFloat(Double(band.lowerBound) / axis))
                }
                Capsule().fill(NunaPalette.effort).frame(width: max(8, w * CGFloat(min((room.soFar ?? 0) / axis, 1))))
                // The band stays visible when the day has passed it: outlined over the bar.
                if let band = room.band {
                    Capsule().strokeBorder(NunaPalette.textPrimary.opacity(0.9), lineWidth: 2)
                        .frame(width: w * CGFloat(Double(band.upperBound - band.lowerBound) / axis))
                        .offset(x: w * CGFloat(Double(band.lowerBound) / axis))
                }
            }
        }
        .frame(height: 12)
    }

    // MARK: Picks

    private func picksSection(_ picks: [ActivityPick], room: NunaStrainRoom) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nunaRuledHeader("Picked for today")
            ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                NunaCard(highlight: i == 0) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: pick.symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(i == 0 ? NunaPalette.charge : NunaPalette.textPrimary)
                            .frame(width: 48, height: 48).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: pick.title).font(.nuna(size: 17, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: pick.meta).font(.nuna(size: 12.5, weight: .heavy)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            if let w = pick.window {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock").font(.nuna(size: 12, weight: .bold))
                                    Text(verbatim: NunaEnvironmentFormat.window(w)).font(.nuna(size: 13.5, weight: .bold, design: NunaType.design))
                                }
                                .foregroundStyle(NunaPalette.textPrimary)
                            }
                            Text(verbatim: pick.reason(strainBand: room.bandText(scale))).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: Hours

    /// The hours as columns: heat as bars in the colour of how they suit time outdoors, rain as a dot row, the air under them, one shared time axis.
    private func hoursCard(_ o: EnvironmentOutlook, s: EnvironmentSnapshot) -> some View {
        let temps = o.steps.map(\.feelsLikeC)
        let lo = (temps.min() ?? 20) - 4, hi = (temps.max() ?? 32) + 2
        func height(_ t: Double) -> CGFloat { 12 + 72 * CGFloat((t - lo) / max(hi - lo, 1)) }
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Hour by hour")
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(o.steps) { step in
                        VStack(spacing: 6) {
                            Text(verbatim: NunaInsightText.degrees(step.feelsLikeC)).font(.nuna(size: 12, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(NunaEnvironmentFormat.fitColor(step.fit).opacity(0.85)).frame(height: height(step.feelsLikeC))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 112, alignment: .bottom)
                // Rain, as a dot that fills with the chance of it.
                row(label: String(localized: "Rain"), o.steps) { step in
                    ZStack {
                        Circle().strokeBorder(NunaPalette.rest.opacity(0.4), lineWidth: 1.5)
                        Circle().fill(NunaPalette.rest).scaleEffect(CGFloat(max(step.rainChance, 0.0)))
                    }
                    .frame(width: 16, height: 16)
                }
                row(label: "AQI", o.steps) { step in
                    VStack(spacing: 3) {
                        if let aqi = step.usAqi {
                            Capsule().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 22, height: 8)
                            Text(verbatim: "\(aqi)").font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        } else {
                            Text(verbatim: "–").font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                    }
                }
                HStack(spacing: 5) {
                    ForEach(o.steps) { step in
                        Text(verbatim: NunaInsightText.clockHour(step.ts)).font(.nuna(size: 9.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func row<Content: View>(label: String, _ steps: [EnvironmentOutlook.Step], @ViewBuilder _ cell: @escaping (EnvironmentOutlook.Step) -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(spacing: 5) { ForEach(steps) { cell($0).frame(maxWidth: .infinity) } }
        }
    }

    // MARK: Now

    private func nowCard(_ s: EnvironmentSnapshot) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                nunaTrendsCap("Right now")
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: NunaEnvironmentFormat.symbol(conditionId: s.conditionId, feelsLikeC: s.effectiveC, night: NunaEnvironmentFormat.isNight(s.ts)))
                        .font(.system(size: 30)).foregroundStyle(NunaPalette.textPrimary).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: s.tempC.map(NunaInsightText.degrees) ?? s.feelsLikeC.map(NunaInsightText.degrees) ?? "–")
                            .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        if let text = s.conditionText {
                            Text(verbatim: text.prefix(1).uppercased() + text.dropFirst()).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                    Spacer(minLength: 0)
                    if let aqi = s.usAqi {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "AQI \(aqi)").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaEnvironmentFormat.airColor(aqi))
                            Text(verbatim: NunaEnvironmentFormat.bandName(AirQuality.band(usAqi: aqi))).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                    }
                }
                NunaDivider()
                HStack(alignment: .top, spacing: 0) {
                    fact("Feels like", s.feelsLikeC.map(NunaInsightText.degrees))
                    fact("Humidity", s.humidityPct.map { "\(Int($0.rounded()))%" })
                    fact("Wind", UnitFormatter.speedFromKilometersPerHour(s.windMps.map { $0 * 3.6 }, system: system))
                    fact("PM2.5", s.pm25.map { "\(Int($0.rounded()))" })
                }
            }
        }
    }

    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value ?? "–").font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

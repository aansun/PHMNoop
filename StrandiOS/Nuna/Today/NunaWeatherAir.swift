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

    /// The sky in words, from the OpenWeather code.
    static func skyText(conditionId: Int?) -> String {
        switch conditionId ?? 800 {
        case 200..<300: return String(localized: "Thunderstorm")
        case 300..<400: return String(localized: "Drizzle")
        case 500..<600: return String(localized: "Rain")
        case 600..<700: return String(localized: "Snow")
        case 700..<800: return String(localized: "Haze")
        case 801...802: return String(localized: "Partly cloudy")
        case 803...: return String(localized: "Cloudy")
        default: return String(localized: "Clear")
        }
    }

    static func partName(_ part: EnvironmentOutlook.Part) -> String {
        switch part {
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
        case .night: return String(localized: "Night")
        }
    }

    /// "06:00 – 11:00".
    static func range(_ slot: EnvironmentOutlook.Slot) -> String {
        NunaInsightText.clockHour(slot.start) + " – " + NunaInsightText.clockHour(slot.end)
    }

    /// Whether a session suits time outdoors, in words for a chip.
    static func fitWord(_ fit: OutdoorFit) -> String {
        switch fit {
        case .good: return String(localized: "Good for outdoor activity")
        case .adjust: return String(localized: "Outdoors with care")
        case .indoors: return String(localized: "Better indoors")
        }
    }

    /// What is in the way in a session, as two short phrases at most; empty when nothing is.
    static func inTheWay(_ slot: EnvironmentOutlook.Slot) -> String {
        var parts: [String] = []
        for r in slot.reasons.prefix(2) {
            switch r {
            case .veryHot(let t): parts.append(String(localized: "Too hot outside (feels like \(NunaInsightText.degrees(t)))"))
            case .hot: parts.append(String(localized: "Hot: go shorter and easier"))
            case .cold: parts.append(String(localized: "Cold: warm up well"))
            case .freezing: parts.append(String(localized: "Freezing: better indoors"))
            case .air(let aqi, let band): parts.append(String(localized: "Air is \(NunaInsightText.airWord(band)) (AQI \(aqi))"))
            case .storm: parts.append(String(localized: "A storm is around"))
            case .rain: parts.append(String(localized: "Rain is likely"))
            case .wind: parts.append(String(localized: "Strong wind"))
            }
        }
        if slot.rainLikely, !slot.reasons.contains(.rain), parts.count < 2 { parts.append(String(localized: "Rain is likely (\(percent(slot.rainChance)))")) }
        return parts.joined(separator: " · ")
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

// MARK: - The sessions

/// The four sessions of the day as cards stacked one on the next, each tucked under the one above it. A card always shows what matters at a glance, the sky and the
/// temperature and the air; touched, it opens to the wind, the humidity, the rain and whether the session suits time outdoors, and the others stay shut.
struct NunaSessionStack: View {
    let slots: [EnvironmentOutlook.Slot]
    var large = false
    @State private var open: Int?

    init(slots: [EnvironmentOutlook.Slot], large: Bool = false, initiallyOpen: Int? = nil) {
        self.slots = slots; self.large = large; _open = State(initialValue: initiallyOpen)
    }

    private static let overlap: CGFloat = 16

    var body: some View {
        VStack(spacing: -Self.overlap) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                card(i, slot).zIndex(Double(slots.count - i))
            }
        }
    }

    /// The same soft blue from the first card to the last, lighter at the top and fainter and fainter after it, the way the day thins out into the night.
    private func tint(_ i: Int) -> Color {
        NunaPalette.recoveryBlue.opacity([0.22, 0.15, 0.09, 0.04][min(i, 3)])
    }

    private func card(_ i: Int, _ slot: EnvironmentOutlook.Slot) -> some View {
        let isOpen = open == i
        return VStack(alignment: .leading, spacing: 14) {
            header(slot, isOpen: isOpen)
            if isOpen { details(slot).transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14 + (i > 0 ? Self.overlap : 0)).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NunaPalette.card))
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tint(i)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { open = isOpen ? nil : i } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Always on show: the sky, the name and hours of the session, the air and the temperature.
    private func header(_ slot: EnvironmentOutlook.Slot, isOpen: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: NunaEnvironmentFormat.symbol(conditionId: slot.conditionId, feelsLikeC: slot.peakFeelsLikeC, night: slot.part == .night))
                .font(.system(size: large ? 28 : 24)).foregroundStyle(NunaPalette.textPrimary).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NunaEnvironmentFormat.partName(slot.part)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                // The session under way reads "Now – 17:00": it is already in progress, so its own start is not worth saying.
                HStack(spacing: 4) {
                    if slot.isCurrent {
                        Text("Now").font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.charge).textCase(nil)
                        Text(verbatim: "– " + NunaInsightText.clockHour(slot.end)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text(verbatim: NunaEnvironmentFormat.range(slot)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 6)
            if let aqi = slot.usAqi { airPill(aqi) }
            Text(verbatim: NunaInsightText.degrees(slot.tempC ?? slot.feelsLikeC))
                .font(.nuna(size: large ? 30 : 26, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).frame(minWidth: 54, alignment: .trailing)
        }
    }

    private func airPill(_ aqi: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7)
            Text(verbatim: "AQI \(aqi)").font(.nuna(size: 11.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(NunaPalette.glassStrong, in: Capsule())
    }

    /// Shown when the card is touched: the sky in words, wind, humidity and rain, and whether it suits time outdoors with what is in the way.
    private func details(_ slot: EnvironmentOutlook.Slot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: NunaEnvironmentFormat.skyText(conditionId: slot.conditionId)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text("Feels like \(NunaInsightText.degrees(slot.peakFeelsLikeC))").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            HStack(alignment: .top, spacing: 0) {
                fact("Wind", slot.windMps.map { String(format: "%.0f", $0 * 3.6) + " km/h" })
                fact("Humidity", slot.humidityPct.map { "\(Int($0.rounded()))%" })
                fact("Rain", NunaEnvironmentFormat.percent(slot.rainChance))
            }
            VStack(alignment: .leading, spacing: 6) {
                NunaChip(verbatim: NunaEnvironmentFormat.fitWord(slot.fit), color: NunaEnvironmentFormat.fitColor(slot.fit))
                let why = NunaEnvironmentFormat.inTheWay(slot)
                if !why.isEmpty {
                    Text(verbatim: why).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value ?? "–").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The card on Today

/// Weather and air as a card of Today: the day as four stacked cards (morning to night) that show the sky, the temperature and the air at a glance and open to the
/// rest when touched. It draws nothing until Weather and air is on and has a key, and its title opens the page with the whole day.
struct NunaWeatherAirCard: View {
    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        Group {
            if store.isActive {
                if let s = store.snapshot {
                    NunaCard(small: true) { content(s) }
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
        return VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: NunaTodayRoute.weatherAir) {
                HStack {
                    nunaTrendsCap("Weather and air")
                    Spacer()
                    if let place = s.place { Text(verbatim: place).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                    Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let outlook, !outlook.slots.isEmpty { NunaSessionStack(slots: outlook.slots) }
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
        NunaDetailScreen("Weather and air", trailing: AnyView(settingsButton), centersTitle: true) {
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
                NunaCard { Text("Turn on Weather and air in settings to see the forecast here.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
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

    // MARK: Sessions

    private func heroCard(_ s: EnvironmentSnapshot, outlook: EnvironmentOutlook?) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaTrendsCap("The day in four sessions")
                    Spacer()
                    if let place = s.place { Text(verbatim: place).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                }
                if let outlook, !outlook.slots.isEmpty { NunaSessionStack(slots: outlook.slots, large: true, initiallyOpen: 0) }
                if let best = outlook?.best {
                    NunaDivider()
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Text("Best time to train").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer(minLength: 6)
                        Text(verbatim: NunaEnvironmentFormat.window(best)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }
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
                                .fill(step.fit == .good ? NunaPalette.rest.opacity(0.75) : NunaEnvironmentFormat.fitColor(step.fit).opacity(0.8)).frame(height: height(step.feelsLikeC))
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

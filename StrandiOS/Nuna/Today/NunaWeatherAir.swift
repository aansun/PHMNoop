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

    /// Whether a session suits time outdoors, in a few words for a chip.
    static func fitWord(_ fit: OutdoorFit) -> String {
        switch fit {
        case .good: return String(localized: "Good outdoors")
        case .adjust: return String(localized: "Outdoors, with care")
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

// MARK: - The deck

/// The four sessions of the day as cards laid on one another and fanned out to the right. The one in front keeps its size and shows the sky, the temperature, the
/// range of the session, the air and whether it suits time outdoors; the others wait behind it, dimmed, with only the name of the session on the edge that shows.
/// Touching one brings it to the front. Nothing changes size.
struct NunaSessionDeck: View {
    let slots: [EnvironmentOutlook.Slot]
    var height: CGFloat = 318
    @State private var active = 0

    /// How much of each card behind shows at the right.
    private static let peek: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let n = slots.count
            let width = geo.size.width - Self.peek * CGFloat(max(n - 1, 0))
            ZStack(alignment: .topLeading) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                    let rank = (i - min(active, n - 1) + n) % max(n, 1)
                    card(slot, rank: rank)
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(rank) * Self.peek)
                        .zIndex(Double(n - rank))
                        .onTapGesture { if rank != 0 { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { active = i } } }
                }
            }
        }
        .frame(height: height)
    }

    private func card(_ slot: EnvironmentOutlook.Slot, rank: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack(alignment: .topLeading) {
            front(slot).opacity(rank == 0 ? 1 : 0)
            if rank != 0 { edge(slot) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(NunaPalette.card))
        .background(shape.fill(NunaPalette.recoveryBlue.opacity(rank == 0 ? 0.16 : 0.05)))
        // Behind the front card, a little darker the further back it is.
        .overlay(shape.fill(Color.black.opacity(rank == 0 ? 0 : 0.14 + 0.07 * Double(rank))))
        .overlay(shape.strokeBorder(Color.white.opacity(rank == 0 ? 0.08 : 0.04), lineWidth: 1))
        .shadow(color: .black.opacity(rank == 3 ? 0 : 0.28), radius: 8, x: -3, y: 0)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: NunaEnvironmentFormat.partName(slot.part)))
        .accessibilityAddTraits(rank == 0 ? [] : .isButton)
    }

    /// The edge of a card behind: the name of the session, turned to read along the strip, and nothing else.
    private func edge(_ slot: EnvironmentOutlook.Slot) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: NunaEnvironmentFormat.partName(slot.part)).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textMuted).lineLimit(1).fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: Self.peek, height: 104)
        }
        .padding(.top, 18)
    }

    /// The card in front: the name and hours, the temperature large with its range, the sky, whether it suits time outdoors, and the air, wind and humidity.
    private func front(_ slot: EnvironmentOutlook.Slot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NunaEnvironmentFormat.partName(slot.part)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                // The session under way reads "Now – 17:00": it is in progress, so its own start is not worth saying.
                HStack(spacing: 4) {
                    if slot.isCurrent {
                        Text("Now").font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.charge).textCase(nil)
                        Text(verbatim: "– " + NunaInsightText.clockHour(slot.end)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text(verbatim: NunaEnvironmentFormat.range(slot)).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
                .lineLimit(1)
            }
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: NunaInsightText.degrees(slot.tempC ?? slot.feelsLikeC))
                        .font(.nuna(size: 50, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    // A session with one reading in it has no range to show: what it feels like says more.
                    if slot.highC - slot.lowC >= 1 {
                        HStack(spacing: 10) {
                            bound(arrow: "arrow.down", NunaInsightText.degrees(slot.lowC), NunaPalette.recoveryBlue)
                            bound(arrow: "arrow.up", NunaInsightText.degrees(slot.highC), NunaPalette.caution)
                        }
                    } else {
                        Text("Feels like \(NunaInsightText.degrees(slot.peakFeelsLikeC))").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: NunaEnvironmentFormat.symbol(conditionId: slot.conditionId, feelsLikeC: slot.peakFeelsLikeC, night: slot.part == .night))
                    .font(.system(size: 44)).foregroundStyle(NunaPalette.recoveryBlue).padding(.top, 4)
            }
            Text(verbatim: NunaEnvironmentFormat.skyText(conditionId: slot.conditionId)).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
            VStack(alignment: .leading, spacing: 5) {
                fitChip(slot.fit)
                let why = NunaEnvironmentFormat.inTheWay(slot)
                if !why.isEmpty {
                    Text(verbatim: why).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            NunaDivider()
            HStack(alignment: .top, spacing: 0) {
                airFact(slot.usAqi)
                fact("Wind", slot.windMps.map { String(format: "%.0f", $0 * 3.6) + " km/h" })
                fact("Humidity", slot.humidityPct.map { "\(Int($0.rounded()))%" })
            }
        }
        .padding(16)
    }

    private func bound(arrow: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: arrow).font(.system(size: 11, weight: .heavy)).foregroundStyle(color)
            Text(verbatim: value).font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private func fitChip(_ fit: OutdoorFit) -> some View {
        let color = NunaEnvironmentFormat.fitColor(fit)
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(verbatim: NunaEnvironmentFormat.fitWord(fit)).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
    }

    private func airFact(_ aqi: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "AQI").font(.nuna(size: 10, weight: .heavy)).tracking(nunaTrackingLabel).foregroundStyle(NunaPalette.textSecondary)
            HStack(spacing: 5) {
                if let aqi { Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7) }
                Text(verbatim: aqi.map { "\($0)" } ?? "–").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 10, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
            Text(verbatim: value ?? "–").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The card on Today

/// Weather and air as a card of Today: the day as four cards fanned out to the right, the one in front showing the whole of its session. It draws nothing until
/// Weather and air is on and has a key, and its title opens the page with the whole day.
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
            if let outlook, !outlook.slots.isEmpty { NunaSessionDeck(slots: outlook.slots) }
        }
    }
}

// MARK: - The page

/// The whole day: the four sessions as the deck, the best hours to train, the hours with their heat, rain and air, and the weather now.
struct NunaWeatherAirView: View {
    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        NunaDetailScreen("Weather and air", trailing: AnyView(settingsButton), centersTitle: true) {
            if let s = store.snapshot {
                let outlook = EnvironmentOutlook.make(s, now: Int(Date().timeIntervalSince1970))
                deckCard(s, outlook: outlook)
                if let o = outlook, !o.steps.isEmpty { forecastCard(o, s) }
                nunaFootnote("Weather and the forecast from OpenWeather; the air now from IQAir, or from OpenWeather without an IQAir key. General guidance for a healthy adult, not medical advice.")
            } else if store.isActive {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                NunaCard { Text("Turn on Weather and air in settings to see the forecast here.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .task { await store.refreshIfNeeded() }
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

    /// The deck stands on the page by itself, with no card behind it and no title: the place above it, the best hours to train under it.
    private func deckCard(_ s: EnvironmentSnapshot, outlook: EnvironmentOutlook?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let place = s.place {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.nuna(size: 12, weight: .bold))
                    Text(verbatim: place).font(.nuna(size: 13, weight: .semibold)).textCase(nil)
                }
                .foregroundStyle(NunaPalette.textSecondary).padding(.horizontal, 4)
            }
            if let outlook, !outlook.slots.isEmpty { NunaSessionDeck(slots: outlook.slots, height: 332) }
            if let best = outlook?.best {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.charge)
                    Text("Best time to train").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Spacer(minLength: 6)
                    Text(verbatim: NunaEnvironmentFormat.window(best)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Forecast

    /// The forecast in two rows: the hours coming up (time, sky, temperature and air) and the days (date, sky, low and high and air).
    private func forecastCard(_ o: EnvironmentOutlook, _ s: EnvironmentSnapshot) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 18) {
                nunaTrendsCap("Forecast")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Hourly forecast").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 6) {
                            hourColumn(time: String(localized: "Now"), conditionId: s.conditionId, feels: s.effectiveC, night: NunaEnvironmentFormat.isNight(s.ts),
                                       temp: s.tempC ?? s.effectiveC, aqi: s.usAqi, strong: true)
                            ForEach(o.steps) { step in
                                hourColumn(time: NunaInsightText.clockHour(step.ts), conditionId: step.conditionId, feels: step.feelsLikeC,
                                           night: NunaEnvironmentFormat.isNight(step.ts), temp: step.tempC ?? step.feelsLikeC, aqi: step.usAqi, strong: false)
                            }
                        }
                    }
                }
                NunaDivider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Daily forecast").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(o.days.enumerated()), id: \.element.id) { i, day in dayColumn(day, today: i == 0).frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    /// A sun is warm, every other sky is cool.
    private func skyColor(_ conditionId: Int?, night: Bool) -> Color {
        (conditionId ?? 800) == 800 && !night ? NunaPalette.caution : (night && (conditionId ?? 800) == 800 ? NunaPalette.textSecondary : NunaPalette.recoveryBlue)
    }

    private func hourColumn(time: String, conditionId: Int?, feels: Double?, night: Bool, temp: Double?, aqi: Int?, strong: Bool) -> some View {
        VStack(spacing: 8) {
            Text(verbatim: time).font(.nuna(size: 13, weight: strong ? .heavy : .semibold)).foregroundStyle(strong ? NunaPalette.textPrimary : NunaPalette.textSecondary).textCase(nil)
            Image(systemName: NunaEnvironmentFormat.symbol(conditionId: conditionId, feelsLikeC: feels, night: night)).font(.system(size: 24))
                .foregroundStyle(skyColor(conditionId, night: night)).frame(height: 28)
            Text(verbatim: temp.map(NunaInsightText.degrees) ?? "–").font(.nuna(size: 15, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            airDot(aqi)
        }
        .frame(width: 52)
    }

    private func dayColumn(_ day: EnvironmentOutlook.Day, today: Bool) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(day.start))
        return VStack(spacing: 8) {
            Text(verbatim: today ? String(localized: "Today") : date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.nuna(size: 12.5, weight: today ? .heavy : .semibold)).foregroundStyle(today ? NunaPalette.textPrimary : NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
            Image(systemName: NunaEnvironmentFormat.symbol(conditionId: day.conditionId, feelsLikeC: day.highC)).font(.system(size: 24))
                .foregroundStyle(skyColor(day.conditionId, night: false)).frame(height: 28)
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.recoveryBlue)
                    Text(verbatim: NunaInsightText.degrees(day.lowC)).font(.nuna(size: 13.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.caution)
                    Text(verbatim: NunaInsightText.degrees(day.highC)).font(.nuna(size: 13.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
            }
            airDot(day.usAqi)
        }
    }

    /// The air as a coloured dot and its index; a dash when the forecast does not reach.
    private func airDot(_ aqi: Int?) -> some View {
        HStack(spacing: 4) {
            if let aqi {
                Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7)
                Text(verbatim: "\(aqi)").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            } else {
                Text(verbatim: "–").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
            }
        }
    }
}
#endif

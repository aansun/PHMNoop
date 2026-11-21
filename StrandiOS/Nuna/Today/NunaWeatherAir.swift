#if os(iOS)
import SwiftUI
import Charts
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
        inTheWay(reasons: slot.reasons, rainLikely: slot.rainLikely, rainChance: slot.rainChance)
    }

    static func inTheWay(reasons: [EnvironmentAdvice.Reason], rainLikely: Bool, rainChance: Double) -> String {
        var parts: [String] = []
        for r in reasons.prefix(2) {
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
        if rainLikely, !reasons.contains(.rain), parts.count < 2 { parts.append(String(localized: "Rain is likely (\(percent(rainChance)))")) }
        return parts.joined(separator: " · ")
    }

    /// Whether the weather and the air of one moment suit time outdoors, and what is in the way, by the rules of the advice.
    static func advise(feels: Double?, humidity: Double?, wind: Double?, condition: Int?, aqi: Int?, rain: Double) -> (fit: OutdoorFit, text: String) {
        let probe = EnvironmentSnapshot(ts: 0, tempC: feels, feelsLikeC: feels, humidityPct: humidity, windMps: wind, conditionId: condition, usAqi: aqi)
        let advice = EnvironmentAdvice.analyze(probe, hours: 0...23)
        var fit: OutdoorFit = advice.map { $0.level == .indoors ? .indoors : ($0.level == .adjust ? .adjust : .good) } ?? .good
        if rain >= 0.5, fit < .adjust { fit = .adjust }
        // The worst first: a storm, the air or the heat, then the cold, the rain and the wind.
        func rank(_ r: EnvironmentAdvice.Reason) -> Int {
            switch r {
            case .storm: return 0
            case .air(_, let band): return band >= .unhealthy ? 1 : 3
            case .veryHot, .freezing: return 1
            case .hot: return 2
            case .cold: return 3
            case .rain: return 4
            case .wind: return 5
            }
        }
        let reasons = (advice?.reasons ?? []).sorted { rank($0) < rank($1) }
        // In a sentence after the colon the reasons run on in lower case: "too hot outside, air is unhealthy".
        let why = inTheWay(reasons: reasons, rainLikely: rain >= 0.5, rainChance: rain)
            .components(separatedBy: " · ").map { $0.prefix(1).lowercased() + $0.dropFirst() }.joined(separator: ", ")
        switch fit {
        case .good: return (fit, String(localized: "Good for outdoor activity."))
        case .adjust: return (fit, why.isEmpty ? String(localized: "Outdoors, with care.") : String(localized: "Outdoors, with care: \(why).") )
        case .indoors: return (fit, why.isEmpty ? String(localized: "Better indoors.") : String(localized: "Better indoors: \(why)."))
        }
    }
}

// MARK: - The card on Today

/// Weather and air as a card of Today, one row as wide as the Daily Outlook one: the sky now at the left, the temperature, the air quality and what that means for
/// time outdoors ("Outdoors, with care"). It draws nothing until Weather and air is on, and opens the page with the whole day.
struct NunaWeatherAirCard: View {
    @ObservedObject private var store = EnvironmentStore.shared

    var body: some View {
        Group {
            if store.isActive {
                if let s = store.snapshot {
                    NavigationLink(value: NunaTodayRoute.weatherAir) { row { content(s) } }.buttonStyle(.plain)
                } else {
                    row {
                        ProgressView().controlSize(.small)
                        Text("Reading the weather and the air…").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .task { await store.refreshIfNeeded() }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 18).frame(height: 47).frame(maxWidth: .infinity)
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// "32°, AQI 132: Better indoors".
    private func line(_ s: EnvironmentSnapshot, fit: OutdoorFit) -> String {
        var facts: [String] = []
        if let t = s.tempC ?? s.effectiveC { facts.append(NunaInsightText.degrees(t)) }
        if let aqi = s.usAqi { facts.append("AQI \(aqi)") }
        let head = facts.joined(separator: ", ")
        return head.isEmpty ? NunaEnvironmentFormat.fitWord(fit) : head + ": " + NunaEnvironmentFormat.fitWord(fit)
    }

    @ViewBuilder private func content(_ s: EnvironmentSnapshot) -> some View {
        let now = Int(Date().timeIntervalSince1970)
        let symbol = NunaEnvironmentFormat.symbol(conditionId: s.conditionId, feelsLikeC: s.effectiveC, night: NunaEnvironmentFormat.isNight(now))
        let fit = NunaEnvironmentFormat.advise(feels: s.effectiveC, humidity: s.humidityPct, wind: s.windMps, condition: s.conditionId, aqi: s.usAqi,
                                               rain: s.conditionId.map { (300..<600).contains($0) } == true ? 0.8 : 0).fit
        // The sky inside a ring that takes the colour of the air quality.
        Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
            .frame(width: 34, height: 34)
            .overlay(Circle().stroke(s.usAqi.map { NunaEnvironmentFormat.airColor($0) } ?? NunaPalette.textMuted, lineWidth: 2.5))
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: s.place.flatMap { $0.isEmpty ? nil : String(localized: "Today in \($0)") } ?? String(localized: "Today"))
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
            Text(verbatim: line(s, fit: fit)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
    }
}

// MARK: - The page

/// The weather and the air as a trend view: the metric to read (weather or air quality), the hours (H) or the days (D) switch and a date stepper, the moment that is
/// on show with its figure (the one now, until a point is touched), a sentence about it, and a line of the forecast. Touching a point makes it the one on show.
struct NunaWeatherAirView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    @State private var metric = Metric.weather
    /// 1 is the hours (H), 5 the days (D).
    @State private var range = 1
    /// For the hours: which day-long window of the forecast, 0 being the next 24 hours.
    @State private var page = 0
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?
    @State private var menuOpen = false

    private enum Metric: Hashable { case weather, air }

    /// One moment of the forecast with everything the page says about it.
    private struct Point: Identifiable {
        let date: Date
        let value: Double
        /// For the days of the weather: the low under the high.
        let low: Double?
        let symbol: String
        let feels: Double?
        let windMps: Double?
        let humidity: Double?
        let rain: Double
        let aqi: Int?
        let condition: Int?
        var id: Date { date }
    }

    private let color = NunaPalette.effortModerate
    private static let choices: [(value: Int, title: String)] = [(1, "H"), (5, "D")]

    var body: some View {
        NunaDetailScreen("Weather and air", trailing: AnyView(settingsButton), centersTitle: true) {
            if let s = store.snapshot {
                let outlook = EnvironmentOutlook.make(s, now: Int(Date().timeIntervalSince1970))
                let pts = points(s, outlook)
                let active = picked.flatMap { d in pts.first { $0.date == d } } ?? pts.first
                metricBox
                header(pts, active)
                if let active {
                    Text(verbatim: lead(pts, active, place: s.place) + sentence(active)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                } else {
                    Text(verbatim: metric == .air ? String(localized: "The air forecast needs an OpenWeather key.") : String(localized: "Nothing in the forecast for this period yet."))
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                }
                if range == 5, metric == .weather { legend }
                if pts.count >= 2 { chart(pts, active: active) } else { needKey }
                if let best = outlook?.best {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Text("Best time to train").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer(minLength: 6)
                        Text(verbatim: NunaEnvironmentFormat.window(best)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    .padding(.horizontal, 4)
                }
                nunaFootnote("Weather and the forecast from OpenWeather; the air now from IQAir, or from OpenWeather without an IQAir key. General guidance for a healthy adult, not medical advice.")
            } else if store.isActive {
                ProgressView().tint(NunaPalette.textSecondary).frame(maxWidth: .infinity, minHeight: 200)
            } else {
                NunaCard { Text("Turn on Weather and air in settings to see the forecast here.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
        }
        .environment(\.nunaDetailSwitch, nil)
        .task { await store.refreshIfNeeded() }
        .refreshable { await store.refreshIfNeeded(maxAge: 0) }
        .onChange(of: metric) { _, _ in picked = nil }
    }

    private var settingsButton: some View {
        NavigationLink { NunaEnvironmentView() } label: {
            Image(systemName: "gearshape").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).accessibilityLabel(Text("Weather and air settings"))
    }

    // MARK: Metric

    /// The name box of a trend view, which is also where the metric is chosen: touched, it opens the two to pick from.
    private var metricBox: some View {
        VStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { menuOpen.toggle() } } label: { box(metric) }.buttonStyle(.plain)
            if menuOpen {
                VStack(spacing: 0) {
                    ForEach([Metric.weather, .air], id: \.self) { m in
                        Button { metric = m; withAnimation(.easeOut(duration: 0.2)) { menuOpen = false } } label: {
                            HStack(spacing: 14) {
                                Image(systemName: icon(m)).font(.nuna(size: 18, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 28)
                                Text(title(m)).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 52)
                            .background(m == metric ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
            }
        }
    }

    private func box(_ m: Metric) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon(m)).font(.nuna(size: 21, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 32)
            Text(title(m)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: menuOpen ? "chevron.up" : "chevron.down").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
        }
        .padding(.horizontal, 18).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    private func icon(_ m: Metric) -> String { m == .weather ? "cloud.sun" : "aqi.medium" }
    private func title(_ m: Metric) -> LocalizedStringKey { m == .weather ? "Weather" : "Air quality" }

    // MARK: Points

    private func points(_ s: EnvironmentSnapshot, _ o: EnvironmentOutlook?) -> [Point] {
        let cal = Calendar.current
        let from = Int(Date().timeIntervalSince1970)
        func near(_ ts: Int) -> EnvironmentSnapshot.Hour? { s.forecast.min { abs($0.ts - ts) < abs($1.ts - ts) } }
        func symbol(_ ts: Int) -> String {
            let n = near(ts)
            return NunaEnvironmentFormat.symbol(conditionId: n?.conditionId ?? s.conditionId, feelsLikeC: n?.feelsLikeC ?? s.effectiveC, night: NunaEnvironmentFormat.isNight(ts))
        }
        func date(_ ts: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
        if range == 5 {
            return (o?.days ?? []).compactMap { d in
                let noon = cal.date(byAdding: .hour, value: 12, to: date(d.start)) ?? date(d.start)
                let sym = NunaEnvironmentFormat.symbol(conditionId: d.conditionId, feelsLikeC: d.highC)
                let value: Double
                switch metric {
                case .weather: value = d.highC
                case .air: guard let aqi = d.usAqi else { return nil }; value = Double(aqi)
                }
                return Point(date: noon, value: value, low: metric == .weather ? d.lowC : nil, symbol: sym, feels: d.peakFeelsLikeC, windMps: d.windMps,
                             humidity: d.humidityPct, rain: d.rainChance, aqi: d.usAqi, condition: d.conditionId)
            }
        }
        let start = from + page * 86_400, end = start + 86_400
        switch metric {
        case .weather:
            var out: [Point] = []
            if page == 0, let t = s.tempC ?? s.effectiveC {
                let rainNow = s.conditionId.map { (300..<600).contains($0) } == true ? 0.8 : 0.0
                out.append(Point(date: date(from), value: t, low: nil, symbol: symbol(from), feels: s.effectiveC, windMps: s.windMps, humidity: s.humidityPct,
                                 rain: rainNow, aqi: s.usAqi, condition: s.conditionId))
            }
            out += s.forecast.filter { $0.ts > from && $0.ts >= start && $0.ts <= end }.sorted { $0.ts < $1.ts }.map {
                Point(date: date($0.ts), value: $0.tempC ?? $0.feelsLikeC, low: nil, symbol: symbol($0.ts), feels: $0.feelsLikeC, windMps: $0.windMps,
                      humidity: $0.humidityPct ?? s.humidityPct, rain: $0.rainChance, aqi: EnvironmentOutlook.usAqi(at: $0.ts, in: s), condition: $0.conditionId)
            }
            return out
        case .air:
            return s.airForecast.filter { $0.ts >= start - 1800 && $0.ts <= end }.sorted { $0.ts < $1.ts }.map { h in
                let n = near(h.ts)
                return Point(date: date(h.ts), value: Double(h.usAqi), low: nil, symbol: symbol(h.ts), feels: n?.feelsLikeC ?? s.effectiveC, windMps: n?.windMps ?? s.windMps,
                             humidity: n?.humidityPct ?? s.humidityPct, rain: n?.rainChance ?? 0, aqi: h.usAqi, condition: n?.conditionId ?? s.conditionId)
            }
        }
    }

    /// The last window of the hours that still has forecast in it.
    private var lastPage: Int {
        guard let last = store.snapshot?.forecast.map(\.ts).max() else { return 0 }
        return max(0, Int(Double(last - Int(Date().timeIntervalSince1970)) / 86_400.0 - 0.001))
    }

    private var windowLabel: String {
        if range == 5 { return String(localized: "Next 5 days") }
        if page == 0 { return String(localized: "Next 24 hours") }
        let d = Date(timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970) + page * 86_400))
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func label(_ date: Date) -> String {
        range == 5 ? date.formatted(.dateTime.weekday(.abbreviated).day()) : NunaInsightText.clockHour(Int(date.timeIntervalSince1970))
    }

    /// A label under the plot, the way the other trend views write it: the weekday over the day for the days, the hour alone for the hours.
    private func axisLabel(_ d: Date) -> some View {
        let templates: [String] = range == 5 ? ["EEE", "d"] : []
        return VStack(spacing: 2) {
            if range == 5 {
                ForEach(templates, id: \.self) { t in
                    let f = DateFormatter()
                    Text(verbatim: { f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(t); return f.string(from: d) }())
                        .font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
                }
            } else {
                Text(verbatim: label(d)).font(.nuna(size: 12.5, weight: .semibold)).textCase(nil).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    /// The name of a moment at the top: "Now" for the reading now, "Today" for the first day, else its hour or day.
    private func activeLabel(_ p: Point, first: Bool) -> String {
        if first, range == 1, page == 0 { return String(localized: "Now") }
        if first, range == 5 { return String(localized: "Today") }
        return label(p.date)
    }

    private func fmt(_ v: Double) -> String { "\(Int(v.rounded()))" }

    private func skyColor(_ symbol: String) -> Color { symbol.hasPrefix("sun") ? NunaPalette.caution : (symbol.contains("moon") ? NunaPalette.textSecondary : NunaPalette.recoveryBlue) }

    // MARK: Header

    private func header(_ pts: [Point], _ active: Point?) -> some View {
        let isFirst = active.map { a in pts.first.map { $0.date == a.date } ?? false } ?? false
        let unit = metric == .weather ? "°C" : "AQI"
        let tint = picked == nil ? NunaPalette.textPrimary : color
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: active.map { activeLabel($0, first: isFirst) } ?? "–").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(picked == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: active.map { fmt($0.value) } ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if active != nil { Text(verbatim: unit).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                    // The sky of the moment on show, beside the temperature.
                    if metric == .weather, let active {
                        Image(systemName: active.symbol).font(.system(size: 30)).foregroundStyle(skyColor(active.symbol)).padding(.leading, 10).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    }
                }
                if let active { chip(pts, active) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 14) {
                NunaRangeSwitch(choices: Self.choices, range: $range) { page = 0; picked = nil }
                NunaDateStepper(label: windowLabel, canGoBack: range == 1 && page > 0, canGoForward: range == 1 && page < lastPage,
                                back: { page = max(0, page - 1); picked = nil }, forward: { page = min(lastPage, page + 1); picked = nil })
            }
        }
        .padding(.horizontal, 2)
    }

    /// Under the figure: for the weather, the low and the high (of the window for the hours, of the day for the days); for the air, the band it falls in.
    @ViewBuilder private func chip(_ pts: [Point], _ active: Point) -> some View {
        switch metric {
        case .weather:
            let lo = range == 5 ? (active.low ?? active.value) : (pts.map(\.value).min() ?? active.value)
            let hi = range == 5 ? active.value : (pts.map(\.value).max() ?? active.value)
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.recoveryBlue)
                    Text(verbatim: NunaInsightText.degrees(lo)).font(.nuna(size: 12, weight: .bold, design: NunaType.design))
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.caution)
                    Text(verbatim: NunaInsightText.degrees(hi)).font(.nuna(size: 12, weight: .bold, design: NunaType.design))
                }
            }
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 9).padding(.vertical, 4)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .air:
            let aqi = Int(active.value.rounded())
            HStack(spacing: 6) {
                Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7)
                Text(verbatim: NunaEnvironmentFormat.bandName(AirQuality.band(usAqi: aqi))).font(.nuna(size: 12, weight: .bold)).textCase(nil)
            }
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 9).padding(.vertical, 4)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// The place and the moment that open the sentence: "Now in Jakarta. ", "Today in Jakarta. ", "At 18.03 in Jakarta. ". Nothing without a place.
    private func lead(_ pts: [Point], _ p: Point, place: String?) -> String {
        guard let place, !place.isEmpty else { return "" }
        let first = pts.first.map { $0.date == p.date } ?? false
        let when: String
        if first, range == 1, page == 0 { when = String(localized: "Now") }
        else if first, range == 5 { when = String(localized: "Today") }
        else if range == 5 { when = String(localized: "On \(label(p.date))") }
        else { when = String(localized: "At \(label(p.date))") }
        return String(localized: "\(when) in \(place)") + ". "
    }

    /// What is said about the moment on show: the feel, the wind and the humidity (or the air), and whether it is a good time to be outdoors.
    private func sentence(_ p: Point) -> String {
        let verdict = NunaEnvironmentFormat.advise(feels: p.feels, humidity: p.humidity, wind: p.windMps, condition: p.condition, aqi: p.aqi, rain: p.rain).text
        var facts: [String] = []
        switch metric {
        case .weather:
            if let f = p.feels { facts.append(String(localized: "Feels like \(NunaInsightText.degrees(f))")) }
            if let w = p.windMps { facts.append(String(localized: "wind \(String(format: "%.0f", w * 3.6)) km/h")) }
            if let h = p.humidity { facts.append(String(localized: "humidity \(Int(h.rounded()))%")) }
            let head = facts.isEmpty ? "" : facts.joined(separator: ", ").prefix(1).uppercased() + facts.joined(separator: ", ").dropFirst() + ". "
            return head + verdict
        case .air:
            let aqi = Int(p.value.rounded())
            return String(localized: "Air quality is \(NunaInsightText.airWord(AirQuality.band(usAqi: aqi))) (AQI \(aqi)).") + " " + verdict
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            HStack(spacing: 6) { Image(systemName: "arrow.up").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.caution); Text("High") }
            HStack(spacing: 6) { Image(systemName: "arrow.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(NunaPalette.recoveryBlue); Text("Low") }
        }
        .font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 2).padding(.top, 4)
    }

    private var needKey: some View {
        Text(metric == .air ? "The hour-by-hour air needs an OpenWeather key." : "Nothing in the forecast for this period yet.")
            .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: Chart

    /// Five evenly spaced labels that cover the readings.
    private func axis(_ pts: [Point]) -> (low: Double, high: Double, ticks: [Double]) {
        if metric == .air {
            let top = max(100, (((pts.map(\.value).max() ?? 100) + 15) / 50).rounded(.up) * 50)
            return (0, top, stride(from: 0, through: top, by: 50).map { $0 })
        }
        let values = pts.map(\.value) + pts.compactMap(\.low)
        let lo = values.min() ?? 20, hi = values.max() ?? 32
        let pad = max((hi - lo) * 0.14, 2)
        let step = max(1, ((hi - lo + 2 * pad) / 4).rounded(.up))
        let low = (lo - pad).rounded(.down)
        return (low, low + 4 * step, (0...4).map { low + Double($0) * step })
    }

    private func nearest(_ x: CGFloat, _ proxy: ChartProxy, _ frame: CGRect, among pts: [Point]) -> Date? {
        guard let touched: Date = proxy.value(atX: x - frame.minX) else { return nil }
        return pts.min { abs($0.date.timeIntervalSince(touched)) < abs($1.date.timeIntervalSince(touched)) }?.date
    }

    /// The points that get a figure beside them: all of them when there are few, the highest and the lowest when there are many (the hours of the air).
    private func marked(_ pts: [Point]) -> [Point] {
        if pts.count <= 9 { return pts }
        guard let hi = pts.max(by: { $0.value < $1.value }), let lo = pts.min(by: { $0.value < $1.value }) else { return [] }
        return hi.date == lo.date ? [hi] : [hi, lo]
    }

    private func chart(_ pts: [Point], active: Point?) -> some View {
        let (low, high, ticks) = axis(pts)
        let first = pts.first!.date, last = pts.last!.date
        let pad: TimeInterval = range == 5 ? 18 * 3600 : 1800
        let domain = first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
        let every = range == 5 ? 1 : (pts.count > 9 ? 3 : 2)
        let tickDates = pts.enumerated().filter { $0.offset % every == 0 }.map(\.element.date)
        let twoLines = metric == .weather && range == 5
        let bands: [(ClosedRange<Double>, Color)] = [(0...50, NunaPalette.charge), (50...100, NunaPalette.warning), (100...150, NunaPalette.caution), (150...300, NunaPalette.alert)]
        return Chart {
            if metric == .air {
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    if band.0.lowerBound < high {
                        RectangleMark(xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                                      yStart: .value("Low", band.0.lowerBound), yEnd: .value("High", min(band.0.upperBound, high)))
                            .foregroundStyle(band.1.opacity(0.10))
                    }
                }
            }
            ForEach(pts) { p in
                // One line is filled down to the axis; the high and the low of the days are two lines and stay unfilled, so the fill does not cover the low.
                if !twoLines {
                    AreaMark(x: .value("Time", p.date), yStart: .value("Base", low), yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.26), .clear], startPoint: .top, endPoint: .bottom))
                }
                LineMark(x: .value("Time", p.date), y: .value("Value", p.value), series: .value("Series", "high"))
                    .foregroundStyle(twoLines ? NunaPalette.caution : color).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                if let lo = p.low {
                    LineMark(x: .value("Time", p.date), y: .value("Low", lo), series: .value("Series", "low"))
                        .foregroundStyle(NunaPalette.recoveryBlue).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                }
            }
            if pts.count <= 9 {
                ForEach(pts) { p in
                    PointMark(x: .value("Time", p.date), y: .value("Value", p.value))
                        .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(twoLines ? NunaPalette.caution : color, lineWidth: 2.5)).frame(width: 11, height: 11) }
                    if let lo = p.low {
                        PointMark(x: .value("Time", p.date), y: .value("Low", lo))
                            .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(NunaPalette.recoveryBlue, lineWidth: 2.5)).frame(width: 11, height: 11) }
                    }
                }
            }
            // The moment on show is filled; a dashed line joins it to the axis once it has been touched.
            if let active {
                if picked != nil { RuleMark(x: .value("Picked", active.date)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])) }
                PointMark(x: .value("Time", active.date), y: .value("Value", active.value))
                    .symbol { Circle().fill(color).overlay(Circle().stroke(Color.white, lineWidth: 2)).frame(width: 12, height: 12) }
            }
        }
        .chartYScale(domain: low...high)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { v in
                AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.7))
                AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: fmt(d)).font(.nuna(size: 12, weight: .heavy)).foregroundStyle(NunaPalette.textMuted) } }
            }
        }
        // The time labels sit under the plot, as in the other trend views: hidden axis, room under the plot, labels drawn in the overlay.
        .chartXAxis(.hidden)
        .chartPlotStyle { $0.padding(.bottom, 50) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let frame = proxy.plotFrame.map({ geo[$0] }) {
                    ZStack {
                        ZStack {
                            ForEach(marked(pts)) { p in
                                if let x = proxy.position(forX: p.date), let y = proxy.position(forY: p.value) {
                                    Text(verbatim: fmt(p.value)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                        .fixedSize().position(x: frame.minX + x, y: frame.minY + y - 18)
                                }
                                if let lo = p.low, let x = proxy.position(forX: p.date), let y = proxy.position(forY: lo) {
                                    Text(verbatim: fmt(lo)).font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.recoveryBlue)
                                        .fixedSize().position(x: frame.minX + x, y: frame.minY + y + 20)
                                }
                            }
                        }
                        .allowsHitTesting(false)
                        ZStack {
                            ForEach(tickDates, id: \.self) { d in
                                if let x = proxy.position(forX: d) { axisLabel(d).position(x: frame.minX + x, y: frame.maxY + 26) }
                            }
                        }
                        .allowsHitTesting(false)
                        Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    if touchBeganOnPicked == nil { touchBeganOnPicked = picked.map { nearest(g.location.x, proxy, frame, among: pts) == $0 } ?? false }
                                    if let d = nearest(g.location.x, proxy, frame, among: pts) { picked = d }
                                }
                                .onEnded { g in
                                    if touchBeganOnPicked == true, abs(g.translation.width) < 6 { picked = nil }
                                    touchBeganOnPicked = nil
                                })
                    }
                }
            }
        }
        .frame(height: 340)
        .accessibilityLabel(Text(title(metric)))
    }
}
#endif

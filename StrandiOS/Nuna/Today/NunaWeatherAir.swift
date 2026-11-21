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

// MARK: - The sessions

/// The four sessions of the day as pages to slide through, left and right, each one a card with no background of its own, and four dots under them to say which is
/// on show. The first is the session under way. Every page has the same size, so nothing moves when you slide.
struct NunaSessionDeck: View {
    let slots: [EnvironmentOutlook.Slot]
    /// The place, said in the top line of the page: "Jakarta in Afternoon".
    var place: String?
    var height: CGFloat = 344
    @State private var active = 0

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $active) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in front(slot).tag(i) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            HStack(spacing: 8) {
                ForEach(0..<slots.count, id: \.self) { i in
                    Circle().fill(NunaPalette.textPrimary.opacity(i == active ? 0.9 : 0.25)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The card in front, centred from top to bottom: the session, the temperature large with its range, the sky large, its name, whether it suits time outdoors,
    /// and the air, wind and humidity in one small row at the foot. All of it sits in this one card.
    private func front(_ slot: EnvironmentOutlook.Slot) -> some View {
        VStack(spacing: 9) {
            VStack(spacing: 2) {
                Text(verbatim: place.map { String(localized: "\($0) in \(NunaEnvironmentFormat.partName(slot.part))") } ?? NunaEnvironmentFormat.partName(slot.part))
                    .font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
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
            // 32°C: the figure large and the unit small beside it, as on a weather face.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(Int((slot.tempC ?? slot.feelsLikeC).rounded()))").font(.nuna(size: 60, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: "°C").font(.nuna(size: 22, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            // A session with one reading in it has no range to show: what it feels like says more.
            if slot.highC - slot.lowC >= 1 {
                HStack(spacing: 14) {
                    bound(arrow: "arrow.down", NunaInsightText.degrees(slot.lowC), NunaPalette.recoveryBlue)
                    bound(arrow: "arrow.up", NunaInsightText.degrees(slot.highC), NunaPalette.caution)
                }
            } else {
                Text("Feels like \(NunaInsightText.degrees(slot.peakFeelsLikeC))").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Image(systemName: NunaEnvironmentFormat.symbol(conditionId: slot.conditionId, feelsLikeC: slot.peakFeelsLikeC, night: slot.part == .night || NunaEnvironmentFormat.isNight(slot.start)))
                .font(.system(size: 58)).foregroundStyle(NunaPalette.recoveryBlue).frame(height: 62).padding(.top, 4)
            Text(verbatim: NunaEnvironmentFormat.skyText(conditionId: slot.conditionId)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1)
            VStack(spacing: 5) {
                fitChip(slot.fit)
                let why = NunaEnvironmentFormat.inTheWay(slot)
                if !why.isEmpty {
                    Text(verbatim: why).font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            // Air, wind and humidity: small, with their own symbols, in one row.
            HStack(spacing: 12) {
                if let aqi = slot.usAqi {
                    HStack(spacing: 4) {
                        Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7)
                        Text(verbatim: "AQI \(aqi)")
                    }
                }
                if let w = slot.windMps { miniFact("wind", String(format: "%.0f", w * 3.6) + " km/h") }
                if let h = slot.humidityPct { miniFact("drop.fill", "\(Int(h.rounded()))%") }
            }
            .font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 16)
    }

    private func miniFact(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.recoveryBlue)
            Text(verbatim: value)
        }
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
                    Image(systemName: "chevron.right").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let outlook, !outlook.slots.isEmpty { NunaSessionDeck(slots: outlook.slots, place: s.place) }
        }
    }
}

// MARK: - The page

/// The weather and the air as a trend view: the metric to read (temperature or air quality), the hours (H) or the days (D) switch and a date stepper, the average
/// with its range, a sentence, and a line of the forecast with the sky of each point under it. Touching a point shows its time and figure at the top.
struct NunaWeatherAirView: View {
    @ObservedObject private var store = EnvironmentStore.shared
    @State private var metric = Metric.temperature
    /// 1 is the hours (H), 5 the days (D).
    @State private var range = 1
    /// For the hours: which day-long window of the forecast, 0 being the next 24 hours.
    @State private var page = 0
    @State private var picked: Date?
    @State private var touchBeganOnPicked: Bool?
    @State private var menuOpen = false

    private enum Metric: Hashable { case temperature, air }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        /// For the days of the temperature: the low under the high.
        let low: Double?
        let symbol: String
        var id: Date { date }
    }

    private let color = NunaPalette.effortModerate
    private static let choices: [(value: Int, title: String)] = [(1, "H"), (5, "D")]

    var body: some View {
        NunaDetailScreen("Weather and air", trailing: AnyView(settingsButton), centersTitle: true) {
            if let s = store.snapshot {
                let outlook = EnvironmentOutlook.make(s, now: Int(Date().timeIntervalSince1970))
                let pts = points(s, outlook)
                metricBox
                header(pts, s)
                Text(verbatim: sentence(pts, s)).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.horizontal, 2)
                if range == 5, metric == .temperature { legend }
                if pts.count >= 2 { chart(pts) } else { needKey }
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

    // MARK: Metric

    /// The name box of a trend view, which is also where the metric is chosen: touched, it opens the two to pick from.
    private var metricBox: some View {
        VStack(spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { menuOpen.toggle() } } label: { box(metric, chevron: true) }.buttonStyle(.plain)
            if menuOpen {
                VStack(spacing: 0) {
                    ForEach([Metric.temperature, .air], id: \.self) { m in
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

    private func box(_ m: Metric, chevron: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon(m)).font(.nuna(size: 21, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 32)
            Text(title(m)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer(minLength: 0)
            if chevron { Image(systemName: menuOpen ? "chevron.up" : "chevron.down").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary) }
        }
        .padding(.horizontal, 18).frame(height: 60)
        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    private func icon(_ m: Metric) -> String { m == .temperature ? "thermometer.medium" : "aqi.medium" }
    private func title(_ m: Metric) -> LocalizedStringKey { m == .temperature ? "Temperature" : "Air quality" }

    // MARK: Points

    private func points(_ s: EnvironmentSnapshot, _ o: EnvironmentOutlook?) -> [Point] {
        let cal = Calendar.current
        let from = Int(Date().timeIntervalSince1970)
        func sky(_ ts: Int) -> String {
            let near = s.forecast.min { abs($0.ts - ts) < abs($1.ts - ts) }
            return NunaEnvironmentFormat.symbol(conditionId: near?.conditionId ?? s.conditionId, feelsLikeC: near?.feelsLikeC ?? s.effectiveC, night: NunaEnvironmentFormat.isNight(ts))
        }
        if range == 5 {
            return (o?.days ?? []).compactMap { d in
                let noon = cal.date(byAdding: .hour, value: 12, to: Date(timeIntervalSince1970: TimeInterval(d.start))) ?? Date(timeIntervalSince1970: TimeInterval(d.start))
                let symbol = NunaEnvironmentFormat.symbol(conditionId: d.conditionId, feelsLikeC: d.highC)
                switch metric {
                case .temperature: return Point(date: noon, value: d.highC, low: d.lowC, symbol: symbol)
                case .air: return d.usAqi.map { Point(date: noon, value: Double($0), low: nil, symbol: symbol) }
                }
            }
        }
        let start = from + page * 86_400, end = start + 86_400
        switch metric {
        case .temperature:
            var out: [Point] = []
            if page == 0, let t = s.tempC ?? s.effectiveC { out.append(Point(date: Date(timeIntervalSince1970: TimeInterval(from)), value: t, low: nil, symbol: sky(from))) }
            out += s.forecast.filter { $0.ts > from && $0.ts >= start && $0.ts <= end }.sorted { $0.ts < $1.ts }.map {
                Point(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.tempC ?? $0.feelsLikeC, low: nil, symbol: sky($0.ts))
            }
            return out
        case .air:
            return s.airForecast.filter { $0.ts >= start - 1800 && $0.ts <= end }.sorted { $0.ts < $1.ts }.map {
                Point(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: Double($0.usAqi), low: nil, symbol: sky($0.ts))
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

    private func fmt(_ v: Double) -> String { "\(Int(v.rounded()))" }

    // MARK: Header

    private func header(_ pts: [Point], _ s: EnvironmentSnapshot) -> some View {
        let pickedPoint = picked.flatMap { d in pts.first { $0.date == d } }
        let average: Double? = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        let shown = pickedPoint?.value ?? average
        let tint = pickedPoint == nil ? NunaPalette.textPrimary : color
        let unit = metric == .temperature ? "°C" : "AQI"
        let caption: String = pickedPoint.map { label($0.date) } ?? (range == 5 && metric == .temperature ? String(localized: "Avg. high") : String(localized: "Average"))
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: caption).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(pickedPoint == nil ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: shown.map(fmt) ?? "–").font(.nuna(size: 40, weight: .semibold, design: NunaType.design)).foregroundStyle(tint)
                    if shown != nil { Text(verbatim: unit).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(tint).textCase(nil) }
                }
                if pickedPoint == nil, let average { chip(pts, average) }
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

    /// Under the figure: the low and the high of the window for the temperature, the band the average falls in for the air.
    @ViewBuilder private func chip(_ pts: [Point], _ average: Double) -> some View {
        switch metric {
        case .temperature:
            let lo = pts.map { $0.low ?? $0.value }.min() ?? average, hi = pts.map(\.value).max() ?? average
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
            let aqi = Int(average.rounded())
            HStack(spacing: 6) {
                Circle().fill(NunaEnvironmentFormat.airColor(aqi)).frame(width: 7, height: 7)
                Text(verbatim: NunaEnvironmentFormat.bandName(AirQuality.band(usAqi: aqi))).font(.nuna(size: 12, weight: .bold)).textCase(nil)
            }
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 9).padding(.vertical, 4)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func sentence(_ pts: [Point], _ s: EnvironmentSnapshot) -> String {
        guard pts.count >= 2 else { return metric == .air ? String(localized: "The air forecast needs an OpenWeather key.") : String(localized: "Nothing in the forecast for this period yet.") }
        switch metric {
        case .temperature:
            let hi = pts.max { $0.value < $1.value }!
            if range == 5 {
                let lo = pts.compactMap(\.low).min() ?? hi.value
                return String(localized: "Warmest on \(label(hi.date)) at \(NunaInsightText.degrees(hi.value)), with nights down to \(NunaInsightText.degrees(lo)).")
            }
            let lo = pts.min { $0.value < $1.value }!
            return String(localized: "Warmest around \(label(hi.date)) at \(NunaInsightText.degrees(hi.value)), coolest around \(label(lo.date)) at \(NunaInsightText.degrees(lo.value)).")
        case .air:
            let worst = pts.max { $0.value < $1.value }!, best = pts.min { $0.value < $1.value }!
            var text = String(localized: "The air is at its worst around \(label(worst.date)) (AQI \(fmt(worst.value))) and at its best around \(label(best.date)) (AQI \(fmt(best.value))).")
            if worst.value >= 101 { text += " " + String(localized: "Above 100, go easier outside if you are sensitive to the air.") }
            return text
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

    private func chart(_ pts: [Point]) -> some View {
        let (low, high, ticks) = axis(pts)
        let first = pts.first!.date, last = pts.last!.date
        let pad: TimeInterval = range == 5 ? 18 * 3600 : 1800
        let domain = first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
        let every = pts.count > 9 ? 3 : 1
        let tickDates = pts.enumerated().filter { $0.offset % every == 0 }.map(\.element.date)
        let symbols = Dictionary(uniqueKeysWithValues: pts.map { ($0.date, $0.symbol) })
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
                if !(metric == .temperature && range == 5) {
                    AreaMark(x: .value("Time", p.date), yStart: .value("Base", low), yEnd: .value("Value", p.value))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.26), .clear], startPoint: .top, endPoint: .bottom))
                }
                LineMark(x: .value("Time", p.date), y: .value("Value", p.value), series: .value("Series", "high"))
                    .foregroundStyle(metric == .temperature && range == 5 ? NunaPalette.caution : color).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                if let lo = p.low {
                    LineMark(x: .value("Time", p.date), y: .value("Low", lo), series: .value("Series", "low"))
                        .foregroundStyle(NunaPalette.recoveryBlue).lineStyle(StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                }
            }
            if pts.count <= 9 {
                ForEach(pts) { p in
                    PointMark(x: .value("Time", p.date), y: .value("Value", p.value))
                        .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(metric == .temperature && range == 5 ? NunaPalette.caution : color, lineWidth: 2.5)).frame(width: 11, height: 11) }
                    if let lo = p.low {
                        PointMark(x: .value("Time", p.date), y: .value("Low", lo))
                            .symbol { Circle().fill(NunaPalette.canvas).overlay(Circle().stroke(NunaPalette.recoveryBlue, lineWidth: 2.5)).frame(width: 11, height: 11) }
                    }
                }
            }
            if let picked, let p = pts.first(where: { $0.date == picked }) {
                RuleMark(x: .value("Picked", picked)).foregroundStyle(Color.white.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Time", picked), y: .value("Value", p.value))
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
        .chartXAxis {
            AxisMarks(values: tickDates) { v in
                AxisValueLabel(centered: true) {
                    if let d = v.as(Date.self) {
                        VStack(spacing: 5) {
                            Image(systemName: symbols[d] ?? "cloud").font(.system(size: 17))
                                .foregroundStyle((symbols[d] ?? "").hasPrefix("sun") ? NunaPalette.caution : NunaPalette.recoveryBlue)
                            Text(verbatim: label(d)).font(.nuna(size: 10.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
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
        .frame(height: 330)
        .accessibilityLabel(Text(metric == .temperature ? "Temperature" : "Air quality"))
    }
}
#endif

#if os(iOS)
import SwiftUI
import Charts
import StrandDesign
import WhoopStore
import WhoopProtocol

// MARK: - Charges read off the battery history

/// One charge of the strap, found in the stored readings: where the level began to rise, where it stopped (or reached its top), and how long it took.
struct NunaChargeSession: Equatable {
    let start: Int
    let end: Int
    let fromPct: Double
    let toPct: Double
    var duration: Int { end - start }
}

enum NunaBatteryHistory {
    /// The charges in a run of readings (oldest first). A charge is a stretch in which the level only goes up (a point of noise is let through) with no gap
    /// of more than 45 minutes between readings, that rose by 8 points or more over at least 10 minutes. It ends at the first reading of its top level, so
    /// the time on the charger after a full battery is not counted.
    static func sessions(_ samples: [(ts: Int, soc: Double)]) -> [NunaChargeSession] {
        let s = samples
        guard s.count >= 2 else { return [] }
        var out: [NunaChargeSession] = []
        var i = 0
        while i < s.count - 1 {
            var j = i, peak = i
            while j + 1 < s.count, s[j + 1].ts - s[j].ts <= 45 * 60, s[j + 1].soc >= s[j].soc - 1 {
                j += 1
                if s[j].soc > s[peak].soc { peak = j }
            }
            if s[peak].soc - s[i].soc >= 8, s[peak].ts - s[i].ts >= 10 * 60 {
                let top = s[peak].soc
                let end = (i...peak).first { s[$0].soc >= top - 1 } ?? peak
                out.append(NunaChargeSession(start: s[i].ts, end: s[end].ts, fromPct: s[i].soc, toPct: s[end].soc))
            }
            i = max(j, i + 1)
        }
        return out
    }

    /// The readings of the last `days` days from the store, with the ones the strap sent since they were saved.
    @MainActor static func load(repo: Repository, live: LiveState, days: Int = 7) async -> [(ts: Int, soc: Double)] {
        let now = Int(Date().timeIntervalSince1970)
        var rows: [(ts: Int, soc: Double)] = []
        if let store = await repo.storeHandle() {
            let found = (try? await store.batterySamples(deviceId: repo.deviceId, from: now - days * 86_400, to: now + 60, limit: 20_000)) ?? []
            rows = found.compactMap { r in r.soc.map { (ts: r.ts, soc: $0) } }
        }
        let last = rows.last?.ts ?? 0
        rows += live.batterySamples.filter { $0.ts > last }
        return rows.sorted { $0.ts < $1.ts }
    }

    static func hm(_ seconds: Int) -> String {
        let m = max(0, Int((Double(seconds) / 60).rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

// MARK: - The page

/// The strap's battery as a ring and a few figures: the time to full (or the time left) in the ring, the level in a small glass tile beside it, the
/// average and the last charge under them, and the level over the last week as a line to touch.
struct NunaDeviceBatteryView: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @State private var readings: [(ts: Int, soc: Double)] = []
    @State private var picked: Date?
    @State private var bars = false

    private struct Point: Identifiable { let date: Date; let value: Double; var id: Date { date } }

    private let blue = NunaPalette.recoveryBlue

    #if DEBUG
    /// `--demo-battery`: a charge in progress at 73% and a week of readings with a charge each day, to look at the page without a strap.
    private static var demo: Bool { CommandLine.arguments.contains("--demo-battery") }
    /// With `--demo-battery-discharge` the strap is not charging: 64% and about three days left.
    private static var demoDischarging: Bool { CommandLine.arguments.contains("--demo-battery-discharge") }
    private static func demoReadings() -> [(ts: Int, soc: Double)] {
        let now = Int(Date().timeIntervalSince1970)
        var out: [(ts: Int, soc: Double)] = []
        for d in stride(from: 7, through: 0, by: -1) {
            let day = now - d * 86_400
            for k in 0..<30 { out.append((ts: day - 43_200 + k * 1_200, soc: max(8, 98 - Double(k) * 2.9 - Double(d % 3) * 6))) }
            for k in 0..<12 { out.append((ts: day + k * 420, soc: min(100, 18 + Double(k) * 7.4))) }
        }
        return out.filter { $0.ts <= now }.sorted { $0.ts < $1.ts }
    }
    #endif

    var body: some View {
        #if DEBUG
        let pct: Double? = Self.demo ? (Self.demoDischarging ? 64 : 73) : live.batteryPct
        #else
        let pct = live.batteryPct
        #endif
        let sessions = NunaBatteryHistory.sessions(readings)
        NunaDetailScreen("Battery", centersTitle: true) {
            hero(pct)
            figures(sessions)
            chart
            if let mv = live.batteryMv {
                HStack {
                    nunaTrendsCap("Voltage")
                    Spacer()
                    Text(verbatim: String(format: "%.2f V", locale: AppLanguage.activeLocale, Double(mv) / 1000)).font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                }
                .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                nunaRuledHeader("Looking after the battery")
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                    VStack(spacing: 0) {
                        NunaListRow("Recovery while you are awake", description: "In the shower or at your desk, so no sleep data is lost", systemImage: NunaIcons.sleep)
                        NunaDivider()
                        NunaListRow("Avoid heat", description: "Do not charge in direct sunlight", systemImage: "sun.max")
                        NunaDivider()
                        NunaListRow("Dry the contacts", description: "Clean and dry them before charging", systemImage: "drop")
                    }
                }
            }
            Text("The percentage is read from the strap. The time left is estimated from the readings of this session only and gets better the longer the strap stays connected.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .task {
            #if DEBUG
            if Self.demo { readings = Self.demoReadings(); return }
            #endif
            readings = await NunaBatteryHistory.load(repo: repo, live: live)
        }
        .onChange(of: live.batterySamples.count) { _, _ in Task { readings = await NunaBatteryHistory.load(repo: repo, live: live) } }
    }

    // MARK: Ring

    private func hero(_ pct: Double?) -> some View {
        #if DEBUG
        let charging = Self.demo ? !Self.demoDischarging : live.isCharging
        #else
        let charging = live.isCharging
        #endif
        let caption: LocalizedStringKey = charging ? "Charging" : (live.connected || Self.isDemo ? "Not charging" : "Not connected")
        let estimate = estimateValue(charging: charging)
        return ZStack {
            ring(pct: pct, caption: caption)
            VStack(spacing: 2) {
                Text(verbatim: estimate ?? "–").font(.nuna(size: 28, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
                Text(charging ? "To full" : "Left").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(blue)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(NunaPalette.canvas))
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(NunaPalette.glassStrong))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: blue.opacity(0.25), radius: 14, y: 6)
            .offset(x: 92, y: 96)
        }
        .frame(maxWidth: .infinity).frame(height: 292)
        .accessibilityElement(children: .combine)
    }

    private static var isDemo: Bool {
        #if DEBUG
        return demo
        #else
        return false
        #endif
    }

    /// The time to full while charging, the time left (the estimate of the discharge) when not; nil while either is not known.
    private func estimateValue(charging: Bool) -> String? {
        #if DEBUG
        if Self.demo { return charging ? "1:28" : "3d 4h" }
        #endif
        if charging { return live.chargeHoursToFull.map { NunaBatteryHistory.hm(Int($0 * 3600)) } }
        guard live.connected, let est = live.batteryEstimate else { return nil }
        let h = Int(est.remainingHours.rounded())
        return h >= 48 ? "\(h / 24)d \(h % 24)h" : NunaBatteryHistory.hm(h * 3600)
    }

    /// The ring is the level: filled to it, with the percentage in the middle.
    private func ring(pct: Double?, caption: LocalizedStringKey) -> some View {
        let frac = CGFloat(min(max((pct ?? 0) / 100, 0), 1))
        return ZStack {
            Circle().fill(RadialGradient(colors: [blue.opacity(0.20), blue.opacity(0.03), .clear], center: .center, startRadius: 4, endRadius: 128))
            Circle().stroke(NunaPalette.hairline.opacity(0.7), lineWidth: 1.5)
            Circle().trim(from: 0, to: frac)
                .stroke(AngularGradient(colors: [blue.opacity(0.25), blue, Color.white.opacity(0.92)], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Double(max(frac, 0.02)))),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: blue.opacity(0.8), radius: 7)
            VStack(spacing: 4) {
                Text(caption).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(blue)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: pct.map { "\(Int($0.rounded()))" } ?? "–").font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64))
                        .foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if pct != nil { Text("%").font(.nuna(size: 24, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            .padding(.horizontal, 26)
        }
        .frame(width: 244, height: 244)
    }

    // MARK: Average and last

    private func figures(_ sessions: [NunaChargeSession]) -> some View {
        let average: (Int, Double)? = sessions.isEmpty ? nil : (
            sessions.map(\.duration).reduce(0, +) / sessions.count,
            sessions.map(\.toPct).reduce(0, +) / Double(sessions.count))
        return HStack(alignment: .top, spacing: 0) {
            figure("Average charge", average.map { (NunaBatteryHistory.hm($0.0), $0.1) }, alignment: .leading)
            Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 44).padding(.top, 8)
            figure("Last charge", sessions.last.map { (NunaBatteryHistory.hm($0.duration), $0.toPct) }, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    private func figure(_ title: LocalizedStringKey, _ value: (String, Double)?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(title).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: value?.0 ?? "–").font(.nuna(size: 24, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                if let v = value { Text(verbatim: "\(Int(v.1.rounded()))%").font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(blue) }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: Level over the week

    private var points: [Point] {
        let step = max(1, readings.count / 220)
        var out = readings.enumerated().filter { $0.offset % step == 0 }.map { Point(date: Date(timeIntervalSince1970: TimeInterval($0.element.ts)), value: $0.element.soc) }
        if let last = readings.last, out.last?.date.timeIntervalSince1970 != TimeInterval(last.ts) {
            out.append(Point(date: Date(timeIntervalSince1970: TimeInterval(last.ts)), value: last.soc))
        }
        return out
    }

    /// The average level of each day, for the bars.
    private var dayBars: [Point] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: readings) { cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.ts))) }
        return byDay.map { Point(date: $0.key, value: $0.value.map(\.soc).reduce(0, +) / Double($0.value.count)) }.sorted { $0.date < $1.date }
    }

    /// The history as a card: the level of the point touched (the latest at first) in its head, the curve over a grid of 0 to 100 with a dashed cross to the point,
    /// and the days under it. The tabs at the head switch to the average level of each day as bars.
    @ViewBuilder private var chart: some View {
        let pts = points
        if pts.count >= 2 {
            let active = picked.flatMap { d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } } ?? pts.last
            let first = pts.first!.date
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Battery charge:").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Text(verbatim: (bars ? dayBars.last?.value : active?.value).map { "\(Int($0.rounded()))%" } ?? "–")
                            .font(.nuna(size: 18, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        HStack(spacing: 2) {
                            modeButton("percent", on: !bars) { bars = false }
                            modeButton("chart.bar.fill", on: bars) { bars = true }
                        }
                        .padding(2).background(NunaPalette.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Chart {
                        if bars {
                            ForEach(dayBars) { p in
                                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Level", p.value), width: .ratio(0.55))
                                    .foregroundStyle(LinearGradient(colors: [blue, blue.opacity(0.35)], startPoint: .top, endPoint: .bottom)).cornerRadius(3)
                            }
                        } else {
                            ForEach(pts) { p in
                                AreaMark(x: .value("Time", p.date), yStart: .value("Base", 0), yEnd: .value("Level", p.value))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(LinearGradient(colors: [blue.opacity(0.30), blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("Time", p.date), y: .value("Level", p.value))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            }
                            if let a = active {
                                RuleMark(xStart: .value("From", first), xEnd: .value("Picked", a.date), y: .value("Level", a.value))
                                    .foregroundStyle(Color.white.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                RuleMark(x: .value("Picked", a.date), yStart: .value("Base", 0), yEnd: .value("Level", a.value))
                                    .foregroundStyle(Color.white.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                                PointMark(x: .value("Time", a.date), y: .value("Level", a.value))
                                    .symbol { Circle().fill(Color.white).overlay(Circle().stroke(NunaPalette.canvas, lineWidth: 3)).overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5).padding(-3)).frame(width: 11, height: 11) }
                            }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100]) { v in
                            AxisGridLine().foregroundStyle(NunaPalette.hairline.opacity(0.6))
                            AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: "\(Int(d))").font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { v in
                            AxisValueLabel(centered: true) {
                                if let d = v.as(Date.self) {
                                    Text(verbatim: d.formatted(.dateTime.day().month(.abbreviated))).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { $0.padding(.horizontal, 12) }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            if let frame = proxy.plotFrame.map({ geo[$0] }), !bars {
                                Rectangle().fill(Color.clear).contentShape(Rectangle()).frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                                        if let d: Date = proxy.value(atX: g.location.x - frame.minX) { picked = d }
                                    }.onEnded { _ in picked = nil })
                            }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel(Text("Battery level"))
                }
            }
        } else {
            Text("Readings appear here as the strap reports them. Keep it connected for a while to see the trend.")
                .font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).padding(.horizontal, 4)
        }
    }

    private func modeButton(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textMuted)
                .frame(width: 34, height: 28).background(on ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
#endif

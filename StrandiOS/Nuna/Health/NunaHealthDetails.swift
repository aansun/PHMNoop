#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

private func nunaCap(_ t: LocalizedStringKey) -> some View {
    Text(t).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
}

private func nunaFmt(_ v: Double?, _ digits: Int = 0) -> String {
    v.map { String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, $0) } ?? "–"
}

private func nunaSigned(_ v: Double, _ digits: Int = 1) -> String {
    (v >= 0 ? "+" : "−") + String(format: "%.\(digits)f", locale: AppLanguage.activeLocale, abs(v))
}

private func nunaMiniStat(_ label: LocalizedStringKey, _ value: String, unit: String = "") -> some View {
    NunaStatTile(label: label, value: value, unit: unit)
}

// MARK: - Live heart rate

struct NunaLiveHeartView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @AppStorage(UnitPrefs.liveActivityKey) private var islandOn = true
    @AppStorage(PuffinExperiment.broadcastHrKey) private var broadcastOn = false

    @State private var range = 0
    @State private var rolling: [Double] = []
    @State private var banked: [(ts: Int, bpm: Double)] = []
    @State private var rangeSamples: [HRSample] = []
    @State private var daySamples: [HRSample] = []

    private var isLive: Bool { live.connected && rolling.count >= 2 }
    private var zoneSet: HRZoneSet { profile.hrZoneSet }

    private var currentBpm: Int? {
        if live.connected, let hr = live.heartRate, hr > 0 { return hr }
        return banked.last.map { Int($0.bpm.rounded()) }
    }

    private var stateLabel: LocalizedStringKey? {
        guard let bpm = currentBpm else { return nil }
        switch zoneSet.zoneNumber(forBPM: Double(bpm)) {
        case 0, 1: return "Resting"
        case 2: return "Light"
        case 3: return "Aerobic"
        case 4: return "Threshold"
        default: return "Maximum"
        }
    }

    var body: some View {
        NunaDetailScreen("Live heart rate") {
            heroCard
            NunaSegmented([(value: 0, title: "5 min"), (value: 1, title: "1 hour"), (value: 2, title: "Today")], selection: $range)
            statTiles
            zonesCard
            togglesCard
            NavigationLink(value: NunaTodayRoute.deepTimeline) {
                NunaCard(small: true) { NunaListRow("Deep timeline", subtitle: "Every second of your day, zoomable.", systemImage: "waveform.path.ecg", showsChevron: true) }
            }.buttonStyle(.plain)
            Button { router.requestedDestination = .activeWorkout } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.nuna(size: 14, weight: .bold))
                    Text("Start a session with heart rate").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
        .task(id: repo.refreshSeq) { await loadDay() }
        .task(id: range) { await loadRange() }
        .onAppear { if rolling.isEmpty, let hr = live.heartRate, hr > 0 { rolling = [Double(hr)] } }
        .onChange(of: live.heartRate) { _, hr in
            guard let hr, hr > 0 else { return }
            rolling.append(Double(hr))
            if rolling.count > 90 { rolling.removeFirst(rolling.count - 90) }
        }
    }

    private var heroCard: some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NunaChip(isLive ? "Live" : (live.connected ? "Waiting for the strap" : "Not connected"),
                             color: isLive ? NunaPalette.charge : (live.connected ? nil : NunaPalette.warning))
                    Spacer()
                    if let b = live.batteryPct {
                        NunaChip(verbatim: String(localized: "Strap \(Int(b.rounded()))%"), systemImage: "applewatch")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "heart.fill").font(.nuna(size: 26)).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: currentBpm.map(String.init) ?? "–").font(.nuna(size: 76, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(76)).foregroundStyle(NunaPalette.textPrimary)
                    Text("bpm").font(.nuna(size: 20, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack {
                    if let stateLabel { NunaChip(stateLabel) }
                    Spacer()
                    Text(isLive ? "Updated every second" : (banked.last.map { lastReading($0.ts) } ?? "–"))
                        .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                if isLive || banked.count >= 2 {
                    NunaHRTrace(values: isLive ? rolling : banked.suffix(36).map(\.bpm), segments: nil).frame(height: 100)
                    HStack {
                        Text(isLive ? "−\(rolling.count) s" : "Earlier today"); Spacer(); Text(isLive ? "Now" : "Latest")
                    }
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                } else {
                    Text(live.connected ? "Waiting for a live heartbeat…" : "Connect your strap to see live heart rate")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
    }

    private func lastReading(_ ts: Int) -> LocalizedStringKey {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("jj:mm")
        return LocalizedStringKey(String(localized: "Last reading \(f.string(from: Date(timeIntervalSince1970: TimeInterval(ts))))"))
    }

    private var statTiles: some View {
        let v = rangeSamples.map { Double($0.bpm) }
        return HStack(spacing: 10) {
            NunaStatTile(label: "Lowest", value: nunaFmt(v.min()))
            NunaStatTile(label: "Average", value: nunaFmt(v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)))
            NunaStatTile(label: "Highest", value: nunaFmt(v.max()))
        }
    }

    // Zone colours: rest, light, aerobic, threshold, maximum.
    private let zoneColors: [Color] = [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
    private let zoneNames: [LocalizedStringKey] = ["Zone 1 · easy", "Zone 2 · light", "Zone 3 · aerobic", "Zone 4 · threshold", "Zone 5 · maximum"]

    private var zonesCard: some View {
        let tiz = HRZones.timeInZone(daySamples, zoneSet: zoneSet)
        let secs = [tiz.belowZone1] + tiz.seconds
        let total = max(tiz.total, 1)
        func dur(_ s: Double) -> String { NunaSleepFormat.duration(s / 60) }
        return NunaCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    nunaCap("Zones today")
                    Spacer()
                    Text(verbatim: String(localized: "Total \(dur(tiz.total))")).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                if tiz.total > 0 {
                    NunaProportionBar(parts: (0..<6).map { i in (secs[i], i == 0 ? NunaPalette.zoneBase.opacity(0.6) : zoneColors[i - 1]) })
                    VStack(spacing: 10) {
                        zoneRow(Text("Resting · below zone 1"), secs[0], NunaPalette.zoneBase.opacity(0.6), dur)
                        ForEach(0..<5, id: \.self) { i in zoneRow(Text(zoneNames[i]), secs[i + 1], zoneColors[i], dur) }
                    }
                } else {
                    Text("No heart-rate readings yet today").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    private func zoneRow(_ title: Text, _ seconds: Double, _ color: Color, _ dur: (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            title.font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Text(verbatim: dur(seconds)).font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
        }
    }

    private var togglesCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("Show on the Dynamic Island", subtitle: "Live heart rate while the strap is connected") {
                    Toggle("", isOn: $islandOn).labelsHidden().tint(NunaPalette.charge)
                }
                if model.whoop5Detected || broadcastOn {
                    NunaDivider()
                    NunaListRow("Broadcast to other apps", subtitle: "The strap shows up as a Bluetooth heart-rate sensor. Experimental, WHOOP 5/MG.") {
                        Toggle("", isOn: $broadcastOn).labelsHidden().tint(NunaPalette.charge)
                            .onChange(of: broadcastOn) { _, on in model.ble.setBroadcastHr(on) }
                    }
                }
            }
        }
    }

    private func loadDay() async {
        let now = Int(Date().timeIntervalSince1970)
        let midnight = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        daySamples = await repo.hrSamples(from: midnight, to: now, limit: 200_000)
        banked = await repo.hrBuckets(from: midnight, to: now, bucketSeconds: 300).map { ($0.ts, $0.bpm) }
        await loadRange()
    }

    private func loadRange() async {
        let now = Int(Date().timeIntervalSince1970)
        let midnight = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let from = range == 0 ? now - 300 : (range == 1 ? now - 3600 : midnight)
        rangeSamples = range == 2 ? daySamples : await repo.hrSamples(from: from, to: now, limit: 200_000)
        if range == 0, rangeSamples.isEmpty, let last = daySamples.last {
            // Nothing in the last 5 minutes (strap not streaming): fall back to the latest 5 minutes recorded.
            rangeSamples = daySamples.filter { $0.ts >= last.ts - 300 }
        } else if range == 1, rangeSamples.isEmpty, let last = daySamples.last {
            rangeSamples = daySamples.filter { $0.ts >= last.ts - 3600 }
        }
    }
}

// MARK: - Oxygen and breathing

// MARK: - Skin temperature

struct NunaSkinTempView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var skinS = NunaSeriesModel()

    var body: some View {
        let nights = skinS.readings(14)
        let latest = skinS.latest?.value
        NunaDetailScreen("Skin temperature") {
            NunaCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        nunaCap("Last night")
                        Spacer()
                        if let latest { NunaChip(abs(latest) < 0.5 ? "Small deviation" : "Larger deviation", color: abs(latest) < 0.5 ? NunaPalette.charge : NunaPalette.warning) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: latest.map { nunaSigned($0) } ?? "–").font(.nuna(size: 68, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(68)).foregroundStyle(NunaPalette.textPrimary)
                        if latest != nil { Text("°C").font(.nuna(size: 23, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    Text("Compared with your personal baseline").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        nunaCap("14 nights")
                        Spacer()
                        Text("Centre line = baseline").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    if nights.count >= 2 {
                        NunaDivergingBars(values: nights.map(\.value))
                        HStack {
                            Text(verbatim: nunaAxisDate(nights.first!.date)); Spacer(); Text(verbatim: nunaAxisDate(nights.last!.date))
                        }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text("Not enough data yet").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                }
            }
            if let latest {
                VStack(spacing: 8) {
                    NunaDeviationScale(value: latest)
                    HStack { Text("−1 °C"); Spacer(); Text("+1 °C") }
                        .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            NunaTitleRow(title: "What affects it") { EmptyView() }
            NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
                VStack(spacing: 0) {
                    NunaListRow("Room temperature", subtitle: "A warm room can raise it a little", systemImage: "thermometer.medium")
                    NunaDivider()
                    NunaListRow("Alcohol", subtitle: "Log it in your journal to see the link", systemImage: "drop")
                    if appModel.cyclePhase != nil {
                        NunaDivider()
                        NunaListRow("Cycle phase", subtitle: "The luteal phase can raise your baseline", systemImage: "moon")
                    }
                }
            }
            NavigationLink(value: NunaTodayRoute.earlyWarning) {
                NunaCard(small: true) { NunaListRow("Early warning", subtitle: "It takes two signals away from your range", systemImage: "bell", showsChevron: true) }
            }.buttonStyle(.plain)
            NunaExpandRow(title: "How it's calculated", subtitle: "A deviation, not core body temperature", systemImage: "sparkles",
                          text: "The strap measures skin temperature at the wrist while you sleep and compares it with your own recent nights. The figure is a deviation from your baseline, not your core body temperature.")
        }
        .task { await skinS.load(repo: repo, key: "skin_temp", source: "my-whoop") }
    }
}

/// Bars up or down from a dashed centre line (the baseline). Bars past half a degree turn yellow.
struct NunaDivergingBars: View {
    let values: [Double]
    var body: some View {
        let scale = max(0.6, values.map { abs($0) }.max() ?? 0.6)
        GeometryReader { geo in
            let mid = geo.size.height / 2
            ZStack {
                HStack(spacing: 5) {
                    ForEach(values.indices, id: \.self) { i in
                        let v = values[i]
                        let h = max(3, CGFloat(abs(v) / scale) * mid)
                        VStack(spacing: 0) {
                            if v >= 0 {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(abs(v) >= 0.5 ? NunaPalette.warning : NunaPalette.rest).frame(height: h)
                                Color.clear.frame(height: mid)
                            } else {
                                Color.clear.frame(height: mid)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(abs(v) >= 0.5 ? NunaPalette.warning : NunaPalette.rest).frame(height: h)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: geo.size.width, y: mid)) }
                    .stroke(NunaPalette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}

/// Three-segment scale from −1 to +1 with a marker at the value.
struct NunaDeviationScale: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            let f = CGFloat(min(max((value + 1) / 2, 0), 1))
            ZStack(alignment: .leading) {
                NunaProportionBar(parts: [(3, NunaPalette.zoneBase), (4, NunaPalette.ink.opacity(0.2)), (3, NunaPalette.zoneBase)], height: 12)
                RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.ink).frame(width: 6, height: 20)
                    .shadow(color: NunaPalette.ink.opacity(0.2), radius: 3)
                    .offset(x: min(max(geo.size.width * f - 3, 0), geo.size.width - 6))
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}
#endif

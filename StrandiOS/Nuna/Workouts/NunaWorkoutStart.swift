#if os(iOS)
import SwiftUI
import UIKit
import ActivityKit
import StrandDesign
import StrandAnalytics
import WhoopStore

/// What the wearer asked for before starting. The live screen shows progress against it and nudges once when it is met.
struct NunaWorkoutGoal: Equatable {
    enum Mode: String { case free, time, distance, zone }
    var mode: Mode = .free
    var minutes = 30
    var km = 5.0
    var zone = 2
}

// MARK: - Start (WorkoutStart)

struct NunaWorkoutStartView: View {
    let sport: String?
    /// Opened to carry on a session that is already running: straight to its live screen instead of the start screen.
    var resume = false
    @State private var didResume = false
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @State private var planned: NavRouter.PlannedSession?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage("nuna.workout.zoneBuzz") private var zoneBuzz = true
    @State private var chosen: String = "Running"
    @State private var goal = NunaWorkoutGoal()
    @State private var showPicker = false
    @State private var countdown: Int?
    @State private var live = false

    private var isDistance: Bool { WorkoutCatalog.sport(named: chosen)?.isDistanceSport ?? false }
    private var zoneSet: HRZoneSet { profile.hrZoneSet }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(chosen)) {
            if let planned {
                NunaCard(small: true, highlight: true) {
                    HStack(spacing: 12) {
                        AnyaIconTile()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From Anya's plan").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                            Text(verbatim: planned.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                        Spacer(minLength: 6)
                        Button { withAnimation { self.planned = nil; goal = NunaWorkoutGoal() } } label: {
                            Text("Clear").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
            readiness
            NunaSegmented([(value: NunaWorkoutGoal.Mode.free, title: "Free"), (value: .time, title: "Time"), (value: .distance, title: "Distance"), (value: .zone, title: "Zone")], selection: $goal.mode)
            goalCard
            optionsCard
            Button { showPicker = true } label: {
                NunaCard(small: true) { NunaListRow("Sport", subtitle: LocalizedStringKey(chosen), systemImage: NunaSportPicker.symbol(for: chosen), showsChevron: true) }
            }.buttonStyle(.plain)
            if chosen == "Strength" || chosen == "Weightlifting" || chosen == "Powerlifting" || chosen == "Bodybuilding" {
                NavigationLink(value: NunaWorkoutRoute.gym) {
                    NunaCard(highlight: true) { NunaListRow("Log sets and weights", description: "Open Gym to run a program or a freehand session", systemImage: "dumbbell", showsChevron: true) }
                }.buttonStyle(.plain)
            }
            Button { begin() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.nuna(size: 14, weight: .bold))
                    Text(model.activeWorkout == nil ? "Start in 3 seconds" : "View active workout").font(.nuna(size: 17, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
        .onAppear {
            if resume, !didResume, model.activeWorkout != nil { didResume = true; live = true }
            // A session suggested by the day plan: hold its main zone, and keep its length for the Time goal.
            if let p = router.plannedSession {
                router.plannedSession = nil
                planned = p; goal.mode = .zone; goal.zone = min(max(p.zone, 1), 5); goal.minutes = max(5, min(p.minutes, 300))
            }
            if let s = planned?.sport, let match = WorkoutCatalog.sport(named: s) { chosen = match.name }
            if let sport { chosen = sport } else if let a = model.activeWorkout { chosen = a.sport } }
        .sheet(isPresented: $showPicker) { sportPicker.nunaSheetChrome(detents: [.large]) }
        .fullScreenCover(isPresented: $live) { NunaLiveWorkoutView(goal: goal, zoneBuzz: zoneBuzz, onClose: { live = false }) }
        .overlay { if let c = countdown { countdownView(c) } }
    }

    // MARK: Parts

    private var readiness: some View {
        let charge = repo.today?.recovery
        return Group {
            if let c = charge {
                HStack(spacing: 10) {
                    Image(systemName: "bolt").foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: String(localized: "Charge \(Int(c.rounded()))%. \(c >= 67 ? String(localized: "Ready for a hard session.") : (c >= 34 ? String(localized: "A steady session suits today.") : String(localized: "Keep it easy today.")))"))
                        .font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 12).background(NunaPalette.tint(NunaPalette.charge), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
        }
    }

    @ViewBuilder private var goalCard: some View {
        switch goal.mode {
        case .free:
            NunaCard { Text("No target. The session records heart rate, Effort and, for outdoor sports, your route.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
        case .time:
            stepperCard("Target duration", "\(goal.minutes)", "min", minus: { goal.minutes = max(5, goal.minutes - 5) }, plus: { goal.minutes = min(300, goal.minutes + 5) })
        case .distance:
            stepperCard("Target distance", String(format: "%.1f", locale: AppLanguage.activeLocale, goal.km), unitSystemRaw == UnitSystem.imperial.rawValue ? "km" : "km",
                        minus: { goal.km = max(0.5, goal.km - 0.5) }, plus: { goal.km = min(100, goal.km + 0.5) })
        case .zone:
            zoneCard
        }
    }

    // MARK: Zone picker

    /// The colour of each heart-rate zone, light to hard.
    private static let zoneColors: [Color] = [NunaPalette.zoneBase, NunaPalette.charge, NunaPalette.effort, NunaPalette.warning, NunaPalette.alert]

    /// One slim bar of five zones: tap a segment to choose it. A pointer sits under the chosen zone, the lowest and highest heart
    /// rate of the wearer's own zones are at the ends and the chosen zone's range is written in its colour in the middle.
    private var zoneCard: some View {
        let z = min(max(goal.zone, 1), 5)
        let color = Self.zoneColors[z - 1]
        let zones = zoneSet.zones
        let range = zones.first(where: { $0.number == z })
        let lo = zones.first(where: { $0.number == 1 }).map { Int($0.lower.rounded()) }
        let hi = zones.first(where: { $0.number == 5 }).map { Int($0.upper.rounded()) }
        return NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16)) {
            VStack(spacing: 8) {
                GeometryReader { geo in
                    let w = geo.size.width, gap: CGFloat = 3
                    let seg = (w - gap * 4) / 5
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: gap) {
                            ForEach(1...5, id: \.self) { n in
                                Button { withAnimation(.easeOut(duration: 0.18)) { goal.zone = n } } label: {
                                    RoundedRectangle(cornerRadius: n == 1 || n == 5 ? 12 : 4, style: .continuous)
                                        .fill(Self.zoneColors[n - 1].opacity(n == z ? 1 : 0.6)).frame(height: 26)
                                        .padding(.vertical, 6).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).frame(width: seg)
                                .accessibilityLabel(Text("Zone \(n)")).accessibilityAddTraits(n == z ? .isSelected : [])
                            }
                        }
                        Triangle().fill(NunaPalette.textPrimary).frame(width: 14, height: 9)
                            .offset(x: CGFloat(z - 1) * (seg + gap) + seg / 2 - 7, y: 42)
                            .animation(.easeOut(duration: 0.18), value: z).allowsHitTesting(false)
                    }
                }
                .frame(height: 52)
                ZStack {
                    HStack {
                        Text(verbatim: lo.map(String.init) ?? "").font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                        Spacer()
                        Text(verbatim: hi.map(String.init) ?? "").font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                    }
                    Text(verbatim: String(localized: "Zone \(z)") + (range.map { " · \(Int($0.lower.rounded())) – \(Int($0.upper.rounded()))" } ?? ""))
                        .font(.nuna(size: 16, weight: .heavy, design: NunaType.design)).foregroundStyle(z == 1 ? NunaPalette.textPrimary : color).monospacedDigit()
                }
            }
        }
    }

    private func stepperCard(_ title: LocalizedStringKey, _ v: String, _ unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                nunaTrendsCap(title)
                HStack {
                    stepBtn("minus", minus)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: v).font(.nuna(size: 46, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(46)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: unit).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    stepBtn("plus", plus)
                }
            }
        }
    }

    private func stepBtn(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 52) }.buttonStyle(.plain)
    }

    private var optionsCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("GPS and route", subtitle: isDistance ? "The route is recorded when location is allowed" : "Not used for this sport", systemImage: "location") {
                    NunaChip(isDistance ? "On" : "Off", color: isDistance ? NunaPalette.charge : nil)
                }
                NunaDivider()
                NunaListRow("Silent buzz on the strap", description: "When you leave the target zone or reach the target", systemImage: "applewatch.radiowaves.left.and.right") {
                    Toggle("", isOn: $zoneBuzz).labelsHidden().tint(NunaPalette.charge)
                }
            }
        }
    }

    private var sportPicker: some View {
        NunaSportPicker(selection: $chosen) { showPicker = false }
    }

    private func countdownView(_ c: Int) -> some View {
        ZStack {
            NunaPalette.shade.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(verbatim: "\(c)").font(.nuna(size: 120, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(120)).foregroundStyle(NunaPalette.textPrimary)
                Button("Cancel") { countdown = nil }.font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .transition(.opacity)
    }

    private func begin() {
        if model.activeWorkout != nil { live = true; return }
        countdown = 3
        Task {
            for n in stride(from: 3, through: 1, by: -1) {
                guard countdown != nil else { return }
                countdown = n
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard countdown != nil else { return }
            countdown = nil
            model.startWorkout(sport: chosen)
            switch goal.mode {
            case .free: model.workoutTarget = nil
            case .time: model.workoutTarget = .init(seconds: goal.minutes * 60)
            case .distance: model.workoutTarget = .init(meters: goal.km * 1000)
            case .zone: model.workoutTarget = .init(zone: goal.zone)
            }
            live = true
        }
    }
}

// MARK: - Live (in-exercise)

struct NunaLiveWorkoutView: View {
    let goal: NunaWorkoutGoal
    let zoneBuzz: Bool
    let onClose: () -> Void
    @EnvironmentObject private var model: AppModel
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false
    @AppStorage("nuna.live.hideBpm") private var hideBpm = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @State private var confirmEnd = false
    @State private var goalHit = false
    @State private var lastBuzz = Date.distantPast

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var zoneSet: HRZoneSet { model.profile.hrZoneSet }

    var body: some View {
        ZStack {
            NunaPalette.canvas.ignoresSafeArea()
            if let w = model.activeWorkout {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    content(w, now: tick.date)
                }
            } else {
                finished
            }
        }
        .onAppear { if keepScreenOn { UIApplication.shared.isIdleTimerDisabled = true } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save") { model.endWorkout() }
            Button("Discard", role: .destructive) { model.discardWorkout(); onClose() }
            Button("Keep going", role: .cancel) {}
        }
    }

    /// After the session: what it was, how it felt and a photo, then Done.
    private var finished: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Session finished").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 40)
                if let last = model.lastWorkout {
                    Text(verbatim: WorkoutSource.displaySport(last.sport) + " · " + NunaWorkoutFormat.duration(last.durationS)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    NunaWorkoutFinishedReview(row: last, onDone: onClose).padding(.top, 8)
                } else {
                    Text("Sessions under a minute are not saved.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Button(action: onClose) { Text("OK").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)) }.buttonStyle(.plain).padding(.top, 8)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private static let zoneColors: [Color] = [NunaPalette.zoneBase, NunaPalette.charge, NunaPalette.effort, NunaPalette.warning, NunaPalette.alert]
    private var distanceSystem: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw) }

    private enum ZoneState { case none, inZone, below, above, farAbove }

    private func content(_ w: AppModel.ActiveWorkout, now: Date) -> some View {
        let elapsed = w.elapsed(at: now)
        let bpm = model.bpm
        let zone = bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0
        let gps = model.gpsRecorder
        let state = zoneState(bpm: bpm, zone: zone)
        let tone = tone(zone: zone, state: state)
        let shownZone = zone > 0 ? zone : (goal.mode == .zone ? goal.zone : 0)
        return ScrollView {
            VStack(spacing: 14) {
                header(w, shownZone: shownZone, color: zone > 0 ? Self.zoneColors[min(zone, 5) - 1] : NunaPalette.textSecondary)
                ring(elapsed: elapsed, distance: gps.distanceM, state: state, zone: zone, color: tone)
                heartCard(bpm: bpm, zone: zone, state: state, tone: tone)
                if usesRoute(w) == false { zoneTimeCard(w) }
                metricRow(w, elapsed: elapsed)
                footnote(w, state: state, now: now)
                if !ActivityAuthorizationInfo().areActivitiesEnabled { liveActivityOffCard }
                controls(w)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .onChange(of: Int(elapsed)) { _, _ in checkGoal(elapsed: elapsed, zone: zone, distance: gps.distanceM) }
    }

    // MARK: header + ring

    private func header(_ w: AppModel.ActiveWorkout, shownZone: Int, color: Color) -> some View {
        let gps = model.gpsRecorder
        let gpsText = usesRoute(w) ? (gps.pointCount == 0 ? String(localized: "Searching GPS") : String(localized: "GPS on")) : String(localized: "No GPS")
        let buzzText = zoneBuzz ? String(localized: "zone buzz on") : String(localized: "silent session")
        let title = String(localized: String.LocalizationValue(w.sport)) + (shownZone > 0 ? " · " + String(localized: "Zone \(shownZone)") : "")
        return HStack(alignment: .center) {
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("Minimise"))
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(verbatim: title).font(.nuna(size: 12, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(color).lineLimit(1)
                Text(verbatim: gpsText + " · " + buzzText).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(w.isPaused ? NunaPalette.warning : NunaPalette.alert).frame(width: 8, height: 8)
                Text(w.isPaused ? "Paused" : "Recording").font(.nuna(size: 12.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }
    }

    private func ring(elapsed: TimeInterval, distance: Double, state: ZoneState, zone: Int, color: Color) -> some View {
        var f = 1.0
        var caption = String(localized: "session time")
        switch goal.mode {
        case .time:
            f = elapsed / Double(max(goal.minutes, 1) * 60)
            caption = String(localized: "of target \(String(format: "%d:00", goal.minutes))")
        case .distance:
            f = distance / (max(goal.km, 0.1) * 1000)
            caption = String(localized: "of target \(String(format: "%.1f km", locale: AppLanguage.activeLocale, goal.km))")
        default: break
        }
        f = min(max(f, 0), 1)
        let chip: (String, Color)? = {
            switch state {
            case .inZone: return (String(localized: "In zone"), NunaPalette.charge)
            case .below: return (String(localized: "Below zone"), NunaPalette.warning)
            case .above, .farAbove: return (String(localized: "Above zone"), state == .farAbove ? NunaPalette.alert : NunaPalette.warning)
            case .none: return zone > 0 ? (String(localized: "Zone \(zone)"), color) : nil
            }
        }()
        return ZStack {
            Circle().fill(color.opacity(0.10)).padding(16)
            Circle().stroke(NunaPalette.glassStrong, lineWidth: 12)
            Circle().trim(from: 0, to: max(f, 0.004)).stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                if let chip { NunaChip(verbatim: chip.0, color: chip.1) } else { Color.clear.frame(height: 30) }
                Text(verbatim: clock(elapsed)).font(.nuna(size: 46, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(46)).monospacedDigit()
                    .foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.7).lineLimit(1)
                Text(verbatim: caption).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }.padding(.horizontal, 26)
        }
        .frame(width: 220, height: 220)
        .animation(.easeOut(duration: 0.4), value: f)
    }

    // MARK: heart rate

    private func heartCard(bpm: Int?, zone: Int, state: ZoneState, tone: Color) -> some View {
        let zones = zoneSet.zones
        let target = zone > 0 ? zone : (goal.mode == .zone ? goal.zone : 0)
        let range = zones.first(where: { $0.number == target })
        let lo = zones.first(where: { $0.number == 1 }).map { Int($0.lower.rounded()) }
        let hi = zones.first(where: { $0.number == 5 }).map { Int($0.upper.rounded()) }
        return NunaCard(padding: EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    nunaTrendsCap("Live heart rate")
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.15)) { hideBpm.toggle() } } label: {
                        Text(hideBpm ? "Show bpm" : "Hide bpm").font(.nuna(size: 11.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
                    }.buttonStyle(.plain)
                }
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "heart.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.alert)
                        Text(verbatim: hideBpm ? "•••" : (bpm.map(String.init) ?? "–")).font(.nuna(size: 44, weight: .bold, design: NunaType.design))
                            .tracking(nunaTrackingNumber(44)).monospacedDigit().foregroundStyle(hideBpm ? NunaPalette.textPrimary : tone)
                        Text("bpm").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    if zone > 0 { NunaChip(verbatim: String(localized: "Zone \(zone)"), color: Self.zoneColors[min(zone, 5) - 1]) }
                }
                zoneBar(bpm: bpm, zone: zone, tone: tone).padding(.top, 8)
                ZStack {
                    HStack {
                        Text(verbatim: lo.map(String.init) ?? "").font(.nuna(size: 12, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                        Spacer()
                        Text(verbatim: hi.map(String.init) ?? "").font(.nuna(size: 12, weight: .semibold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary).monospacedDigit()
                    }
                    if target > 0 {
                        Text(verbatim: String(localized: "Zone \(target)") + (range.map { " · \(Int($0.lower.rounded())) – \(Int($0.upper.rounded()))" } ?? ""))
                            .font(.nuna(size: 13, weight: .heavy, design: NunaType.design)).foregroundStyle(target == 1 ? NunaPalette.textPrimary : Self.zoneColors[min(target, 5) - 1]).monospacedDigit()
                    }
                }.padding(.top, 14)
                if goal.mode == .zone, let line = guidance(bpm: bpm, state: state) {
                    Text(verbatim: line).font(.nuna(size: 14, weight: .bold)).foregroundStyle(state == .inZone ? NunaPalette.textPrimary : tone)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil).padding(.top, 6)
                }
            }
        }
    }

    /// Five slim zone segments with a pointer under the reading: its place inside the segment follows where the heart rate sits in that zone.
    private func zoneBar(bpm: Int?, zone: Int, tone: Color) -> some View {
        let zones = zoneSet.zones
        var pos: CGFloat?   // 0...1 across the bar
        if let bpm {
            if zone >= 1, let z = zones.first(where: { $0.number == min(zone, 5) }), z.upper > z.lower {
                let frac = min(max((Double(bpm) - z.lower) / (z.upper - z.lower), 0), 1)
                pos = (CGFloat(zone - 1) + CGFloat(frac)) / 5
            } else { pos = 0 }
        }
        return GeometryReader { geo in
            let w = geo.size.width, gap: CGFloat = 3
            let seg = (w - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(1...5, id: \.self) { n in
                        RoundedRectangle(cornerRadius: n == 1 || n == 5 ? 6 : 3, style: .continuous)
                            .fill(Self.zoneColors[n - 1].opacity(n == zone ? 1 : 0.55)).frame(width: seg, height: 12)
                    }
                }
                if let pos {
                    let x = pos * w
                    Triangle().fill(NunaPalette.textPrimary).frame(width: 14, height: 9)
                        .offset(x: min(max(x - 7, 0), w - 14), y: 17)
                        .animation(.easeOut(duration: 0.25), value: pos)
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: metrics

    private func usesRoute(_ w: AppModel.ActiveWorkout) -> Bool {
        model.gpsRecorder.isRecording || (WorkoutCatalog.all.first(where: { $0.name == w.sport })?.isDistanceSport ?? false)
    }

    private func split(_ s: String) -> (String, String) {
        guard let i = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    private func kcal(_ w: AppModel.ActiveWorkout) -> Int? { NunaLiveMetrics.kcal(w, model: model) }
    private func zoneSeconds(_ w: AppModel.ActiveWorkout) -> [Int] { NunaLiveMetrics.zoneSeconds(w, zoneSet: zoneSet) }

    private typealias Tile = (label: LocalizedStringKey, value: String, unit: String)

    private func metricRow(_ w: AppModel.ActiveWorkout, elapsed: TimeInterval) -> some View {
        let gps = model.gpsRecorder
        let sys = distanceSystem
        let dash = "–"
        let dist = gps.pointCount > 0 ? split(UnitFormatter.distanceFromMeters(gps.distanceM, system: sys)) : (dash, sys == .imperial ? "mi" : "km")
        let pace = gps.paceSecPerKm != nil ? split(UnitFormatter.paceFromSecPerKm(gps.paceSecPerKm, system: sys)) : (dash, sys == .imperial ? "/mi" : "/km")
        let kmh = gps.paceSecPerKm.map { 3600 / $0 } ?? model.live.sensorSpeedKmh
        let speed = UnitFormatter.speedFromKilometersPerHour(kmh, system: sys).map(split) ?? (dash, sys == .imperial ? "mph" : "km/h")
        let gain = sys == .imperial ? gps.elevationGainM * 3.28084 : gps.elevationGainM
        let cal: Tile = ("Calories", kcal(w).map(String.init) ?? dash, kcal(w) == nil ? "" : String(localized: "kcal"))
        let tiles: [Tile]
        if usesRoute(w) {
            if w.sport == "Cycling" {
                tiles = [("Distance", dist.0, dist.1), ("Speed", speed.0, speed.1), ("Elevation", gps.pointCount > 0 ? "+\(Int(gain.rounded()))" : dash, sys == .imperial ? "ft" : "m"), cal]
            } else {
                let cad = model.live.sensorCadence.map { String(Int($0.rounded())) } ?? dash
                tiles = [("Distance", dist.0, dist.1), ("Pace", pace.0, pace.1), cal, ("Cadence", cad, cad == dash ? "" : String(localized: "spm"))]
            }
        } else {
            tiles = [cal, ("Avg HR", w.avgHr > 0 ? "\(w.avgHr)" : dash, w.avgHr > 0 ? "bpm" : ""), ("Peak", w.peakHr > 0 ? "\(w.peakHr)" : dash, w.peakHr > 0 ? "bpm" : ""),
                     ("Effort", UnitFormatter.effortDisplay(w.liveStrain, scale: scale), "")]
        }
        return HStack(spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 6) {
                    Text(t.label).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.6).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: t.value).font(.nuna(size: 20, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: t.unit.isEmpty ? " " : t.unit).font(.nuna(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                .padding(.vertical, 10).padding(.horizontal, 6).frame(maxWidth: .infinity)
                .background(NunaPalette.card, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous).strokeBorder(NunaPalette.hairlineSoft, lineWidth: 1))
            }
        }
    }

    private func zoneTimeCard(_ w: AppModel.ActiveWorkout) -> some View {
        let secs = zoneSeconds(w)
        let total = max(secs.reduce(0, +), 1)
        return NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 10) {
                nunaTrendsCap("Time in zone")
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text(verbatim: String(localized: "Zone \(i + 1)")).font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(NunaPalette.glassStrong)
                                Capsule().fill(Self.zoneColors[i]).frame(width: max(secs[i] > 0 ? 4 : 0, geo.size.width * CGFloat(secs[i]) / CGFloat(total)))
                            }
                        }.frame(height: 8)
                        Text(verbatim: clock(TimeInterval(secs[i]))).font(.nuna(size: 13, weight: .semibold, design: NunaType.design)).monospacedDigit()
                            .foregroundStyle(NunaPalette.textSecondary).frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: footnote + controls

    private func footnote(_ w: AppModel.ActiveWorkout, state: ZoneState, now: Date) -> some View {
        let effort = UnitFormatter.effortDisplay(w.liveStrain, scale: scale)
        let text: String
        if goal.mode == .zone, zoneBuzz {
            text = state == .inZone || state == .none ? String(localized: "Strap: no buzz. Silence means on target.")
                : String(localized: "1 short buzz on the strap, repeats every 45 s until you are back.")
        } else if lastBuzz != .distantPast {
            text = String(localized: "Last buzz \(clock(now.timeIntervalSince(lastBuzz))) ago · Session Effort \(effort)")
        } else {
            text = String(localized: "Session Effort \(effort)")
        }
        return HStack(spacing: 8) {
            Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.charge)
            Text(verbatim: text).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    /// Shown only while iOS has Live Activities switched off for this app: the session then has no banner on the Lock Screen or in the Island.
    private var liveActivityOffCard: some View {
        NunaCard(small: true) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(NunaPalette.warning)
                Text("Live Activities are off, so this session will not show on the Lock Screen or in the Dynamic Island.")
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Spacer(minLength: 4)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Settings").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 12).frame(height: 32)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private func controls(_ w: AppModel.ActiveWorkout) -> some View {
        HStack(spacing: 12) {
            Button { model.toggleWorkoutPause() } label: {
                HStack(spacing: 8) {
                    Image(systemName: w.isPaused ? "play.fill" : "pause.fill").font(.system(size: 14, weight: .bold))
                    Text(w.isPaused ? "Resume" : "Pause").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 60)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }.buttonStyle(.plain)
            Button { confirmEnd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold))
                    Text("End").font(.nuna(size: 16, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 28).frame(height: 60)
                .background(NunaPalette.alertText, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: zone guidance

    private func zoneState(bpm: Int?, zone: Int) -> ZoneState {
        guard goal.mode == .zone, bpm != nil, zone > 0 else { return .none }
        if zone == goal.zone { return .inZone }
        if zone < goal.zone { return .below }
        return zone >= goal.zone + 2 || zone == 5 ? .farAbove : .above
    }

    /// Only the zone colour, the bpm and one sentence change when the heart rate leaves the target; time, distance and pace stay white.
    private func tone(zone: Int, state: ZoneState) -> Color {
        switch state {
        case .above: return NunaPalette.warning
        case .farAbove: return NunaPalette.alert
        default:
            if zone > 0 { return Self.zoneColors[min(zone, 5) - 1] }
            return goal.mode == .zone ? Self.zoneColors[min(max(goal.zone, 1), 5) - 1] : NunaPalette.textMuted
        }
    }

    private func guidance(bpm: Int?, state: ZoneState) -> String? {
        guard let bpm, let z = zoneSet.zones.first(where: { $0.number == goal.zone }) else { return nil }
        let lo = Int(z.lower.rounded()), hi = Int(z.upper.rounded())
        switch state {
        case .none: return nil
        case .inZone: return String(localized: "Hold steady. You are in Zone \(goal.zone), \(lo) – \(hi) bpm.")
        case .below: return String(localized: "Pick up the pace a little. Target Zone \(goal.zone), \(lo) – \(hi) bpm.")
        case .above: return String(localized: "Ease off a little. Target Zone \(goal.zone), \(lo) – \(hi) bpm.")
        case .farAbove: return String(localized: "Slow down now. \(bpm) bpm is too high.")
        }
    }

    private func checkGoal(elapsed: TimeInterval, zone: Int, distance: Double) {
        guard zoneBuzz else { return }
        switch goal.mode {
        case .time where !goalHit && elapsed >= Double(goal.minutes * 60): goalHit = true; cue(loops: 3)
        case .distance where !goalHit && distance >= goal.km * 1000: goalHit = true; cue(loops: 3)
        case .zone where zone > 0 && zone != goal.zone && Date().timeIntervalSince(lastBuzz) > 45: lastBuzz = Date(); cue(loops: 1)
        default: break
        }
    }

    private func cue(loops: UInt8) {
        lastBuzz = Date()
        model.buzz(loops: loops)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func clock(_ s: TimeInterval) -> String {
        let t = Int(s); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}
#endif

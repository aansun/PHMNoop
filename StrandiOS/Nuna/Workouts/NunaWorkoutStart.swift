#if os(iOS)
import SwiftUI
import UIKit
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
                            Text(verbatim: planned.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
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
                    NunaCard(highlight: true) { NunaListRow("Log sets and weights", subtitle: "Open the Lift Log to run a program or a freehand session", systemImage: "dumbbell", showsChevron: true) }
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
            NunaCard { Text("No target. The session records heart rate, Effort and, for outdoor sports, your route.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
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
                                        .fill(Self.zoneColors[n - 1].opacity(n == z ? 1 : 0.45)).frame(height: 26)
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
        Button(action: a) { Image(systemName: s).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous)) }.buttonStyle(.plain)
    }

    private var optionsCard: some View {
        NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)) {
            VStack(spacing: 0) {
                NunaListRow("GPS and route", subtitle: isDistance ? "The route is recorded when location is allowed" : "Not used for this sport", systemImage: "location") {
                    NunaChip(isDistance ? "On" : "Off", color: isDistance ? NunaPalette.charge : nil)
                }
                NunaDivider()
                NunaListRow("Silent buzz on the strap", subtitle: "When you leave the target zone or reach the target", systemImage: "applewatch.radiowaves.left.and.right") {
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
                VStack(spacing: 16) {
                    Text("Session finished").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if let last = model.lastWorkout {
                        Text(verbatim: WorkoutSource.displaySport(last.sport) + " · " + NunaWorkoutFormat.duration(last.durationS)).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text("Sessions under a minute are not saved.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Button(action: onClose) { Text("Done").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 40).frame(height: 52).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)) }.buttonStyle(.plain)
                }
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

    private func content(_ w: AppModel.ActiveWorkout, now: Date) -> some View {
        let elapsed = w.elapsed(at: now)
        let bpm = model.bpm
        let zone = bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0
        let gps = model.gpsRecorder
        let colors: [Color] = [NunaPalette.zoneBase, NunaPalette.rest, NunaPalette.charge, NunaPalette.warning, NunaPalette.alert]
        return ScrollView {
            VStack(spacing: NunaSpacing.section) {
                HStack {
                    NunaChip(w.isPaused ? "Paused" : "Recording", color: w.isPaused ? NunaPalette.warning : NunaPalette.charge)
                    Spacer()
                    Text(verbatim: WorkoutSource.displaySport(w.sport)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                NunaCard {
                    VStack(spacing: 8) {
                        Text(verbatim: clock(elapsed)).font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "heart.fill").foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: bpm.map(String.init) ?? "–").font(.nuna(size: 48, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(48)).foregroundStyle(NunaPalette.textPrimary)
                            Text("bpm").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if zone > 0 {
                            HStack(spacing: 8) { Circle().fill(colors[min(zone, 5) - 1]).frame(width: 10, height: 10); Text(verbatim: "Zone \(zone)").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
                        }
                    }.frame(maxWidth: .infinity)
                }
                goalCard(elapsed: elapsed, zone: zone, bpm: bpm, distance: gps.distanceM)
                HStack(spacing: 12) {
                    NunaStatTile(label: "Effort", value: UnitFormatter.effortDisplay(w.liveStrain, scale: scale))
                    NunaStatTile(label: "Avg HR", value: w.avgHr > 0 ? "\(w.avgHr)" : "–", unit: w.avgHr > 0 ? "bpm" : "")
                    NunaStatTile(label: "Peak", value: w.peakHr > 0 ? "\(w.peakHr)" : "–", unit: w.peakHr > 0 ? "bpm" : "")
                }
                if gps.isRecording, gps.distanceM > 0 {
                    HStack(spacing: 12) {
                        NunaStatTile(label: "Distance", value: String(format: "%.2f", locale: AppLanguage.activeLocale, gps.distanceM / 1000), unit: "km")
                        NunaStatTile(label: "Pace", value: gps.paceSecPerKm.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "–", unit: "/km")
                    }
                }
                HStack(spacing: 12) {
                    Button { model.toggleWorkoutPause() } label: {
                        Text(w.isPaused ? "Resume" : "Pause").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                    Button { confirmEnd = true } label: {
                        Text("End").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.alertText, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button(action: onClose) { Text("Minimise").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .onChange(of: Int(elapsed)) { _, _ in checkGoal(elapsed: elapsed, zone: zone, distance: gps.distanceM) }
    }

    @ViewBuilder private func goalCard(elapsed: TimeInterval, zone: Int, bpm: Int?, distance: Double) -> some View {
        switch goal.mode {
        case .free: EmptyView()
        case .time:
            let f = elapsed / Double(goal.minutes * 60)
            progress(String(localized: "Target \(goal.minutes) min"), f, String(localized: "\(max(0, goal.minutes - Int(elapsed / 60))) min left"))
        case .distance:
            progress(String(localized: "Target \(String(format: "%.1f", locale: AppLanguage.activeLocale, goal.km)) km"), distance / (goal.km * 1000),
                     String(format: "%.2f km", locale: AppLanguage.activeLocale, distance / 1000))
        case .zone:
            NunaCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: String(localized: "Target zone \(goal.zone)")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        if let z = zoneSet.zones.first(where: { $0.number == goal.zone }) { Text(verbatim: "\(Int(z.lower.rounded()))–\(Int(z.upper.rounded())) bpm").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                    }
                    Spacer()
                    NunaChip(zone == goal.zone ? "In zone" : (zone < goal.zone ? "Below zone" : "Above zone"), color: zone == goal.zone ? NunaPalette.charge : NunaPalette.warning)
                }
            }
        }
    }

    private func progress(_ title: String, _ f: Double, _ detail: String) -> some View {
        NunaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(verbatim: title).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer(); Text(verbatim: detail).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
                NunaProgressBar(fraction: f, color: f >= 1 ? NunaPalette.charge : NunaPalette.effort)
            }
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

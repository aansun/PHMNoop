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
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage("nuna.workout.zoneBuzz") private var zoneBuzz = true
    @State private var chosen: String = "Running"
    @State private var goal = NunaWorkoutGoal()
    @State private var showPicker = false
    @State private var countdown: Int?
    @State private var live = false
    @State private var query = ""

    private var isDistance: Bool { WorkoutCatalog.sport(named: chosen)?.isDistanceSport ?? false }
    private var zoneSet: HRZoneSet { profile.hrZoneSet }

    var body: some View {
        NunaDetailScreen(LocalizedStringKey(chosen)) {
            readiness
            NunaSegmented([(value: NunaWorkoutGoal.Mode.free, title: "Free"), (value: .time, title: "Time"), (value: .distance, title: "Distance"), (value: .zone, title: "Zone")], selection: $goal.mode)
            goalCard
            optionsCard
            Button { showPicker = true } label: {
                NunaCard(small: true) { NunaListRow("Sport", subtitle: LocalizedStringKey(chosen), systemImage: "figure.run", showsChevron: true) }
            }.buttonStyle(.plain)
            if chosen == "Strength" || chosen == "Weightlifting" || chosen == "Powerlifting" || chosen == "Bodybuilding" {
                NavigationLink(value: NunaWorkoutRoute.gym) {
                    NunaCard(highlight: true) { NunaListRow("Log sets and weights", subtitle: "Open the Lift Log to run a program or a freehand session", systemImage: "dumbbell", showsChevron: true) }
                }.buttonStyle(.plain)
            }
            Button { begin() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                    Text(model.activeWorkout == nil ? "Start in 3 seconds" : "View active workout").font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: Capsule())
            }.buttonStyle(.plain)
        }
        .onAppear { if let sport { chosen = sport } else if let a = model.activeWorkout { chosen = a.sport } }
        .sheet(isPresented: $showPicker) { sportPicker }
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
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 12).background(NunaPalette.tint(NunaPalette.charge), in: Capsule())
            }
        }
    }

    @ViewBuilder private var goalCard: some View {
        switch goal.mode {
        case .free:
            NunaCard { Text("No target. The session records heart rate, Effort and, for outdoor sports, your route.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
        case .time:
            stepperCard("Target duration", "\(goal.minutes)", "min", minus: { goal.minutes = max(5, goal.minutes - 5) }, plus: { goal.minutes = min(300, goal.minutes + 5) })
        case .distance:
            stepperCard("Target distance", String(format: "%.1f", locale: AppLanguage.activeLocale, goal.km), unitSystemRaw == UnitSystem.imperial.rawValue ? "km" : "km",
                        minus: { goal.km = max(0.5, goal.km - 0.5) }, plus: { goal.km = min(100, goal.km + 0.5) })
        case .zone:
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    nunaTrendsCap("Target zone")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "Zone \(goal.zone)").font(.system(size: 30, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        if let z = zoneSet.zones.first(where: { $0.number == goal.zone }) {
                            Text(verbatim: "\(Int(z.lower.rounded()))–\(Int(z.upper.rounded())) bpm").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { z in
                            Button { goal.zone = z } label: {
                                Text(verbatim: "\(z)").font(.system(size: 16, weight: .bold)).foregroundStyle(goal.zone == z ? NunaPalette.onAccent : NunaPalette.textPrimary)
                                    .frame(maxWidth: .infinity).frame(height: 44).background(goal.zone == z ? NunaPalette.accent : NunaPalette.glassStrong, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
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
                        Text(verbatim: v).font(.system(size: 46, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                        Text(verbatim: unit).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    stepBtn("plus", plus)
                }
            }
        }
    }

    private func stepBtn(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 52, height: 52).background(NunaPalette.glassStrong, in: Circle()) }.buttonStyle(.plain)
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
        NavigationStack {
            List {
                ForEach(WorkoutCatalog.matching(query)) { s in
                    Button { chosen = s.name; showPicker = false } label: {
                        HStack { Text(verbatim: s.name); Spacer(); if s.name == chosen { Image(systemName: "checkmark") } }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Sport").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showPicker = false } } }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func countdownView(_ c: Int) -> some View {
        ZStack {
            NunaPalette.shade.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(verbatim: "\(c)").font(.system(size: 120, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Button("Cancel") { countdown = nil }.font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
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
                    Text("Session finished").font(.system(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    if let last = model.lastWorkout {
                        Text(verbatim: WorkoutSource.displaySport(last.sport) + " · " + NunaWorkoutFormat.duration(last.durationS)).font(.system(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    } else {
                        Text("Sessions under a minute are not saved.").font(.system(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Button(action: onClose) { Text("Done").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 40).frame(height: 52).background(NunaPalette.accent, in: Capsule()) }.buttonStyle(.plain)
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
                    Text(verbatim: WorkoutSource.displaySport(w.sport)).font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                }
                NunaCard {
                    VStack(spacing: 8) {
                        Text(verbatim: clock(elapsed)).font(.system(size: 64, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "heart.fill").foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: bpm.map(String.init) ?? "–").font(.system(size: 48, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("bpm").font(.system(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        if zone > 0 {
                            HStack(spacing: 8) { Circle().fill(colors[min(zone, 5) - 1]).frame(width: 10, height: 10); Text(verbatim: "Zone \(zone)").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
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
                        Text(w.isPaused ? "Resume" : "Pause").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.glassStrong, in: Capsule())
                    }.buttonStyle(.plain)
                    Button { confirmEnd = true } label: {
                        Text("End").font(.system(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.alertText, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Button(action: onClose) { Text("Minimise").font(.system(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }.buttonStyle(.plain)
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
                        Text(verbatim: String(localized: "Target zone \(goal.zone)")).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        if let z = zoneSet.zones.first(where: { $0.number == goal.zone }) { Text(verbatim: "\(Int(z.lower.rounded()))–\(Int(z.upper.rounded())) bpm").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
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
                HStack { Text(verbatim: title).font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer(); Text(verbatim: detail).font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
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
#endif

#if os(iOS)
import SwiftUI
import UIKit
import ActivityKit
import MapKit
import CoreLocation
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// What the wearer asked for before starting. The live screen shows progress against it and nudges once when it is met.
struct NunaWorkoutGoal: Equatable {
    /// Time, distance and a heart-rate zone are three targets, each on or off by itself: any one, any two, or all three.
    var timeOn = false
    var minutes = 30
    var distanceOn = false
    var km = 5.0
    var zoneOn = false
    var zone = 2

    var isFree: Bool { !timeOn && !distanceOn && !zoneOn }

    /// Anya's session as a target: its length and the zone most of it is spent in. A session under 30 minutes is shown as 30, the shortest
    /// the setup offers.
    static func suggested(by plan: DayPlan.Plan) -> NunaWorkoutGoal {
        var g = NunaWorkoutGoal()
        g.timeOn = true
        g.minutes = min(300, max(30, Int((Double(plan.totalMinutes) / 5).rounded()) * 5))
        g.zoneOn = true
        g.zone = min(max(plan.mainZone, 1), 5)
        return g
    }

    /// Where a target starts when switched on with nothing chosen: Zone 2 alone.
    static var zoneOnly: NunaWorkoutGoal { var g = NunaWorkoutGoal(); g.zoneOn = true; return g }

    /// A planning estimate on the 0-100 Effort axis, used by the setup screen and the live target marker. The zone sets how hard; the
    /// time, or the distance at an assumed 6 min/km when there is no time, sets how long (with both, the time). With neither, a typical
    /// 45 minutes is assumed.
    var estimatedEffort: Double {
        let scale = UnitFormatter.effortScaleFactor
        let mins: Double = timeOn ? Double(minutes) : (distanceOn ? km * 6 : 45)
        if zoneOn {
            // The zone's effort at an hour, stretched or shrunk with the length of the session.
            let atHour = 3.6 + Double(zone) * 2.55
            let length = 0.35 + 0.65 * log(1 + mins / 30) / log(3)
            return min(20, atHour * length) / scale
        }
        if !timeOn && !distanceOn { return 3.6 / scale }
        return min(20, 2.8 + mins / 17) / scale
    }
}

// MARK: - Start (WorkoutStart)

struct NunaWorkoutStartView: View {
    let sport: String?
    /// Opened to carry on a session that is already running: straight to its live screen instead of the start screen.
    var resume = false
    @State private var didResume = false
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liveState: LiveState
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var planned: NavRouter.PlannedSession?
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @AppStorage("nuna.workout.zoneBuzz") private var zoneBuzz = true
    @State private var chosen: String = "Running"
    @State private var goal = NunaWorkoutGoal()
    @State private var lastGoal = NunaWorkoutGoal.zoneOnly
    /// Anya's session for today (from Charge, yesterday's load and the wearer's own sessions); the target starts as this.
    @State private var dayPlan: NunaDayPlanResult?
    @State private var didApplyAnya = false
    @State private var showPicker = false
    @State private var showStartSettings = false
    @State private var showTargetSetup = false
    @State private var startAfterTargetSetup = false
    @State private var countdown: Int?
    @State private var live = false
    @State private var mapPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @StateObject private var locationPreview = NunaWorkoutLocationPreview()

    private var isDistance: Bool { WorkoutCatalog.sport(named: chosen)?.isDistanceSport ?? false }
    private var isStrength: Bool { ["Strength", "Weightlifting", "Powerlifting", "Bodybuilding"].contains(chosen) }
    /// The Sleep tab's own need and debt, so the target sheet judges the session against the same sleep the rest of the app shows.
    private var sleepDebtMin: Double? {
        let need = SleepModel.debtNeedMin(days: repo.days)
        let ledger = SleepDebt.ledger(series: repo.days.map { (day: $0.day, totalSleepMin: $0.totalSleepMin) }, needHours: need / 60)
        return ledger.nightCount > 0 ? ledger.magnitudeMin : nil
    }
    private var hasSupportingDetails: Bool { repo.today?.recovery != nil || planned != nil || isStrength }
    private var zoneSet: HRZoneSet { profile.hrZoneSet }
    private var distanceSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw)
    }

    var body: some View {
        GeometryReader { geometry in
            hero(height: geometry.size.height)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if hasSupportingDetails {
                    VStack(spacing: NunaSpacing.section) {
                        readiness
                        anyaPlan
                        strengthShortcut
                    }
                    .padding(.horizontal, NunaSpacing.screenH)
                    .padding(.vertical, NunaSpacing.cardInnerSmall)
                    .background(NunaPalette.card)
                }
                actionDock
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if resume, !didResume, model.activeWorkout != nil { didResume = true; live = true }
            // A session suggested by the day plan: hold its main zone, and keep its length for the Time goal.
            if let p = router.plannedSession {
                router.plannedSession = nil
                planned = p
                goal.zoneOn = true; goal.zone = min(max(p.zone, 1), 5)
                goal.timeOn = true; goal.minutes = max(30, min(Int((Double(p.minutes) / 5).rounded()) * 5, 300))
                lastGoal = goal
            }
            if let s = planned?.sport, let match = WorkoutCatalog.sport(named: s) { chosen = match.name }
            if let sport { chosen = sport } else if let a = model.activeWorkout { chosen = a.sport }
            updateLocationPreview()
        }
        .task {
            dayPlan = await NunaDayPlanResult.load(repo: repo, profile: profile)
            applyAnyaDefaults()
        }
        .onDisappear { locationPreview.stop() }
        .onChange(of: chosen) { _, _ in
            if !isDistance, goal.distanceOn { goal.distanceOn = false }
            updateLocationPreview()
        }
        .onChange(of: locationPreview.status) { _, status in
            guard status == .ready, let coordinate = locationPreview.coordinate else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200))
            }
        }
        .sheet(isPresented: $showPicker) { sportPicker.nunaSheetChrome(detents: [.large]) }
        .sheet(isPresented: $showStartSettings) {
            NunaWorkoutStartSettings(zoneBuzz: $zoneBuzz)
                .nunaSheetChrome(detents: [.height(240)])
        }
        .sheet(isPresented: $showTargetSetup, onDismiss: {
            guard startAfterTargetSetup else { return }
            startAfterTargetSetup = false
            begin()
        }) {
            NunaWorkoutTargetSheet(
                goal: $goal,
                lastGoal: $lastGoal,
                startRequested: $startAfterTargetSetup,
                sport: chosen,
                isDistanceActivity: isDistance,
                distanceSystem: distanceSystem,
                zones: zoneSet.zones,
                charge: repo.today?.recovery,
                dayEffort: repo.today?.strain,
                sleepDebtMin: sleepDebtMin,
                suggestion: dayPlan,
                hasActiveWorkout: model.activeWorkout != nil)
                .nunaSheetChrome(detents: [.large])
        }
        .fullScreenCover(isPresented: $live) { NunaLiveWorkoutView(goal: goal, zoneBuzz: zoneBuzz, onClose: { live = false }) }
        .overlay { if let c = countdown { countdownView(c) } }
    }

    // MARK: Hero

    private func hero(height: CGFloat) -> some View {
        ZStack {
            if isDistance {
                Map(position: $mapPosition, interactionModes: []) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                .accessibilityLabel(Text("Current location map"))
            } else {
                NunaPalette.card
                Image(systemName: NunaSportPicker.symbol(for: chosen))
                    .font(.system(size: 136, weight: .thin))
                    .foregroundStyle(NunaPalette.textMuted.opacity(0.22))
            }

            NunaPalette.shade.opacity(isDistance ? 0.38 : 0.12)

            VStack(spacing: 0) {
                heroHeader
                Spacer(minLength: 16)
                heroHeartRate
                Spacer(minLength: 16)
                locationStatus
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(height: height)
        .clipped()
    }

    /// Before the session starts: the heart rate as a beating disc in the colour of the current zone, with the strap's battery in it.
    private var heroHeartRate: some View {
        let bpm = model.bpm
        let zone = bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0
        let range = zoneSet.zones.first(where: { $0.number == zone })
        let caption = range.map { String(localized: "Zone \(zone) · \(Int($0.lower.rounded()))–\(Int($0.upper.rounded())) bpm") }
        return NunaHeartBeat(bpm: bpm, color: NunaHeartBeat.zoneColor(zone), zone: zone, battery: liveState.batteryPct,
                             caption: caption, captionColor: NunaPalette.mapOverlayText)
    }

    private var heroHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.nuna(size: 18, weight: .bold))
                    .foregroundStyle(NunaPalette.mapOverlayText)
                    .frame(width: 44, height: 44)
                    .background(NunaPalette.mapOverlay.opacity(0.65), in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))

            Button { showPicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: NunaSportPicker.symbol(for: chosen))
                        .font(.nuna(size: 18, weight: .bold))
                    Text(LocalizedStringKey(chosen))
                        .font(.nuna(size: 15, weight: .heavy))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.nuna(size: 11, weight: .bold))
                }
                .foregroundStyle(NunaPalette.mapOverlayText)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(NunaPalette.mapOverlay.opacity(0.65), in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Select activity"))

            Spacer(minLength: 0)

            Button { showStartSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.nuna(size: 17, weight: .bold))
                    .foregroundStyle(NunaPalette.mapOverlayText)
                    .frame(width: 44, height: 44)
                    .background(NunaPalette.mapOverlay.opacity(0.65), in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Activity settings"))
        }
    }

    private var locationStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: isDistance ? "location.fill" : "location.slash")
                .font(.nuna(size: 12, weight: .bold))
            Text(locationStatusText)
                .font(.nuna(size: 12.5, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(NunaPalette.mapOverlayText)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(NunaPalette.mapOverlay.opacity(0.72), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var locationStatusText: LocalizedStringKey {
        guard isDistance else { return "No GPS for this activity" }
        switch locationPreview.status {
        case .ready: return "GPS on · Current location"
        case .requesting: return "Finding current location"
        case .denied: return "Location is off"
        }
    }

    // MARK: Plan + target

    @ViewBuilder private var anyaPlan: some View {
        if let planned {
            NunaAnyaNote {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("From Anya's plan")
                            .font(.nuna(size: 11.5, weight: .heavy))
                            .tracking(nunaTrackingLabel)
                            .textCase(.uppercase)
                            .foregroundStyle(NunaPalette.textSecondary)
                        Text(verbatim: planned.title)
                            .font(.nuna(size: 15.5, weight: .bold))
                            .foregroundStyle(NunaPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textCase(nil)
                    }
                    Spacer(minLength: 6)
                    Button { clearPlan() } label: {
                        Text("Clear")
                            .font(.nuna(size: 13, weight: .bold))
                            .foregroundStyle(NunaPalette.textPrimary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var targetSummary: String {
        var parts: [String] = []
        if goal.timeOn { parts.append(String(localized: "\(goal.minutes) min")) }
        if goal.distanceOn {
            let value = distanceSystem == .imperial ? goal.km * UnitFormatter.milesPerKilometer : goal.km
            parts.append(String(format: "%.1f %@", locale: AppLanguage.activeLocale, value, UnitFormatter.distanceUnit(distanceSystem)))
        }
        if goal.zoneOn { parts.append(String(localized: "Zone \(goal.zone)")) }
        return parts.isEmpty ? String(localized: "Off") : parts.joined(separator: " · ")
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

    @ViewBuilder private var strengthShortcut: some View {
        if isStrength {
            NavigationLink(value: NunaWorkoutRoute.gym) {
                NunaCard(highlight: true) {
                    NunaListRow("Log sets and weights", description: "Open Gym to run a program or a freehand session", systemImage: "dumbbell", showsChevron: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var actionDock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.nuna(size: 16, weight: .bold))
                    .foregroundStyle(goal.isFree ? NunaPalette.textSecondary : NunaPalette.effortModerate)
                    .frame(width: 36, height: 36)
                    .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                Button {
                    showTargetSetup = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Effort target")
                            .font(.nuna(size: NunaTypeSize.h3, weight: .heavy))
                            .foregroundStyle(NunaPalette.textPrimary)
                        HStack(spacing: 4) {
                            Text(verbatim: goal.isFree ? String(localized: "Free session") : targetSummary)
                            Image(systemName: "chevron.right")
                        }
                        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: NoopButtonMetrics.minHitTarget, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Configure Effort target"))
                Toggle("", isOn: targetEnabledBinding)
                    .labelsHidden()
                    .tint(NunaPalette.effortModerate)
            }

            Button { begin() } label: {
                HStack(spacing: 8) {
                    Image(systemName: model.activeWorkout == nil ? "play.fill" : "arrow.up.right")
                        .font(.nuna(size: 14, weight: .bold))
                    Text(model.activeWorkout == nil ? "Start activity" : "View active workout")
                        .font(.nuna(size: 17, weight: .heavy))
                }
                .foregroundStyle(NunaPalette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(NunaPalette.card)
        .overlay(alignment: .top) { NunaDivider() }
    }

    private var targetEnabledBinding: Binding<Bool> {
        Binding(get: { !goal.isFree }, set: { enabled in
            withAnimation(.easeInOut(duration: 0.28)) {
                if enabled {
                    goal = lastGoal.isFree ? .zoneOnly : lastGoal
                    if !isDistance, goal.distanceOn { goal.distanceOn = false }
                    showTargetSetup = true
                } else {
                    if !goal.isFree { lastGoal = goal }
                    goal = NunaWorkoutGoal()
                }
            }
            UISelectionFeedbackGenerator().selectionChanged()
        })
    }

    private var sportPicker: some View {
        NunaSportPicker(selection: $chosen) { showPicker = false }
    }

    /// The target starts as Anya's session, once, unless a plan was already sent here or the sport has no target to set.
    private func applyAnyaDefaults() {
        guard !didApplyAnya, let plan = dayPlan?.plan else { return }
        didApplyAnya = true
        guard planned == nil, goal.isFree, !isStrength else { return }
        goal = .suggested(by: plan)
        lastGoal = goal
    }

    private func clearPlan() {
        withAnimation(.easeInOut(duration: 0.2)) {
            planned = nil
            goal = NunaWorkoutGoal()
            lastGoal = .zoneOnly
        }
    }

    private func updateLocationPreview() {
        if isDistance { locationPreview.start() } else { locationPreview.stop() }
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
            RecentSportsPrefs.recordSelection(chosen)
            model.startWorkout(sport: chosen)
            model.workoutTarget = goal.isFree ? nil : .init(
                seconds: goal.timeOn ? goal.minutes * 60 : nil,
                meters: goal.distanceOn ? goal.km * 1000 : nil,
                zone: goal.zoneOn ? goal.zone : nil)
            live = true
        }
    }
}

/// A lightweight location read used only to place the pre-workout map. Route recording remains owned by
/// `GpsWorkoutRecorder` and starts only after the user starts a distance workout.
@MainActor
private final class NunaWorkoutLocationPreview: NSObject, ObservableObject {
    enum Status: Equatable { case requesting, ready, denied }

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var status: Status = .requesting

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { status = .denied; return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .requesting
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = .requesting
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    func stop() { manager.stopUpdatingLocation() }
}

extension NunaWorkoutLocationPreview: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            status = .requesting
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = .denied
            manager.stopUpdatingLocation()
        case .notDetermined:
            status = .requesting
        @unknown default:
            status = .denied
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        coordinate = latest.coordinate
        status = .ready
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .denied { status = .denied }
    }
}

// MARK: - Start settings + Effort target

private struct NunaWorkoutStartSettings: View {
    @Binding var zoneBuzz: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AudioCoachingPreferences.enabledKey) private var audioCoachOn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: NunaSpacing.section) {
                NunaCard(small: true) {
                    HStack(spacing: 14) {
                        NunaIconTile("applewatch.radiowaves.left.and.right", tint: NunaPalette.charge)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Silent buzz")
                                .font(.nuna(size: 16, weight: .heavy))
                                .foregroundStyle(NunaPalette.textPrimary)
                            Text("Buzz when you leave the selected heart-rate range or complete a target.")
                                .font(.nuna(size: 13, weight: .semibold))
                                .foregroundStyle(NunaPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: $zoneBuzz)
                            .labelsHidden()
                            .tint(NunaPalette.charge)
                    }
                }
                // The spoken cues have their own screen; this is the way to it from here.
                NavigationLink {
                    NunaAnyaVoiceCoachView()
                } label: {
                    NunaCard(small: true) {
                        NunaListRow("Audio coach", subtitle: LocalizedStringKey(audioCoachOn ? String(localized: "On") : String(localized: "Off")),
                                    systemImage: "speaker.wave.2", showsChevron: true)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, NunaSpacing.section)
            .background(NunaPalette.canvas.ignoresSafeArea())
            .navigationTitle("Activity settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.nuna(size: 15, weight: .bold))
                        .foregroundStyle(NunaPalette.accent)
                }
            }
        }
    }
}

private struct NunaWorkoutTargetSheet: View {
    @Binding var goal: NunaWorkoutGoal
    @Binding var lastGoal: NunaWorkoutGoal
    @Binding var startRequested: Bool
    let sport: String
    let isDistanceActivity: Bool
    let distanceSystem: UnitSystem
    let zones: [HRZone]
    let charge: Double?
    let dayEffort: Double?
    /// Recency-weighted sleep debt in minutes (nil without enough nights): the sleep half of how much the day can take.
    let sleepDebtMin: Double?
    /// Anya's session for today, shown under the zones and applied with one tap.
    let suggestion: NunaDayPlanResult?
    let hasActiveWorkout: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card whose controls are open; the others show their value on one line.
    @State private var open: Kind?
    private enum Kind: Hashable { case time, distance, zone }

    private static let maximumDistanceKm = 60.0
    private static let minimumMinutes = 30
    private static let timePresets = [30, 45, 60, 90, 120, 180]
    /// In kilometres: 3, 5, 10, 15, the half marathon and the marathon.
    private static let distancePresets = [3.0, 5.0, 10.0, 15.0, 21.0975, 42.195]
    private static let minimumDistanceKm = 1.0

    private var estimatedEffort: Double { goal.estimatedEffort }
    private func effortNumber(_ value: Double) -> String { String(format: "%.1f", locale: AppLanguage.activeLocale, value) }
    private var unit: String { UnitFormatter.distanceUnit(distanceSystem) }
    private var perKm: Double { distanceSystem == .imperial ? UnitFormatter.milesPerKilometer : 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            NunaDivider()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        effortCard
                            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 12)
                        panel
                    }
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            startDock
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .onAppear {
            if !isDistanceActivity, goal.distanceOn { goal.distanceOn = false }
            open = goal.timeOn ? .time : (goal.distanceOn ? .distance : (goal.zoneOn ? .zone : nil))
        }
    }

    // MARK: Panel (three targets, each on or off by itself)

    /// The lower panel, in the manner of a choice sheet: a title, then one square card per target.
    private var panel: some View {
        VStack(spacing: 10) {
            Text("Choose your target")
                .font(.nuna(size: NunaTypeSize.h3, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(maxWidth: .infinity).padding(.bottom, 2)
            targetCard(.time)
            if isDistanceActivity { targetCard(.distance) }
            targetCard(.zone)
            anyaCard.padding(.top, 4)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NunaPalette.card, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
    }

    private func isOn(_ k: Kind) -> Bool {
        switch k { case .time: return goal.timeOn; case .distance: return goal.distanceOn; case .zone: return goal.zoneOn }
    }

    private func setOn(_ k: Kind, _ on: Bool) {
        withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
            switch k {
            case .time: goal.timeOn = on; if on { goal.minutes = max(goal.minutes, Self.minimumMinutes) }
            case .distance: goal.distanceOn = on; if on { setShown(max(goal.km * perKm, Self.minimumDistanceKm * perKm)) }
            case .zone: goal.zoneOn = on
            }
            if on { open = k } else if open == k { open = nil }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func tap(_ k: Kind) {
        if !isOn(k) { setOn(k, true); return }
        withAnimation(reduceMotion ? nil : StrandMotion.gentle) { open = open == k ? nil : k }
    }

    private func title(_ k: Kind) -> LocalizedStringKey {
        switch k { case .time: return "Time"; case .distance: return "Distance"; case .zone: return "Heart rate zone" }
    }

    /// Off: what the target does, in a line. On: the value it is set to.
    private func subtitle(_ k: Kind) -> String {
        switch k {
        case .time:
            return goal.timeOn ? String(localized: "\(goal.minutes) min") : String(localized: "Reach a set duration.")
        case .distance:
            guard goal.distanceOn else { return String(localized: "Reach a set distance.") }
            let v = String(format: "%.1f %@", locale: AppLanguage.activeLocale, goal.km * perKm, unit)
            if abs(goal.km - 42.195) < 0.05 { return v + " · " + String(localized: "Marathon") }
            if abs(goal.km - 21.0975) < 0.05 { return v + " · " + String(localized: "Half marathon") }
            return v
        case .zone:
            guard goal.zoneOn else { return String(localized: "Stay in a heart-rate zone.") }
            let band = zones.first(where: { $0.number == goal.zone })
            return band.map { String(localized: "Zone \(goal.zone)") + " · \(Int($0.lower.rounded()))–\(Int($0.upper.rounded())) bpm" } ?? String(localized: "Zone \(goal.zone)")
        }
    }

    private func targetCard(_ k: Kind) -> some View {
        let on = isOn(k)
        let expanded = on && open == k
        return VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Text(title(k)).font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    Text(verbatim: subtitle(k)).font(.nuna(size: 13, weight: .semibold)).textCase(nil)
                        .foregroundStyle(on ? NunaPalette.effortText : NunaPalette.textMuted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 48)
                Toggle("", isOn: Binding(get: { isOn(k) }, set: { setOn(k, $0) }))
                    .labelsHidden().tint(NunaPalette.effortModerate).scaleEffect(0.8, anchor: .topTrailing)
            }
            if expanded { controls(k) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous)
            .stroke(on ? NunaPalette.effortModerate : NunaPalette.hairline, lineWidth: on ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
        .onTapGesture { tap(k) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func controls(_ k: Kind) -> some View {
        switch k {
        case .time: timeControls
        case .distance: distanceControls
        case .zone: HStack(spacing: 8) { ForEach(1...5, id: \.self) { z in zoneTile(z) } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                    .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close target settings"))
            Image(systemName: NunaSportPicker.symbol(for: sport)).font(.nuna(size: NunaTypeSize.h2, weight: .semibold))
            Text(LocalizedStringKey(sport)).font(.nuna(size: NunaTypeSize.h3, weight: .bold)).lineLimit(1)
            Spacer(minLength: 8)
            if !goal.isFree {
                Button("Clear") { clear() }
                    .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    .foregroundStyle(NunaPalette.textSecondary)
                    .frame(minHeight: NoopButtonMetrics.minHitTarget)
                    .buttonStyle(.plain)
            }
            Button("Done") { dismiss() }
                .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                .frame(minHeight: NoopButtonMetrics.minHitTarget)
                .buttonStyle(.plain)
        }
        .foregroundStyle(NunaPalette.textPrimary)
        .padding(.horizontal, NunaSpacing.screenH)
        .padding(.top, 8)
    }

    // MARK: Effort

    /// Effort now, what the target adds and where the day would end, against the range that suits today.
    private var effortCard: some View {
        let day = dayEffort ?? 0
        let sex = UserDefaults.standard.string(forKey: "profile.sex") ?? ""
        let denominator = StrainScorer.logMapDenominator(method: PuffinExperiment.effortMethod, sex: sex)
        let free = goal.isFree
        let after = free ? day : StrainScorer.effortAfter(day: day, adding: estimatedEffort, denominator: denominator)
        let band = CoupledView.optimalStrainRange(recovery: charge).map {
            (Double($0.lowerBound) / UnitFormatter.effortScaleFactor)...(Double($0.upperBound) / UnitFormatter.effortScaleFactor)
        }
        let verdict: (text: String, color: Color)? = free ? nil : band.map { b in
            after < b.lowerBound ? (String(localized: "Room for more"), NunaPalette.textSecondary)
                : (after <= b.upperBound ? (String(localized: "Right for today"), NunaPalette.charge)
                   : (String(localized: "More than today needs"), NunaPalette.warning))
        }
        let debt = (sleepDebtMin ?? 0) >= 60 ? sleepDebtMin : nil
        return NunaCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    stat("Effort", dayEffort.map(effortNumber) ?? "–")
                    stat("Target", free ? "–" : effortNumber(estimatedEffort), color: NunaPalette.effortModerate)
                    stat("After (est.)", free ? "–" : effortNumber(after))
                }
                effortBar(current: day, after: after, band: band, free: free)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(NunaPalette.charge.opacity(band == nil ? 0.3 : 1), lineWidth: 2).frame(width: 16, height: 10)
                    Text("Optimal today").font(.nuna(size: NunaTypeSize.sub, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    Spacer(minLength: 6)
                    Text(verbatim: band.map { "\(effortNumber($0.lowerBound))–\(effortNumber($0.upperBound))" } ?? "–")
                        .font(.nuna(size: NunaTypeSize.h3, weight: .bold, design: NunaType.design)).monospacedDigit()
                        .foregroundStyle(NunaPalette.textPrimary)
                }
                if let verdict {
                    HStack(spacing: 8) {
                        Text(verbatim: verdict.text).font(.nuna(size: NunaTypeSize.sub, weight: .bold)).foregroundStyle(verdict.color)
                        if let debt, let band, after >= band.lowerBound {
                            Text(verbatim: String(localized: "Sleep debt \(Self.hoursText(debt))"))
                                .font(.nuna(size: NunaTypeSize.caption, weight: .semibold)).foregroundStyle(NunaPalette.warning)
                        }
                    }
                } else if band == nil {
                    Text(free ? "Pick a target below" : "No Charge for today yet")
                        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .animation(reduceMotion ? nil : StrandMotion.gentle, value: estimatedEffort)
    }

    /// 0–100: what the day already holds, what the session adds on top of it, and the range Charge supports behind both.
    private func effortBar(current: Double, after: Double, band: ClosedRange<Double>?, free: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = w / 100
            let bandStart = (band?.lowerBound ?? 0).clamped(0, 100) * unit
            let bandWidth = band.map { max(($0.upperBound.clamped(0, 100) - $0.lowerBound.clamped(0, 100)) * unit, 6) } ?? 0
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(NunaPalette.field)
                    Rectangle().fill(NunaPalette.effortModerate).frame(width: free ? 0 : max(after.clamped(0, 100) * unit, 6))
                    Rectangle().fill(NunaPalette.effortMinimal).frame(width: current > 0 ? max(current.clamped(0, 100) * unit, 6) : 0)
                }
                .frame(height: 10).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                // The range that suits today is a green bracket around the bar, so it shows over the fill.
                if band != nil {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(NunaPalette.charge, lineWidth: 2).frame(width: bandWidth, height: 18).offset(x: bandStart)
                }
            }
            .frame(height: 18)
        }
        .frame(height: 18)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, color: Color = NunaPalette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textMuted).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: value).font(.nuna(size: 28, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(28))
                .foregroundStyle(color).monospacedDigit().contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func hoursText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    // MARK: Time and distance controls

    private var timeControls: some View {
        valuePanel(value: "\(goal.minutes)", unit: String(localized: "min"),
                   up: { goal.minutes = min(300, max(Self.minimumMinutes, goal.minutes + 5)) },
                   down: { goal.minutes = max(Self.minimumMinutes, goal.minutes - 5) },
                   canUp: goal.minutes < 300, canDown: goal.minutes > Self.minimumMinutes,
                   templates: Self.timePresets.map { m in (m.formatted(), goal.minutes == m, { goal.minutes = m }) })
    }

    private var distanceControls: some View {
        let shown = goal.km * perKm
        let step = shown < 10 ? 0.5 : 1.0
        return valuePanel(value: String(format: "%.1f", locale: AppLanguage.activeLocale, shown), unit: unit,
                          up: { setShown(shown + step) }, down: { setShown(shown - step) },
                          canUp: shown < Self.maximumDistanceKm * perKm - 0.001,
                          canDown: shown > Self.minimumDistanceKm * perKm + 0.001,
                          templates: Self.distancePresets.map { km in
                              (Self.presetLabel(km * perKm), abs(goal.km - km) < 0.01, { goal.km = km })
                          })
    }

    private static func presetLabel(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The value on the left with a triangle above to raise it and one below to lower it; on the right, six templates in two rows of three.
    private func valuePanel(value: String, unit: String, up: @escaping () -> Void, down: @escaping () -> Void,
                            canUp: Bool, canDown: Bool, templates: [(String, Bool, () -> Void)]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 2) {
                triangle("arrowtriangle.up.fill", enabled: canUp, action: up).accessibilityLabel(Text("Increase"))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: value)
                        .font(.nuna(size: 38, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(38))
                        .foregroundStyle(NunaPalette.textPrimary).monospacedDigit().contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: unit).font(.nuna(size: NunaTypeSize.sub, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                .frame(height: 40)
                triangle("arrowtriangle.down.fill", enabled: canDown, action: down).accessibilityLabel(Text("Decrease"))
            }
            .frame(width: 128)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(templates.indices, id: \.self) { i in template(templates[i]) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func triangle(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : StrandMotion.gentle) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func template(_ item: (String, Bool, () -> Void)) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : StrandMotion.gentle) { item.2() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(verbatim: item.0).font(.nuna(size: NunaTypeSize.h3, weight: .bold, design: NunaType.design)).monospacedDigit()
                .foregroundStyle(item.1 ? NunaPalette.effortModerate : NunaPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 51, maxHeight: 51)
                .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous).stroke(item.1 ? NunaPalette.effortModerate : NunaPalette.hairline, lineWidth: item.1 ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.1 ? .isSelected : [])
    }

    private func setShown(_ value: Double) {
        goal.km = min(max(value / perKm, Self.minimumDistanceKm), Self.maximumDistanceKm)
    }

    // MARK: Heart-rate zone tiles

    private func zoneTile(_ z: Int) -> some View {
        let on = goal.zoneOn && goal.zone == z
        let color = NunaHeartBeat.zoneColor(z)
        return Button {
            withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
                if on { goal.zoneOn = false } else { goal.zoneOn = true; goal.zone = z }
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(z)").font(.nuna(size: 22, weight: .bold, design: NunaType.design))
                Text("Zone").font(.nuna(size: 10, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
            }
            .foregroundStyle(on ? NunaHeartBeat.inkColor(zone: z, hasReading: true) : color)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(on ? color : NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous).stroke(on ? .clear : color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Zone \(z)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Anya's suggestion

    /// Anya's session for today in one sentence, with the tap that applies it. The target starts as this already.
    @ViewBuilder private var anyaCard: some View {
        if let suggestion {
            let suggested = NunaWorkoutGoal.suggested(by: suggestion.plan)
            let applied = goal.timeOn && !goal.distanceOn && goal.minutes == suggested.minutes && goal.zoneOn && goal.zone == suggested.zone
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    AnyaMark(size: 26)
                    Text(verbatim: sentence(suggestion))
                        .font(.nuna(size: NunaTypeSize.sub, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if applied {
                        Image(systemName: "checkmark.circle.fill").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.charge)
                            .accessibilityLabel(Text("Applied"))
                    } else {
                        Button {
                            withAnimation(reduceMotion ? nil : StrandMotion.gentle) { goal = suggested; open = .time }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text("Use").font(.nuna(size: NunaTypeSize.sub, weight: .bold)).foregroundStyle(NunaPalette.mapOverlayText)
                                .padding(.horizontal, 16).frame(height: 34).background(NunaPalette.effortModerate, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if charge == nil {
            Text("Anya suggests a session once today's Charge is ready.")
                .font(.nuna(size: NunaTypeSize.caption + 1, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Anya suggests steady zone 2, 42 min for Charge 51 (+31–46 Effort)."
    private func sentence(_ s: NunaDayPlanResult) -> String {
        let title = s.title.prefix(1).lowercased() + s.title.dropFirst()
        guard let lo = s.plan.effortLow, let hi = s.plan.effortHigh else {
            return String(localized: "Anya suggests \(title) for Charge \(s.charge).")
        }
        return String(localized: "Anya suggests \(title) for Charge \(s.charge) (+\(Int(lo.rounded()))–\(Int(hi.rounded())) Effort).")
    }

    // MARK: Actions

    private func clear() {
        withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
            if !goal.isFree { lastGoal = goal }
            let minutes = goal.minutes, km = goal.km, zone = goal.zone
            goal = NunaWorkoutGoal()
            goal.minutes = minutes; goal.km = km; goal.zone = zone
            open = nil
        }
    }

    private var startDock: some View {
        VStack(spacing: 0) {
            NunaDivider()
            Button {
                if !goal.isFree { lastGoal = goal }
                startRequested = true
                dismiss()
            } label: {
                Text(hasActiveWorkout ? "View active workout" : "Start activity")
                    .font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                    .foregroundStyle(NunaPalette.mapOverlayText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(NunaPalette.effortModerate, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.vertical, 12)
        }
        .background(NunaPalette.card)
    }
}

// MARK: - Live (in-exercise)

struct NunaLiveWorkoutView: View {
    let goal: NunaWorkoutGoal
    let zoneBuzz: Bool
    let onClose: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("workoutKeepScreenOn") private var keepScreenOn = false
    @AppStorage("nuna.live.hideBpm") private var hideBpm = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""
    @State private var confirmEnd = false
    @State private var goalHit = false
    @State private var distanceHit = false
    @State private var lastBuzz = Date.distantPast
    @State private var selectedTab = LiveTab.effort
    @State private var sessionSteps: Int?
    @State private var savedActivity: NunaWorkoutKey?
    @State private var savedActivityRow: WorkoutRow?
    @State private var openingSavedActivity = false
    @State private var saveError: String?

    private var zoneSet: HRZoneSet { model.profile.hrZoneSet }
    private enum LiveTab: Hashable { case effort, heartRate }
    private struct StepWindow: Hashable {
        let start: Int
        let end: Int
        let sport: String
        let refresh: Int
    }

    private func stepWindow(_ workout: AppModel.ActiveWorkout, now: Date) -> StepWindow {
        let end = workout.pausedAt.map { Int($0.timeIntervalSince1970) } ?? (Int(now.timeIntervalSince1970) / 15 * 15)
        return StepWindow(start: Int(workout.start.timeIntervalSince1970), end: end, sport: workout.sport, refresh: repo.refreshSeq)
    }

    var body: some View {
        NavigationStack {
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
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $savedActivity) { key in
                NunaWorkoutSummaryView(key: key, initialRow: savedActivityRow)
            }
        }
        .onAppear { if keepScreenOn { UIApplication.shared.isIdleTimerDisabled = true } }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: model.activeWorkout == nil) { _, ended in
            if ended { UIApplication.shared.isIdleTimerDisabled = false }
        }
        .confirmationDialog("End this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and save") { finishAndOpenActivity() }
            Button("Discard", role: .destructive) { model.discardWorkout(); onClose() }
            Button("Keep going", role: .cancel) {}
        }
    }

    /// Wait for the saved row before opening its detail; unsaved sessions retain a clear way back.
    private var finished: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Activity finished").font(.nuna(size: NunaTypeSize.h1, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).padding(.top, 40)
                if let last = model.lastWorkout {
                    Text(verbatim: WorkoutSource.displaySport(last.sport) + " · " + NunaWorkoutFormat.duration(last.durationS)).font(.nuna(size: NunaTypeSize.sub, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    if openingSavedActivity {
                        ProgressView("Saving activity…")
                            .tint(NunaPalette.effortModerate)
                    } else {
                        if let saveError {
                            Text(verbatim: saveError)
                                .font(.nuna(size: NunaTypeSize.sub, weight: .regular))
                                .foregroundStyle(NunaPalette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        Button("View activity") { openSavedActivity(last) }
                            .font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                            .foregroundStyle(NunaPalette.effortModerate)
                            .frame(minHeight: NoopButtonMetrics.minHitTarget)
                    }
                    Button("Done", action: onClose)
                        .font(.nuna(size: NunaTypeSize.sub, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .frame(minHeight: NoopButtonMetrics.minHitTarget)
                } else {
                    Text("The activity was not saved. It needs at least one minute and recorded heart rate or a GPS route.").font(.nuna(size: NunaTypeSize.sub, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    Button(action: onClose) { Text("OK").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)) }.buttonStyle(.plain).padding(.top, 8)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func finishAndOpenActivity() {
        model.endWorkout()
        if let row = model.lastWorkout { openSavedActivity(row) }
    }

    private func openSavedActivity(_ row: WorkoutRow) {
        guard !openingSavedActivity else { return }
        openingSavedActivity = true
        saveError = nil
        Task {
            defer { openingSavedActivity = false }
            guard let store = await repo.storeHandle() else {
                saveError = String(localized: "The saved activity could not be loaded. Please try again.")
                return
            }
            do {
                for attempt in 0..<8 {
                    let rows = try await store.workouts(deviceId: model.deviceId, from: row.startTs, to: row.startTs, limit: 10)
                    if rows.contains(where: { $0.sport == row.sport && $0.source == row.source }) {
                        let visible = await repo.workoutRows()
                        let resolved = visible.first(where: { $0.startTs == row.startTs && $0.sport == row.sport })
                            ?? visible.first(where: { WorkoutSource.sameActivity($0, row) }) ?? row
                        savedActivityRow = resolved
                        savedActivity = NunaWorkoutKey(startTs: resolved.startTs, sport: resolved.sport, source: resolved.source)
                        return
                    }
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 125_000_000)
                }
                saveError = String(localized: "The activity is still being saved. Please try opening it again in a moment.")
            } catch {
                saveError = String(localized: "The saved activity could not be loaded. Please try again.")
            }
        }
    }

    private static let zoneColors = NunaHeartBeat.zoneColors
    private var distanceSystem: UnitSystem { UnitPrefs.resolveDistance(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: distanceSystemRaw) }

    private enum ZoneState { case none, inZone, below, above, farAbove }

    private func content(_ w: AppModel.ActiveWorkout, now: Date) -> some View {
        let elapsed = w.elapsed(at: now)
        let bpm = model.bpm
        let zone = bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0
        let gps = model.gpsRecorder
        let state = zoneState(bpm: bpm, zone: zone)
        let tone = tone(zone: zone, state: state)
        let calories = kcal(w)
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                header(w)
                sessionProgress(w, elapsed: elapsed, distance: gps.distanceM)
                NunaPageTabs([(value: LiveTab.effort, title: "Effort"), (value: .heartRate, title: "Heart rate")], selection: $selectedTab)
                    .transaction { if reduceMotion { $0.disablesAnimations = true } }
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.top, 8)
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: NunaSpacing.section) {
                        if selectedTab == .heartRate {
                            heartRateBeat(bpm: bpm, zone: zone, color: tone, height: viewport.size.height)
                        } else {
                            activityRing(w, bpm: bpm, zone: zone, color: tone,
                                         size: min(260,
                                                   max(188, viewport.size.height - NunaSpacing.section * 2)))
                        }
                        if !ActivityAuthorizationInfo().areActivitiesEnabled { liveActivityOffCard }
                    }
                    .padding(.vertical, NunaSpacing.section)
                    .padding(.horizontal, NunaSpacing.screenH)
                }
                .scrollIndicators(.hidden)
            }
            VStack(spacing: NunaSpacing.section) {
                if selectedTab == .heartRate {
                    heartZoneSection(bpm: bpm, zone: zone, state: state, tone: tone)
                    heartStatistics(w, calories: calories)
                } else {
                    metricRow(w, calories: calories)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                footnote(state: state, now: now)
                controls(w)
            }
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.vertical, 12)
            .background(NunaPalette.canvas)
            .overlay(alignment: .top) { NunaDivider() }
        }
        .onChange(of: Int(elapsed)) { _, _ in checkGoal(elapsed: elapsed, zone: zone, distance: gps.distanceM) }
        .task(id: stepWindow(w, now: now)) {
            let window = stepWindow(w, now: now)
            let steps = await NunaLiveMetrics.steps(sport: w.sport, from: window.start, to: window.end, repo: repo, ticksPerStep: model.profile.stepTicksPerStep)
            guard !Task.isCancelled, model.activeWorkout?.start == w.start else { return }
            sessionSteps = steps
        }
    }

    // MARK: header + ring

    private func header(_ w: AppModel.ActiveWorkout) -> some View {
        let gps = model.gpsRecorder
        let gpsText = usesRoute(w) ? (gps.pointCount == 0 ? String(localized: "Searching GPS") : String(localized: "GPS on")) : String(localized: "No GPS")
        let buzzText = zoneBuzz && !goal.isFree ? String(localized: "target alerts on") : String(localized: "silent session")
        let title = String(localized: String.LocalizationValue(w.sport))
        return HStack(alignment: .center) {
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("Minimise"))
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text(verbatim: title).font(.nuna(size: NunaTypeSize.sub, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                Text(verbatim: gpsText + " · " + buzzText).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Color.clear.frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
        }
    }

    /// The Heart rate tab: the beating disc in the colour of the current zone (see `NunaHeartBeat`).
    private func heartRateBeat(bpm: Int?, zone: Int, color: Color, height: CGFloat) -> some View {
        let range = zoneSet.zones.first(where: { $0.number == zone })
        let caption = range.map { String(localized: "Zone \(zone) · \(Int($0.lower.rounded()))–\(Int($0.upper.rounded())) bpm") }
        return NunaHeartBeat(bpm: bpm, color: bpm == nil ? NunaPalette.effortModerate : color, zone: zone,
                             numberText: hideBpm ? "•••" : nil, size: min(250, max(170, (height - NunaSpacing.section * 2 - 40) / 1.2)),
                             caption: hideBpm ? nil : caption)
            .frame(maxWidth: .infinity, minHeight: max(height - NunaSpacing.section * 2, 0), alignment: .center)
            .overlay(alignment: .topTrailing) {
                Button { hideBpm.toggle() } label: {
                    Image(systemName: hideBpm ? "eye" : "eye.slash")
                        .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(hideBpm ? "Show bpm" : "Hide bpm"))
            }
    }

    private func activityRing(_ w: AppModel.ActiveWorkout, bpm: Int?, zone: Int, color: Color, size: CGFloat) -> some View {
        let isHeartRate = selectedTab == .heartRate
        let fraction = isHeartRate ? (hideBpm ? 0 : Double(bpm ?? 0) / max(zoneSet.maxHR, 1)) : w.liveStrain / 100
        let number = isHeartRate ? (hideBpm ? "•••" : bpm.map(String.init) ?? "–") : String(format: "%.1f", locale: AppLanguage.activeLocale, w.liveStrain)
        return NunaRingGauge(
            fraction: fraction,
            color: isHeartRate ? color : nunaEffortColor(w.liveStrain),
            gradient: isHeartRate ? nil : nunaEffortRingColors(w.liveStrain),
            target: !isHeartRate && !goal.isFree ? (goal.estimatedEffort / 100)...(goal.estimatedEffort / 100) : nil,
            size: size,
            lineWidth: 16
        ) {
            VStack(spacing: 8) {
                Text(isHeartRate ? "Heart rate" : "Activity effort")
                    .font(.nuna(size: NunaTypeSize.caption, weight: .heavy))
                    .tracking(nunaTrackingLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: number)
                    .font(.nuna(size: NunaTypeSize.numberXL, weight: .bold, design: NunaType.design))
                    .tracking(nunaTrackingNumber(NunaTypeSize.numberXL))
                    .monospacedDigit()
                    .foregroundStyle(NunaPalette.textPrimary)
                    .contentTransition(.numericText())
                if isHeartRate {
                    Text(hideBpm ? "Hidden" : "bpm")
                        .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                        .foregroundStyle(NunaPalette.textSecondary)
                    if bpm == nil {
                        Text("Waiting for WHOOP")
                            .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary)
                    }
                } else {
                    Text(w.samples.isEmpty ? "Waiting for HR" : (w.liveStrain < 33 ? "Light" : (w.liveStrain < 66 ? "Moderate" : "High")))
                        .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                        .foregroundStyle(NunaPalette.textSecondary)
                    Text("0–100")
                        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                        .foregroundStyle(NunaPalette.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if isHeartRate {
                Button { hideBpm.toggle() } label: {
                    Image(systemName: hideBpm ? "eye" : "eye.slash")
                        .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(hideBpm ? "Show bpm" : "Hide bpm"))
            }
        }
        .animation(reduceMotion ? nil : StrandMotion.gentle, value: fraction)
    }

    private func sessionProgress(_ w: AppModel.ActiveWorkout, elapsed: TimeInterval, distance: Double) -> some View {
        let hasTarget = !goal.isFree
        let hasProgress = goal.timeOn || goal.distanceOn
        // With both a time and a distance, the bar follows whichever is closer to done.
        let timeFraction = goal.timeOn ? elapsed / Double(max(goal.minutes, 1) * 60) : 0
        let distanceFraction = goal.distanceOn ? distance / (max(goal.km, 0.1) * 1000) : 0
        let fraction = min(max(max(timeFraction, distanceFraction), 0), 1)
        var targetParts: [String] = []
        if goal.timeOn { targetParts.append(String(localized: "\(goal.minutes) min")) }
        if goal.distanceOn {
            // The distance so far is on the statistics row; the bar and this line only say what the target is, unless it is the only one.
            let goalText = UnitFormatter.distanceFromMeters(goal.km * 1000, system: distanceSystem)
            targetParts.append(goal.timeOn || goal.zoneOn ? goalText : UnitFormatter.distanceFromMeters(distance, system: distanceSystem) + " / " + goalText)
        }
        // The zone only, as a number: the range in bpm is on the Heart rate tab.
        if goal.zoneOn { targetParts.append(String(localized: "Zone \(goal.zone)")) }
        let targetText = targetParts.joined(separator: " · ")
        let targetLabel: LocalizedStringKey = targetParts.count > 1 ? "Target"
            : (goal.timeOn ? "Time target" : (goal.distanceOn ? "Distance target" : "Heart rate target"))
        return HStack(alignment: .center, spacing: 16) {
            if hasTarget {
                VStack(alignment: .leading, spacing: 4) {
                    Text(targetLabel)
                        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                    Text(verbatim: targetText)
                        .font(.nuna(size: NunaTypeSize.h3, weight: .bold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Image(systemName: w.isPaused ? "pause.fill" : "stopwatch")
                    .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                    .foregroundStyle(w.isPaused ? NunaPalette.warning : NunaPalette.effortModerate)
                Text(verbatim: clock(elapsed))
                    .font(.nuna(size: NunaTypeSize.numberM, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: hasTarget ? .trailing : .center)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    NunaPalette.card
                    if hasProgress {
                        LinearGradient(colors: [NunaPalette.effortModerate, NunaPalette.effortMinimal], startPoint: .leading, endPoint: .trailing)
                            .opacity(0.2 + fraction * 0.3)
                            .frame(width: geo.size.width * fraction)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Session time \(clock(elapsed))"))
        .accessibilityValue(Text(verbatim: hasProgress ? targetText + " · " + fraction.formatted(.percent.precision(.fractionLength(0))) : targetText))
    }

    // MARK: heart rate

    private func heartZoneSection(bpm: Int?, zone: Int, state: ZoneState, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heart rate zones")
                    .font(.nuna(size: NunaTypeSize.caption, weight: .heavy))
                    .tracking(nunaTrackingLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                if let range = zoneSet.zones.first(where: { $0.number == zone }), bpm != nil {
                    Text(verbatim: "\(Int(range.lower.rounded()))–\(Int(range.upper.rounded())) bpm")
                        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold, design: NunaType.design))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .monospacedDigit()
                }
            }
            zoneBar(bpm: bpm, zone: zone)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { number in
                    let active = bpm != nil && number == zone
                    Text("Zone \(number)")
                        .font(.nuna(size: NunaTypeSize.caption, weight: active ? .heavy : .semibold))
                        .foregroundStyle(active ? Self.zoneColors[number - 1] : NunaPalette.textMuted.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: zone)
                }
            }
            if goal.zoneOn, let line = guidance(bpm: bpm, state: state) {
                Text(verbatim: line)
                    .font(.nuna(size: NunaTypeSize.sub, weight: .semibold))
                    .foregroundStyle(state == .inZone ? NunaPalette.textPrimary : tone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Five visible segments follow the profile's canonical HR zones; below-range values stay at the beginning.
    private func zoneBar(bpm: Int?, zone: Int) -> some View {
        let position = bpm.map { NunaLiveMetrics.barPosition(bpm: $0, zoneSet: zoneSet) }
        return GeometryReader { geo in
            let gap: CGFloat = 2
            let segment = (geo.size.width - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(1...5, id: \.self) { number in
                        RoundedRectangle(cornerRadius: NunaRadius.chip, style: .continuous)
                            .fill(Self.zoneColors[number - 1].opacity(bpm != nil && number == zone ? 1 : 0.22))
                            .frame(width: segment, height: 8)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: zone)
                    }
                }
                if let position, !hideBpm {
                    Triangle().fill(NunaPalette.textPrimary)
                        .frame(width: 12, height: 8)
                        .offset(x: min(max(CGFloat(position) * geo.size.width - 6, 0), geo.size.width - 12), y: 12)
                        .animation(reduceMotion ? nil : StrandMotion.gentle, value: position)
                }
            }
        }
        .frame(height: 24)
    }

    private func heartStatistics(_ w: AppModel.ActiveWorkout, calories: Int?) -> some View {
        statisticsRow([
            Statistic(label: "Avg HR", value: w.avgHr > 0 ? "\(w.avgHr)" : "–", unit: "bpm", icon: "heart.fill"),
            Statistic(label: "Max HR", value: w.peakHr > 0 ? "\(w.peakHr)" : "–", unit: "bpm", icon: "heart.circle"),
            Statistic(label: "Calories", value: calories.map(String.init) ?? "–", unit: String(localized: "kcal"), icon: "flame")
        ])
    }

    private struct Statistic {
        let label: LocalizedStringKey
        let value: String
        let unit: String
        let icon: String
    }

    private func statisticsRow(_ tiles: [Statistic]) -> some View {
        let isSingle = tiles.count == 1
        return HStack(alignment: .top, spacing: 12) {
            ForEach(tiles.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(NunaPalette.hairline)
                        .frame(width: 1, height: 96)
                }
                let tile = tiles[index]
                VStack(alignment: isSingle ? .center : .leading, spacing: 8) {
                    Image(systemName: tile.icon)
                        .font(.nuna(size: NunaTypeSize.h2, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                    Text(tile.label)
                        .font(.nuna(size: NunaTypeSize.caption, weight: .heavy))
                        .tracking(nunaTrackingLabel)
                        .textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    VStack(alignment: isSingle ? .center : .leading, spacing: 4) {
                        Text(verbatim: tile.value)
                            .font(.nuna(size: NunaTypeSize.numberL, weight: .bold, design: NunaType.design))
                            .foregroundStyle(NunaPalette.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if !tile.unit.isEmpty {
                            Text(verbatim: tile.unit)
                                .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                                .foregroundStyle(NunaPalette.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: isSingle ? .center : .leading)
            }
        }
        .padding(.vertical, 8)
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
    @ViewBuilder private func metricRow(_ w: AppModel.ActiveWorkout, calories: Int?) -> some View {
        let gps = model.gpsRecorder
        let sys = distanceSystem
        let dash = "–"
        let dist = gps.pointCount > 0 ? split(UnitFormatter.distanceFromMeters(gps.distanceM, system: sys)) : (dash, sys == .imperial ? "mi" : "km")
        let sensorSpeed = model.live.sensorSpeedKmh.flatMap { $0 > 0 ? $0 : nil }
        let paceSeconds = gps.paceSecPerKm ?? sensorSpeed.map { 3600 / $0 }
        let pace = paceSeconds != nil ? split(UnitFormatter.paceFromSecPerKm(paceSeconds, system: sys)) : (dash, sys == .imperial ? "/mi" : "/km")
        let kmh = gps.paceSecPerKm.flatMap { $0 > 0 ? 3600 / $0 : nil } ?? sensorSpeed
        let speed = UnitFormatter.speedFromKilometersPerHour(kmh, system: sys).map(split) ?? (dash, sys == .imperial ? "mph" : "km/h")
        let gain = sys == .imperial ? gps.elevationGainM * 3.28084 : gps.elevationGainM
        let cadence = model.live.sensorCadence.map { String(Int($0.rounded())) } ?? dash
        let fields = NunaLiveMetricLayout.fields(sport: w.sport, usesGPS: usesRoute(w))
        let tiles: [Statistic] = fields.map { field in
            switch field {
            case .distance: return Statistic(label: "Distance", value: dist.0, unit: dist.1, icon: "point.topleft.down.to.point.bottomright.curvepath")
            case .pace: return Statistic(label: "Pace", value: pace.0, unit: pace.1, icon: "speedometer")
            case .steps: return Statistic(label: "Steps", value: sessionSteps.map { $0.formatted(.number.locale(AppLanguage.activeLocale)) } ?? dash, unit: "", icon: "shoeprints.fill")
            case .cadence: return Statistic(label: "Cadence", value: cadence, unit: "spm", icon: "figure.run")
            case .speed: return Statistic(label: "Speed", value: speed.0, unit: speed.1, icon: "speedometer")
            case .elevation: return Statistic(label: "Elevation", value: gps.pointCount > 0 ? "+\(Int(gain.rounded()))" : dash, unit: sys == .imperial ? "ft" : "m", icon: "mountain.2")
            case .calories: return Statistic(label: "Calories", value: calories.map(String.init) ?? dash, unit: String(localized: "kcal"), icon: "flame")
            }
        }
        if fields == [.calories], calories == nil {
            Text("Calorie data is not available for this activity yet.")
                .font(.nuna(size: NunaTypeSize.sub, weight: .regular))
                .foregroundStyle(NunaPalette.textSecondary)
                .multilineTextAlignment(.center)
        } else {
            statisticsRow(tiles)
        }
    }

    // MARK: footnote + controls

    @ViewBuilder private func footnote(state: ZoneState, now: Date) -> some View {
        if zoneBuzz, !goal.isFree {
            let text: String = {
                if lastBuzz != .distantPast { return String(localized: "Last buzz \(clock(now.timeIntervalSince(lastBuzz))) ago") }
                if goal.zoneOn {
                    switch state {
                    case .none: return String(localized: "Waiting for HR before checking your target zone.")
                    case .inZone: return String(localized: "In target zone · no buzz needed.")
                    default: return String(localized: "1 short buzz every 45 seconds while outside your target zone.")
                    }
                }
                return String(localized: "Your strap will buzz when the target is reached.")
            }()
            HStack(spacing: 8) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.nuna(size: NunaTypeSize.sub, weight: .semibold))
                    .foregroundStyle(NunaPalette.charge)
                Text(verbatim: text)
                    .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
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
                    Image(systemName: w.isPaused ? "play.fill" : "pause.fill").font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    Text(w.isPaused ? "Resume" : "Pause").font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 60)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
            Button { confirmEnd = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill").font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    Text("End").font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 24).frame(height: 60)
                .background(NunaPalette.alertText, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: zone guidance

    private func zoneState(bpm: Int?, zone: Int) -> ZoneState {
        guard goal.zoneOn, bpm != nil, zone > 0 else { return .none }
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
            return goal.zoneOn ? Self.zoneColors[min(max(goal.zone, 1), 5) - 1] : NunaPalette.textMuted
        }
    }

    private func guidance(bpm: Int?, state: ZoneState) -> String? {
        guard let bpm, zoneSet.zones.contains(where: { $0.number == goal.zone }) else { return nil }
        switch state {
        case .none: return nil
        case .inZone: return String(localized: "Hold steady. You are in your target zone.")
        case .below: return String(localized: "Pick up the pace a little.")
        case .above: return String(localized: "Ease off a little.")
        case .farAbove: return String(localized: "Slow down now. \(bpm) bpm is too high.")
        }
    }

    private func checkGoal(elapsed: TimeInterval, zone: Int, distance: Double) {
        guard zoneBuzz else { return }
        if goal.timeOn, !goalHit, elapsed >= Double(goal.minutes * 60) { goalHit = true; cue(loops: 3) }
        if goal.distanceOn, !distanceHit, distance >= goal.km * 1000 { distanceHit = true; cue(loops: 3) }
        if goal.zoneOn, zone > 0, zone != goal.zone, Date().timeIntervalSince(lastBuzz) > 45 { lastBuzz = Date(); cue(loops: 1) }
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

/// The three small squares of the planning strip: the day as it is (solid), the activity on top of it (hatched) and the day after it
/// (half and half).
private struct NunaEffortSwatch: View {
    enum Kind { case solid, hatched, half }
    let kind: Kind

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let shape = Path(roundedRect: rect, cornerRadius: 4)
            let blue = NunaPalette.effortModerate
            func stripes() -> Path {
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 5
                }
                return p
            }
            switch kind {
            case .solid:
                ctx.fill(shape, with: .color(blue))
            case .hatched:
                ctx.fill(shape, with: .color(blue.opacity(0.18)))
                ctx.clipToLayer { c in c.fill(shape, with: .color(.black)) }
                ctx.stroke(stripes(), with: .color(blue), lineWidth: 1.6)
            case .half:
                ctx.fill(shape, with: .color(blue.opacity(0.18)))
                ctx.clipToLayer { c in c.fill(shape, with: .color(.black)) }
                var tri = Path()
                tri.move(to: .zero); tri.addLine(to: CGPoint(x: size.width, y: 0)); tri.addLine(to: CGPoint(x: 0, y: size.height)); tri.closeSubpath()
                ctx.fill(tri, with: .color(blue))
                ctx.stroke(stripes(), with: .color(blue), lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}

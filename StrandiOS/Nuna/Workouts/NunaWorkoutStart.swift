#if os(iOS)
import SwiftUI
import UIKit
import ActivityKit
import MapKit
import CoreLocation
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
    @State private var lastTargetMode = NunaWorkoutGoal.Mode.zone
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
                planned = p; goal.mode = .zone; lastTargetMode = .zone
                goal.zone = min(max(p.zone, 1), 5); goal.minutes = max(5, min(p.minutes, 300))
            }
            if let s = planned?.sport, let match = WorkoutCatalog.sport(named: s) { chosen = match.name }
            if let sport { chosen = sport } else if let a = model.activeWorkout { chosen = a.sport }
            updateLocationPreview()
        }
        .onDisappear { locationPreview.stop() }
        .onChange(of: chosen) { _, _ in
            if !isDistance, goal.mode == .distance { goal.mode = .zone; lastTargetMode = .zone }
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
                lastTargetMode: $lastTargetMode,
                startRequested: $startAfterTargetSetup,
                sport: chosen,
                isDistanceActivity: isDistance,
                distanceSystem: distanceSystem,
                zones: zoneSet.zones,
                charge: repo.today?.recovery,
                dayEffort: repo.today?.strain,
                anyaPlanTitle: planned?.title,
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
                NunaWorkoutHeartPulse(
                    bpm: model.bpm,
                    battery: liveState.batteryPct,
                    reduceMotion: reduceMotion)
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
        switch goal.mode {
        case .free: return String(localized: "Off")
        case .time: return String(localized: "\(goal.minutes) min")
        case .distance:
            let value = distanceSystem == .imperial ? goal.km * UnitFormatter.milesPerKilometer : goal.km
            return String(format: "%.1f %@", locale: AppLanguage.activeLocale, value, UnitFormatter.distanceUnit(distanceSystem))
        case .zone: return String(localized: "Zone \(goal.zone)")
        }
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
                    .foregroundStyle(goal.mode == .free ? NunaPalette.textSecondary : NunaPalette.effortModerate)
                    .frame(width: 36, height: 36)
                    .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: NunaRadius.iconTile, style: .continuous))
                Button {
                    if goal.mode == .free { goal.mode = lastTargetMode }
                    showTargetSetup = true
                } label: {
                    VStack(alignment: .leading, spacing: NoopMetrics.spaceHalf) {
                        Text("Effort target")
                            .font(.nuna(size: NunaTypeSize.h3, weight: .heavy))
                            .foregroundStyle(NunaPalette.textPrimary)
                        HStack(spacing: NoopMetrics.space1) {
                            Text(verbatim: goal.mode == .free ? String(localized: "Free session") : targetSummary)
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
        Binding(get: { goal.mode != .free }, set: { enabled in
            withAnimation(.easeInOut(duration: 0.28)) {
                if enabled {
                    goal.mode = lastTargetMode == .distance && !isDistance ? .zone : lastTargetMode
                    showTargetSetup = true
                } else {
                    if goal.mode != .free { lastTargetMode = goal.mode }
                    goal.mode = .free
                }
            }
            UISelectionFeedbackGenerator().selectionChanged()
        })
    }

    private var sportPicker: some View {
        NunaSportPicker(selection: $chosen) { showPicker = false }
    }

    private func clearPlan() {
        withAnimation(.easeInOut(duration: 0.2)) {
            planned = nil
            goal = NunaWorkoutGoal()
            lastTargetMode = .zone
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
    @Binding var lastTargetMode: NunaWorkoutGoal.Mode
    @Binding var startRequested: Bool
    let sport: String
    let isDistanceActivity: Bool
    let distanceSystem: UnitSystem
    let zones: [HRZone]
    let charge: Double?
    let dayEffort: Double?
    let anyaPlanTitle: String?
    let hasActiveWorkout: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var configuredMode: NunaWorkoutGoal.Mode?
    @State private var showInfo = false

    private var modes: [NunaWorkoutGoal.Mode] {
        isDistanceActivity ? [.time, .zone, .distance] : [.time, .zone]
    }

    private var estimatedEffort: Double {
        let estimate: Double
        switch goal.mode {
        case .time: estimate = min(20, 2.8 + Double(goal.minutes) / 17)
        case .distance: estimate = min(20, 2.6 + goal.km * 1.34)
        case .zone: estimate = min(20, 3.6 + Double(goal.zone) * 2.55)
        case .free: estimate = 3.6
        }
        return estimate / UnitFormatter.effortScaleFactor
    }

    private var effortText: String {
        effortNumber(estimatedEffort)
    }

    private func effortNumber(_ value: Double) -> String {
        String(format: "%.1f", locale: AppLanguage.activeLocale, value)
    }

    var body: some View {
        VStack(spacing: 0) {
            activityHeader
            NunaDivider()
            ScrollView {
                VStack(spacing: NunaSpacing.cardInnerSmall) {
                    targetHeader
                    if showInfo {
                        Text("This is a planning estimate on the 0–100 Effort scale. Actual Effort is calculated from the heart rate recorded during your activity.")
                            .font(.nuna(size: NunaTypeSize.sub, weight: .regular))
                            .foregroundStyle(NunaPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    effortRing
                    targetExplanation
                    trainingSummary
                    HStack(spacing: NoopMetrics.space2) {
                        ForEach(modes, id: \.rawValue) { mode in
                            targetModeButton(mode)
                        }
                    }
                    if let configuredMode {
                        configuration(for: configuredMode)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Text("Choose Time, HR or Distance to adjust your target.")
                            .font(.nuna(size: NunaTypeSize.sub, weight: .regular))
                            .foregroundStyle(NunaPalette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH)
                .padding(.vertical, NunaSpacing.section)
            }
            .scrollIndicators(.hidden)
            startDock
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
    }

    private var activityHeader: some View {
        HStack(spacing: NoopMetrics.space2) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                    .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close target settings"))
            Image(systemName: NunaSportPicker.symbol(for: sport))
                .font(.nuna(size: NunaTypeSize.h2, weight: .semibold))
            Text(LocalizedStringKey(sport))
                .font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: NoopMetrics.space2)
            Button("Done") { dismiss() }
                .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                .frame(minHeight: NoopButtonMetrics.minHitTarget)
                .buttonStyle(.plain)
        }
        .foregroundStyle(NunaPalette.textPrimary)
        .padding(.horizontal, NunaSpacing.screenH)
        .padding(.top, NoopMetrics.space2)
    }

    private var targetHeader: some View {
        HStack(spacing: NoopMetrics.space2) {
            NunaInfoButton(isOn: $showInfo)
                .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
            Text("Effort target")
                .font(.nuna(size: NunaTypeSize.sub, weight: .heavy))
                .tracking(nunaTrackingLabel)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .foregroundStyle(NunaPalette.textPrimary)
            Toggle("Effort target", isOn: enabledBinding)
                .labelsHidden()
                .tint(NunaPalette.effortModerate)
        }
    }

    private var effortRing: some View {
        NunaRingGauge(
            fraction: estimatedEffort / 100,
            color: NunaPalette.effortModerate,
            gradient: [NunaPalette.effortMinimal, NunaPalette.effortModerate],
            target: nunaEffortTargetFractions(charge: charge),
            size: NoopMetrics.chartHeight + NoopMetrics.space4,
            lineWidth: NoopMetrics.space4
        ) {
            VStack(spacing: NoopMetrics.space2) {
                Text("Activity effort")
                    .font(.nuna(size: NunaTypeSize.caption, weight: .heavy))
                    .tracking(nunaTrackingLabel)
                    .textCase(.uppercase)
                    .foregroundStyle(NunaPalette.textSecondary)
                Text(verbatim: effortText)
                    .font(.nuna(size: NunaTypeSize.numberXL, weight: .bold, design: NunaType.design))
                    .tracking(nunaTrackingNumber(NunaTypeSize.numberXL))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Estimated")
                    .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary)
                Button { resetTarget() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.nuna(size: NunaTypeSize.sub, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary)
                        .frame(width: NoopButtonMetrics.minHitTarget, height: NoopButtonMetrics.minHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Reset activity target"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoopMetrics.space1)
        .animation(reduceMotion ? nil : StrandMotion.gentle, value: estimatedEffort)
    }

    private var targetExplanation: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            Image(systemName: "sparkles")
                .font(.nuna(size: NunaTypeSize.h2, weight: .semibold))
                .foregroundStyle(NunaPalette.effortModerate)
                .frame(width: NoopMetrics.compactControlSize, height: NoopMetrics.compactControlSize)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                if let anyaPlanTitle {
                    Text(verbatim: anyaPlanTitle)
                        .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                        .foregroundStyle(NunaPalette.textPrimary)
                }
                Text(explanation)
                    .font(.nuna(size: NunaTypeSize.sub, weight: .regular))
                    .foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanation: String {
        let target = configurationValue(goal.mode)
        if let band = CoupledView.optimalStrainRange(recovery: charge) {
            let lower = effortNumber(Double(band.lowerBound) / UnitFormatter.effortScaleFactor)
            let upper = effortNumber(Double(band.upperBound) / UnitFormatter.effortScaleFactor)
            return String(localized: "Your \(target) target estimates \(effortText) activity Effort. Today's suggested day range is \(lower)–\(upper), based on Charge.")
        }
        return String(localized: "Your \(target) target estimates \(effortText) activity Effort. Adjust the slider to plan this session.")
    }

    private var trainingSummary: some View {
        VStack(spacing: NoopMetrics.space3) {
            NunaDivider()
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                summaryStat("Current day", value: dayEffort.map(effortNumber) ?? "–", color: NunaPalette.textPrimary)
                summaryStat("Activity target", value: effortText, color: NunaPalette.effortModerate)
                summaryStat("Charge", value: charge.map { "\(Int($0.rounded()))%" } ?? "–", color: NunaPalette.charge)
            }
        }
    }

    private func summaryStat(_ label: LocalizedStringKey, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text(label)
                .font(.nuna(size: NunaTypeSize.caption, weight: .semibold))
                .foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: value)
                .font(.nuna(size: NunaTypeSize.numberS, weight: .bold, design: NunaType.design))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startDock: some View {
        VStack(spacing: 0) {
            NunaDivider()
            Button {
                startRequested = true
                dismiss()
            } label: {
                Text(hasActiveWorkout ? "View active workout" : "Start activity")
                    .font(.nuna(size: NunaTypeSize.h3, weight: .bold))
                    .foregroundStyle(NunaPalette.mapOverlayText)
                    .frame(maxWidth: .infinity, minHeight: NoopMetrics.controlHeight)
                    .background(NunaPalette.effortModerate, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, NunaSpacing.screenH)
            .padding(.vertical, NoopMetrics.space3)
        }
        .background(NunaPalette.card)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { goal.mode != .free }, set: { enabled in
            guard !enabled else { return }
            if goal.mode != .free { lastTargetMode = goal.mode }
            goal.mode = .free
            dismiss()
        })
    }

    private func resetTarget() {
        withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
            let previousMode = goal.mode
            goal = NunaWorkoutGoal()
            goal.mode = previousMode
        }
    }

    private func targetModeButton(_ mode: NunaWorkoutGoal.Mode) -> some View {
        let isSelected = configuredMode == mode
        return Button {
            withAnimation(reduceMotion ? nil : StrandMotion.gentle) {
                goal.mode = mode
                lastTargetMode = mode
                configuredMode = mode
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: NoopMetrics.space2) {
                Image(systemName: targetIcon(mode))
                    .font(.nuna(size: NunaTypeSize.h3, weight: .semibold))
                Text(targetName(mode))
                    .font(.nuna(size: NunaTypeSize.sub, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? NunaPalette.mapOverlayText : NunaPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.tabBarClearance)
            .background(isSelected ? NunaPalette.effortModerate : NunaPalette.card, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous)
                    .stroke(isSelected ? NunaPalette.effortModerate : NunaPalette.hairline, lineWidth: NoopMetrics.hairlineWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func configuration(for mode: NunaWorkoutGoal.Mode) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(configurationTitle(mode))
                    .font(.nuna(size: NunaTypeSize.sub, weight: .semibold))
                    .foregroundStyle(NunaPalette.textSecondary)
                Spacer()
                Text(verbatim: configurationValue(mode))
                    .font(.nuna(size: NunaTypeSize.numberS, weight: .bold, design: NunaType.design))
                    .foregroundStyle(NunaPalette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            switch mode {
            case .time:
                NunaSlider(value: timeBinding, in: 5...300, step: 5, accessibilityValue: configurationValue(mode))
                    .accessibilityLabel(Text("Target duration"))
                sliderBounds(String(localized: "5 min"), String(localized: "5 hr"))
            case .distance:
                NunaSlider(value: distanceBinding, in: distanceRange, step: 0.5, accessibilityValue: configurationValue(mode))
                    .accessibilityLabel(Text("Target distance"))
                sliderBounds(distanceLowerText, distanceUpperText)
            case .zone:
                zoneConfiguration
            case .free:
                EmptyView()
            }
        }
    }

    private var zoneConfiguration: some View {
        let zone = min(max(goal.zone, 1), 5)
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            NunaSlider(value: zoneBinding, in: 1...5, step: 1, accessibilityValue: configurationValue(.zone))
                .accessibilityLabel(Text("Target heart-rate zone"))
            HStack {
                Text("Zone 1")
                Spacer()
                Text("Zone \(zone)")
                    .foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Text("Zone 5")
            }
            .font(.nuna(size: NunaTypeSize.caption, weight: .semibold, design: NunaType.design))
            .foregroundStyle(NunaPalette.textSecondary)
            .monospacedDigit()
        }
    }

    private var timeBinding: Binding<Double> {
        Binding(get: { Double(goal.minutes) }, set: { goal.minutes = Int($0.rounded()) })
    }

    private var distanceBinding: Binding<Double> {
        Binding(
            get: { distanceSystem == .imperial ? goal.km * UnitFormatter.milesPerKilometer : goal.km },
            set: { goal.km = distanceSystem == .imperial ? $0 / UnitFormatter.milesPerKilometer : $0 })
    }

    private var zoneBinding: Binding<Double> {
        Binding(get: { Double(goal.zone) }, set: { goal.zone = min(max(Int($0.rounded()), 1), 5) })
    }

    private var distanceRange: ClosedRange<Double> {
        distanceSystem == .imperial ? 0.5...62 : 0.5...100
    }

    private var distanceLowerText: String { String(format: "%.1f %@", locale: AppLanguage.activeLocale, distanceRange.lowerBound, UnitFormatter.distanceUnit(distanceSystem)) }
    private var distanceUpperText: String { String(format: "%.0f %@", locale: AppLanguage.activeLocale, distanceRange.upperBound, UnitFormatter.distanceUnit(distanceSystem)) }

    private func sliderBounds(_ leading: String, _ trailing: String) -> some View {
        HStack {
            Text(verbatim: leading)
            Spacer()
            Text(verbatim: trailing)
        }
        .font(.nuna(size: NunaTypeSize.caption, weight: .semibold, design: NunaType.design))
        .foregroundStyle(NunaPalette.textSecondary)
        .monospacedDigit()
    }

    private func targetName(_ mode: NunaWorkoutGoal.Mode) -> LocalizedStringKey {
        switch mode {
        case .time: return "Time"
        case .distance: return "Distance"
        case .zone: return "HR"
        case .free: return "Free session"
        }
    }

    private func targetIcon(_ mode: NunaWorkoutGoal.Mode) -> String {
        switch mode {
        case .time: return "timer"
        case .distance: return "point.topleft.down.curvedto.point.bottomright.up"
        case .zone: return "heart.fill"
        case .free: return "figure.walk"
        }
    }

    private func configurationTitle(_ mode: NunaWorkoutGoal.Mode) -> LocalizedStringKey {
        switch mode {
        case .time: return "Target duration"
        case .distance: return "Target distance"
        case .zone: return "Target heart rate"
        case .free: return "Target"
        }
    }

    private func configurationValue(_ mode: NunaWorkoutGoal.Mode) -> String {
        switch mode {
        case .time: return String(localized: "\(goal.minutes) min")
        case .distance:
            let value = distanceSystem == .imperial ? goal.km * UnitFormatter.milesPerKilometer : goal.km
            return String(format: "%.1f %@", locale: AppLanguage.activeLocale, value, UnitFormatter.distanceUnit(distanceSystem))
        case .zone:
            let range = zones.first(where: { $0.number == goal.zone })
            return range.map { "\(Int($0.lower.rounded())) – \(Int($0.upper.rounded())) bpm" } ?? String(localized: "Zone \(goal.zone)")
        case .free: return "–"
        }
    }
}

/// The live status is isolated from the rest of the start screen so frequent HR ticks redraw only this circle.
private struct NunaWorkoutHeartPulse: View {
    let bpm: Int?
    let battery: Double?
    let reduceMotion: Bool
    @State private var beating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(NunaPalette.effortModerate.opacity(0.93))
                .frame(width: 238, height: 238)
                .scaleEffect(beating ? 1.035 : 0.985)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.58).repeatForever(autoreverses: true), value: beating)

            VStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.nuna(size: 38, weight: .bold))
                    .scaleEffect(beating ? 1.12 : 0.92)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.58).repeatForever(autoreverses: true), value: beating)
                Text(verbatim: bpm.map(String.init) ?? "–")
                    .font(.nuna(size: 80, weight: .bold, design: NunaType.design))
                    .tracking(nunaTrackingNumber(80))
                    .monospacedDigit()
                Text("bpm")
                    .font(.nuna(size: 12, weight: .heavy))
                    .textCase(.uppercase)
                    .tracking(nunaTrackingLabel)
                if let battery {
                    HStack(spacing: 5) {
                        Image(systemName: "battery.75percent")
                        Text(verbatim: "\(Int(battery.rounded()))%")
                    }
                    .font(.nuna(size: 13, weight: .bold))
                    .padding(.top, 4)
                }
            }
            .foregroundStyle(NunaPalette.mapOverlayText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bpm.map { "Heart rate \($0) bpm" } ?? String(localized: "Heart rate unavailable")))
        .onAppear { beating = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in beating = !reduced }
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

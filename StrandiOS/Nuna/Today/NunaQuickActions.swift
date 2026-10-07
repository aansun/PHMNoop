#if os(iOS)
import SwiftUI
import StrandDesign

/// Everything the quick actions sheet can hold. The wearer picks up to `NunaQuickActions.maxCount` of these; the choice is a
/// comma-separated list of ids in `nuna.quickActions`.
struct NunaQuickAction: Identifiable, Hashable {
    enum Kind: Hashable {
        case addActivity
        case route(NavRouter.Destination)
        case breathing
        case today(NunaTodayRoute)
        case me(NunaMeRoute)
        case workout(NunaWorkoutRoute)
        case metric(String)
    }
    let id: String
    let title: String
    let icon: String
    let group: String
    let kind: Kind
}

enum NunaQuickActions {
    static let storageKey = "nuna.quickActions"
    static let maxCount = 6
    static let defaultIDs = ["start", "breathing", "nap", "gym", "add", "theme"]

    static let all: [NunaQuickAction] = [
        // Log
        .init(id: "add", title: "Add activity", icon: "plus", group: "Log", kind: .addActivity),
        .init(id: "journal", title: "Journal", icon: "bookmark", group: "Log", kind: .route(.journal)),
        .init(id: "mood", title: "Mood", icon: "face.smiling", group: "Log", kind: .today(.mood)),
        .init(id: "weight", title: "Weight", icon: "scalemass", group: "Log", kind: .today(.weight)),
        .init(id: "waist", title: "Waist", icon: "ruler", group: "Log", kind: .today(.waist)),
        .init(id: "nutrition", title: "Nutrition", icon: "fork.knife", group: "Log", kind: .today(.nutrition)),
        .init(id: "cycle", title: "Menstrual cycle", icon: "calendar", group: "Log", kind: .today(.cycle)),
        // Train
        .init(id: "start", title: "Start session", icon: "play", group: "Train", kind: .route(.activeWorkout)),
        .init(id: "gym", title: "Gym", icon: "dumbbell", group: "Train", kind: .workout(.gym)),
        .init(id: "workouts", title: "Workouts", icon: "figure.run", group: "Train", kind: .route(.workouts)),
        .init(id: "history", title: "History", icon: "clock.arrow.circlepath", group: "Train", kind: .workout(.history)),
        .init(id: "load", title: "Training load", icon: "chart.bar", group: "Train", kind: .workout(.load)),
        .init(id: "liveHeart", title: "Live heart rate", icon: "heart", group: "Train", kind: .today(.liveHeart)),
        // Calm and sleep
        .init(id: "breathing", title: "Breathing", icon: "wind", group: "Rest", kind: .breathing),
        .init(id: "nap", title: "Nap", icon: "moon", group: "Rest", kind: .today(.sleepNaps(0))),
        .init(id: "sleep", title: "Sleep", icon: "bed.double", group: "Rest", kind: .today(.sleep(0))),
        .init(id: "bodyClock", title: "Body clock", icon: "clock", group: "Rest", kind: .today(.bodyClock)),
        .init(id: "smartAlarm", title: "Smart alarm", icon: "alarm", group: "Rest", kind: .today(.smartAlarm)),
        .init(id: "windDown", title: "Wind down", icon: "moon.stars", group: "Rest", kind: .today(.windDown)),
        // Read
        .init(id: "hrv", title: "Heart Rate Variability", icon: "waveform.path.ecg", group: "Read", kind: .metric("hrv")),
        .init(id: "stress", title: "Stress monitor", icon: "gauge.with.dots.needle.50percent", group: "Read", kind: .metric("stress")),
        .init(id: "earlyWarning", title: "Early warning", icon: "bell", group: "Read", kind: .today(.earlyWarning)),
        .init(id: "fitnessAge", title: "Fitness age", icon: "figure.run", group: "Read", kind: .today(.fitnessAge)),
        .init(id: "trends", title: "Trends", icon: "chart.line.uptrend.xyaxis", group: "Read", kind: .route(.trends)),
        .init(id: "labBook", title: "Lab book", icon: "testtube.2", group: "Read", kind: .route(.labBook)),
        // App
        .init(id: "theme", title: "Theme", icon: "paintpalette", group: "App", kind: .me(.theme)),
        .init(id: "devices", title: "Strap", icon: "applewatch", group: "App", kind: .route(.devices)),
        .init(id: "notifications", title: "Notifications", icon: "bell.badge", group: "App", kind: .me(.notifications)),
        .init(id: "units", title: "Units", icon: "ruler", group: "App", kind: .me(.units)),
        .init(id: "workoutSettings", title: "Workout settings", icon: "gearshape", group: "App", kind: .workout(.settings)),
    ]

    static func action(_ id: String) -> NunaQuickAction? { all.first { $0.id == id } }

    static func decode(_ raw: String) -> [String] {
        let ids = raw.split(separator: ",").map(String.init).filter { action($0) != nil }
        var seen = Set<String>(); var out: [String] = []
        for id in ids where !seen.contains(id) { seen.insert(id); out.append(id) }
        return Array(out.prefix(maxCount))
    }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }
}

/// Opens a route inside a sheet: the screen is pushed onto a stack whose root is blank, so its own back button pops to the
/// root, which closes the sheet.
struct NunaQuickPanel<Root: Hashable>: View {
    let route: Root
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var liftSession: LiftSessionController
    @State private var path: NavigationPath

    init(route: Root) {
        self.route = route
        _path = State(initialValue: NavigationPath([route]))
    }

    var body: some View {
        NavigationStack(path: $path) {
            NunaPalette.canvas.ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .nunaTodayDestinations()
                .nunaMeDestinations()
                .nunaWorkoutDestinations()
                .nunaTrendsDestinations()
                .nunaAnyaDestinations()
                .nunaDeviceDestinations()
        }
        .onChange(of: path.count) { _, n in if n == 0 { dismiss() } }
        // A gym session shows as a sheet over the whole app, and a sheet cannot open on top of this one. When a session asks to be shown
        // from in here (starting one in Gym, or tapping Open), this panel closes and the session follows once the screen is clear.
        .onChange(of: liftSession.wantsPresent) { _, wants in if wants { dismiss() } }
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}

/// Choose, order and reset the quick actions (at most six).
struct NunaQuickActionsEditor: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []

    private var available: [NunaQuickAction] { NunaQuickActions.all.filter { !ids.contains($0.id) } }
    private var full: Bool { ids.count >= NunaQuickActions.maxCount }

    var body: some View {
        List {
            Section {
                ForEach(ids, id: \.self) { id in
                    if let a = NunaQuickActions.action(id) {
                        HStack(spacing: 12) {
                            NunaIconTile(a.icon)
                            Text(LocalizedStringKey(a.title)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer(minLength: 0)
                            Button { ids.removeAll { $0 == id }; save() } label: {
                                Image(systemName: "minus.circle.fill").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.alert)
                            }.buttonStyle(.plain).accessibilityLabel(Text("Remove"))
                        }
                        .listRowBackground(NunaPalette.card)
                    }
                }
                .onMove { ids.move(fromOffsets: $0, toOffset: $1); save() }
            } header: {
                HStack {
                    Text(verbatim: String(localized: "Shown · \(ids.count) of \(NunaQuickActions.maxCount)"))
                    Spacer()
                }.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            } footer: {
                if full {
                    Text("Six is the most. Remove one to add another.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            ForEach(Array(Dictionary(grouping: available, by: \.group).keys).sorted { groupOrder($0) < groupOrder($1) }, id: \.self) { group in
                Section {
                    ForEach(available.filter { $0.group == group }) { a in
                        Button { guard !full else { return }; ids.append(a.id); save() } label: {
                            HStack(spacing: 12) {
                                NunaIconTile(a.icon)
                                Text(LocalizedStringKey(a.title)).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.charge)
                            }
                        }
                        .buttonStyle(.plain).disabled(full).opacity(full ? 0.4 : 1)
                        .listRowBackground(NunaPalette.card)
                    }
                } header: {
                    Text(LocalizedStringKey(group)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Customize quick actions").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Button { ids = NunaQuickActions.defaultIDs; save() } label: {
                    Text("Reset").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
                Button { dismiss() } label: {
                    Text("Done").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 10)
            .background(NunaPalette.canvas)
        }
        .onAppear { ids = NunaQuickActions.decode(raw.isEmpty ? NunaQuickActions.encode(NunaQuickActions.defaultIDs) : raw) }
        .preferredColorScheme(NunaTheme.colorScheme)
    }

    private func groupOrder(_ g: String) -> Int { ["Log", "Train", "Rest", "Read", "App"].firstIndex(of: g) ?? 9 }
    private func save() { raw = NunaQuickActions.encode(ids) }
}
#endif

#if os(iOS)
extension NunaTodayRoute: Identifiable { var id: Self { self } }
extension NunaMeRoute: Identifiable { var id: Self { self } }
extension NunaWorkoutRoute: Identifiable { var id: Self { self } }
#endif

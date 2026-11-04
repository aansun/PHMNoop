#if os(iOS)
import SwiftUI
import StrandDesign

/// Everything the quick actions menu can hold. The wearer picks up to `NunaQuickActions.maxCount` of these; the choice is a
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
        /// Opens Add food for today.
        case foodAdd
    }
    let id: String
    let title: String
    let icon: String
    let group: String
    let kind: Kind
}

enum NunaQuickActions {
    static let storageKey = "nuna.quickActions"
    /// Five shortcuts at most: the menu behind the "+" is a short list, not a screen.
    static let maxCount = 5
    static let defaultIDs = ["journal", "gym", "add", "start", "breathing"]

    static let all: [NunaQuickAction] = [
        // Log
        .init(id: "add", title: "Add activity", icon: "plus", group: "Log", kind: .addActivity),
        .init(id: "journal", title: "Journal", icon: "bookmark", group: "Log", kind: .route(.journal)),
        .init(id: "mood", title: "Mood", icon: "face.smiling", group: "Log", kind: .today(.mood)),
        .init(id: "weight", title: "Weight", icon: "scalemass", group: "Log", kind: .today(.weight)),
        .init(id: "logFood", title: "Log food", icon: "fork.knife", group: "Log", kind: .foodAdd),
        .init(id: "nutrition", title: "Nutrition", icon: "fork.knife", group: "Log", kind: .today(.nutrition)),
        .init(id: "cycle", title: "Menstrual cycle", icon: "calendar", group: "Log", kind: .today(.cycle)),
        // Train
        .init(id: "start", title: "Start session", icon: "play", group: "Train", kind: .route(.activeWorkout)),
        .init(id: "gym", title: "Strength Trainer", icon: "act:strength-trainer", group: "Train", kind: .workout(.gym)),
        .init(id: "history", title: "History", icon: "clock.arrow.circlepath", group: "Train", kind: .workout(.history)),
        .init(id: "load", title: "Training load", icon: "chart.bar", group: "Train", kind: .workout(.load)),
        .init(id: "liveHeart", title: "Live heart rate", icon: "heart", group: "Train", kind: .today(.deepTimeline)),
        // Calm and sleep
        .init(id: "breathing", title: "Breathing", icon: "wind", group: "Sleep", kind: .breathing),
        .init(id: "nap", title: "Nap", icon: "moon", group: "Sleep", kind: .today(.sleepNaps(0))),
        .init(id: "sleep", title: "Sleep", icon: "bed.double", group: "Sleep", kind: .today(.sleep(0))),
        .init(id: "bodyClock", title: "Body clock", icon: "clock", group: "Sleep", kind: .today(.bodyClock)),
        .init(id: "smartAlarm", title: "Smart alarm", icon: "alarm", group: "Sleep", kind: .today(.smartAlarm)),
        .init(id: "windDown", title: "Wind down", icon: "moon.stars", group: "Sleep", kind: .today(.windDown)),
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
    @State private var path: NavigationPath

    init(route: Root) {
        self.route = route
        _path = State(initialValue: NavigationPath([route]))
    }

    var body: some View {
        NavigationStack(path: $path) {
            NunaBackdrop()
                .toolbar(.hidden, for: .navigationBar)
                .nunaTodayDestinations()
                .nunaMeDestinations()
                .nunaWorkoutDestinations()
                .nunaTrendsDestinations()
                .nunaAnyaDestinations()
                .nunaDeviceDestinations()
        }
        .onChange(of: path.count) { _, n in if n == 0 { dismiss() } }
        .preferredColorScheme(NunaTheme.colorScheme)
    }
}

/// Choose, order and reset the quick actions (at most five). A shown action is removed by sliding it to the left, which uncovers a round
/// delete button; the actions to add are listed only while a slot is empty. The order is changed with the Reorder switch at the top.
struct NunaQuickActionsEditor: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    @State private var reordering = false

    private var available: [NunaQuickAction] { NunaQuickActions.all.filter { !ids.contains($0.id) } }
    private var full: Bool { ids.count >= NunaQuickActions.maxCount }

    var body: some View {
        List {
            Section {
                ForEach(ids, id: \.self) { id in
                    if let a = NunaQuickActions.action(id) {
                        // Slid to the left, the row uncovers a round red delete button (not while the order is being changed).
                        NunaSwipeDeleteRow(enabled: !reordering, onDelete: { ids.removeAll { $0 == id }; save() }) {
                            HStack(spacing: 12) {
                                NunaIconTile(a.icon)
                                Text(LocalizedStringKey(a.title)).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Spacer(minLength: 0)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .onMove { ids.move(fromOffsets: $0, toOffset: $1); save() }
                // The slots still free, drawn as dashed rows.
                ForEach(0..<max(NunaQuickActions.maxCount - ids.count, 0), id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NunaPalette.textMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 36, height: 36)
                        Text("Empty slot").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear).moveDisabled(true)
                }
            } header: {
                HStack {
                    Text(verbatim: String(localized: "Shown · \(ids.count) of \(NunaQuickActions.maxCount)"))
                    Spacer()
                    if ids.count > 1 {
                        Button { withAnimation { reordering.toggle() } } label: {
                            Text(reordering ? "Done" : "Reorder").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                                .foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 30)
                        }.buttonStyle(.plain)
                    }
                }.font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            } footer: {
                if full {
                    Text("Five is the most. Swipe one to the left to remove it and make room for another.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            if !full {
                ForEach(Array(Dictionary(grouping: available, by: \.group).keys).sorted { groupOrder($0) < groupOrder($1) }, id: \.self) { group in
                    Section {
                        ForEach(available.filter { $0.group == group }) { a in
                            Button { guard !full else { return }; withAnimation { ids.append(a.id); save() } } label: {
                                HStack(spacing: 12) {
                                    NunaIconTile(a.icon)
                                    Text(LocalizedStringKey(a.title)).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                                    Spacer(minLength: 0)
                                    Image(systemName: "plus.circle.fill").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(NunaPalette.charge)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(LocalizedStringKey(group)).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NunaBackdrop())
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Customize quick actions").font(.nuna(size: NunaTypeSize.h2, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Spacer()
                Button { withAnimation { ids = NunaQuickActions.defaultIDs; save() } } label: {
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

    private func groupOrder(_ g: String) -> Int { ["Log", "Train", "Sleep", "Read", "App"].firstIndex(of: g) ?? 9 }
    private func save() { raw = NunaQuickActions.encode(ids) }
}
#endif

#if os(iOS)
extension NunaTodayRoute: Identifiable { var id: Self { self } }
extension NunaMeRoute: Identifiable { var id: Self { self } }
extension NunaWorkoutRoute: Identifiable { var id: Self { self } }
#endif

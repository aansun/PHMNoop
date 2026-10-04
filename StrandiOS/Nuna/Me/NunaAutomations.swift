#if os(iOS)
import SwiftUI
import AppIntents
import StrandDesign

// MARK: - Strap automations (Automations.dc)

/// The switches that make the strap act: the wrist master, double-tap, wear and presence, in-session vibrations, coaching,
/// reminders. Every value is the one the Default Automations screen edits, so the two always agree.
struct NunaAutomationsView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var model: AppModel
    @StateObject private var inactivity = InactivityPrefs()
    @AppStorage("notif.masterEnabled") private var wrist = false
    @AppStorage(HapticPrefs.breathing) private var breathing = true
    @AppStorage(HapticPrefs.intervals) private var intervals = true
    @AppStorage(HapticPrefs.liveSession) private var liveSession = true
    @AppStorage(HapticPrefs.workout) private var workout = true

    private var sessionCues: Int { [breathing, intervals, liveSession, workout].filter { $0 }.count }

    var body: some View {
        NunaDetailScreen("Strap automations") {
            Text("Let the strap act: a tap does something, a vibration coaches you, and it tells you things without opening the phone.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            NunaCard(highlight: wrist) {
                NunaToggleRow("Wrist alerts", subtitle: "The master switch for all vibrations. Off means the strap stays silent", systemImage: "bell.badge", isOn: $wrist).padding(.vertical, 8)
            }
            NunaSettingsGroup("Gestures and presence") {
                NavigationLink(value: NunaMeRoute.doubleTap) { NunaListRow("Double tap", subtitle: LocalizedStringKey(behavior.doubleTapAction.label), systemImage: "hand.tap", showsChevron: true) }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.presence) {
                    NunaListRow("Strap on and off", subtitle: "Run a Shortcut when it is put on or taken off", systemImage: "figure.walk.motion", showsChevron: true) {
                        NunaChip(!behavior.wristOnShortcut.isEmpty || !behavior.wristOffShortcut.isEmpty ? "On" : "Off")
                    }
                }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Vibration during activity") {
                NavigationLink(value: NunaMeRoute.sessionCues) { NunaListRow("Session cues", subtitle: "Breathing, intervals, live session, workout start and end", systemImage: "waveform.path", showsChevron: true) { NunaChip(verbatim: String(localized: "\(sessionCues) on")) } }.buttonStyle(.plain)
                NunaDivider()
                NunaToggleRow("Heart-rate zone coaching", subtitle: "Vibrates in the top zone and when you recover", systemImage: "heart", isOn: $behavior.zoneCoaching).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Stress check with vibration", subtitle: "A minute of guided breathing when HRV drops while you are still", systemImage: "wind", isOn: $behavior.stressCheckIn).padding(.vertical, 8)
            }
            NunaSettingsGroup("Reminders") {
                NavigationLink(value: NunaMeRoute.sedentary) {
                    NunaListRow("Sitting too long", subtitle: LocalizedStringKey(inactivity.enabled ? String(localized: "Vibrates after \(inactivity.thresholdMinutes) minutes") : String(localized: "Off")), systemImage: "chair", showsChevron: true)
                }.buttonStyle(.plain)
                NunaDivider()
                NavigationLink(value: NunaMeRoute.notifications) { NunaListRow("Battery, Effort target and reports", subtitle: "Under Notifications", systemImage: "bell", showsChevron: true) }.buttonStyle(.plain)
            }
            NunaSettingsGroup("Siri and Shortcuts") {
                NavigationLink(value: NunaMeRoute.shortcuts) { NunaListRow("Available shortcuts", subtitle: "Sync Strap, breathe, mark a moment, export", systemImage: "square.stack.3d.up", showsChevron: true) }.buttonStyle(.plain)
            }
            nunaFootnote("Every vibration is off until you turn it on. Locking the screen when the strap comes off exists only on Mac, because iPhone does not allow it.")
        }
    }
}

// MARK: - Double tap (AutoDoubleTap.dc)

struct NunaDoubleTapView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    private let options = MacActionKind.allCases.filter { $0 != .lockScreen }
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm"); return f
    }()

    var body: some View {
        NunaDetailScreen("Double tap") {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    NunaIconTile("hand.tap")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tap the strap twice").font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        Text("Then it does what you choose below.").font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer()
                    NunaChip(live.bonded ? "Connected" : "Not connected", color: live.bonded ? NunaPalette.charge : nil)
                }
            }
            NunaSettingsGroup("Action") {
                ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                    if i > 0 { NunaDivider() }
                    Button { behavior.doubleTapAction = o } label: {
                        HStack(spacing: 12) {
                            NunaIconTile(o.symbol)
                            Text(verbatim: o.label).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            Image(systemName: behavior.doubleTapAction == o ? "checkmark.circle.fill" : "circle").font(.nuna(size: 21)).foregroundStyle(behavior.doubleTapAction == o ? NunaPalette.textPrimary : NunaPalette.textMuted)
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if behavior.doubleTapAction == .runShortcut {
                NunaFormField("Shortcut name") { TextField("", text: $behavior.doubleTapShortcut, prompt: Text("The name of your Shortcut").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            Button { model.runMacAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut) } label: {
                Text("Try the action").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: Capsule())
            }.buttonStyle(.plain).disabled(behavior.doubleTapAction == .none).opacity(behavior.doubleTapAction == .none ? 0.4 : 1)
            if !model.moments.isEmpty {
                NunaSettingsGroup("Latest moments") {
                    ForEach(Array(model.moments.suffix(5).reversed().enumerated()), id: \.offset) { i, d in
                        if i > 0 { NunaDivider() }
                        NunaListRow("Mark a moment", subtitle: LocalizedStringKey(Self.fmt.string(from: d)), systemImage: "mappin.and.ellipse")
                    }
                }
                Button { model.moments.removeAll(); UserDefaults.standard.removeObject(forKey: "moments") } label: {
                    Text("Clear").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 46).background(NunaPalette.glassStrong, in: Capsule())
                }.buttonStyle(.plain)
            }
            nunaFootnote("A tap that arrives late during a sync is kept in the strap log but does not run the action.")
        }
    }
}

// MARK: - Strap on and off (AutoPresence.dc)

struct NunaPresenceView: View {
    @EnvironmentObject private var behavior: BehaviorStore
    var body: some View {
        NunaDetailScreen("Strap on and off") {
            NunaFormField("When the strap is taken off") { TextField("", text: $behavior.wristOffShortcut, prompt: Text("Shortcut name, for example Focus on").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled() }
            NunaFormField("When the strap is put on") { TextField("", text: $behavior.wristOnShortcut, prompt: Text("Shortcut name, for example Focus off").foregroundStyle(NunaPalette.textMuted)).textInputAutocapitalization(.never).autocorrectionDisabled() }
            nunaFootnote("Leave a name empty to do nothing. Shortcuts run on this iPhone and send nothing out. Locking the screen when the strap comes off is Mac only.")
        }
    }
}

// MARK: - Session cues

struct NunaSessionCuesView: View {
    @AppStorage(HapticPrefs.breathing) private var breathing = true
    @AppStorage(HapticPrefs.intervals) private var intervals = true
    @AppStorage(HapticPrefs.liveSession) private var liveSession = true
    @AppStorage(HapticPrefs.workout) private var workout = true
    var body: some View {
        NunaDetailScreen("Session cues") {
            Text("Choose which cues vibrate the strap during a session you start.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            NunaSettingsGroup {
                NunaToggleRow("Breathing pacer", subtitle: "Each breath in and out", systemImage: "wind", isOn: $breathing).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Interval timer", subtitle: "Each change of interval", systemImage: "timer", isOn: $intervals).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Live session cues", subtitle: "Coaching during a live workout", systemImage: "figure.run", isOn: $liveSession).padding(.vertical, 8)
                NunaDivider()
                NunaToggleRow("Workout start and end", subtitle: "Confirms a workout starting and saving", systemImage: "play.circle", isOn: $workout).padding(.vertical, 8)
            }
            nunaFootnote("They only vibrate when Wrist alerts is on in Strap automations.")
        }
    }
}

// MARK: - Sitting too long (AutoSedentary.dc)

struct NunaSedentaryView: View {
    @StateObject private var p = InactivityPrefs()
    @AppStorage("notif.masterEnabled") private var wrist = false

    var body: some View {
        NunaDetailScreen("Sitting too long") {
            NunaCard(highlight: p.enabled) {
                NunaToggleRow("Sitting reminder", subtitle: "The strap vibrates when you sit still for too long", systemImage: "chair", isOn: $p.enabled).padding(.vertical, 8)
            }
            if p.enabled {
                if !wrist {
                    NunaCard(small: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Needs the master switch").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.warning)
                            Text("It cannot vibrate while Wrist alerts is off. Turn it on in Strap automations.").font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                NunaSettingsGroup {
                    NunaStepRow(label: "Sitting for", value: "\(p.thresholdMinutes) min", note: "Minutes seated before the first vibration", canDecrement: p.thresholdMinutes > 15,
                                onMinus: { p.thresholdMinutes = max(15, p.thresholdMinutes - 15) }, onPlus: { p.thresholdMinutes = min(120, p.thresholdMinutes + 15) })
                    NunaDivider()
                    NunaStepRow(label: "Repeat every", value: "\(p.reNudgeMinutes) min", note: "If you are still sitting, vibrate again", canDecrement: p.reNudgeMinutes > 15,
                                onMinus: { p.reNudgeMinutes = max(15, p.reNudgeMinutes - 15) }, onPlus: { p.reNudgeMinutes = min(120, p.reNudgeMinutes + 15) })
                    NunaDivider()
                    NunaStepRow(label: "Strength", value: "\(p.buzzLoops)×", note: "How strong the vibration is", canDecrement: p.buzzLoops > 1,
                                onMinus: { p.buzzLoops = max(1, p.buzzLoops - 1) }, onPlus: { p.buzzLoops = min(4, p.buzzLoops + 1) })
                }
                NunaSettingsGroup("Active hours") {
                    NunaToggleRow("Only in active hours", subtitle: "No vibration outside this range", systemImage: "clock", isOn: $p.activeHoursEnabled).padding(.vertical, 8)
                    if p.activeHoursEnabled {
                        NunaDivider()
                        HStack {
                            Text("From").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            DatePicker("", selection: bind($p.activeStartMinutes), displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                            Spacer()
                            Text("Until").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            DatePicker("", selection: bind($p.activeEndMinutes), displayedComponents: .hourAndMinute).labelsHidden().colorScheme(.dark)
                        }.padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func bind(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)) ?? Date() },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
}

// MARK: - Siri and Shortcuts (AutoShortcuts.dc)

struct NunaShortcutsView: View {
    var body: some View {
        NunaDetailScreen("Siri and Shortcuts") {
            Text("Run NOOP actions by voice or from the Shortcuts app. Good for Focus, Sleep mode or the Action button.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
            NunaSettingsGroup {
                NunaListRow("Sync Strap", subtitle: "Pulls the history from the strap", systemImage: "arrow.triangle.2.circlepath")
                NunaDivider()
                NunaListRow("Start breathing", subtitle: "Opens Breathe with vibration", systemImage: "wind")
                NunaDivider()
                NunaListRow("Mark a moment", subtitle: "Marks the current time", systemImage: "mappin.and.ellipse")
                NunaDivider()
                NunaListRow("Export my data", subtitle: "Saves your data to a file", systemImage: "square.and.arrow.up")
            }
            ShortcutsLink().shortcutsLinkStyle(.dark).frame(maxWidth: .infinity, alignment: .leading)
            nunaFootnote("Shortcuts run on this iPhone and send no data out. Add them, and choose Siri phrases, in the Shortcuts app.")
        }
    }
}
#endif

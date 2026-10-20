#if os(iOS)
import SwiftUI
import MuscleMap
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The running gym session in the Nuna look (WorkoutLift.dc). The session itself is the existing `LiftSessionController`
/// that lives above every screen; this is only another face for it, so a session started from either Experience can be
/// continued from the other. Every set is typed here, nothing is estimated, and Effort is never derived from weights.
struct NunaLiftSessionView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    @State private var showingFinish = false
    @State private var confirmingDiscard = false
    @State private var sessionRpeText = ""
    @State private var saving = false
    @State private var unfinishedChoice: UnfinishedChoice?
    @State private var programChoice: ProgramChoice?
    @State private var setCountChanges: [LiftSessionController.SetCountChange] = []
    /// Exercises the user opened by hand, on top of the one being worked.
    @State private var opened: Set<Int> = []
    /// The library entry whose demo is open in a sheet.
    @State private var demo: NunaLibraryExercise?
    @State private var pickingExercise = false
    @State private var showingSettings = false
    /// The RPE column is hidden until asked for, as in most logs; the typed values are kept either way.
    @AppStorage("nuna.gym.showRpe") private var showRpe = false
    /// A sound when a rest period ends.
    @AppStorage(AudioCoachingPreferences.restEndSoundKey) private var restEndSound = true
    @State private var draft: [FocusTarget: String] = [:]
    /// Set when the saved session's summary is about to replace this screen, so the session going away does not close it.
    @State private var showingSummary = false
    @FocusState private var focused: FocusTarget?
    /// The set whose hold is being timed, and when it started.
    @State private var timing: (slot: LiftSlot, since: Date)?
    /// The exercise whose how-to video is open, for the ones the library has no demo for.
    @State private var video: String?

    private enum UnfinishedChoice: Hashable { case complete, discard }
    private enum ProgramChoice: Hashable { case update, keep }
    private enum FocusTarget: Hashable { case weight(LiftSlot), reps(LiftSlot), time(LiftSlot), rpe(LiftSlot), sessionRpe }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var engine: LiftSessionEngine? { session.engine }
    private let setColumn: CGFloat = 30, kgColumn: CGFloat = 66, repsColumn: CGFloat = 56, rpeColumn: CGFloat = 46, timeColumn: CGFloat = 96

    var body: some View {
        ZStack {
            NunaPalette.canvas.ignoresSafeArea()
            if let engine {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: NunaSpacing.section) {
                                header(engine)
                                if let name = session.programName {
                                    // The whole name, under the header, however long it is.
                                    Text(verbatim: name).font(.nuna(size: NunaTypeSize.h2, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true).textCase(nil)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                statsCard(engine)
                                statusCard(engine)
                                ForEach(Array(engine.plan.enumerated()), id: \.offset) { i, item in exerciseCard(engine, index: i, item: item).id(i) }
                                musclesCard(engine)
                                bottomButtons
                            }
                            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: engine.currentSlot) { slot in
                            guard let slot else { return }
                            withAnimation { proxy.scrollTo(slot.exerciseIndex, anchor: .top) }
                        }
                    }
                    controlBar(engine)
                }
            } else {
                Text("No session running").font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focused = nil }
        } }
        .task { await loadLastTime() }
        // A screen with no session behind it has nothing to show: it closes itself, in case the presenter's own dismissal was ignored
        // (UIKit drops a dismissal asked for while another one is still running).
        .onChange(of: session.engine == nil) { _, gone in if gone, !showingSummary { dismiss() } }
        .onChange(of: focused) { now in draft = draft.filter { $0.key == now } }
        .sheet(isPresented: $showingFinish) { finishSheet }
        .sheet(item: $demo) { e in
            NavigationStack { NunaExerciseDetailView(exerciseId: e.id) }
                .preferredColorScheme(NunaTheme.colorScheme).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $pickingExercise) {
            NunaExercisePicker(confirm: { $0 == 1 ? String(localized: "Add 1 exercise") : String(localized: "Add \($0) exercises") }, title: "Add exercise") { picked in addExercises(picked) }
        }
        .sheet(isPresented: $showingSettings) { settingsSheet }
        .sheet(item: Binding(get: { video.map { NunaVideoTarget(name: $0) } }, set: { video = $0?.name })) { t in NunaExerciseVideoSheet(name: t.name) }
    }

    /// Exercises added in the gym go to the end of the session, three sets each, and open so the first set can be typed.
    private func addExercises(_ picked: [NunaPickedExercise]) {
        var firstNew: Int?
        for p in picked {
            let before = session.engine?.plan.count ?? 0
            if session.addExercise(LiftPlanItem(exercise: p.name, primaryMuscle: p.primary, secondaryMuscles: p.secondary, targetSets: 3)) {
                if firstNew == nil { firstNew = before }
            }
        }
        if let i = firstNew { opened.insert(i) }
        Task { await loadLastTime() }
    }

    private var settingsSheet: some View {
        NavigationStack {
            NunaDetailScreen("Session settings") {
                NunaCard(small: true) {
                    NunaToggleRow("Sound when rest ends", subtitle: "A short rising tone; music is lowered for it", systemImage: "speaker.wave.2", isOn: $restEndSound)
                }
                NunaCard(small: true) {
                    NunaToggleRow("RPE column", subtitle: "How hard each set felt, from 1 to 10", systemImage: "gauge.with.needle", isOn: $showRpe)
                }
                nunaFootnote("Hidden or shown, what you typed is kept.")
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(NunaTheme.colorScheme).presentationDetents([.medium]).presentationDragIndicator(.visible)
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button { pickingExercise = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.nuna(size: 15, weight: .bold))
                    Text("Add exercise").font(.nuna(size: 16.5, weight: .bold))
                }
                .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    // MARK: Header, figures, status

    private func header(_ engine: LiftSessionEngine) -> some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("Minimise"))
            Text(session.programName == nil ? "Gym" : "Program gym")
                .font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let bpm = model.bpm {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.alert)
                    Text(verbatim: "\(bpm)").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).monospacedDigit()
                }
                .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 10).frame(height: 36)
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }
            Button { showingSettings = true } label: { NunaBareIcon("slider.horizontal.3", target: 40) }
                .buttonStyle(.plain).accessibilityLabel(Text("Settings"))
            Button {
                unfinishedChoice = nil; programChoice = nil; setCountChanges = []
                showingFinish = true
            } label: {
                Text("Finish").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .padding(.horizontal, 18).frame(height: 40).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Figures

    /// Duration, volume and sets, with the body on the right showing which muscles the session has reached.
    private func statsCard(_ engine: LiftSessionEngine) -> some View {
        let volume = engine.sets.filter { !$0.isWarmup }.reduce(0.0) { acc, s in
            let v = session.enteredValues(for: s.slot)
            return acc + (v.weightKg ?? 0) * Double(v.reps ?? 0)
        }
        return NunaCard(small: true) {
            HStack(alignment: .center, spacing: 14) {
                stat("Duration", LiftFormat.duration(max(0, session.now - engine.startTs)), nil)
                stat("Volume", volume > 0 ? NunaTrendsFormat.num(volume) : "0", UnitFormatter.massUnit(system))
                stat("Sets", "\(engine.completedWorkingSets)/\(engine.plannedWorkingSets)", nil)
                Spacer(minLength: 0)
                miniBodies(engine)
            }
        }
    }

    private func stat(_ l: LocalizedStringKey, _ v: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: v).font(.nuna(size: 19, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(verbatim: unit).font(.nuna(size: 10.5, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
            }
        }
    }

    /// How far each part of the body is through its planned sets: a faint tint for the muscles in the plan, warming up as their sets are done.
    private func miniBodies(_ engine: LiftSessionEngine) -> some View {
        var level: [Muscle: Double] = [:]
        for (i, item) in engine.plan.enumerated() {
            let slots = engine.slots(forExercise: i)
            let done = Double(slots.filter { engine.isCompleted($0) }.count) / Double(max(slots.count, 1))
            if let p = item.primaryMuscle { level[p.bodyMap] = max(level[p.bodyMap] ?? 0, 0.18 + 0.82 * done) }
            for m in item.secondaryMuscles { level[m.bodyMap] = max(level[m.bodyMap] ?? 0, 0.12 + 0.4 * done) }
        }
        let data = level.map { MuscleIntensity(muscle: $0.key, intensity: $0.value) }
        return HStack(spacing: 0) {
            ForEach(BodySide.allCases, id: \.self) { side in
                BodyView(gender: .male, side: side).heatmap(data, colorScale: .workout).frame(width: 38, height: 78)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func statusCard(_ engine: LiftSessionEngine) -> some View {
        switch engine.stage {
        case .resting(let slot, _):
            let remaining = engine.restRemaining(now: session.now) ?? 0
            let total = Double(max(engine.planItem(for: slot)?.restSec ?? LiftPlanItem.defaultRestSec, 1))
            let done = engine.allCompleted
            NunaCard(highlight: true) {
                HStack(spacing: 16) {
                    NunaRingGauge(fraction: done ? 1 : min(1, Double(remaining) / total), color: NunaPalette.rest, size: 96, lineWidth: 8) {
                        Text(verbatim: LiftFormat.duration(remaining)).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest period").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.restText)
                        Text(verbatim: done ? String(localized: "All sets done") : String(localized: "Set \(engine.slotAfter(slot)?.setIndex ?? slot.setIndex) is ready soon"))
                            .font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            restChip("−15 s") { session.adjustRest(by: -15) }
                            restChip("+15 s") { session.adjustRest(by: 15) }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        case .working:
            NunaCard(highlight: true) {
                HStack(spacing: 14) {
                    Text(verbatim: LiftFormat.duration(max(0, session.now - engine.stageStartedAt))).font(.nuna(size: 30, weight: .bold, design: NunaType.design)).monospacedDigit().foregroundStyle(NunaPalette.textPrimary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This set").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.charge)
                        Text("Tap Set done when you finish").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 0)
                }
            }
        default:
            NunaCard(small: true) {
                Text("Start the first set when you are ready.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func restChip(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: t).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 34).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Exercises

    private func isOpen(_ engine: LiftSessionEngine, _ index: Int) -> Bool {
        opened.contains(index) || engine.currentSlot?.exerciseIndex == index
            || (engine.currentSlot == nil && index == 0)
    }

    @ViewBuilder private func exerciseCard(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem) -> some View {
        let slots = engine.slots(forExercise: index)
        let done = slots.filter { engine.isCompleted($0) }.count
        let lib = NunaExerciseLibrary.match(item.exercise)
        let kind = NunaExerciseKind.of(item.exercise)
        if isOpen(engine, index) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Button { if let lib { demo = lib } else { video = item.exercise } } label: { NunaExerciseThumb(lib, width: 58, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel(lib == nil ? Text("Watch a video") : Text("Show the demo"))
                        Button { if let lib { demo = lib } else { video = item.exercise } } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: item.exercise).font(.nuna(size: 18, weight: .bold)).foregroundStyle(lib == nil ? NunaPalette.textPrimary : NunaPalette.restText).multilineTextAlignment(.leading).lineLimit(2)
                                Text(verbatim: LiftMuscleSummary.line(primary: item.primaryMuscle, secondaries: item.secondaryMuscles)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Text(verbatim: "\(done)/\(slots.count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                        exerciseMenu(engine, index: index, item: item, lib: lib)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(verbatim: note).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(4).padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading).background(NunaPalette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "timer").font(.nuna(size: 14, weight: .semibold))
                        Text(verbatim: String(localized: "Rest timer: \(LiftFormat.duration(item.restSec))")).font(.nuna(size: 14, weight: .bold)).textCase(nil)
                    }.foregroundStyle(NunaPalette.restText)
                    columnHeadings(kind)
                    VStack(spacing: 6) { ForEach(slots, id: \.self) { slot in setRow(engine, slot: slot, kind: kind) } }
                    if lib == nil {
                        Button { video = item.exercise } label: {
                            HStack(spacing: 8) { Image(systemName: "play.rectangle.fill").font(.nuna(size: 14, weight: .semibold)); Text("Watch how it is done").font(.nuna(size: 14, weight: .bold)) }
                                .foregroundStyle(NunaPalette.restText).frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(.plain)
                    }
                    Button { session.addSet(toExercise: index) } label: {
                        HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 13, weight: .bold)); Text("Add set").font(.nuna(size: 14.5, weight: .bold)) }
                            .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain).disabled(item.targetSets >= LiftSessionEngine.maxSetsPerExercise)
                }
            }
        } else {
            NunaCard(small: true) {
                HStack(spacing: 12) {
                    Button { opened.insert(index) } label: {
                        HStack(spacing: 12) {
                            NunaExerciseThumb(lib, width: 50, height: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: item.exercise).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading)
                                Text(verbatim: collapsedLine(item, done: done, total: slots.count)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    /// The three dots of an exercise: its demo, one set more or fewer, the RPE column, and folding it away.
    private func exerciseMenu(_ engine: LiftSessionEngine, index: Int, item: LiftPlanItem, lib: NunaLibraryExercise?) -> some View {
        Menu {
            if let lib { Button { demo = lib } label: { Label("Show the demo", systemImage: "play.rectangle") } }
            else { Button { video = item.exercise } label: { Label("Watch a video", systemImage: "play.rectangle") } }
            if NunaExerciseKind.natural(item.exercise) == .bodyweight {
                let tracks = NunaExerciseKind.weightOverrides.contains(item.exercise)
                Button { NunaExerciseKind.setTracksWeight(!tracks, for: item.exercise) } label: {
                    Label(tracks ? "Bodyweight only" : "Add weight", systemImage: tracks ? "figure.stand" : "scalemass")
                }
            }
            Button { session.addSet(toExercise: index) } label: { Label("Add set", systemImage: "plus") }
                .disabled(item.targetSets >= LiftSessionEngine.maxSetsPerExercise)
            Button { session.removeSet(fromExercise: index) } label: { Label("Remove last set", systemImage: "minus") }
                .disabled(!engine.canRemoveSet(fromExercise: index))
            Button { showRpe.toggle() } label: { Label(showRpe ? "Hide RPE" : "Show RPE", systemImage: "gauge.with.needle") }
            Button { opened.remove(index) } label: { Label("Fold away", systemImage: "chevron.up") }
        } label: {
            Image(systemName: "ellipsis").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).rotationEffect(.degrees(90))
                .frame(width: 34, height: 40).contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More"))
    }

    private func collapsedLine(_ item: LiftPlanItem, done: Int, total: Int) -> String {
        let muscle = item.primaryMuscle?.displayName ?? String(localized: "Not classified")
        if done == 0 { return muscle + " · " + String(localized: "\(total) sets not started") }
        if done == total { return muscle + " · " + String(localized: "\(total) sets done") }
        return muscle + " · " + String(localized: "\(done) of \(total) sets done")
    }

    private func columnHeadings(_ kind: NunaExerciseKind) -> some View {
        HStack(spacing: 8) {
            Text("Set").frame(width: setColumn, alignment: .center)
            Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
            if kind == .weighted { Text(system == .imperial ? "Lb" : "Kg").frame(width: kgColumn, alignment: .center) }
            if kind == .timed { Text("Time").frame(width: timeColumn, alignment: .center) } else { Text("Reps").frame(width: repsColumn, alignment: .center) }
            if showRpe { Text("RPE").frame(width: rpeColumn, alignment: .center) }
        }
        .font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    /// What the last session did on this set, or what the previous set of this one did: "60 kg × 8".
    private func previousText(_ slot: LiftSlot, kind: NunaExerciseKind) -> String {
        let c = session.carry(for: slot)
        switch kind {
        case .timed: return c.reps.map(NunaExerciseKind.clock) ?? "—"
        case .bodyweight: return c.reps.map { "× \($0)" } ?? "—"
        case .weighted:
            switch (c.weightKg, c.reps) {
            case let (w?, r?): return "\(display(w)) \(UnitFormatter.massUnit(system)) × \(r)"
            case let (w?, nil): return "\(display(w)) \(UnitFormatter.massUnit(system))"
            case let (nil, r?): return "× \(r)"
            default: return "—"
            }
        }
    }

    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot, kind: NunaExerciseKind) -> some View {
        let recorded = engine.recordedSet(for: slot)
        let isWorking = engine.stage == .working(slot)
        let warm = session.isWarmup(slot)
        return HStack(spacing: 8) {
            Button { session.setWarmup(slot, !warm) } label: {
                Text(verbatim: warm ? String(localized: "W") : "\(slot.setIndex)").font(.nuna(size: 15, weight: .bold, design: NunaType.design))
                    .foregroundStyle(warm ? NunaPalette.warning : (isWorking ? NunaPalette.restText : NunaPalette.textPrimary))
                    .frame(width: setColumn, height: 40).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous)).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(warm ? Text("Warm-up set — tap to make it a working set") : Text("Set \(slot.setIndex) — tap to mark it a warm-up"))
            Group {
                if isWorking {
                    HStack(spacing: 6) {
                        stepButton("minus") { stepSet(slot, kind, -1) }; stepButton("plus") { stepSet(slot, kind, 1) }
                    }
                } else {
                    Text(verbatim: previousText(slot, kind: kind)).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if kind == .weighted {
                field(text: weightBinding(slot), ghost: ghostWeight(slot), target: .weight(slot), decimal: true, big: isWorking, done: recorded != nil).frame(width: kgColumn)
            }
            if kind == .timed {
                timeField(slot, isWorking: isWorking, done: recorded != nil).frame(width: timeColumn)
            } else {
                field(text: repsBinding(slot), ghost: ghostReps(slot), target: .reps(slot), decimal: false, big: isWorking, done: recorded != nil).frame(width: repsColumn)
            }
            if showRpe { field(text: rpeBinding(slot), ghost: ghostRpe(engine, slot: slot), target: .rpe(slot), decimal: true, big: false, done: recorded != nil).frame(width: rpeColumn) }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(isWorking ? NunaPalette.rest.opacity(0.14) : (recorded != nil ? NunaPalette.charge.opacity(0.10) : Color.clear), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .nunaSwipeToDelete(enabled: engine.canRemoveSet(slot)) { removeSet(slot) }
    }

    /// Delete one set. The numbers being typed or timed for that exercise are let go with it, because the rows below move up.
    private func removeSet(_ slot: LiftSlot) {
        if timing?.slot.exerciseIndex == slot.exerciseIndex { timing = nil }
        focused = nil
        draft = [:]
        withAnimation(.easeOut(duration: 0.2)) { _ = session.removeSet(slot) }
    }

    private func field(text: Binding<String>, ghost: String, target: FocusTarget, decimal: Bool, big: Bool, done: Bool) -> some View {
        TextField("", text: text, prompt: Text(verbatim: ghost).foregroundStyle(NunaPalette.textMuted))
            .font(.nuna(size: big ? 19 : 16.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            .multilineTextAlignment(.center)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .focused($focused, equals: target)
            .frame(height: 40)
            .background(done ? NunaPalette.charge.opacity(0.16) : NunaPalette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// A hold: a play button that times it, and the time as 00:45. Typing "45" or "1:05" works too.
    private func timeField(_ slot: LiftSlot, isWorking: Bool, done: Bool) -> some View {
        let running = timing?.slot == slot
        return HStack(spacing: 6) {
            Button { toggleTimer(slot) } label: {
                Image(systemName: running ? "stop.fill" : "play.fill").font(.nuna(size: 12, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 30, height: 30).background(NunaPalette.rest, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(running ? Text("Stop the timer") : Text("Time this set"))
            if running, let since = timing?.since {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(verbatim: NunaExerciseKind.clock(Int(ctx.date.timeIntervalSince(since))))
                        .font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.restText).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 40).background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            } else {
                TextField("", text: timeBinding(slot), prompt: Text(verbatim: ghostTime(slot)).foregroundStyle(NunaPalette.textMuted))
                    .font(.nuna(size: isWorking ? 17 : 15.5, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).monospacedDigit()
                    .multilineTextAlignment(.center).keyboardType(.numbersAndPunctuation)
                    .focused($focused, equals: .time(slot)).frame(height: 40)
                    .background(done ? NunaPalette.charge.opacity(0.16) : NunaPalette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    /// Starts timing the hold of a set (and the set with it), or stops, writes the seconds and finishes the set.
    private func toggleTimer(_ slot: LiftSlot) {
        if let t = timing, t.slot == slot {
            let secs = max(1, Int(Date().timeIntervalSince(t.since)))
            timing = nil
            draft[.time(slot)] = nil
            write(slot) { $0.reps = secs }
            if engine?.stage == .working(slot) { session.advance() }
        } else {
            if let t = timing { write(t.slot) { $0.reps = max(1, Int(Date().timeIntervalSince(t.since))) } }
            if engine?.stage != .working(slot) { session.start(slot) }
            timing = (slot, Date())
        }
    }

    /// One step of the working set's number: weight for a barbell lift, reps for a bodyweight one, five seconds for a hold.
    private func stepSet(_ slot: LiftSlot, _ kind: NunaExerciseKind, _ direction: Int) {
        switch kind {
        case .weighted: bump(slot, step * Double(direction))
        case .bodyweight:
            let cur = session.enteredValues(for: slot).reps ?? session.carry(for: slot).reps ?? 0
            draft[.reps(slot)] = nil
            write(slot) { $0.reps = max(0, cur + direction) }
        case .timed:
            let cur = session.enteredValues(for: slot).reps ?? session.carry(for: slot).reps ?? 0
            draft[.time(slot)] = nil
            write(slot) { $0.reps = max(0, cur + 5 * direction) }
        }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 28, height: 28)
        }.buttonStyle(.plain)
    }

    private var step: Double { system == .imperial ? 5 : 2.5 }

    /// Move the typed weight by one step, starting from the grey number when nothing was typed.
    private func bump(_ slot: LiftSlot, _ delta: Double) {
        let current = session.enteredValues(for: slot).weightKg ?? session.carry(for: slot).weightKg ?? 0
        let shown = LiftFormat.display(fromKilograms: current, system: system)
        let kg = LiftFormat.kilograms(fromDisplay: max(0, shown + delta), system: system)
        draft[.weight(slot)] = nil
        write(slot) { $0.weightKg = kg }
    }

    // MARK: Muscles

    private func muscleRows(_ engine: LiftSessionEngine) -> [(key: LiftMuscle, value: Double)] {
        var vol: [LiftMuscle: Double] = [:]
        for s in engine.sets where !s.isWarmup {
            guard let mu = engine.planItem(for: s.slot)?.primaryMuscle else { continue }
            let v = session.enteredValues(for: s.slot)
            vol[mu, default: 0] += (v.weightKg ?? 0) * Double(v.reps ?? 0)
        }
        return vol.filter { $0.value > 0 }.sorted { $0.value > $1.value }
    }

    @ViewBuilder private func musclesCard(_ engine: LiftSessionEngine) -> some View {
        let rows = muscleRows(engine)
        if !rows.isEmpty {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    nunaTrendsCap("Muscles trained")
                    ForEach(rows, id: \.key) { mu, v in
                        VStack(spacing: 6) {
                            HStack { Text(verbatim: mu.displayName).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary); Spacer()
                                Text(verbatim: NunaTrendsFormat.num(v) + " " + UnitFormatter.massUnit(system)).font(.nuna(size: 16, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary) }
                            NunaProgressBar(fraction: v / (rows.first?.value ?? 1), color: NunaPalette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Control bar

    private func controlBar(_ engine: LiftSessionEngine) -> some View {
        HStack(spacing: 12) {
            Button { session.undo() } label: {
                Image(systemName: "arrow.uturn.backward").font(.nuna(size: 16, weight: .bold))
                    .foregroundStyle(engine.canUndo ? NunaPalette.textPrimary : NunaPalette.textMuted)
                    .frame(width: 56, height: 56)
            }.buttonStyle(.plain).disabled(!engine.canUndo).accessibilityLabel(Text("Undo"))
            Button { session.advance() } label: {
                Text(actionLabel(engine)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 10).padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(NunaPalette.hairline).frame(height: 0.5) }
    }

    private func actionLabel(_ engine: LiftSessionEngine) -> LocalizedStringKey {
        switch engine.stage {
        case .warmup: return "Start first set"
        case .working: return "Set done"
        case .resting: return engine.allCompleted ? "All sets done" : "Start next set"
        case .finished: return "Saving…"
        }
    }

    // MARK: Ghost values and bindings (same chain as the Default sheet)

    private func ghostWeight(_ slot: LiftSlot) -> String { session.carry(for: slot).weightKg.map { display($0) } ?? "—" }
    private func ghostReps(_ slot: LiftSlot) -> String { session.carry(for: slot).reps.map(String.init) ?? "—" }
    private func ghostTime(_ slot: LiftSlot) -> String { session.carry(for: slot).reps.map(NunaExerciseKind.clock) ?? "00:00" }
    private func ghostRpe(_ engine: LiftSessionEngine, slot: LiftSlot) -> String { engine.previousSetInSession(for: slot)?.rpe.map { LiftFormat.trim($0) } ?? "—" }
    private func display(_ kg: Double) -> String { LiftFormat.trim(LiftFormat.display(fromKilograms: kg, system: system)) }

    private func fieldBinding(_ f: FocusTarget, formatted: @escaping () -> String, store: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { draft[f] ?? formatted() }, set: { typed in
            let text = typed.replacingOccurrences(of: ",", with: ".")
            draft[f] = text
            store(text)
        })
    }

    private func weightBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.weight(slot), formatted: { session.enteredValues(for: slot).weightKg.map { display($0) } ?? "" }, store: { text in
            let kg = LiftFormat.number(text).map { LiftFormat.kilograms(fromDisplay: $0, system: system) }
            write(slot) { $0.weightKg = kg }
        })
    }
    private func repsBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.reps(slot), formatted: { session.enteredValues(for: slot).reps.map(String.init) ?? "" }, store: { text in
            write(slot) { $0.reps = Int(text.trimmingCharacters(in: .whitespaces)) }
        })
    }
    private func timeBinding(_ slot: LiftSlot) -> Binding<String> {
        Binding(get: { draft[.time(slot)] ?? session.enteredValues(for: slot).reps.map(NunaExerciseKind.clock) ?? "" }, set: { typed in
            draft[.time(slot)] = typed
            // Stored as soon as it reads as a time; a half-typed "1:" waits.
            write(slot) { $0.reps = typed.trimmingCharacters(in: .whitespaces).isEmpty ? nil : NunaExerciseKind.seconds(from: typed) ?? $0.reps }
        })
    }
    private func rpeBinding(_ slot: LiftSlot) -> Binding<String> {
        fieldBinding(.rpe(slot), formatted: { session.enteredValues(for: slot).rpe.map { LiftFormat.trim($0) } ?? "" }, store: { text in
            write(slot) { $0.rpe = LiftFormat.number(text) }
        })
    }

    private func write(_ slot: LiftSlot, _ mutate: (inout LiftRecordedSet) -> Void) {
        let e = session.enteredValues(for: slot)
        var row = LiftRecordedSet(exerciseIndex: slot.exerciseIndex, setIndex: slot.setIndex, weightKg: e.weightKg, reps: e.reps, rpe: e.rpe,
                                  isWarmup: session.isWarmup(slot), startTs: 0, endTs: 0, restSec: nil)
        mutate(&row)
        session.updateSet(slot, weightKg: row.weightKg, reps: row.reps, rpe: row.rpe, isWarmup: row.isWarmup)
    }

    // MARK: Finish

    private var finishSheet: some View {
        let unfinished = session.unfinishedSlots.count
        let answered = (unfinished == 0 || unfinishedChoice != nil) && (setCountChanges.isEmpty || programChoice != nil)
        return NavigationStack {
            NunaDetailScreen("Finish session") {
                NunaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        nunaTrendsCap("How hard was the whole session? (1–10)")
                        NunaFormField("Session RPE") {
                            TextField("", text: $sessionRpeText, prompt: Text("7").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad).focused($focused, equals: .sessionRpe)
                        }
                        Text("This is session RPE. Multiplied by the session's length it gives session load — the one figure that compares across completely different training.")
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }
                }
                if unfinished > 0 {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            nunaTrendsCap("Unfinished sets")
                            Text("\(unfinished) sets have no numbers typed in — sets you did not start, or finished without typing.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            NunaSegmented([(value: UnfinishedChoice?.some(.complete), title: "Complete them"), (value: UnfinishedChoice?.some(.discard), title: "Discard them")], selection: $unfinishedChoice)
                            Text("Completing saves them with the grey numbers shown. Discarding leaves them out of the session.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                    }
                }
                if !setCountChanges.isEmpty {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            nunaTrendsCap("Program")
                            Text("You changed the number of sets. Keep the new counts in the program for next time?").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            ForEach(setCountChanges, id: \.itemId) { c in
                                Text("\(c.exercise): \(c.from) → \(c.to) sets").font(.nuna(size: 14, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            NunaSegmented([(value: ProgramChoice?.some(.update), title: "Update program"), (value: ProgramChoice?.some(.keep), title: "Keep as it was")], selection: $programChoice)
                        }
                    }
                }
                Button { Task { await save() } } label: {
                    Text("Save session").font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(saving || !answered).opacity(saving || !answered ? 0.4 : 1)
                if !answered { Text("Choose an option above to save.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil) }
                Button(role: .destructive) { confirmingDiscard = true } label: {
                    Text("Discard session").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText).frame(maxWidth: .infinity).frame(height: 52).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(saving)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } } }
        }
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await loadSetCountChanges() }
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { Task { await closeScreen(); session.discard(); showingFinish = false } }
            Button("Keep going", role: .cancel) {}
        } message: { Text("\(engine?.completedWorkingSets ?? 0) recorded sets will be thrown away. Nothing is saved and no workout is created.") }
    }

    // MARK: Loading and saving (same rules as the Default sheet)

    private func loadLastTime() async {
        guard let engine, let store = await repo.storeHandle() else { return }
        var out: [String: [Int: LiftSetCarry]] = [:]
        for exercise in NSOrderedSet(array: engine.plan.map(\.exercise)).compactMap({ $0 as? String }) {
            let rows = (try? await store.lastLiftSets(deviceId: repo.deviceId, exercise: exercise, before: engine.startTs)) ?? []
            var bySet: [Int: LiftSetCarry] = [:]
            for r in rows where !r.isWarmup { bySet[r.setIndex] = LiftSetCarry(weightKg: r.weightKg, reps: r.reps) }
            out[exercise] = bySet
        }
        session.setLastSession(out)
    }

    private func save() async {
        guard !saving, let store = await repo.storeHandle() else { return }
        saving = true; defer { saving = false }
        session.finish()
        guard let engine = session.engine else { return }
        let endTs = Int(Date().timeIntervalSince1970)
        let sessionId = UUID().uuidString
        let finished = session.setsToSave(completingUnfinished: unfinishedChoice == .complete)
        guard !finished.isEmpty else {
            if programChoice == .update { await writeSetCountsToProgram(store: store, plan: engine.plan) }
            await finishAndDismiss()
            return
        }
        let row = LiftSessionRow(id: sessionId, deviceId: repo.deviceId, startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport,
                                 programId: session.programId, programName: session.programName,
                                 sessionRpe: LiftFormat.number(sessionRpeText), note: session.programName)
        _ = try? await store.upsertLiftSessions([row])
        let rows = finished.enumerated().map { ord, s -> LiftSetRow in
            let item = engine.planItem(for: s.slot)
            return LiftSetRow(id: UUID().uuidString, deviceId: repo.deviceId, sessionId: sessionId, ord: ord, exercise: item?.exercise ?? "",
                              primaryMuscle: item?.primaryMuscle, secondaryMuscles: item?.secondaryMuscles ?? [],
                              setIndex: s.slot.setIndex, weightKg: s.weightKg, reps: s.reps, rpe: s.rpe, isWarmup: s.isWarmup,
                              startTs: s.startTs, endTs: s.endTs, restSec: s.restSec, note: nil)
        }
        _ = try? await store.upsertLiftSets(rows)
        if programChoice == .update { await writeSetCountsToProgram(store: store, plan: engine.plan) }
        // Through the same path a manual workout takes; strain stays nil so the engine fills it from the measured heart rate.
        let workout = WorkoutRow(startTs: engine.startTs, endTs: endTs, sport: LiftSessionView.sport, source: "manual",
                                 durationS: Double(max(0, endTs - engine.startTs)), energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                                 distanceM: nil, zonesJSON: nil, notes: session.programName, steps: nil)
        await repo.saveManualWorkout(workout)
        // A session logged here may go to Strava (one that came from Hevy or Apple Health never does, see `StravaOwnGym`). In automatic mode
        // it goes now, from the workout as the lists read it, with the heart rate the strap measured filled in.
        StravaOwnGym.add(startTs: workout.startTs, sport: workout.sport)
        let repo = self.repo
        Task {
            await repo.refresh()
            if let row = await repo.workoutRows().first(where: { $0.startTs == workout.startTs && $0.sport == workout.sport }) {
                await StravaAutoUploadCoordinator.uploadIfNeeded(row)
            }
        }
        await finishAndShowSummary(sessionId)
    }

    /// The session is saved: its finish sheet closes and the screen turns into the summary page, with no trip back to the Gym tab.
    private func finishAndShowSummary(_ sessionId: String) async {
        showingSummary = true
        showingFinish = false
        await repo.refresh()
        try? await Task.sleep(nanoseconds: 600_000_000)
        session.finishedSaving(summaryId: sessionId)
    }

    /// Starts the screen's slide down and waits for it to end.
    private func closeScreen() async {
        session.isPresented = false
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    private func finishAndDismiss() async {
        // The screen slides away with its content still on it; only then is the session taken down. Taken down first, the page read
        // "No session running" for the whole slide, and for as long as the refresh below kept the main thread busy.
        await closeScreen()
        session.finishedSaving()
        await repo.refresh()
        showingFinish = false
        dismiss()
    }

    private func loadSetCountChanges() async {
        guard let programId = session.programId, let plan = session.engine?.plan, let store = await repo.storeHandle(),
              let rows = try? await store.liftProgramItems(programId: programId) else { return }
        setCountChanges = LiftSessionController.setCountChanges(plan: plan, program: rows)
    }

    private func writeSetCountsToProgram(store: WhoopStore, plan: [LiftPlanItem]) async {
        guard let programId = session.programId, let rows = try? await store.liftProgramItems(programId: programId) else { return }
        let changes = LiftSessionController.setCountChanges(plan: plan, program: rows)
        guard !changes.isEmpty else { return }
        _ = try? await store.replaceLiftProgramItems(programId: programId, items: LiftSessionController.applying(changes, to: rows))
    }
}

/// The minimised session in the Nuna look: the exercise, the clock and a tap to open. Sits above the tab bar.
struct NunaLiftBar: View {
    @EnvironmentObject private var session: LiftSessionController

    var body: some View {
        if session.isActive, !session.isPresented, let e = session.engine {
            Button { session.present() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: session.programName ?? String(localized: "Gym session")).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                        Text(verbatim: "\(e.completedWorkingSets)/\(e.plannedWorkingSets) · " + LiftFormat.duration(max(0, session.now - e.startTs)))
                            .font(.nuna(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer()
                    Text("Open").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.onAccent).padding(.horizontal, 16).frame(height: 34).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NunaPalette.canvas))
                .background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
                .padding(.horizontal, 12).padding(.bottom, 6)
            }.buttonStyle(.plain)
        }
    }
}

/// Swipe a row to the left to reveal a red Delete button, as in a list. A tap on the row, or a swipe back, closes it again.
private struct NunaSwipeToDelete: ViewModifier {
    let enabled: Bool
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat?
    private let reveal: CGFloat = 84

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) { offset = 0; onDelete() } label: {
                    Text("Delete").font(.nuna(size: 14, weight: .bold)).foregroundStyle(Color.white)
                        .frame(width: reveal - 6, height: 40).background(NunaPalette.alert, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain).frame(width: -offset, alignment: .trailing).clipped()
            }
            content.offset(x: offset)
                .simultaneousGesture(DragGesture(minimumDistance: 16).onChanged { g in
                    guard enabled, abs(g.translation.width) > abs(g.translation.height) else { return }
                    let from = start ?? offset
                    start = from
                    offset = min(0, max(-reveal, from + g.translation.width))
                }.onEnded { _ in
                    start = nil
                    guard enabled else { return }
                    withAnimation(.easeOut(duration: 0.18)) { offset = offset < -reveal / 2 ? -reveal : 0 }
                })
        }
    }
}

private extension View {
    func nunaSwipeToDelete(enabled: Bool, onDelete: @escaping () -> Void) -> some View { modifier(NunaSwipeToDelete(enabled: enabled, onDelete: onDelete)) }
}
#endif

#if os(iOS)
import SwiftUI
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
    @State private var draft: [FocusTarget: String] = [:]
    @FocusState private var focused: FocusTarget?

    private enum UnfinishedChoice: Hashable { case complete, discard }
    private enum ProgramChoice: Hashable { case update, keep }
    private enum FocusTarget: Hashable { case weight(LiftSlot), reps(LiftSlot), rpe(LiftSlot), sessionRpe }

    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var engine: LiftSessionEngine? { session.engine }
    private let setColumn: CGFloat = 30, tickColumn: CGFloat = 30, repsColumn: CGFloat = 54, rpeColumn: CGFloat = 46

    var body: some View {
        ZStack {
            NunaPalette.canvas.ignoresSafeArea()
            if let engine {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: NunaSpacing.section) {
                                header(engine)
                                statsRow(engine)
                                statusCard(engine)
                                ForEach(Array(engine.plan.enumerated()), id: \.offset) { i, item in exerciseCard(engine, index: i, item: item).id(i) }
                                musclesCard(engine)
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
        .presentationDragIndicator(.visible)
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focused = nil }
        } }
        .task { await loadLastTime() }
        .onChange(of: focused) { now in draft = draft.filter { $0.key == now } }
        .sheet(isPresented: $showingFinish) { finishSheet }
    }

    // MARK: Header, figures, status

    private func header(_ engine: LiftSessionEngine) -> some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous).strokeBorder(NunaPalette.hairline, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel(Text("Minimise"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.programName.map { String(localized: "Gym session · \($0)") } ?? String(localized: "Gym session"))
                    .font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1)
                Text("Lift Log").font(.nuna(size: 24, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Circle().fill(NunaPalette.alert).frame(width: 8, height: 8)
                Text(verbatim: LiftFormat.duration(max(0, session.now - engine.startTs))).font(.nuna(size: 14.5, weight: .bold, design: NunaType.design)).monospacedDigit()
            }
            .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }
    }

    private func statsRow(_ engine: LiftSessionEngine) -> some View {
        let volume = engine.sets.filter { !$0.isWarmup }.reduce(0.0) { acc, s in
            let v = session.enteredValues(for: s.slot)
            return acc + (v.weightKg ?? 0) * Double(v.reps ?? 0)
        }
        return HStack(spacing: 12) {
            tile("Volume", volume > 0 ? NunaTrendsFormat.num(volume) : "–", UnitFormatter.massUnit(system))
            tile("Heart rate", model.bpm.map(String.init) ?? "–", "bpm")
            tile("Sets", "\(engine.completedWorkingSets)/\(engine.plannedWorkingSets)", nil)
        }
    }

    private func tile(_ l: LocalizedStringKey, _ v: String, _ unit: String?) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(l).font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: v).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    if let unit { Text(verbatim: unit).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
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
                        Text("Tap Set done when you finish").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        default:
            NunaCard(small: true) {
                Text("Start the first set when you are ready.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
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
        if isOpen(engine, index) {
            NunaCard {
                VStack(alignment: .leading, spacing: 12) {
                    Button { opened.remove(index) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: item.exercise).font(.nuna(size: 19, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.leading)
                                Text(verbatim: LiftMuscleSummary.line(primary: item.primaryMuscle, secondaries: item.secondaryMuscles)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                            }
                            Spacer()
                            Text(verbatim: "\(done)/\(slots.count)").font(.nuna(size: 13, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textSecondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if let note = item.note, !note.isEmpty {
                        Text(verbatim: note).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).lineLimit(4).padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading).background(NunaPalette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    columnHeadings
                    VStack(spacing: 2) { ForEach(slots, id: \.self) { slot in setRow(engine, slot: slot) } }
                    HStack {
                        Button { session.addSet(toExercise: index) } label: {
                            HStack(spacing: 8) { Image(systemName: "plus").font(.nuna(size: 13, weight: .bold)); Text("Add set").font(.nuna(size: 14.5, weight: .bold)) }
                                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity).frame(height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                        }.buttonStyle(.plain).disabled(item.targetSets >= LiftSessionEngine.maxSetsPerExercise)
                        Button { session.removeSet(fromExercise: index) } label: {
                            Image(systemName: "minus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 44, height: 44).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                        }.buttonStyle(.plain).disabled(!engine.canRemoveSet(fromExercise: index)).opacity(engine.canRemoveSet(fromExercise: index) ? 1 : 0.4)
                    }
                }
            }
        } else {
            Button { opened.insert(index) } label: {
                NunaCard(small: true) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.exercise).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: collapsedLine(item, done: done, total: slots.count)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                    }
                }
            }.buttonStyle(.plain)
        }
    }

    private func collapsedLine(_ item: LiftPlanItem, done: Int, total: Int) -> String {
        let muscle = item.primaryMuscle?.displayName ?? String(localized: "Not classified")
        if done == 0 { return muscle + " · " + String(localized: "\(total) sets not started") }
        if done == total { return muscle + " · " + String(localized: "\(total) sets done") }
        return muscle + " · " + String(localized: "\(done) of \(total) sets done")
    }

    private var columnHeadings: some View {
        HStack(spacing: 8) {
            Text("Set").frame(width: setColumn, alignment: .center)
            Text(system == .imperial ? "Lb" : "Kg").frame(maxWidth: .infinity, alignment: .leading)
            Text("Reps").frame(width: repsColumn, alignment: .leading)
            Text("RPE").frame(width: rpeColumn, alignment: .leading)
            Color.clear.frame(width: tickColumn)
        }
        .padding(.horizontal, 8)
        .font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    private func setRow(_ engine: LiftSessionEngine, slot: LiftSlot) -> some View {
        let recorded = engine.recordedSet(for: slot)
        let isWorking = engine.stage == .working(slot)
        let warm = session.isWarmup(slot)
        return HStack(spacing: 8) {
            Button { session.setWarmup(slot, !warm) } label: {
                Text(verbatim: warm ? String(localized: "W") : "\(slot.setIndex)").font(.nuna(size: 16, weight: .bold, design: NunaType.design))
                    .foregroundStyle(warm ? NunaPalette.warning : (isWorking ? NunaPalette.restText : NunaPalette.textSecondary))
                    .frame(width: setColumn, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(warm ? Text("Warm-up set — tap to make it a working set") : Text("Set \(slot.setIndex) — tap to mark it a warm-up"))
            HStack(spacing: 4) {
                if isWorking { stepButton("minus") { bump(slot, -step) } }
                field(text: weightBinding(slot), ghost: ghostWeight(slot), target: .weight(slot), decimal: true, big: isWorking)
                if isWorking { stepButton("plus") { bump(slot, step) } }
            }.frame(maxWidth: .infinity, alignment: .leading)
            field(text: repsBinding(slot), ghost: ghostReps(slot), target: .reps(slot), decimal: false, big: isWorking).frame(width: repsColumn)
            field(text: rpeBinding(slot), ghost: ghostRpe(engine, slot: slot), target: .rpe(slot), decimal: true, big: false).frame(width: rpeColumn)
            Button { session.start(slot) } label: {
                Image(systemName: recorded == nil ? "circle" : "checkmark.circle.fill").font(.nuna(size: 24, weight: .semibold))
                    .foregroundStyle(recorded == nil ? NunaPalette.textMuted : (isWorking ? NunaPalette.rest : NunaPalette.charge))
                    .frame(width: tickColumn, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(recorded == nil ? Text("Start this set") : Text("Redo this set"))
        }
        .padding(.vertical, isWorking ? 6 : 2).padding(.horizontal, 8)
        .background(isWorking ? NunaPalette.rest.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) { if !isWorking { Rectangle().fill(NunaPalette.hairline).frame(height: 0.5) } }
    }

    private func field(text: Binding<String>, ghost: String, target: FocusTarget, decimal: Bool, big: Bool) -> some View {
        TextField("", text: text, prompt: Text(verbatim: ghost).foregroundStyle(NunaPalette.textMuted))
            .font(.nuna(size: big ? 20 : 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .focused($focused, equals: target)
            .frame(minHeight: 44)
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 28, height: 28).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
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
                    .frame(width: 56, height: 56).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
            }.buttonStyle(.plain).disabled(!engine.canUndo).accessibilityLabel(Text("Undo"))
            Button { session.advance() } label: {
                Text(actionLabel(engine)).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 56).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                unfinishedChoice = nil; programChoice = nil; setCountChanges = []
                showingFinish = true
            } label: {
                Text("Finish").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.alertText)
                    .padding(.horizontal, 20).frame(height: 56).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
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
                            .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if unfinished > 0 {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            nunaTrendsCap("Unfinished sets")
                            Text("\(unfinished) sets have no numbers typed in — sets you did not start, or finished without typing.").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                            NunaSegmented([(value: UnfinishedChoice?.some(.complete), title: "Complete them"), (value: UnfinishedChoice?.some(.discard), title: "Discard them")], selection: $unfinishedChoice)
                            Text("Completing saves them with the grey numbers shown. Discarding leaves them out of the session.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !setCountChanges.isEmpty {
                    NunaCard {
                        VStack(alignment: .leading, spacing: 12) {
                            nunaTrendsCap("Program")
                            Text("You changed the number of sets. Keep the new counts in the program for next time?").font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
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
                if !answered { Text("Choose an option above to save.").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted) }
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
            Button("Discard", role: .destructive) { session.discard(); showingFinish = false }
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
        await finishAndDismiss()
    }

    private func finishAndDismiss() async {
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
            Button { session.isPresented = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(width: 38, height: 38).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.iconButton, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: session.programName ?? String(localized: "Gym session")).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                        Text(verbatim: "\(e.completedWorkingSets)/\(e.plannedWorkingSets) · " + LiftFormat.duration(max(0, session.now - e.startTs)))
                            .font(.nuna(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(NunaPalette.textSecondary)
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
#endif

#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The stored sleep block an edit is written against, plus what the sheet needs to seed its pickers.
struct NunaSleepEditTarget: Identifiable {
    let detectedStartTs: Int
    let bedTs: Int
    let wakeTs: Int
    let stagesJSON: String?
    /// Hand-edited or hand-added. Deleting one writes no tombstone, so the copy must not promise one.
    let userEdited: Bool
    let isNap: Bool
    var id: Int { detectedStartTs }

    init(_ block: CachedSleepSession, isNap: Bool) {
        detectedStartTs = block.startTs
        bedTs = block.effectiveStartTs
        wakeTs = block.endTs
        stagesJSON = block.stagesJSON
        userEdited = block.userEdited || isNap
        self.isNap = isNap
    }
}

/// Correct when a night (or nap) started and ended. Same rules as the Default sleep editor: the stages are re-derived from the
/// strap's raw data, the edit survives the next sync, a bed time rolled past the wake falls back a day, a window with no recorded
/// data asks first, and a sleep can be deleted.
struct NunaSleepTimeSheet: View {
    let target: NunaSleepEditTarget
    /// Called once the edit or delete is saved. A delete hands back the snapshot the host offers to restore.
    let onDone: (SleepDeletionSnapshot?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var bed: Date
    @State private var wake: Date
    @State private var previousBed: Date
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var confirmDisjoint = false

    init(target: NunaSleepEditTarget, onDone: @escaping (SleepDeletionSnapshot?) async -> Void) {
        self.target = target; self.onDone = onDone
        let seed = Date(timeIntervalSince1970: TimeInterval(min(target.bedTs, Int(Date().timeIntervalSince1970))))
        _bed = State(initialValue: seed)
        _previousBed = State(initialValue: seed)
        _wake = State(initialValue: Date(timeIntervalSince1970: TimeInterval(target.wakeTs)))
    }

    private var coverage: ClosedRange<Int> {
        let lo = min(target.detectedStartTs, target.bedTs)
        return lo...max(target.wakeTs, lo + 1)
    }

    private var window: (start: Int, end: Int)? {
        SleepEditGuard.clampedEditWindow(start: Int(bed.timeIntervalSince1970), end: Int(wake.timeIntervalSince1970),
                                         now: Int(Date().timeIntervalSince1970))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target.isNap ? "Edit nap times" : "Edit sleep times")
                .font(.nuna(size: NunaTypeSize.h2, weight: .heavy, design: NunaType.design))
                .foregroundStyle(NunaPalette.textPrimary).padding(.top, 22)
            NunaCard(small: true) {
                VStack(spacing: 0) {
                    DatePicker(target.isNap ? "Nap started" : "Asleep", selection: $bed, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .tint(NunaPalette.charge).foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 52)
                    NunaDivider()
                    DatePicker(target.isNap ? "Nap ended" : "Woke", selection: $wake, in: ...Date(),
                               displayedComponents: [.date, .hourAndMinute])
                        .tint(NunaPalette.charge).foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 52)
                }
            }
            Text("Correct when you went to bed and woke. Stages are re-derived from your data; the edit is kept through the next strap sync.")
                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
            Button { save() } label: { Text(saving ? "Saving…" : "Save") }
                .buttonStyle(.nuna(.primary, fullWidth: true))
                .disabled(saving || window == nil)
            Button { confirmDelete = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.nuna(size: 15, weight: .bold))
                    Text(target.isNap ? "Delete this nap" : "Delete this sleep").font(.nuna(size: 15, weight: .heavy))
                }
                .foregroundStyle(NunaPalette.alert).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain).disabled(saving)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NunaSpacing.screenH)
        .background(NunaPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(NunaTheme.colorScheme)
        .nunaSheetChrome(detents: [.medium, .large])
        // A time-only roll that lands the bed in the future or after the wake means the previous evening.
        .onChange(of: bed) { _, newBed in
            let corrected = SleepEditGuard.autoCorrectedBed(
                previousBed: previousBed, candidateBed: newBed,
                originalWake: Date(timeIntervalSince1970: TimeInterval(coverage.upperBound)), now: Date())
            previousBed = corrected
            if corrected != newBed { bed = corrected }
        }
        .alert("Move this sleep?", isPresented: $confirmDisjoint) {
            Button("Cancel", role: .cancel) {}
            Button("Move anyway") { if let w = window { commit(w.start, w.end) } }
        } message: {
            Text("This moves the night to a time with no recorded data. Stages can't be derived there, so it may show as empty until data covers it.")
        }
        .alert("Delete this sleep session?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text(target.userEdited
                 ? "It is removed from your sleep and every score that uses it is recalculated. You can undo it for a few seconds."
                 : "It is removed and every score that uses it is recalculated. It will not be detected again. You can undo it for a few seconds.")
        }
    }

    private func save() {
        guard let w = window else { return }
        if SleepEditGuard.isDisjoint(newStart: w.start, newEnd: w.end,
                                     coverageStart: coverage.lowerBound, coverageEnd: coverage.upperBound) {
            confirmDisjoint = true
        } else {
            commit(w.start, w.end)
        }
    }

    private func commit(_ start: Int, _ end: Int) {
        saving = true
        Task {
            await repo.editSleepTimes(detectedStartTs: target.detectedStartTs, oldEndTs: target.wakeTs,
                                      storedStagesJSON: target.stagesJSON, newStartTs: start, newEndTs: end)
            await intelligence.analyzeRecent()
            await repo.refresh()
            await onDone(nil)
            dismiss()
        }
    }

    private func delete() {
        saving = true
        Task {
            let snapshot = await repo.deleteSleepSession(detectedStartTs: target.detectedStartTs, endTs: target.wakeTs)
            await intelligence.analyzeRecent()
            await repo.refresh()
            await onDone(snapshot)
            dismiss()
        }
    }
}

/// The strip shown after a delete: what was removed and an Undo that puts the sleep back where it came from.
private struct NunaSleepUndoModifier: ViewModifier {
    @Binding var snapshot: SleepDeletionSnapshot?
    let onRestored: () async -> Void
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @State private var timer: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let snap = snapshot {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sleep deleted").font(.nuna(size: 14.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: "\(NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(snap.session.effectiveStartTs)))) – \(NunaSleepFormat.clock(Date(timeIntervalSince1970: TimeInterval(snap.session.endTs))))")
                                .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer(minLength: 8)
                        Button { restore(snap) } label: {
                            Text("Undo").font(.nuna(size: 14.5, weight: .heavy)).foregroundStyle(NunaPalette.charge)
                                .padding(.horizontal, 10).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(NunaPalette.canvas, in: RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NunaRadius.cardSmall, style: .continuous).strokeBorder(NunaPalette.ink.opacity(0.18), lineWidth: 1))
                    .padding(.horizontal, NunaSpacing.screenH).padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: snapshot)
            .onChange(of: snapshot) { _, snap in
                timer?.cancel()
                guard snap != nil else { return }
                timer = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if !Task.isCancelled { snapshot = nil }
                }
            }
    }

    private func restore(_ snap: SleepDeletionSnapshot) {
        timer?.cancel()
        Task {
            await repo.undoDeleteSleepSession(snap)
            await intelligence.analyzeRecent()
            await repo.refresh()
            await onRestored()
            snapshot = nil
        }
    }
}

extension View {
    /// Offers to put a just-deleted sleep back for a few seconds.
    func nunaSleepUndo(_ snapshot: Binding<SleepDeletionSnapshot?>, onRestored: @escaping () async -> Void) -> some View {
        modifier(NunaSleepUndoModifier(snapshot: snapshot, onRestored: onRestored))
    }
}
#endif

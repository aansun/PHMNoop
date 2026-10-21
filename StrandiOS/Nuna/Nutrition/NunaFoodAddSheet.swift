#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Add food: type the numbers in, pick a saved or recent food, or describe the meal to Anya and let her work the calories and macros out.
struct NunaFoodAddSheet: View {
    /// `yyyy-MM-dd` the entries are for.
    let day: String
    let initialMeal: NunaMeal
    /// Stay on the Anya tab even when she is not connected, so the tab can say how to connect her.
    var anyaFirst = false

    enum Mode: Hashable { case quick, saved, recent, anya }

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .anya
    @State private var meal: NunaMeal
    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fromMacros = false
    @State private var keepIt = false
    @State private var saved: [SavedFoodRow] = []
    @State private var recent: [FoodEntryRow] = []
    @State private var description = ""
    @State private var estimating = false
    @State private var estimate: AnyaFoodSpec?
    @State private var estimateError: String?
    @FocusState private var focused: Bool

    init(day: String, meal: NunaMeal, anyaFirst: Bool = false) {
        self.day = day; self.initialMeal = meal; self.anyaFirst = anyaFirst
        _meal = State(initialValue: meal)
    }

    private func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
    private var protein: Double? { number(proteinText) }
    private var carbs: Double? { number(carbsText) }
    private var fat: Double? { number(fatText) }
    private var kcal: Double? { fromMacros ? NutritionMath.kcal(proteinG: protein, carbsG: carbs, fatG: fat) : number(kcalText) }
    private var canAdd: Bool { (kcal ?? 0) > 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    NunaSegmented([(Mode.anya, "Anya"), (.quick, "Quick add"), (.saved, "Saved"), (.recent, "Recent")], selection: $mode)
                    mealChips
                    switch mode {
                    case .quick: quick
                    case .saved: savedList
                    case .recent: recentList
                    case .anya: anya
                    }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                // The button rides above the keyboard, so a typed entry can be added without putting the keyboard away.
                if mode == .quick {
                    addButton(title: String(localized: "Add to \(mealName)"), enabled: canAdd) { Task { await addQuick() } }
                        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10).background(NunaPalette.canvas)
                }
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .task {
            // Anya comes first; without a connection there is nothing to ask her, so the sheet opens on typing the numbers instead.
            if !coach.isConfigured, !anyaFirst { mode = .quick }
            saved = await NunaFoodStore.savedFoods(repo: repo); recent = await NunaFoodStore.recentFoods(repo: repo)
        }
        .nunaKeyboardDone()
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { NunaBareIcon("xmark") }.accessibilityLabel(Text("Close"))
            Spacer()
            Text("Add food").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8).padding(.top, 8)
    }

    private var mealChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NunaMeal.allCases) { m in
                    let on = meal == m
                    Button { meal = m } label: {
                        Text(m.singular).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Quick add

    private var quick: some View {
        VStack(spacing: 14) {
            NunaFormField("Name") {
                TextField("", text: $name, prompt: Text("Chicken rice bowl").foregroundStyle(NunaPalette.textMuted)).focused($focused)
            }
            NunaFormField("Calories") {
                if fromMacros {
                    HStack { Text(verbatim: "\(Int((kcal ?? 0).rounded()))").foregroundStyle(NunaPalette.textPrimary); Spacer(); Text("kcal").foregroundStyle(NunaPalette.textSecondary) }
                } else {
                    HStack { TextField("", text: $kcalText, prompt: Text("0").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad).focused($focused); Text("kcal").foregroundStyle(NunaPalette.textSecondary) }
                }
            }
            HStack(spacing: 10) {
                macroField("Protein", $proteinText)
                macroField("Carbs", $carbsText)
                macroField("Fat", $fatText)
            }
            NunaCard(small: true) {
                VStack(spacing: 4) {
                    NunaToggleRow("Work calories out from macros", subtitle: "4 kcal per gram of protein and carbs, 9 per gram of fat", isOn: $fromMacros)
                    NunaToggleRow("Save as a food to reuse", isOn: $keepIt)
                }
            }
        }
    }

    private func macroField(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        NunaFormField(label) {
            HStack(spacing: 4) {
                TextField("", text: text, prompt: Text("0").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad).focused($focused)
                Text("g").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private var mealName: String {
        switch meal { case .breakfast: String(localized: "Breakfast"); case .lunch: String(localized: "Lunch"); case .dinner: String(localized: "Dinner"); case .snack: String(localized: "Snacks") }
    }

    private func addButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }

    private func addQuick() async {
        guard let kcal else { return }
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Quick add") : name
        await NunaFoodStore.add([NunaFoodStore.entry(day: day, meal: meal, name: label, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, source: "manual", repo: repo)], repo: repo)
        if keepIt { await NunaFoodStore.keep(name: label, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, repo: repo) }
        dismiss()
    }

    // MARK: Saved and recent

    private var savedList: some View {
        Group {
            if saved.isEmpty {
                emptyNote("Foods you save show up here, most used first. Turn on “Save as a food to reuse” when you add one.")
            } else {
                NunaCard(small: true, padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 8)) {
                    VStack(spacing: 0) {
                        ForEach(Array(saved.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { NunaDivider() }
                            HStack(spacing: 8) {
                                Button { Task { await addSaved(f) } } label: { foodLabel(f.name, f.kcal, f.proteinG, f.carbsG, f.fatG) }.buttonStyle(.plain)
                                Button { Task { await NunaFoodStore.deleteSaved(id: f.id, repo: repo); saved = await NunaFoodStore.savedFoods(repo: repo) } } label: {
                                    Image(systemName: "trash").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.alertText).frame(width: 40, height: 40)
                                }.buttonStyle(.plain).accessibilityLabel(Text("Delete"))
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentList: some View {
        Group {
            if recent.isEmpty {
                emptyNote("What you eat shows up here, newest first, so you can add it again with one tap.")
            } else {
                NunaCard(small: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { i, e in
                            if i > 0 { NunaDivider() }
                            Button { Task { await addRecent(e) } } label: { foodLabel(e.name, e.kcal, e.proteinG, e.carbsG, e.fatG) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func foodLabel(_ name: String, _ kcal: Double, _ p: Double?, _ c: Double?, _ f: Double?) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: name).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2).multilineTextAlignment(.leading).textCase(nil)
                let macros = [p.map { "P \(Int($0.rounded()))" }, c.map { "C \(Int($0.rounded()))" }, f.map { "F \(Int($0.rounded()))" }].compactMap { $0 }
                if !macros.isEmpty { Text(verbatim: macros.joined(separator: " · ")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
            }
            Spacer(minLength: 6)
            Text(verbatim: "\(Int(kcal.rounded()))").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
            Text("kcal").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
        }
        .padding(.vertical, 12).contentShape(Rectangle())
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        NunaCard(small: true) {
            Text(text).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func addSaved(_ f: SavedFoodRow) async {
        await NunaFoodStore.add([NunaFoodStore.entry(day: day, meal: meal, name: f.name, kcal: f.kcal, proteinG: f.proteinG, carbsG: f.carbsG, fatG: f.fatG, source: "saved", repo: repo)], repo: repo)
        await NunaFoodStore.bump(f.id, repo: repo)
        dismiss()
    }

    private func addRecent(_ e: FoodEntryRow) async {
        await NunaFoodStore.add([NunaFoodStore.entry(day: day, meal: meal, name: e.name, kcal: e.kcal, proteinG: e.proteinG, carbsG: e.carbsG, fatG: e.fatG, source: e.source == "anya" ? "anya" : "saved", repo: repo)], repo: repo)
        dismiss()
    }

    // MARK: Anya

    private var anya: some View {
        VStack(spacing: 14) {
            if !coach.isConfigured {
                emptyNote("Connect Anya in More to describe a meal and have the calories and macros worked out for you.")
            } else {
                NunaFormField("What did you eat?") {
                    TextField("", text: $description, prompt: Text("Two eggs and a plate of nasi goreng").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                        .lineLimit(2...5).focused($focused).padding(.vertical, 10)
                }
                Text("Only this description is sent to Anya, with none of your health data. She estimates each item; you check it before it is added.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await estimateMeal() } } label: {
                    HStack(spacing: 8) {
                        if estimating { ProgressView().tint(NunaPalette.onAccent) } else { Image(systemName: "sparkles").font(.nuna(size: 15, weight: .bold)) }
                        Text(estimating ? "Working it out…" : "Work out calories").font(.nuna(size: 17, weight: .bold))
                    }
                    .foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                    .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain).disabled(estimating || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(estimating || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                if let estimateError {
                    Text(verbatim: estimateError).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let estimate {
                    NunaAnyaFoodCard(spec: AnyaFoodSpec(meal: meal.rawValue, day: day, items: estimate.items)) { Task { try? await Task.sleep(nanoseconds: 700_000_000); dismiss() } }
                        .id(estimate.items.map(\.name).joined())
                }
            }
        }
    }

    private func estimateMeal() async {
        focused = false; estimating = true; estimate = nil; estimateError = nil
        defer { estimating = false }
        guard let reply = await coach.estimateFood(description) else {
            estimateError = String(localized: "Anya couldn't answer. Check her connection in More, then try again."); return
        }
        if let spec = AnyaActions.parse(reply).compactMap({ b -> AnyaFoodSpec? in if case .food(let f) = b { return f } else { return nil } }).first {
            estimate = spec
        } else {
            estimateError = String(localized: "Anya couldn't read that as food. Try naming each item and its portion.")
        }
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A meal Anya estimated from a description. Nothing goes in the diary until the person taps Add: each item can be left out or scaled, the meal and the
/// day can be changed, and the numbers are shown as an estimate. Used in the chat and inside the Add food sheet. Figures the person changes are
/// remembered (`FoodMemory`) and used in place of Anya's the next time she estimates the same food.
struct NunaAnyaFoodCard: View {
    let spec: AnyaFoodSpec
    /// Set inside the Add food sheet, where the meal and the day are already chosen: the card then shows no meal chips or day row.
    var fixed: (meal: NunaMeal, day: String)?
    /// Called once the items are in the diary (the Add food sheet closes itself).
    var onAdded: (() -> Void)?

    @EnvironmentObject private var repo: Repository
    /// One item's numbers as the person sees and edits them: text, so a half-typed number is never lost.
    struct Draft: Equatable { var name: String; var kcal: String; var protein: String; var carbs: String; var fat: String }

    @State private var excluded: Set<Int> = []
    @State private var scale: [Int: Double] = [:]
    @State private var drafts: [Draft]
    /// The figures the card opened with, to tell what the person changed.
    @State private var original: [Draft]
    /// The items that opened with the person's own figures instead of Anya's.
    @State private var learned: Set<Int>
    @State private var editing: Int?
    @State private var meal: NunaMeal
    @State private var date: Date
    @State private var adding = false
    @State private var addedCount: Int?
    @State private var showNutrition = false
    @Environment(\.nunaAnyaCardID) private var cardID

    init(spec: AnyaFoodSpec, fixed: (meal: NunaMeal, day: String)? = nil, onAdded: (() -> Void)? = nil) {
        self.spec = spec; self.fixed = fixed; self.onAdded = onAdded
        let known = NunaFoodMemoryStore.load()
        let mine = spec.items.map { FoodMemory.figures(for: $0, in: known) }
        let opening = spec.items.indices.map { Self.draft(mine[$0] ?? spec.items[$0]) }
        _drafts = State(initialValue: opening)
        _original = State(initialValue: opening)
        _learned = State(initialValue: Set(spec.items.indices.filter { mine[$0] != nil }))
        _meal = State(initialValue: spec.meal.flatMap(NunaMeal.init(rawValue:)) ?? NunaMeal.suggested())
        let day = spec.day.flatMap { d -> Date? in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: d)
        }
        _date = State(initialValue: min(day ?? Date(), Date()))
    }

    private static func draft(_ item: AnyaFoodItem) -> Draft {
        func text(_ v: Double?) -> String { v.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "" }
        return Draft(name: item.name, kcal: text(item.kcal), protein: text(item.proteinG), carbs: text(item.carbsG), fat: text(item.fatG))
    }

    /// Whether an item's figures are the person's, from before or changed just now.
    private func isMine(_ i: Int) -> Bool { learned.contains(i) || drafts[i] != original[i] }

    private func factor(_ i: Int) -> Double { scale[i] ?? 1 }
    private func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
    /// Calories, protein, carbs and fat of an item as they stand now: what Anya said or what the person changed it to, times the size.
    private func kcal(_ i: Int) -> Double { (num(drafts[i].kcal) ?? 0) * factor(i) }
    private func macro(_ i: Int, _ s: String) -> Double? { num(s).map { $0 * factor(i) } }
    private var chosen: [Int] { spec.items.indices.filter { !excluded.contains($0) } }
    private var totalKcal: Double { chosen.reduce(0) { $0 + kcal($1) } }

    var body: some View {
        NunaCard(small: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NunaIconTile("fork.knife")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meal estimate").font(.nuna(size: 16.5, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        Text(verbatim: chosen.contains(where: isMine) ? String(localized: "\(Int(totalKcal.rounded())) kcal · with your own figures")
                             : String(localized: "\(Int(totalKcal.rounded())) kcal · estimated by Anya")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    Spacer(minLength: 0)
                }
                if addedCount == nil, fixed == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(NunaMeal.allCases) { m in mealChip(m) } }
                    }
                    HStack {
                        Text("Day").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                        Spacer()
                        DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                }
                ForEach(spec.items.indices, id: \.self) { i in line(i) }
                if let n = addedCount {
                    HStack(spacing: 10) {
                        Label(String(localized: "Added \(n) to the diary"), systemImage: "checkmark.circle.fill").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.charge)
                        Spacer()
                        Button { showNutrition = true } label: { Text("Open Nutrition").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }.buttonStyle(.plain)
                    }
                } else {
                    Button { Task { await add() } } label: {
                        Text(String(localized: "Add \(chosen.count) to \(fixed.map { Self.name($0.meal) } ?? mealName)")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(adding || chosen.isEmpty).opacity(adding || chosen.isEmpty ? 0.5 : 1)
                    Text("These are estimates. Change the size, or tap the pencil to edit the name, calories and macros, before you add.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .sheet(isPresented: $showNutrition) { NunaQuickPanel(route: NunaTodayRoute.nutrition) }
        .onAppear(perform: restore)
    }

    /// A card already added shows what was added, and offers nothing to add again.
    private func restore() {
        guard addedCount == nil, let used = NunaAnyaCardUses.use(cardID) else { return }
        excluded = Set(used.excluded)
        scale = Dictionary(uniqueKeysWithValues: used.scale.compactMap { key, f in Int(key).map { ($0, f) } })
        addedCount = used.count
    }

    private static func name(_ m: NunaMeal) -> String {
        switch m { case .breakfast: String(localized: "Breakfast"); case .lunch: String(localized: "Lunch"); case .dinner: String(localized: "Dinner"); case .snack: String(localized: "Snacks") }
    }

    private var mealName: String {
        switch meal { case .breakfast: String(localized: "Breakfast"); case .lunch: String(localized: "Lunch"); case .dinner: String(localized: "Dinner"); case .snack: String(localized: "Snacks") }
    }

    private func mealChip(_ m: NunaMeal) -> some View {
        let on = meal == m
        return Button { meal = m } label: {
            Text(m.singular).font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(on ? NunaPalette.onAccent : NunaPalette.textPrimary)
                .padding(.horizontal, 14).frame(height: 32)
                .background(on ? NunaPalette.accent : NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func line(_ i: Int) -> some View {
        let on = !excluded.contains(i)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button { if addedCount == nil { if on { excluded.insert(i) } else { excluded.remove(i) } } } label: {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(on ? NunaPalette.charge : NunaPalette.textMuted).padding(.top, 1)
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: drafts[i].name).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    Text(verbatim: detail(i)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(verbatim: "\(Int(kcal(i).rounded()))").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                    Text("kcal").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                    if addedCount == nil {
                        HStack(spacing: 6) {
                            NunaMenu {
                                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { f in
                                    NunaMenuItem(verbatim: sizeLabel(f), selected: factor(i) == f) { scale[i] = f }
                                }
                            } label: {
                                Text(verbatim: sizeLabel(factor(i))).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    .padding(.horizontal, 8).frame(height: 28).background(NunaPalette.glassStrong, in: Capsule())
                            }
                            Button { withAnimation(.easeInOut(duration: 0.15)) { editing = editing == i ? nil : i } } label: {
                                Image(systemName: editing == i ? "checkmark" : "pencil").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                    .frame(width: 28, height: 28).background(NunaPalette.glassStrong, in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel(Text(editing == i ? "Done" : "Edit"))
                        }
                    }
                }
            }
            if editing == i, addedCount == nil { editor(i) }
        }
        .opacity(on ? 1 : 0.5)
    }

    /// Anya's numbers are a starting point: the name, calories and macros of an item can all be changed before it is added.
    private func editor(_ i: Int) -> some View {
        VStack(spacing: 10) {
            NunaFormField("Name") { TextField("", text: $drafts[i].name) }
            HStack(spacing: 10) {
                NunaFormField("Calories") { TextField("0", text: $drafts[i].kcal).keyboardType(.decimalPad) }
                NunaFormField("Protein g") { TextField("0", text: $drafts[i].protein).keyboardType(.decimalPad) }
            }
            HStack(spacing: 10) {
                NunaFormField("Carbs g") { TextField("0", text: $drafts[i].carbs).keyboardType(.decimalPad) }
                NunaFormField("Fat g") { TextField("0", text: $drafts[i].fat).keyboardType(.decimalPad) }
            }
            Button {
                let k = NutritionMath.kcal(proteinG: num(drafts[i].protein), carbsG: num(drafts[i].carbs), fatG: num(drafts[i].fat))
                drafts[i].kcal = String(Int(k))
            } label: {
                Text("Work calories out from the macros").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if learned.contains(i) {
                Button { useAnyas(i) } label: {
                    Text("Forget my figures and use Anya's").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            Text("Figures you change are remembered and used the next time Anya estimates this food.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textCase(nil)
        }
        .padding(.leading, 30)
    }

    private func sizeLabel(_ f: Double) -> String { f == f.rounded() ? "\(Int(f))×" : String(format: "%.1f×", locale: AppLanguage.activeLocale, f) }

    private func detail(_ i: Int) -> String {
        let item = spec.items[i]
        var parts: [String] = []
        if let a = item.amount { parts.append(a) }
        var macros: [String] = []
        if let p = macro(i, drafts[i].protein) { macros.append("P \(Int(p.rounded()))") }
        if let c = macro(i, drafts[i].carbs) { macros.append("C \(Int(c.rounded()))") }
        if let g = macro(i, drafts[i].fat) { macros.append("F \(Int(g.rounded()))") }
        if !macros.isEmpty { parts.append(macros.joined(separator: " · ")) }
        if isMine(i) { parts.append(String(localized: "your figures")) }
        return parts.joined(separator: " · ")
    }

    private func useAnyas(_ i: Int) {
        let known = NunaFoodMemoryStore.load()
        let item = spec.items[i]
        if let used = known.first(where: { FoodMemory.key($0.name) == FoodMemory.key(item.name) && FoodMemory.unit(of: $0.amount) == FoodMemory.unit(of: item.amount) }) {
            NunaFoodMemoryStore.forget(id: used.id)
        }
        drafts[i] = Self.draft(item); original[i] = drafts[i]; learned.remove(i)
    }

    /// Keeps what the person changed, for the portion Anya named: the size chosen on the card is how much was eaten, not a correction.
    private func remember() {
        let now = Int(Date().timeIntervalSince1970)
        for i in chosen where drafts[i] != original[i] {
            let d = drafts[i]
            guard let kcal = num(d.kcal), kcal > 0 else { continue }
            let name = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? spec.items[i].name : d.name
            NunaFoodMemoryStore.remember(LearnedFood(name: name, amount: spec.items[i].amount, kcal: kcal, proteinG: num(d.protein), carbsG: num(d.carbs), fatG: num(d.fat), updatedAt: now))
        }
    }

    private func add() async {
        guard NunaAnyaCardUses.use(cardID) == nil else { restore(); return }
        adding = true; defer { adding = false }
        let day = fixed?.day ?? Repository.localDayKey(date)
        let target = fixed?.meal ?? meal
        let entries = chosen.map { i -> FoodEntryRow in
            let d = drafts[i]
            let name = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? spec.items[i].name : d.name
            // Figures the person set are theirs, so the diary does not call them an estimate.
            return NunaFoodStore.entry(day: day, meal: target, name: name, kcal: kcal(i), proteinG: macro(i, d.protein), carbsG: macro(i, d.carbs), fatG: macro(i, d.fat),
                                       source: isMine(i) ? "manual" : "anya", repo: repo)
        }
        await NunaFoodStore.add(entries, repo: repo)
        remember()
        NunaAnyaCardUses.record(NunaAnyaCardUse(count: entries.count, excluded: excluded.sorted(),
                                                scale: Dictionary(uniqueKeysWithValues: scale.map { (String($0.key), $0.value) })), for: cardID)
        addedCount = entries.count
        onAdded?()
    }
}
#endif

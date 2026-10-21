#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A meal Anya estimated from a description. Nothing goes in the diary until the person taps Add: each item can be left out or scaled, the meal and the
/// day can be changed, and the numbers are shown as an estimate. Used in the chat and inside the Add food sheet.
struct NunaAnyaFoodCard: View {
    let spec: AnyaFoodSpec
    /// Set inside the Add food sheet, where the meal and the day are already chosen: the card then shows no meal chips or day row.
    var fixed: (meal: NunaMeal, day: String)?
    /// Called once the items are in the diary (the Add food sheet closes itself).
    var onAdded: (() -> Void)?

    @EnvironmentObject private var repo: Repository
    /// One item's numbers as the person sees and edits them: text, so a half-typed number is never lost.
    struct Draft { var name: String; var kcal: String; var protein: String; var carbs: String; var fat: String }

    @State private var excluded: Set<Int> = []
    @State private var scale: [Int: Double] = [:]
    @State private var drafts: [Draft]
    @State private var editing: Int?
    @State private var meal: NunaMeal
    @State private var date: Date
    @State private var adding = false
    @State private var addedCount: Int?
    @State private var showNutrition = false

    init(spec: AnyaFoodSpec, fixed: (meal: NunaMeal, day: String)? = nil, onAdded: (() -> Void)? = nil) {
        self.spec = spec; self.fixed = fixed; self.onAdded = onAdded
        func text(_ v: Double?) -> String { v.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "" }
        _drafts = State(initialValue: spec.items.map { Draft(name: $0.name, kcal: text($0.kcal), protein: text($0.proteinG), carbs: text($0.carbsG), fat: text($0.fatG)) })
        _meal = State(initialValue: spec.meal.flatMap(NunaMeal.init(rawValue:)) ?? NunaMeal.suggested())
        let day = spec.day.flatMap { d -> Date? in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: d)
        }
        _date = State(initialValue: min(day ?? Date(), Date()))
    }

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
                        Text(verbatim: String(localized: "\(Int(totalKcal.rounded())) kcal · estimated by Anya")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
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
                            Menu {
                                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { f in
                                    Button { scale[i] = f } label: { if factor(i) == f { Label(sizeLabel(f), systemImage: "checkmark") } else { Text(verbatim: sizeLabel(f)) } }
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
        return parts.joined(separator: " · ")
    }

    private func add() async {
        adding = true; defer { adding = false }
        let day = fixed?.day ?? Repository.localDayKey(date)
        let target = fixed?.meal ?? meal
        let entries = chosen.map { i -> FoodEntryRow in
            let d = drafts[i]
            let name = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? spec.items[i].name : d.name
            return NunaFoodStore.entry(day: day, meal: target, name: name, kcal: kcal(i), proteinG: macro(i, d.protein), carbsG: macro(i, d.carbs), fatG: macro(i, d.fat), source: "anya", repo: repo)
        }
        await NunaFoodStore.add(entries, repo: repo)
        addedCount = entries.count
        onAdded?()
    }
}
#endif

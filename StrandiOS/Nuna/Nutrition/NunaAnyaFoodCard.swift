#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// A meal Anya estimated from a description. Nothing goes in the diary until the person taps Add: each item can be left out or scaled, the meal and the
/// day can be changed, and the numbers are shown as an estimate. Used in the chat and inside the Add food sheet.
struct NunaAnyaFoodCard: View {
    let spec: AnyaFoodSpec
    /// Called once the items are in the diary (the Add food sheet closes itself).
    var onAdded: (() -> Void)?

    @EnvironmentObject private var repo: Repository
    @State private var excluded: Set<Int> = []
    @State private var scale: [Int: Double] = [:]
    @State private var meal: NunaMeal
    @State private var date: Date
    @State private var adding = false
    @State private var addedCount: Int?
    @State private var showNutrition = false

    init(spec: AnyaFoodSpec, onAdded: (() -> Void)? = nil) {
        self.spec = spec; self.onAdded = onAdded
        _meal = State(initialValue: spec.meal.flatMap(NunaMeal.init(rawValue:)) ?? NunaMeal.suggested())
        let day = spec.day.flatMap { d -> Date? in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: d)
        }
        _date = State(initialValue: min(day ?? Date(), Date()))
    }

    private func factor(_ i: Int) -> Double { scale[i] ?? 1 }
    private func kcal(_ i: Int) -> Double { spec.items[i].kcal * factor(i) }
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
                if addedCount == nil {
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
                        Text(String(localized: "Add \(chosen.count) to \(mealName)")).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 46)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }.buttonStyle(.plain).disabled(adding || chosen.isEmpty).opacity(adding || chosen.isEmpty ? 0.5 : 1)
                    Text("These are estimates. Check the portions and change them with the size menu before you add.").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }
            }
        }
        .sheet(isPresented: $showNutrition) { NunaQuickPanel(route: NunaTodayRoute.nutrition) }
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
        let item = spec.items[i]
        let on = !excluded.contains(i)
        HStack(alignment: .top, spacing: 10) {
            Button { if addedCount == nil { if on { excluded.insert(i) } else { excluded.remove(i) } } } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(on ? NunaPalette.charge : NunaPalette.textMuted).padding(.top, 1)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                Text(verbatim: detail(i)).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: "\(Int(kcal(i).rounded()))").font(.nuna(size: 17, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                Text("kcal").font(.nuna(size: 11, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                if addedCount == nil {
                    Menu {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { f in
                            Button { scale[i] = f } label: { if factor(i) == f { Label(sizeLabel(f), systemImage: "checkmark") } else { Text(verbatim: sizeLabel(f)) } }
                        }
                    } label: {
                        Text(verbatim: sizeLabel(factor(i))).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            .padding(.horizontal, 8).frame(height: 24).background(NunaPalette.glassStrong, in: Capsule())
                    }
                }
            }
        }
        .opacity(on ? 1 : 0.5)
    }

    private func sizeLabel(_ f: Double) -> String { f == f.rounded() ? "\(Int(f))×" : String(format: "%.1f×", locale: AppLanguage.activeLocale, f) }

    private func detail(_ i: Int) -> String {
        let item = spec.items[i], f = factor(i)
        var parts: [String] = []
        if let a = item.amount { parts.append(a) }
        var macros: [String] = []
        if let p = item.proteinG { macros.append("P \(Int((p * f).rounded()))") }
        if let c = item.carbsG { macros.append("C \(Int((c * f).rounded()))") }
        if let g = item.fatG { macros.append("F \(Int((g * f).rounded()))") }
        if !macros.isEmpty { parts.append(macros.joined(separator: " · ")) }
        return parts.joined(separator: " · ")
    }

    private func add() async {
        adding = true; defer { adding = false }
        let day = Repository.localDayKey(date)
        let entries = chosen.map { i -> FoodEntryRow in
            let it = spec.items[i], f = factor(i)
            return NunaFoodStore.entry(day: day, meal: meal, name: it.name, kcal: it.kcal * f, proteinG: it.proteinG.map { $0 * f }, carbsG: it.carbsG.map { $0 * f }, fatG: it.fatG.map { $0 * f }, source: "anya", repo: repo)
        }
        await NunaFoodStore.add(entries, repo: repo)
        addedCount = entries.count
        onAdded?()
    }
}
#endif

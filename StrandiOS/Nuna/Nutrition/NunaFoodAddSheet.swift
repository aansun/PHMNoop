#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import PhotosUI

/// Add food on one screen. The box at the top is for telling Anya what you ate, in words or with a photo; under it are the foods you keep or ate lately,
/// one tap each, and a way in to type the numbers yourself. The meal is chosen in the header.
struct NunaFoodAddSheet: View {
    /// `yyyy-MM-dd` the entries are for.
    let day: String
    let initialMeal: NunaMeal
    /// Kept so callers need not change; Anya is always the first thing on the screen now.
    var anyaFirst = false

    private enum Page { case home, manual }

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .home
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
    @State private var photoItem: PhotosPickerItem?
    @State private var mealPhoto: UIImage?
    @State private var photoBase64: String?
    @State private var readingPhoto = false
    @State private var showCamera = false
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
    private var hasText: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canEstimate: Bool { !estimating && !readingPhoto && (mealPhoto != nil || hasText) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    if page == .home { home } else { manual }
                }
                .padding(.horizontal, NunaSpacing.screenH).padding(.top, 6).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                // The button rides above the keyboard, so a typed entry can be added without putting the keyboard away.
                if page == .manual {
                    primaryButton(String(localized: "Add to \(mealName)"), enabled: canAdd) { Task { await addManual() } }
                        .padding(.horizontal, NunaSpacing.screenH).padding(.vertical, 10).background(NunaPalette.canvas)
                }
            }
        }
        .background(NunaPalette.canvas.ignoresSafeArea())
        .task { saved = await NunaFoodStore.savedFoods(repo: repo); recent = await NunaFoodStore.recentFoods(repo: repo) }
        .nunaKeyboardDone()
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let p = NunaFoodPhoto.prepare(data) else {
                    estimateError = String(localized: "The selected photo could not be read."); return
                }
                await take(p.image, base64: p.base64)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            NunaCameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9), let p = NunaFoodPhoto.prepare(data) { Task { await take(p.image, base64: p.base64) } }
            }.ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { if page == .manual { page = .home } else { dismiss() } } label: { NunaBareIcon(page == .manual ? "chevron.left" : "xmark") }
                .buttonStyle(.plain).accessibilityLabel(Text(page == .manual ? "Back" : "Close"))
            Text(page == .manual ? "Type the numbers" : "Add food").font(.nuna(size: 20, weight: .heavy, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer(minLength: 8)
            Menu {
                ForEach(NunaMeal.allCases) { m in
                    Button { meal = m } label: { if meal == m { Label(m.singular, systemImage: "checkmark") } else { Text(m.singular) } }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(meal.singular).font(.nuna(size: 14, weight: .bold))
                    Image(systemName: "chevron.down").font(.nuna(size: 11, weight: .bold))
                }
                .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 14).frame(height: 36)
                // A fill and an outline that read against the sheet in both themes: it is a control, not a label.
                .background(NunaPalette.ink.opacity(0.13), in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).strokeBorder(NunaPalette.cardBorderHighlight, lineWidth: 1))
            }
            .accessibilityLabel(Text("Meal"))
        }
        .padding(.leading, 8).padding(.trailing, 18).padding(.top, 8).padding(.bottom, 6)
    }

    private var mealName: String {
        switch meal { case .breakfast: String(localized: "Breakfast"); case .lunch: String(localized: "Lunch"); case .dinner: String(localized: "Dinner"); case .snack: String(localized: "Snacks") }
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.onAccent).frame(maxWidth: .infinity).frame(height: 54)
                .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }

    // MARK: Home

    @ViewBuilder private var home: some View {
        anyaBox
        if let estimate {
            NunaAnyaFoodCard(spec: AnyaFoodSpec(meal: meal.rawValue, day: day, items: estimate.items), fixed: (meal, day)) { Task { try? await Task.sleep(nanoseconds: 700_000_000); dismiss() } }
                .id(estimate.items.map(\.name).joined())
        }
        foodsList
        Button { focused = false; page = .manual } label: {
            NunaCard(small: true) {
                NunaListRow("Type the numbers yourself", subtitle: "Calories and macros, saved for next time if you like", systemImage: "square.and.pencil", showsChevron: true)
            }
        }.buttonStyle(.plain)
    }

    /// The box for telling Anya: the words, a photo, and one round button to work it out.
    @ViewBuilder private var anyaBox: some View {
        if !coach.isConfigured {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connect Anya to log by telling her").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    Text("Connect Anya in More to describe a meal and have the calories and macros worked out for you.")
                        .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    if let image = mealPhoto {
                        HStack(spacing: 12) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(readingPhoto ? "Reading the photo…" : (coach.supportsImages ? "Anya will look at it" : "Read on this iPhone"))
                                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                            Spacer(minLength: 0)
                            Button { mealPhoto = nil; photoBase64 = nil; photoItem = nil; estimateError = nil } label: {
                                Image(systemName: "xmark.circle.fill").font(.nuna(size: 22, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(Text("Remove photo"))
                        }
                    }
                    TextField("", text: $description, prompt: Text(mealPhoto == nil ? "Two eggs and a plate of nasi goreng" : "Portion sizes, anything the photo does not show").foregroundStyle(NunaPalette.textMuted), axis: .vertical)
                        .font(.nuna(size: 17, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(2...6).focused($focused)
                    HStack(spacing: 10) {
                        if NunaCameraPicker.isAvailable { roundIcon("camera") { showCamera = true }.accessibilityLabel(Text("Take photo")) }
                        PhotosPicker(selection: $photoItem, matching: .images) { roundGlyph("photo.on.rectangle") }.buttonStyle(.plain).accessibilityLabel(Text("Choose photo"))
                        Spacer(minLength: 0)
                        Button { Task { await estimateMeal() } } label: {
                            Group {
                                if estimating || readingPhoto { ProgressView().tint(NunaPalette.onAccent) } else { Image(systemName: "sparkles").font(.nuna(size: 16, weight: .bold)) }
                            }
                            .foregroundStyle(NunaPalette.onAccent).frame(width: 46, height: 46).background(NunaPalette.accent, in: Circle())
                        }.buttonStyle(.plain).disabled(!canEstimate).opacity(canEstimate ? 1 : 0.4).accessibilityLabel(Text("Work out calories"))
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LinearGradient(colors: NunaAnyaWing.colors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                Text(photoNote).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                if let estimateError { Text(verbatim: estimateError).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.warning).fixedSize(horizontal: false, vertical: true).textCase(nil).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }

    private func roundIcon(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { roundGlyph(symbol) }.buttonStyle(.plain)
    }

    private func roundGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.nuna(size: 16, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 46, height: 46).background(NunaPalette.glassStrong, in: Circle())
    }

    /// What the person is told about where the photo goes.
    private var photoNote: LocalizedStringKey {
        if mealPhoto == nil { return "Only this description is sent to Anya, with none of your health data. She estimates each item; you check it before it is added." }
        return coach.supportsImages
            ? "The photo and your details go to the Anya provider you chose, with none of your health data. She estimates each item you can see; you check it before it is added."
            : "This Anya can't see photos, so the photo was read on this iPhone for food names and nothing was sent. Check the names, add portions, then work out the calories."
    }

    // MARK: Your foods

    private struct Food: Identifiable {
        let id: String; let name: String; let kcal: Double; let p: Double?; let c: Double?; let f: Double?; let savedID: String?; let source: String
    }

    /// Saved foods first, most used first, then what was eaten lately that is not already saved.
    private var foods: [Food] {
        var out = saved.map { Food(id: "s" + $0.id, name: $0.name, kcal: $0.kcal, p: $0.proteinG, c: $0.carbsG, f: $0.fatG, savedID: $0.id, source: "saved") }
        let names = Set(saved.map { $0.name.lowercased() })
        out += recent.filter { !names.contains($0.name.lowercased()) }.map { Food(id: "r" + $0.id, name: $0.name, kcal: $0.kcal, p: $0.proteinG, c: $0.carbsG, f: $0.fatG, savedID: nil, source: $0.source == "anya" ? "anya" : "saved") }
        return Array(out.prefix(10))
    }

    @ViewBuilder private var foodsList: some View {
        let list = foods
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                nunaTrendsCap("Your foods").padding(.leading, 4)
                NunaCard(small: true, padding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 8)) {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { NunaDivider() }
                            Button { Task { await add(f) } } label: { foodRow(f) }.buttonStyle(.plain)
                                .contextMenu {
                                    if let sid = f.savedID {
                                        Button(role: .destructive) { Task { await NunaFoodStore.deleteSaved(id: sid, repo: repo); saved = await NunaFoodStore.savedFoods(repo: repo) } } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func foodRow(_ f: Food) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: f.name).font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).lineLimit(1).textCase(nil)
                    if f.savedID != nil { Image(systemName: "bookmark.fill").font(.nuna(size: 10, weight: .bold)).foregroundStyle(NunaPalette.textMuted) }
                }
                let macros = [f.p.map { "P \(Int($0.rounded()))" }, f.c.map { "C \(Int($0.rounded()))" }, f.f.map { "F \(Int($0.rounded()))" }].compactMap { $0 }
                Text(verbatim: ([String(localized: "\(Int(f.kcal.rounded())) kcal")] + macros).joined(separator: " · ")).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 6)
            Image(systemName: "plus").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).frame(width: 36, height: 36).background(NunaPalette.glassStrong, in: Circle())
        }
        .padding(.vertical, 10).contentShape(Rectangle())
    }

    private func add(_ f: Food) async {
        await NunaFoodStore.add([NunaFoodStore.entry(day: day, meal: meal, name: f.name, kcal: f.kcal, proteinG: f.p, carbsG: f.c, fatG: f.f, source: f.source, repo: repo)], repo: repo)
        if let sid = f.savedID { await NunaFoodStore.bump(sid, repo: repo) }
        dismiss()
    }

    // MARK: Type the numbers

    @ViewBuilder private var manual: some View {
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

    private func macroField(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        NunaFormField(label) {
            HStack(spacing: 4) {
                TextField("", text: text, prompt: Text("0").foregroundStyle(NunaPalette.textMuted)).keyboardType(.decimalPad).focused($focused)
                Text("g").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private func addManual() async {
        guard let kcal else { return }
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Quick add") : name
        await NunaFoodStore.add([NunaFoodStore.entry(day: day, meal: meal, name: label, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, source: "manual", repo: repo)], repo: repo)
        if keepIt { await NunaFoodStore.keep(name: label, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, repo: repo) }
        dismiss()
    }

    // MARK: Anya

    /// Keeps the photo; when Anya cannot see it, reads food names from it here and puts them in the box for the person to correct.
    private func take(_ image: UIImage, base64: String) async {
        mealPhoto = image; photoBase64 = base64; estimate = nil; estimateError = nil
        guard !coach.supportsImages else { return }
        readingPhoto = true; defer { readingPhoto = false }
        let names = await NunaFoodPhoto.labels(for: image)
        if names.isEmpty {
            estimateError = String(localized: "Nothing recognisable in the photo. Describe the meal in words.")
        } else if description.trimmingCharacters(in: .whitespaces).isEmpty {
            description = names.joined(separator: ", ")
        }
    }

    private func estimateMeal() async {
        focused = false; estimating = true; estimate = nil; estimateError = nil
        defer { estimating = false }
        let image = coach.supportsImages ? photoBase64 : nil
        // A small on-device model now and then answers in prose; one more try with the same words is usually enough.
        var spec: AnyaFoodSpec?
        var answered = false
        for _ in 0..<2 {
            guard let reply = await coach.estimateFood(description, imageBase64: image) else { continue }
            answered = true
            if let f = AnyaActions.parseFood(from: reply) { spec = f; break }
        }
        if let spec { estimate = spec }
        else if answered { estimateError = String(localized: "Anya couldn't read that as food. Try naming each item and its portion.") }
        else { estimateError = String(localized: "Anya couldn't answer. Check her connection in More, then try again.") }
    }
}
#endif

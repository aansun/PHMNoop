#if os(iOS) && DEBUG
import Foundation
import StrandAnalytics

/// Debug only: `--qa-anya <scenario>` runs every Anya surface once against the data in the store and writes what she read and what she said to
/// Documents/qa-<scenario>.json, so the surfaces can be checked one by one across different data (docs/anya/QA.md). Not part of any release.
@MainActor
enum NunaAnyaQA {
    static func runIfRequested(model: AppModel) {
        guard let i = CommandLine.arguments.firstIndex(of: "--qa-anya"), i + 1 < CommandLine.arguments.count else { return }
        let scenario = CommandLine.arguments[i + 1]
        // `--qa-only plan,program` runs just those blocks (pages, chat, food, program, breath, plan, brief), to iterate on one.
        var only: Set<String>?
        if let j = CommandLine.arguments.firstIndex(of: "--qa-only"), j + 1 < CommandLine.arguments.count { only = Set(CommandLine.arguments[j + 1].split(separator: ",").map(String.init)) }
        Task { await run(model, scenario: scenario, only: only) }
    }

    private static func metric(_ key: String, _ title: String, _ unit: String, _ decimals: Int, _ better: Bool?, source: String = "my-whoop") -> NunaAnyaMetric {
        NunaAnyaMetric(key: key, source: source, title: title, unit: unit, decimals: decimals, higherIsBetter: better)
    }

    private static func run(_ model: AppModel, scenario: String, only: Set<String>?) async {
        func on(_ k: String) -> Bool { only?.contains(k) ?? true }
        try? await Task.sleep(nanoseconds: 12_000_000_000)
        let coach = model.coach
        let scale = UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? EffortScale.whoop.rawValue)
        var out: [String: Any] = ["scenario": scenario, "provider": coach.provider.rawValue, "configured": coach.isConfigured, "consent": coach.dataConsent, "scale": "\(scale)"]
        func timed<T>(_ f: () async -> T) async -> (T, Double) { let t = Date(); let r = await f(); return (r, Date().timeIntervalSince(t)) }

        let compact = await coach.buildFullContext(compact: true)
        out["compactContext"] = compact + "\n" + (coach.comparatorBlock([.recovery, .hrv, .rhr, .sleep, .strain, .spo2, .resp]) ?? "")
        out["compactContextChars"] = compact.count
        out["compactSystemChars"] = coach.buildSystemPrompt(compact: true).count
        out["fullSystemChars"] = coach.systemPrompt.count

        // Pages: the pill and the sheet's text, exactly as the page runs them.
        let pages: [(String, NunaAnyaMetric?)] = [
            ("Recovery", nil), ("Strain", nil), ("sleep", nil),
            ("stress", metric("stress", "Stress", "", 1, false)),
            ("HRV", metric("hrv", "HRV", "ms", 0, true)),
            ("Resting heart rate", metric("rhr", "Resting heart rate", "bpm", 0, false)),
            ("Respiratory rate", metric("resp_rate", "Respiratory rate", "/min", 1, nil)),
            ("Weight", metric("weight", "Weight", "kg", 1, nil, source: "apple-health")),
            ("Skin temperature", metric("skin_temp", "Skin temperature", "°C", 1, nil)),
        ]
        var pageOut: [[String: Any]] = []
        for (ctx, m) in pages where on("pages") {
            let read = await NunaAnyaReader.read(context: ctx, metric: m, repo: model.repo, profile: model.profile, scale: scale)
            let fm = NunaAnyaFloatingModel()
            let (_, secs) = await timed { await fm.analyse(context: ctx, metric: m, pageLine: nil, repo: model.repo, profile: model.profile, coach: coach, scale: scale) }
            var e: [String: Any] = ["page": ctx, "local": fm.local ?? "nil", "headline": fm.headline ?? "nil", "text": fm.explanation ?? "nil", "seconds": secs]
            if let v = read?.verdict { e["verdict"] = "\(v.level.rawValue): \(v.why)"; e["topic"] = v.topic.rawValue; e["localAdvice"] = v.advice } else { e["verdict"] = "none" }
            pageOut.append(e)
        }
        out["pages"] = pageOut

        // Module questions (the chips): the first two real questions of each module.
        var chatOut: [[String: Any]] = []
        for module in [NunaAnyaModule.today, .health, .trends, .sleep, .workouts, .nutrition, .breathing, .device] where on("chat") {
            let ctx = "\(module)"
            let read = await NunaAnyaReader.read(context: ctx, repo: model.repo, profile: model.profile, scale: scale)
            // The page as the sheet builds it: the reading, its verdict, and the module's own data pack.
            var page = ctx + (read.map { "\n\n" + NunaMark.plain(NunaMark.compose(headline: $0.headline, detail: $0.detail)) } ?? "")
            if let v = read?.verdict { page += "\n\n" + v.providerLine }
            if let pack = await NunaAnyaPack.text(for: module, repo: model.repo, profile: model.profile, live: model.live) { page += "\n\n" + pack }
            for q in NunaAnyaReader.questions(module).filter({ $0.kind == .ask && !$0.prompt.isEmpty }).prefix(2) {
                // The strap's questions are answered on the phone, as the sheet does.
                let (ans, secs): (String?, Double) = module == .device
                    ? (NunaAnyaPack.deviceAnswer(question: q.prompt, live: model.live), 0)
                    : await timed { await coach.answerContextualMessage(pageContext: page, notice: nil, history: [], question: q.prompt) }
                chatOut.append(["module": ctx, "question": q.prompt, "answer": ans ?? "nil", "seconds": secs,
                                "known": page + "\n" + (coach.comparatorBlock(module: AnyaSurface.Module.of(context: ctx)) ?? "")])
            }
        }
        out["chat"] = chatOut

        // Artefacts and the brief.
        if on("food") {
        let meal = "2 telur dadar dan 1 piring nasi goreng"
        let (food, tf) = await timed { await coach.estimateFood(meal) }
        out["food"] = ["input": meal, "output": food ?? "nil", "seconds": tf]
        }
        if on("program") {
        let (prog, tp) = await timed { await coach.suggestProgram(brief: "3 days a week, dumbbells only, build muscle, 45 minutes, intermediate", trainingSummary: "Chest 6 sets last week, back 4, legs 2, shoulders 4. Legs recovered, chest not fully recovered.") }
        out["program"] = ["output": prog ?? "nil", "parsed": prog.flatMap { AnyaActions.parseProgram(from: $0) } != nil, "seconds": tp]
        }
        if on("breath") {
        let (br, tbr) = await timed { await coach.suggestBreath(request: "calm down before sleep, 5 minutes", context: "") }
        out["breath"] = ["output": br ?? "nil", "parsed": br.flatMap { AnyaActions.parseBreath(from: $0) } != nil, "seconds": tbr]
        }
        if on("plan") {
        let snap = await NunaNutritionSnapshot.build(repo: model.repo, profile: model.profile, includeLabBook: false)
        let (plan, tpl) = await timed { await coach.suggestNutritionPlan(snapshot: snap) }
        out["plan"] = ["output": plan ?? "nil", "parsed": (plan.map { AnyaActions.parse($0) } ?? []).contains { if case .plan = $0 { return true } else { return false } }, "seconds": tpl]
        }
        if on("brief") {
        let (mb, tmb) = await timed { await coach.generateBrief() }
        out["morningBrief"] = ["output": mb ?? "nil", "seconds": tmb]
        }

        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
           let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: dir.appendingPathComponent("qa-\(scenario).json"))
        }
        NSLog("[AnyaQA] done %@", scenario)
    }
}
#endif

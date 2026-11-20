// === PHM OVERLAY (PHMNOOP) ===
// On-device Apple Intelligence provider for the Coach, via Apple's Foundation Models framework.
//
// No API key, no network: the prompt is answered by the system on-device model and never leaves the
// device. Requires an Apple-Intelligence-capable device on iOS 26 / macOS 26+. On an older OS, an
// SDK without the framework, or an ineligible / not-yet-enabled device, every call fails with a
// clear, actionable message instead of a silent nothing.
//
// Implements only `send` + `fetchModels`; the protocol's default `stream` (send + one delta) and
// `streamWithImage` (delegates to stream) cover the rest — on-device replies are fast, so a single
// delta is fine and avoids depending on the streaming API's shape.

#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

struct AppleIntelligenceClient: AIProviderClient {

    /// The single "model" id surfaced in the picker (there is one system model).
    static let modelId = "on-device"

    /// True when the on-device model can answer on THIS device right now. False when the OS is too old,
    /// the framework is absent from the build, the hardware is ineligible, Apple Intelligence is off, or
    /// the model assets are still downloading. Cheap + synchronous — safe to read from `isConfigured`.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }

    /// A human-readable reason on-device AI can't be used right now, or nil when it can.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return "Apple Intelligence isn't available (\(String(describing: reason))). Check "
                    + "Settings › Apple Intelligence & Siri, or this device may not support it."
            }
        } else {
            return "Apple Intelligence needs iOS 26 / macOS 26 or later."
        }
        #else
        return "This build was compiled without the Apple Intelligence framework."
        #endif
    }

    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw AICoachError.server(0, AppleIntelligenceClient.unavailableReason
                    ?? "Apple Intelligence is unavailable on this device.")
            }
            let llm = LanguageModelSession(instructions: systemPrompt)
            let prompt = AppleIntelligenceClient.renderPrompt(messages)
            guard !prompt.isEmpty else { throw AICoachError.emptyQuestion }
            do {
                let response = try await llm.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw AICoachError.emptyReply("Apple Intelligence returned an empty reply.")
                }
                return text
            } catch let e as AICoachError {
                throw e
            } catch {
                // Guardrail violations, context-window overflow, etc. surface with their own message.
                throw AICoachError.server(0, "Apple Intelligence: \(error.localizedDescription)")
            }
        } else {
            throw AICoachError.server(0, "Apple Intelligence needs iOS 26 / macOS 26 or later.")
        }
        #else
        throw AICoachError.server(0, "This build was compiled without the Apple Intelligence framework.")
        #endif
    }

    func fetchModels(key: String, session: URLSession) async throws -> [String] {
        [AppleIntelligenceClient.modelId]
    }

    /// Flatten the transcript into one prompt. The persona/system prompt is passed separately as the
    /// session's `instructions`, so here we only carry the conversation turns. A single-turn ask is
    /// sent verbatim; a multi-turn one is role-labelled and ends on an `Assistant:` cue to continue.
    private static func renderPrompt(_ messages: [(role: ChatMessage.Role, content: String)]) -> String {
        guard !messages.isEmpty else { return "" }
        if messages.count == 1 { return messages[0].content }
        var lines: [String] = []
        for m in messages {
            lines.append((m.role == .user ? "User: " : "Assistant: ") + m.content)
        }
        lines.append("Assistant:")
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - Food estimate by guided generation

#if canImport(FoundationModels)
/// One dish or drink of a meal, as the on-device model fills it in. Guided generation returns exactly this shape, so there is no JSON to parse out of
/// prose, which a small model gets wrong now and then.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedFoodItem {
    @Guide(description: "The dish or drink, named as the person named it, in their own language")
    var name: String
    @Guide(description: "The portion: what the person said, such as 1 plate, 2 eggs or 150 g; a typical serving when none was named")
    var amount: String
    @Guide(description: "Kilocalories in this portion, consistent with the macros: about 4 per gram of protein and carbohydrate and 9 per gram of fat", .range(0...3000))
    var kcal: Int
    @Guide(description: "Grams of protein in this portion", .range(0...200))
    var proteinG: Int
    @Guide(description: "Grams of carbohydrate in this portion", .range(0...400))
    var carbsG: Int
    @Guide(description: "Grams of fat in this portion", .range(0...200))
    var fatG: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedMeal {
    @Guide(description: "One entry for each dish or drink the person listed, with its own portion", .maximumCount(12))
    var items: [GeneratedFoodItem]
}
#endif

extension AppleIntelligenceClient {
    /// The calories and macros of a described meal, worked out on this iPhone by guided generation, as the `anya-food` block the Add food sheet reads.
    /// nil when the on-device model is not available or does not answer; the caller then asks the way it does for any other provider.
    static func estimateMeal(_ description: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let llm = LanguageModelSession(instructions: """
            You estimate calories and macros for a food diary. The person says what they ate or drank, in any language. Give each item its own estimate at the portion \
            they named. Use typical values, and for Indonesian and other local dishes the usual home or street-food serving. Never judge or advise on the food.
            """)
        do {
            let meal = try await llm.respond(to: "What the person ate:\n" + description, generating: GeneratedMeal.self).content
            let items: [[String: Any]] = meal.items.map {
                // The macros decide the calories: the model's own kcal can be far from 4 kcal per gram of protein and carbohydrate and 9 per gram of fat, and a
                // diary whose calories do not follow from its macros cannot be trusted. Where they differ by more than a third, the macros win.
                let fromMacros = 4 * $0.proteinG + 4 * $0.carbsG + 9 * $0.fatG
                let kcal = fromMacros > 0 && abs(Double($0.kcal - fromMacros)) / Double(fromMacros) > 0.34 ? fromMacros : $0.kcal
                return ["name": $0.name, "amount": $0.amount, "kcal": kcal, "proteinG": $0.proteinG, "carbsG": $0.carbsG, "fatG": $0.fatG]
            }
            guard !items.isEmpty, let data = try? JSONSerialization.data(withJSONObject: ["items": items]), let json = String(data: data, encoding: .utf8) else { return nil }
            return "An estimate, worked out on this iPhone.\n```anya-food\n" + json + "\n```"
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

// MARK: - Assistant replies by guided generation

#if canImport(FoundationModels)
/// What Anya says about one page: the four parts as a typed value, so the on-device model cannot drop a part or change the shape.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedPageInsight {
    @Guide(description: "One plain sentence of at most 14 words: what the reading is and whether it is good, fair or needs attention for this person")
    var headline: String
    @Guide(description: "The figure against this person's own baseline, citing two or three numbers at most, exactly as given")
    var see: String
    @Guide(description: "What it most likely means for this person, from their own data: the likeliest cause, in plain words, without a preamble such as 'the data shows'")
    var mean: String
    @Guide(description: "One concrete next step of your own for this reading, with when and how much: a change that would move a poor or slipping reading, or the habit to keep for a good one. Not advice for another page")
    var advice: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GeneratedBreathPhase: String { case inhale, hold, exhale }

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum GeneratedBreathGoal: String { case calm, sleep, focus, energize, recover }

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedBreathStage {
    var phase: GeneratedBreathPhase
    @Guide(description: "Seconds: inhale 2 to 10, hold 1 to 8, exhale 2 to 12", .range(1...12))
    var seconds: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedBreath {
    @Guide(description: "One or two plain sentences: what it is for and how it should feel, without comparisons or similes")
    var explanation: String
    @Guide(description: "A short clear title, in the person's language")
    var title: String
    var goal: GeneratedBreathGoal
    @Guide(description: "Minutes", .range(1...30))
    var minutes: Int
    @Guide(description: "The stages that repeat, in order; unless the person asked for focus or energy the exhale is at least as long as the inhale, and never a hold over 8 seconds", .count(2...6))
    var stages: [GeneratedBreathStage]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedProgramItem {
    @Guide(description: "The exercise named as a standard exercise library names it, in English and in full, such as Barbell Bench Press - Medium Grip")
    var exercise: String
    @Guide(description: "Working sets", .range(1...6))
    var sets: Int
    @Guide(description: "Lowest reps of the range", .range(1...30))
    var repsLow: Int
    @Guide(description: "Highest reps of the range", .range(1...30))
    var repsHigh: Int
    @Guide(description: "Rest between sets in seconds", .range(20...300))
    var restSec: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedProgramDayItems {
    @Guide(description: "Compound lifts first; about 3.5 minutes per working set including rest fits the session length", .count(3...6))
    var items: [GeneratedProgramItem]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedProgramOutline {
    @Guide(description: "At most 40 words: how the days are split and how to progress")
    var explanation: String
    @Guide(description: "A short name such as Upper / lower, 4 days")
    var name: String
    @Guide(description: "One rule for progression, one sentence")
    var note: String
    @Guide(description: "A short title for each training day, one per day asked for, 5 at most, such as Day A: Upper", .count(1...5))
    var dayTitles: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct GeneratedNutritionPlan {
    @Guide(description: "3 to 6 plain sentences on how the target, pace and macros follow from this person's own figures (weight, trend, sleep, recovery, training, intake, any Lab Book value)")
    var explanation: String
    @Guide(description: "Daily kilocalories, never below 1200", .range(1200...4500))
    var targetKcal: Int
    @Guide(description: "Kilograms per week in tenths: -10 to 5, negative to lose", .range(-10...5))
    var paceTenthsKgPerWeek: Int
    @Guide(description: "Protein in tenths of a gram per kg a day: 8 to 24", .range(8...24))
    var proteinTenthsPerKg: Int
    @Guide(description: "Fat as a percent of energy: 20 to 35", .range(20...35))
    var fatPercent: Int
    @Guide(description: "One short line per data point the plan rests on", .maximumCount(5))
    var reasons: [String]
    @Guide(description: "What to watch or take to a clinician, one line each; empty when nothing", .maximumCount(3))
    var cautions: [String]
}
#endif

extension AppleIntelligenceClient {
    private static func json(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// A page's insight by guided generation, as the labelled paragraphs `AnyaPageInsight` reads back. nil when the model is not available or does not answer,
    /// so the caller asks the ordinary way.
    static func pageInsight(system: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let llm = LanguageModelSession(instructions: system)
        do {
            let r = try await llm.respond(to: prompt, generating: GeneratedPageInsight.self).content
            func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            return "HEADLINE: \(clean(r.headline))\nSEE: \(clean(r.see))\nMEAN: \(clean(r.mean))\nDO: \(clean(r.advice))"
        } catch { NSLog("[AnyaGuided] page insight failed: %@", String(describing: error)); return nil }
        #else
        return nil
        #endif
    }

    /// A breathing exercise as the reply and `anya-breath` block the Breathing screen reads.
    static func breath(rules: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let llm = LanguageModelSession(instructions: rules)
        do {
            let b = try await llm.respond(to: prompt, generating: GeneratedBreath.self).content
            let stages: [[String: Any]] = b.stages.map { ["phase": $0.phase.rawValue, "seconds": $0.seconds] }
            guard let block = json(["title": b.title, "goal": b.goal.rawValue, "minutes": b.minutes, "stages": stages] as [String: Any]) else { return nil }
            // A model that is told not to use a comparison sometimes does: a sentence with "like a" or "as if" is dropped rather than shown.
            let sentences = b.explanation.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let plain = sentences.filter { let t = $0.lowercased(); return !t.contains(" like a ") && !t.contains(" like an ") && !t.contains(" as if ") }
            let explanation = (plain.isEmpty ? sentences.prefix(1).map { _ in "A slow, steady rhythm to settle you" } : plain).joined(separator: ". ") + "."
            return explanation + "\n```anya-breath\n" + block + "\n```"
        } catch { NSLog("[AnyaGuided] breath failed: %@", String(describing: error)); return nil }
        #else
        return nil
        #endif
    }

    /// A gym program as the paragraph and `anya-program` block the Gym tab reads. Built in two bounded steps (the split of the week, then each day on its own):
    /// asked for in one piece the model ran on until the window was full.
    static func program(rules: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        do {
            let outline = try await LanguageModelSession(instructions: rules).respond(
                to: prompt + "\n\nFirst give only the split of the week: the name, the progression rule, a short explanation and the title of each training day.",
                generating: GeneratedProgramOutline.self, options: GenerationOptions(maximumResponseTokens: 400)).content
            var days: [[String: Any]] = []
            for (i, title) in outline.dayTitles.prefix(5).enumerated() {
                let day = try await LanguageModelSession(instructions: rules).respond(
                    to: prompt + "\n\nThe split: " + outline.dayTitles.joined(separator: "; ") + ".\nNow build ONLY day \(i + 1), \(title): the exercises with sets, rep range and rest.",
                    generating: GeneratedProgramDayItems.self, options: GenerationOptions(maximumResponseTokens: 700)).content
                days.append(["title": title, "items": day.items.map { ["exercise": $0.exercise, "sets": $0.sets, "repsLow": min($0.repsLow, $0.repsHigh), "repsHigh": max($0.repsLow, $0.repsHigh), "restSec": $0.restSec] as [String: Any] }])
            }
            guard !days.isEmpty, let block = json(["name": outline.name, "note": outline.note, "days": days] as [String: Any]) else { return nil }
            return outline.explanation + "\n```anya-program\n" + block + "\n```"
        } catch { NSLog("[AnyaGuided] program failed: %@", String(describing: error)); return nil }
        #else
        return nil
        #endif
    }

    /// A nutrition plan as the line and `anya-plan` block the Strategy screen reads.
    /// `maintenanceKcal` is set when the person has no goal weight: the plan is then maintenance at their estimated energy use, whatever the model wrote.
    static func nutritionPlan(rules: String, prompt: String, maintenanceKcal: Int? = nil) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let llm = LanguageModelSession(instructions: rules)
        do {
            let p = try await llm.respond(to: prompt, generating: GeneratedNutritionPlan.self, options: GenerationOptions(maximumResponseTokens: 700)).content
            let object: [String: Any] = ["targetKcal": maintenanceKcal ?? p.targetKcal, "paceKgPerWeek": maintenanceKcal == nil ? Double(p.paceTenthsKgPerWeek) / 10 : 0.0, "proteinPerKg": Double(p.proteinTenthsPerKg) / 10,
                                         "fatShare": Double(p.fatPercent) / 100, "explanation": p.explanation, "reasons": p.reasons, "cautions": p.cautions]
            guard let block = json(object) else { return nil }
            return "A suggestion, worked out on this iPhone.\n```anya-plan\n" + block + "\n```"
        } catch { NSLog("[AnyaGuided] plan failed: %@", String(describing: error)); return nil }
        #else
        return nil
        #endif
    }
}

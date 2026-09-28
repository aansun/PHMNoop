import XCTest
@testable import Strand
import WhoopProtocol
import WhoopStore
import StrandAnalytics

/// Covers the two small AI-Coach additions:
///   1. The editable system prompt — persisted in UserDefaults under `AICoachEngine.systemPromptKey`,
///      read FRESH per request via `systemPrompt`, with a Reset-to-default that clears the override.
///   2. The derived Baevsky Stress Index context line — its pure formatter (`stressIndexSummary`) and
///      that the line uses the SAME `StressIndex.stressIndex(rr:)` computation StressView does.
///
/// Both paths are UserDefaults / pure — no network, no Keychain — so they run headlessly.
@MainActor
final class AICoachPromptAndStressTests: XCTestCase {

    /// A fresh engine plus a clean slate: clear the prompt key before and after so tests don't leak.
    private func makeEngine() -> AICoachEngine {
        UserDefaults.standard.removeObject(forKey: AICoachEngine.systemPromptKey)
        return AICoachEngine(repo: Repository(deviceId: "test-aicoach-prompt"))
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AICoachEngine.systemPromptKey)
        super.tearDown()
    }

    // MARK: - Feature 1: editable system prompt

    func testDefaultsToBuiltInPromptWhenNothingStored() {
        let engine = makeEngine()
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
        XCTAssertFalse(engine.hasCustomSystemPrompt)
    }

    func testEditPersistsAndIsReadFreshOnNextSend() {
        let engine = makeEngine()
        let custom = "You are a terse cycling coach. Answer in two sentences."
        engine.customSystemPrompt = custom

        // Persisted under the documented key, and surfaced by the fresh-read property.
        XCTAssertEqual(UserDefaults.standard.string(forKey: AICoachEngine.systemPromptKey), custom)
        XCTAssertEqual(engine.systemPrompt, custom)
        XCTAssertTrue(engine.hasCustomSystemPrompt)

        // "Read fresh per send" — a write straight to UserDefaults (as another session might) is
        // picked up by the next `systemPrompt` read without rebuilding the engine.
        let edited = custom + " Always cite a number."
        UserDefaults.standard.set(edited, forKey: AICoachEngine.systemPromptKey)
        XCTAssertEqual(engine.systemPrompt, edited)
    }

    func testResetRestoresDefaultAndClearsTheKey() {
        let engine = makeEngine()
        engine.customSystemPrompt = "Custom override."
        XCTAssertTrue(engine.hasCustomSystemPrompt)

        engine.resetSystemPrompt()
        XCTAssertNil(UserDefaults.standard.string(forKey: AICoachEngine.systemPromptKey))
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
        XCTAssertFalse(engine.hasCustomSystemPrompt)
    }

    func testBlankOverrideNeverSendsAnEmptyPrompt() {
        let engine = makeEngine()
        engine.customSystemPrompt = "   \n  "   // whitespace only
        // A blank override clears the key, so the default is sent — never an empty system prompt.
        XCTAssertNil(UserDefaults.standard.string(forKey: AICoachEngine.systemPromptKey))
        XCTAssertEqual(engine.systemPrompt, AICoachEngine.defaultSystemPrompt)
        XCTAssertFalse(engine.hasCustomSystemPrompt)
    }

    func testBuiltInPromptPrioritizesConciseActionableReplies() {
        let prompt = AICoachEngine.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Answer the user's question first"))
        XCTAssertTrue(prompt.contains("under 120 words"))
        XCTAssertTrue(prompt.contains("2-3 concrete actions"))
        XCTAssertTrue(prompt.contains("Do not use tables"))
        XCTAssertTrue(prompt.contains("Talk like a perceptive human coach"))
        XCTAssertTrue(prompt.contains("First form a body-state read from the pattern"))
    }

    // MARK: - Feature 3: body-state synthesis

    func testBodyStateConnectsSleepAndAutonomicSignalsToAction() {
        let days = [
            metric(day: "2026-09-01", sleep: 450, hrv: 65, rhr: 52, charge: 72, effort: 10),
            metric(day: "2026-09-02", sleep: 440, hrv: 64, rhr: 52, charge: 70, effort: 11),
            metric(day: "2026-09-03", sleep: 330, hrv: 48, rhr: 57, charge: 68, effort: 12),
        ]

        let summary = AICoachEngine.bodyStateSummary(current: days[2], history: days)

        XCTAssertTrue(summary.contains("under-recovered despite the Charge score"), summary)
        XCTAssertTrue(summary.contains("sleep 5.5h"), summary)
        XCTAssertTrue(summary.contains("HRV 48ms"), summary)
        XCTAssertTrue(summary.contains("RHR 57bpm"), summary)
        XCTAssertTrue(summary.contains("Keep intensity controlled"), summary)
    }

    func testBodyStateDoesNotInventAConclusionFromSparseData() {
        let current = metric(day: "2026-09-03", sleep: nil, hrv: nil, rhr: nil, charge: nil, effort: 4)
        let summary = AICoachEngine.bodyStateSummary(current: current, history: [current])

        XCTAssertTrue(summary.contains("steady but not a clear green light"), summary)
        XCTAssertTrue(summary.contains("Confidence limited"), summary)
        XCTAssertTrue(summary.contains("recent effort 4.0"), summary)
    }

    private func metric(day: String, sleep: Double?, hrv: Double?, rhr: Int?, charge: Double?, effort: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv,
                    recovery: charge, strain: effort, exerciseCount: nil)
    }

    // MARK: - Feature 2: derived stress line

    func testStressIndexSummaryFormatsOneRoundedNumber() {
        // The line carries exactly the rounded SI plus the labelled proxy note — a derived summary.
        let line = AICoachEngine.stressIndexSummary(si: 223.82920110192836)
        XCTAssertTrue(line.hasPrefix("Stress (SI): 224 "), "rounds and labels the SI: \(line)")
        XCTAssertTrue(line.contains("Baevsky Stress Index"))
        // No raw R-R reading leaks into the summary — it's a single derived number only.
        XCTAssertFalse(line.contains("700"))
        XCTAssertFalse(line.contains("ms"), "no raw R-R values in the summary line")
    }

    func testSummaryNumberMatchesStressViewComputation() {
        // The SAME 22-beat golden series StressIndexTests pins (SI ≈ 223.83 → rounds to 224). The coach
        // line must report the value `StressIndex.stressIndex(rr:)` produces — the exact StressView path.
        let raw: [Double] = [700, 720, 740, 760, 780, 800, 820, 840, 860, 800, 800,
                             800, 800, 820, 780, 800, 810, 790, 800, 800, 805, 795]
        let rr = raw.enumerated().map { RRInterval(ts: 1000 + $0.offset, rrMs: Int($0.element)) }
        let si = StressIndex.stressIndex(rr: rr)
        XCTAssertNotNil(si)
        let expected = "Stress (SI): \(Int(si!.rounded())) "
        XCTAssertTrue(AICoachEngine.stressIndexSummary(si: si!).hasPrefix(expected))
    }
}

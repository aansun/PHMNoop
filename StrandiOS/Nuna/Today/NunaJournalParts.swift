#if os(iOS)
import SwiftUI
import StrandDesign

/// What the journal keeps beside the yes and no of a behaviour: how much, and when it last happened, and the day's note. These live in the
/// phone's defaults under their own keys, not in the journal table, so they never read as questions in an export or in the insights.
enum NunaJournalExtras {
    struct Spec { let count: String; let time: String }

    /// The follow-ups a behaviour opens when it is answered yes.
    static func spec(_ canonical: String) -> Spec? {
        let c = canonical.lowercased()
        if c.contains("caffeine") { return Spec(count: String(localized: "How many servings of caffeine did you have?"), time: String(localized: "When was your last serving?")) }
        if c.contains("alcohol") { return Spec(count: String(localized: "How many drinks did you have?"), time: String(localized: "When was your last drink?")) }
        return nil
    }

    private static func key(_ day: String, _ q: String, _ field: String) -> String { "journal.extra.\(day).\(q).\(field)" }
    static func value(day: String, _ q: String, _ field: String) -> Double? { UserDefaults.standard.object(forKey: key(day, q, field)) as? Double }
    static func set(_ v: Double?, day: String, _ q: String, _ field: String) {
        if let v { UserDefaults.standard.set(v, forKey: key(day, q, field)) } else { UserDefaults.standard.removeObject(forKey: key(day, q, field)) }
    }
    static func note(day: String) -> String { UserDefaults.standard.string(forKey: "journal.note.\(day)") ?? "" }
    static func setNote(_ s: String, day: String) { UserDefaults.standard.set(s, forKey: "journal.note.\(day)") }

    /// Minutes since midnight a slider can rest on: 06:00 to 23:30, every half hour.
    static let timeRange: ClosedRange<Double> = 360...1410

    static func clock(_ minutes: Double) -> String {
        var c = DateComponents(); c.hour = Int(minutes) / 60; c.minute = Int(minutes) % 60
        let d = Calendar.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }
}

/// A slider the way the reference draws it: a plain grey track and a white round handle that starts at the left, with nothing chosen until it moves.
struct NunaJournalTimeSlider: View {
    @Binding var value: Double?

    private var fraction: CGFloat {
        guard let value else { return 0 }
        let r = NunaJournalExtras.timeRange
        return CGFloat((value - r.lowerBound) / (r.upperBound - r.lowerBound))
    }

    var body: some View {
        GeometryReader { geo in
            let thumb: CGFloat = 31, travel = geo.size.width - thumb
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.42, green: 0.43, blue: 0.46)).frame(height: 3.5)
                Circle().fill(Color.white).frame(width: thumb, height: thumb).shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max((g.location.x - thumb / 2) / travel, 0), 1)
                let r = NunaJournalExtras.timeRange
                let raw = r.lowerBound + Double(f) * (r.upperBound - r.lowerBound)
                value = (raw / 30).rounded() * 30
            })
        }
        .frame(height: 36)
        .accessibilityValue(Text(verbatim: value.map(NunaJournalExtras.clock) ?? "–"))
        .accessibilityAdjustableAction { dir in
            let r = NunaJournalExtras.timeRange
            let cur = value ?? r.lowerBound
            value = min(max(cur + (dir == .increment ? 30 : -30), r.lowerBound), r.upperBound)
        }
    }
}

/// Reads a sentence ("had two coffees and no alcohol, ate dinner late") and works out which behaviours it answers, on this phone. A behaviour counts
/// when the sentence uses one of its distinctive words (or most of its words); a "no", "not" or "tidak" beside it makes the answer no.
enum NunaJournalSmartLog {
    private static let stop: Set<String> = ["did", "you", "your", "the", "any", "have", "had", "has", "was", "were", "and", "for", "with", "that", "this", "day", "late", "today", "yesterday", "tonight"]
    private static let synonyms: [String: String] = [
        "ate": "eat", "eaten": "eat", "drank": "drink", "drunk": "drink", "coffee": "caffeine", "kopi": "caffeine", "tea": "caffeine", "teh": "caffeine",
        "espresso": "caffeine", "latte": "caffeine", "beer": "alcohol", "wine": "alcohol", "bir": "alcohol", "whiskey": "alcohol", "alkohol": "alcohol",
        "makan": "eat", "minum": "drink", "snacks": "snack", "camilan": "snack", "dinner": "dinner", "magnesium": "magnesium", "protein": "protein",
    ]
    private static let negations: Set<String> = ["no", "not", "didn't", "didnt", "without", "never", "tidak", "nggak", "gak", "belum", "ga"]

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init).map { w in
            if let m = synonyms[w] { return m }
            var t = w
            for suffix in ["ing", "ed", "s"] where t.count > 4 && t.hasSuffix(suffix) { t.removeLast(suffix.count); break }
            return synonyms[t] ?? t
        }
    }

    static func answers(from text: String, items: [JournalCatalogItem]) -> [(canonical: String, yes: Bool)] {
        let key = items.filter { !$0.kind.isNumeric }.map { ($0, Set(tokens($0.display).filter { $0.count > 2 && !stop.contains($0) })) }
        var df: [String: Int] = [:]
        for (_, set) in key { for t in set { df[t, default: 0] += 1 } }
        let clauses = text.lowercased().split(whereSeparator: { ",.;\n!?".contains($0) }).flatMap { $0.components(separatedBy: " and ") }.flatMap { $0.components(separatedBy: " dan ") }
        var out: [String: Bool] = [:]
        for clause in clauses {
            let words = Set(tokens(clause))
            let negated = !Set(clause.split(separator: " ").map(String.init)).isDisjoint(with: negations)
            for (item, set) in key where !set.isEmpty {
                let hit = set.intersection(words)
                let distinctive = hit.contains { df[$0] == 1 }
                if distinctive || (set.count >= 2 && Double(hit.count) >= Double(set.count) * 0.6) { out[item.canonical] = !negated }
            }
        }
        return out.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }
}

/// "Smart log": one box to write the day in, in your own words; what it answers is filled in and can be changed after.
struct NunaJournalSmartSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smart log with Anya").font(.nuna(size: 20, weight: .semibold)).foregroundStyle(.white).padding(.top, 26)
            Text("Write what happened, like “two coffees, no alcohol, ate dinner late”. Matching answers are filled in for you to check.")
                .font(.nuna(size: 14.5, weight: .regular)).foregroundStyle(.white.opacity(0.65))
            TextField("", text: $text, prompt: Text("What happened today?").foregroundStyle(.white.opacity(0.4)), axis: .vertical)
                .font(.nuna(size: 18, weight: .regular)).foregroundStyle(.white).lineLimit(3...8).focused($focused)
                .padding(16).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button { onSave(text); dismiss() } label: {
                Text("Log").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                    .foregroundStyle(Color(red: 0.05, green: 0.06, blue: 0.08)).frame(maxWidth: .infinity).frame(height: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.plain).disabled(empty).opacity(empty ? 0.4 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).textCase(nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.14, green: 0.12, blue: 0.30), Color(red: 0.04, green: 0.05, blue: 0.09)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.height(430), .large]).presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// Days in a row with a reading: where the run began, the longest one, and which days of this week are in it.
struct NunaStreak {
    let current: Int
    let start: Date?
    let best: Int
    /// Day keys that carry a reading.
    let keys: Set<String>
    let todayHasReading: Bool

    static let milestones = [3, 7, 10, 25, 50, 75, 100, 150, 200, 365, 500, 730, 1000]

    static func compute(days: [DailyMetric], now: Date = Date()) -> NunaStreak {
        let cal = Calendar.current
        var keys = Set(days.filter { $0.recovery != nil || ($0.totalSleepMin ?? 0) > 0 || ($0.strain ?? 0) > 0 || $0.restingHr != nil || $0.avgHrv != nil }.map(\.day))
#if DEBUG
        // `--demo-streak=N`: the N days up to yesterday count as worn, since the demo year ends before today.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-streak=") }), let n = Int(arg.dropFirst("--demo-streak=".count)) {
            keys = Set((1...max(n, 1)).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: now)).map(Repository.localDayKey) })
        }
#endif
        let today = cal.startOfDay(for: now)
        let hasToday = keys.contains(Repository.localDayKey(today))
        // Today may still be empty: the run then ends yesterday and is still alive.
        var day = hasToday ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var n = 0, first = day
        while keys.contains(Repository.localDayKey(day)) { n += 1; first = day; day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        // The longest run anywhere in the stored days.
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let dates = keys.compactMap { f.date(from: $0) }.sorted()
        var best = 0, run = 0; var previous: Date?
        for d in dates {
            if let p = previous, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            previous = d; best = max(best, run)
        }
        return NunaStreak(current: n, start: n > 0 ? first : nil, best: max(best, n), keys: keys, todayHasReading: hasToday)
    }
}

/// A flame that moves: the body leans and stretches a little, the inner flame breathes out of step with it, a glow pulses behind, and sparks rise and fade.
struct NunaFlameShape: Shape {
    /// 0 is the outer flame, 1 the lighter one inside it.
    var inner = false
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        func pt(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: x + a * w, y: y + b * h) }
        var p = Path()
        p.move(to: pt(0.5, 1))
        p.addCurve(to: pt(0.12, 0.62), control1: pt(0.2, 0.98), control2: pt(0.0, 0.8))
        p.addCurve(to: pt(0.30, 0.30), control1: pt(0.22, 0.50), control2: pt(0.34, 0.45))
        p.addCurve(to: pt(0.52, 0.0), control1: pt(0.28, 0.15), control2: pt(0.50, 0.12))
        p.addCurve(to: pt(0.72, 0.38), control1: pt(0.58, 0.12), control2: pt(0.62, 0.28))
        p.addCurve(to: pt(0.88, 0.66), control1: pt(0.80, 0.46), control2: pt(0.98, 0.52))
        p.addCurve(to: pt(0.5, 1), control1: pt(1.0, 0.9), control2: pt(0.8, 0.99))
        p.closeSubpath()
        return p
    }
}

/// The flame as a small icon: the same drawing as the big one, in a tall slim frame (half as wide as it is high), with the lighter flame inside.
struct NunaFlameIcon: View {
    var height: CGFloat
    var outer: [Color] = [Color(red: 1, green: 0.50, blue: 0.20), Color(red: 0.97, green: 0.36, blue: 0.10)]
    var inner: [Color] = [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.99, green: 0.78, blue: 0.55)]

    /// The first day of a run, in gold.
    static let gold: [Color] = [Color(red: 1, green: 0.84, blue: 0.48), Color(red: 1, green: 0.70, blue: 0.28)]
    /// A flame that is not lit.
    static let unlit: [Color] = [Color.white.opacity(0.46), Color.white.opacity(0.30)]

    var body: some View {
        ZStack {
            NunaFlameShape().fill(LinearGradient(colors: outer, startPoint: .top, endPoint: .bottom))
            NunaFlameShape(inner: true).fill(LinearGradient(colors: inner, startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: 0.40, y: 0.42, anchor: .bottom).offset(y: -height * 0.03)
        }
        .frame(width: height * 0.5, height: height)
        .accessibilityHidden(true)
    }
}

struct NunaAnimatedFlame: View {
    var lit = true
    var size: CGFloat = 164

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let stretch = 1 + 0.03 * sin(t * 3.1), lean = 1.4 * sin(t * 2.2), breath = 1 + 0.07 * sin(t * 5.0 + 1)
            let w = size * 0.5
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.42, blue: 0.1).opacity(0.28 + 0.06 * sin(t * 2.6)), .clear], center: .center, startRadius: 0, endRadius: size * 0.7))
                    .frame(width: size * 1.5, height: size * 1.5).offset(y: size * 0.1)
                ZStack {
                    NunaFlameShape().fill(LinearGradient(colors: [Color(red: 1, green: 0.50, blue: 0.20), Color(red: 0.97, green: 0.36, blue: 0.10)], startPoint: .top, endPoint: .bottom))
                    NunaFlameShape().fill(Color(red: 0.62, green: 0.18, blue: 0.05).opacity(0.35)).scaleEffect(x: 0.5, y: 0.72, anchor: .bottomLeading).offset(x: w * 0.06)
                    NunaFlameShape(inner: true).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.99, green: 0.78, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                        .scaleEffect(x: 0.36 * breath, y: 0.40 * breath, anchor: .bottom).offset(y: -size * 0.02).rotationEffect(.degrees(-lean * 1.6), anchor: .bottom)
                }
                .frame(width: w, height: size)
                .scaleEffect(x: 1, y: stretch, anchor: .bottom).rotationEffect(.degrees(lean), anchor: .bottom)
                .saturation(lit ? 1 : 0).opacity(lit ? 1 : 0.5)
                if lit {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = (t * (0.28 + 0.05 * Double(i)) + Double(i) * 0.27).truncatingRemainder(dividingBy: 1)
                        Circle().fill(Color(red: 1, green: 0.62, blue: 0.25)).frame(width: 3 + CGFloat(i % 2), height: 3 + CGFloat(i % 2))
                            .offset(x: CGFloat([-18, 10, 26, -6][i]) * (1 + CGFloat(phase) * 0.3) + 4 * CGFloat(sin(t * 2 + Double(i))), y: -size * 0.45 - CGFloat(phase) * size * 0.35)
                            .opacity(1 - phase)
                    }
                }
            }
            .frame(width: size * 1.5, height: size * 1.1)
        }
        .accessibilityHidden(true)
    }
}

struct NunaDayStreakView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var live: LiveState
    private var cal: Calendar { Calendar.current }

    var body: some View {
        let s = NunaStreak.compute(days: repo.days)
        NunaDetailScreen("Day Streak", trailing: AnyView(share(s)), centersTitle: true) {
            hero(s)
            stats(s)
            week(s)
            milestone(s)
            if !s.todayHasReading && s.current > 0 { warning }
        }
    }

    private func share(_ s: NunaStreak) -> some View {
        ShareLink(item: String(localized: "I'm on a \(s.current) day streak with PHMN.")) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 44, height: 44)
        }
    }

    private func hero(_ s: NunaStreak) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                NunaAnimatedFlame(lit: s.current > 0, size: 176)
                Text(verbatim: "\(s.current)").font(.nunaBoldFigure(size: 88)).foregroundStyle(.white).shadow(color: .black.opacity(0.45), radius: 10).offset(y: 22)
            }
            .padding(.top, 4).padding(.bottom, 20)
            Text("Day Streak").font(.nuna(size: 24, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).padding(.top, 14)
            Text("Wear your strap daily").font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary.opacity(0.85)).textCase(nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ s: NunaStreak) -> some View {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.dateFormat = "MMM d, yyyy"
        return HStack(spacing: 0) {
            stat(s.start.map { f.string(from: $0) } ?? "–", "Streak started")
            Rectangle().fill(NunaPalette.hairline).frame(width: 1, height: 44)
            stat("\(s.best)", "Max streak")
        }
        .padding(.top, 8)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: value).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(label).font(.nuna(size: 15, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
        }.frame(maxWidth: .infinity)
    }

    private func week(_ s: NunaStreak) -> some View {
        let today = cal.startOfDay(for: Date())
        var monday = today
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2
        if let start = c.dateInterval(of: .weekOfYear, for: today)?.start { monday = start }
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
        let wf = DateFormatter(); wf.locale = AppLanguage.activeLocale; wf.setLocalizedDateFormatFromTemplate("EEE")
        return VStack(alignment: .leading, spacing: 18) {
            Text("This week").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    let isToday = cal.isDate(d, inSameDayAs: today), has = s.keys.contains(Repository.localDayKey(d)) && d <= today
                    VStack(spacing: 14) {
                        Text(verbatim: wf.string(from: d)).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                            .foregroundStyle(isToday ? NunaPalette.textPrimary : NunaPalette.textMuted)
                        if has {
                            let starts = s.start.map { cal.isDate(d, inSameDayAs: $0) } ?? false
                            NunaFlameIcon(height: 34, outer: starts ? NunaFlameIcon.gold : [Color(red: 1, green: 0.50, blue: 0.20), Color(red: 0.97, green: 0.36, blue: 0.10)],
                                          inner: starts ? [Color(red: 1, green: 0.93, blue: 0.72), Color(red: 1, green: 0.88, blue: 0.60)] : [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.99, green: 0.78, blue: 0.55)])
                                .frame(height: 36)
                        } else {
                            Circle().strokeBorder(NunaPalette.textMuted.opacity(0.7), style: StrokeStyle(lineWidth: 1.3, dash: [3, 3])).frame(width: 36, height: 36)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func milestone(_ s: NunaStreak) -> some View {
        let previous = NunaStreak.milestones.last { $0 <= s.current } ?? 0
        let next = NunaStreak.milestones.first { $0 > s.current } ?? s.current
        let fraction = next > previous ? Double(s.current - previous) / Double(next - previous) : 1
        return HStack(spacing: 14) {
            badge(previous, lit: true)
            VStack(spacing: 12) {
                Text(verbatim: String(localized: "\(next - s.current) more days")).font(.nuna(size: 14.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 7).overlay(alignment: .leading) {
                    GeometryReader { g in Capsule().fill(Color(red: 1, green: 0.42, blue: 0.14)).frame(width: max(8, g.size.width * CGFloat(min(max(fraction, 0), 1)))) }
                }
                Text("to unlock your next milestone.").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            badge(next, lit: false)
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func badge(_ n: Int, lit: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Circle().fill(RadialGradient(colors: [lit ? Color(red: 0.30, green: 0.10, blue: 0.03) : Color(red: 0.16, green: 0.17, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.06)], center: .center, startRadius: 4, endRadius: 40))
                .overlay(Circle().strokeBorder(lit ? Color(red: 1, green: 0.42, blue: 0.14) : Color.white.opacity(0.35), lineWidth: 2.5))
                .frame(width: 74, height: 74)
                .overlay(NunaFlameIcon(height: 40, outer: lit ? [Color(red: 1, green: 0.50, blue: 0.20), Color(red: 0.97, green: 0.36, blue: 0.10)] : NunaFlameIcon.unlit,
                                       inner: lit ? [Color(red: 0.95, green: 0.62, blue: 0.40), Color(red: 0.99, green: 0.78, blue: 0.55)] : [Color.white.opacity(0.62), Color.white.opacity(0.5)]).offset(y: -5))
            Text(verbatim: "\(n)").font(.nunaBoldFigure(size: 36)).foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 4).offset(y: 18)
        }
        .frame(width: 80, height: 96, alignment: .top)
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't let your streak fade").font(.nuna(size: 17, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text("Looks like you're not wearing your strap. Put it back on before tomorrow night to avoid losing your streak.")
                .font(.nuna(size: 16.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
#endif

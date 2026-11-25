#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

/// Clock helpers shared by the body-clock screens. Hours are local clock hours in [0, 24).
enum NunaClockHour {
    static func text(_ hour: Double) -> String {
        let h = (hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24)
        var hh = Int(h), mm = Int(((h - Double(hh)) * 60).rounded())
        if mm == 60 { mm = 0; hh = (hh + 1) % 24 }
        let cal = Calendar.current
        let date = cal.date(bySettingHour: hh, minute: mm, second: 0, of: Date()) ?? Date()
        return NunaSleepFormat.clock(date)
    }

    static func hour(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    static func minutes(_ hours: Double) -> Int { Int((abs(hours) * 60).rounded()) }
}

// MARK: - 24 h dial

/// Two arcs on one ring: dotted = where the body clock wanted the night, solid = the night slept. Without a night to compare, only the ring and the lowest
/// point are drawn.
struct NunaBodyClockDial: View {
    var idealBed: Double?, idealWake: Double?
    var bed: Double?, wake: Double?
    let tempMin: Double
    var size: CGFloat = 248

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = size.width / 248
            func angle(_ h: Double) -> Angle { .degrees(h / 24 * 360 - 90) }
            func point(_ h: Double, _ r: CGFloat) -> CGPoint {
                let a = angle(h).radians
                return CGPoint(x: c.x + r * scale * CGFloat(cos(a)), y: c.y + r * scale * CGFloat(sin(a)))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 100 * scale, y: c.y - 100 * scale, width: 200 * scale, height: 200 * scale)),
                       with: .color(NunaPalette.ink.opacity(0.09)), lineWidth: 1.5)
            for h in 0..<24 {
                var p = Path()
                p.move(to: point(Double(h), 100)); p.addLine(to: point(Double(h), h % 6 == 0 ? 94 : 97))
                ctx.stroke(p, with: .color(NunaPalette.ink.opacity(h % 6 == 0 ? 0.35 : 0.14)), lineWidth: 1.5)
            }
            for (h, t) in [(0.0, "00"), (6.0, "06"), (12.0, "12"), (18.0, "18")] {
                ctx.draw(Text(verbatim: t).font(.nuna(size: 11, weight: .bold)).foregroundColor(NunaPalette.textSecondary),
                         at: point(h, 114))
            }
            func arc(_ from: Double, _ to: Double, _ r: CGFloat) -> Path {
                var sweep = (to - from).truncatingRemainder(dividingBy: 24); if sweep <= 0 { sweep += 24 }
                var p = Path()
                p.addArc(center: c, radius: r * scale, startAngle: angle(from), endAngle: angle(from + sweep), clockwise: false)
                return p
            }
            if let idealBed, let idealWake {
                ctx.stroke(arc(idealBed, idealWake, 88), with: .color(NunaPalette.restText),
                           style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round, dash: [0.1, 9 * scale]))
            }
            if let bed, let wake {
                ctx.stroke(arc(bed, wake, 70), with: .color(NunaPalette.rest),
                           style: StrokeStyle(lineWidth: 13 * scale, lineCap: .round))
            }
            let m = point(tempMin, 88)
            let dot = Path(ellipseIn: CGRect(x: m.x - 6 * scale, y: m.y - 6 * scale, width: 12 * scale, height: 12 * scale))
            ctx.fill(dot, with: .color(NunaPalette.canvas))
            ctx.stroke(dot, with: .color(NunaPalette.ink), lineWidth: 2.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 24 h rhythm curve

/// The activity rhythm drawn as one smooth cycle. Its peak sits at the estimated acrophase; the shape is
/// an estimate, not a measured trace, and the card says so.
struct NunaRhythmCurve: View {
    let acrophase: Double
    let tempMin: Double
    let bed: Double?, wake: Double?

    var body: some View {
        Canvas { ctx, size in
            let top: CGFloat = 8, bottom: CGFloat = size.height - 8
            func x(_ h: Double) -> CGFloat { size.width * CGFloat(h / 24) }
            func y(_ h: Double) -> CGFloat {
                let v = cos((h - acrophase) / 24 * 2 * .pi)
                return bottom - CGFloat((v + 1) / 2) * (bottom - top)
            }
            if let bed, let wake {
                func band(_ a: Double, _ b: Double) {
                    ctx.fill(Path(roundedRect: CGRect(x: x(a), y: 4, width: max(2, x(b) - x(a)), height: size.height - 8), cornerRadius: 6),
                             with: .color(NunaPalette.rest.opacity(0.22)))
                }
                if bed > wake { band(bed, 24); band(0, wake) } else { band(bed, wake) }
            }
            for h in [6.0, 12.0, 18.0] {
                var g = Path(); g.move(to: CGPoint(x: x(h), y: 4)); g.addLine(to: CGPoint(x: x(h), y: size.height - 4))
                ctx.stroke(g, with: .color(NunaPalette.ink.opacity(0.07)), lineWidth: 1)
            }
            var p = Path()
            for i in 0...96 {
                let h = Double(i) / 4
                let pt = CGPoint(x: x(h), y: y(h))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(NunaPalette.restText), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            func marker(_ h: Double, fill: Color, stroke: Color) {
                let c = CGPoint(x: x(h), y: y(h))
                let r = Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
                ctx.fill(r, with: .color(fill)); ctx.stroke(r, with: .color(stroke), lineWidth: 2.5)
            }
            marker(tempMin, fill: NunaPalette.canvas, stroke: NunaPalette.ink)
            marker(acrophase, fill: NunaPalette.charge, stroke: NunaPalette.card)
        }
        .frame(height: 96)
        .accessibilityHidden(true)
    }
}

/// The hour labels under the curve, each centred under its own gridline (00 and 24 at the two edges), so a label and the line it names agree.
struct NunaRhythmAxis: View {
    var body: some View {
        GeometryReader { g in
            ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                Text(verbatim: String(format: "%02d", h))
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .position(x: min(max(g.size.width * CGFloat(h) / 24, 9), g.size.width - 9), y: g.size.height / 2)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Body clock screen

/// The page is laid out like the Sleep pages: the title in the middle, the picture of the night first (the 24-hour dial, with the lowest point in its
/// middle), one panel of figures with a row for each, a titled card for the rhythm, a card that explains, and Anya as the floating pill.
struct NunaBodyClockView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var sleep = NunaSleepModel()

    var body: some View {
        NunaDetailScreen("Body clock", centersTitle: true) {
            if let est = appModel.circadianPhase, est.confidence != .unreadable {
                content(est)
            } else {
                unreadable
            }
        }
        .task(id: repo.refreshSeq) {
            await sleep.load(repo: repo)
            // The estimate is computed in the analytics pass; make sure it is fresh when this screen opens.
            if appModel.circadianPhase == nil { await appModel.refreshV5Signals() }
        }
        // Her line is worked out from the figures on this page; there is no analysis to fetch for it.
        .nunaAnyaFloating(context: "body clock", line: anyaLine, analyses: false)
    }

    private var night: NunaNight? { sleep.nights.first }

    // MARK: Anya

    /// What she says about the page: how the last night sat against the body clock, in a few warm words.
    private var anyaLine: String? {
        guard let est = appModel.circadianPhase, est.confidence != .unreadable else { return nil }
        guard let night, let ideal = idealWindow(est, night) else {
            return String(localized: "Your body clock is at its lowest around \(NunaClockHour.text(est.tempMinHour)). You are sleepiest then, and good sleep ends about two and a half hours after it.")
        }
        let wake = NunaClockHour.hour(of: night.wake)
        let off = CircadianEngine.sleepWindowOffsetHours(tempMinHour: est.tempMinHour, actualWakeHour: wake)
        let mins = NunaClockHour.minutes(off)
        if mins <= 30 {
            return String(localized: "Your sleep sits right on your body clock. Keep waking close to \(NunaClockHour.text(wake)) and the rhythm stays steady.")
        }
        let when = off <= 0 ? String(localized: "earlier") : String(localized: "later")
        return String(localized: "Last night ran \(mins) minutes \(when) than your body clock wanted. Tonight, aim to be asleep nearer \(NunaClockHour.text(ideal.bed)), and get daylight soon after you wake.")
    }

    // MARK: Content

    @ViewBuilder private func content(_ est: CircadianEngine.PhaseEstimate) -> some View {
        let chrono = CircadianEngine.chronotype(est)
        let ideal = night.flatMap { idealWindow(est, $0) }
        let bed = night.map { NunaClockHour.hour(of: $0.onset) }
        let wake = night.map { NunaClockHour.hour(of: $0.wake) }
        hero(est, chrono: chrono, ideal: ideal, bed: bed, wake: wake)
        panel(est, wake: wake, ideal: ideal)
        rhythmCard(est, bed: bed, wake: wake)
        planLink
        NunaBodyClockInfo()
    }

    /// The dial at its full size, with the lowest point in the middle, and under it what kind of clock this is and what the marks mean.
    private func hero(_ est: CircadianEngine.PhaseEstimate, chrono: CircadianEngine.Chronotype?, ideal: (bed: Double, wake: Double)?,
                      bed: Double?, wake: Double?) -> some View {
        VStack(spacing: 18) {
            ZStack {
                NunaBodyClockDial(idealBed: ideal?.bed, idealWake: ideal?.wake, bed: bed, wake: wake, tempMin: est.tempMinHour, size: 300)
                VStack(spacing: 4) {
                    nunaTrendsCap("Lowest point")
                    Text(verbatim: NunaClockHour.text(est.tempMinHour))
                        .font(.nuna(size: 52, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(52)).foregroundStyle(NunaPalette.textPrimary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(est.confidence == .solid ? "Solid" : "Wide range")
                        .font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.restText)
                }
            }
            if let chrono { NunaChip(chronoLabel(chrono), systemImage: "moon", color: NunaPalette.restText) }
            if ideal != nil {
                HStack(spacing: 14) {
                    legend(AnyView(Text(verbatim: "···").font(.nuna(size: 14, weight: .black)).foregroundStyle(NunaPalette.restText)), "Ideal window")
                    legend(AnyView(RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.rest).frame(width: 14, height: 6)), "Last night")
                    legend(AnyView(Circle().strokeBorder(NunaPalette.ink, lineWidth: 2.5).frame(width: 10, height: 10)), "Lowest point")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    /// The panel the Sleep, Recovery and Strain pages put under their ring: a row for each figure in the same type, with the same three bars where there is a
    /// level to show (how close last night sat to the ideal window), and the same legend under them.
    private func panel(_ est: CircadianEngine.PhaseEstimate, wake: Double?, ideal: (bed: Double, wake: Double)?) -> some View {
        NunaSignalPanel {
            VStack(spacing: 0) {
                NunaFigureRow(title: "Peak", icon: "sun.max", value: NunaClockHour.text(est.acrophaseHours))
                NunaDivider()
                NunaFigureRow(title: "Schedule", icon: "met:sleep-consistency", value: signed(est.offsetVsScheduleMinutes), unit: "min")
                if let wake, let ideal {
                    let off = CircadianEngine.sleepWindowOffsetHours(tempMinHour: est.tempMinHour, actualWakeHour: wake)
                    let mins = NunaClockHour.minutes(off)
                    NunaDivider()
                    NunaFigureRow(title: "Last night vs ideal", icon: "met:hours-vs-needed", value: (off <= 0 ? "−" : "+") + "\(mins)", unit: "min",
                                  level: mins <= 30 ? .optimal : (mins <= 60 ? .sufficient : .poor))
                    NunaDivider()
                    NunaFigureRow(title: "Ideal window", icon: "met:time-in-bed", value: "\(NunaClockHour.text(ideal.bed)) – \(NunaClockHour.text(ideal.wake))")
                }
            }
            if wake != nil, ideal != nil { NunaLevelLegend().padding(.top, 8) }
        }
    }

    /// The 24-hour curve, and under it how sure the estimate is.
    private func rhythmCard(_ est: CircadianEngine.PhaseEstimate, bed: Double?, wake: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NunaTitleRow(title: "24-hour rhythm") {
                Text("Estimated shape").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 6) {
                        NunaRhythmCurve(acrophase: est.acrophaseHours, tempMin: est.tempMinHour, bed: bed, wake: wake)
                        NunaRhythmAxis()
                    }
                    // What the marks on the curve are, with their times.
                    HStack(spacing: 14) {
                        if bed != nil {
                            curveKey(AnyView(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NunaPalette.rest.opacity(0.4)).frame(width: 14, height: 10)),
                                     "Last night", nil)
                        }
                        curveKey(AnyView(Circle().strokeBorder(NunaPalette.ink, lineWidth: 2.5).frame(width: 10, height: 10)), "Lowest point",
                                 NunaClockHour.text(est.tempMinHour))
                        curveKey(AnyView(Circle().fill(NunaPalette.charge).frame(width: 10, height: 10)), "Peak", NunaClockHour.text(est.acrophaseHours))
                        Spacer(minLength: 0)
                    }
                    NunaDivider()
                    HStack {
                        nunaTrendsCap("Confidence")
                        Spacer()
                        Text("From the last 14 days").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous)
                                .fill(i < (est.confidence == .solid ? 3 : 2) ? NunaPalette.rest : NunaPalette.ink.opacity(0.09)).frame(height: 8)
                        }
                    }
                    // One label under each of the three bars.
                    HStack(spacing: 6) {
                        Text("Hard to read").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Wide range").frame(maxWidth: .infinity, alignment: .center)
                        Text("Solid").frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundStyle(est.confidence == .solid ? NunaPalette.restText : NunaPalette.textSecondary)
                    }
                    .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
        }
    }

    private var unreadable: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    NunaIconTile("clock", tint: NunaPalette.restText)
                    Text("Your body clock is hard to read right now").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("It needs at least 7 days of heart-rate data with a clear day and night pattern. Wear your strap day and night and check back.")
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
            }
            planLink
            NunaBodyClockInfo()
        }
    }

    private var planLink: some View {
        NavigationLink(value: NunaTodayRoute.bodyClockPlan) {
            NunaCard(small: true) {
                NunaListRow("Plan a trip or shift", description: "Shift your clock with light and sleep timing", systemImage: "timer",
                            tint: NunaPalette.restText, showsChevron: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func curveKey(_ mark: AnyView, _ text: LocalizedStringKey, _ time: String?) -> some View {
        HStack(spacing: 6) {
            mark
            Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).lineLimit(1).minimumScaleFactor(0.8)
            if let time { Text(verbatim: time).font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textPrimary) }
        }
    }

    private func legend(_ mark: AnyView, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { mark; Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
    }

    private func idealWindow(_ est: CircadianEngine.PhaseEstimate, _ night: NunaNight) -> (bed: Double, wake: Double)? {
        let dur = night.inBedMin / 60
        return CircadianEngine.idealSleepWindow(tempMinHour: est.tempMinHour, durationHours: dur).map { ($0.bedHour, $0.wakeHour) }
    }

    private func chronoLabel(_ c: CircadianEngine.Chronotype) -> LocalizedStringKey {
        switch c { case .morning: return "Morning type"; case .intermediate: return "Intermediate type"; case .evening: return "Evening type" }
    }

    private func signed(_ minutes: Double) -> String { (minutes <= 0 ? "−" : "+") + "\(Int(abs(minutes).rounded()))" }
}

// MARK: - Trip and shift planner

struct NunaBodyClockPlanView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var sleep = NunaSleepModel()
    @State private var kind = 0              // 0 trip, 1 shift
    @State private var forward = true        // east / earlier
    @State private var hours = 3

    private var bed: Double { sleep.nights.first.map { NunaClockHour.hour(of: $0.onset) } ?? 23 }
    private var wake: Double { sleep.nights.first.map { NunaClockHour.hour(of: $0.wake) } ?? 7 }
    private var plan: CircadianEngine.JetLagPlan {
        CircadianEngine.planShift(shiftHours: forward ? Double(hours) : -Double(hours), currentSleepHour: bed, currentWakeHour: wake)
    }

    var body: some View {
        NunaDetailScreen("Body clock plan") {
            NunaSegmented([(value: 0, title: "Trip"), (value: 1, title: "Shift work")], selection: $kind)
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(kind == 0 ? "Travel direction" : "Shift direction").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel)
                        .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    NunaSegmented(kind == 0 ? [(value: true, title: "East (earlier)"), (value: false, title: "West (later)")]
                                            : [(value: true, title: "Earlier"), (value: false, title: "Later")], selection: $forward)
                    Text(kind == 0 ? "Time zone difference" : "Shift by").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel)
                        .textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary).padding(.top, 4)
                    HStack {
                        stepper("minus", enabled: hours > 1) { hours -= 1 }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(verbatim: (forward ? "+" : "−") + "\(hours)").font(.nuna(size: 52, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(52)).foregroundStyle(NunaPalette.textPrimary)
                            Text("hours").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        }
                        Spacer()
                        stepper("plus", enabled: hours < 12) { hours += 1 }
                    }
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                    HStack {
                        Text("Your sleep window now").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Spacer()
                        Text(verbatim: "\(NunaClockHour.text(bed)) – \(NunaClockHour.text(wake))").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                }
            }
            summary
            if !plan.days.isEmpty {
                NunaTitleRow(title: "Daily plan") { EmptyView() }
                ForEach(plan.days, id: \.dayIndex) { day in dayCard(day) }
            }
            Text("Light and sleep timing guidance only. Not medical advice.")
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center).textCase(nil)
        }
        .task(id: repo.refreshSeq) { await sleep.load(repo: repo) }
    }

    private var summary: some View {
        NunaCard(highlight: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Summary").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip("Light and sleep timing only")
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(plan.estimatedDays)").font(.nuna(size: 40, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(40)).foregroundStyle(NunaPalette.textPrimary)
                    Text("days").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Text(verbatim: forward
                     ? String(localized: "Move your body clock \(hours) hours earlier, about 1 hour a day.")
                     : String(localized: "Move your body clock \(hours) hours later, about 1 hour a day."))
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                HStack(spacing: 3) {
                    ForEach(plan.days, id: \.dayIndex) { _ in RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous).fill(NunaPalette.rest).frame(height: 10) }
                }
            }
        }
    }

    private func dayCard(_ d: CircadianEngine.DayPlan) -> some View {
        NunaCard(small: true, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: String(localized: "Day \(d.dayIndex)")).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Spacer()
                    NunaChip(verbatim: String(localized: "Sleep \(NunaClockHour.text(d.targetSleepHour))"), color: NunaPalette.restText)
                }
                row("sun.max", nil, "Bright light", "\(NunaClockHour.text(d.brightLightStartHour)) – \(NunaClockHour.text(d.brightLightEndHour))")
                row("moon", NunaPalette.restText, "Dim the lights", String(localized: "From \(NunaClockHour.text(d.dimFromHour))"))
                row("timer", NunaPalette.charge, "Sleep window", "\(NunaClockHour.text(d.targetSleepHour)) – \(NunaClockHour.text(d.targetWakeHour))")
                Text(forward ? "Get bright light soon after waking and keep the evening dim. This moves your clock earlier."
                             : "Get bright light in the evening and go easy on bright morning light. This moves your clock later.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }

    private func row(_ icon: String, _ tint: Color?, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold)).foregroundStyle(tint ?? NunaPalette.textPrimary)
                .frame(width: 32, height: 32).background((tint.map { NunaPalette.tint($0) }) ?? NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: value).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}
#endif

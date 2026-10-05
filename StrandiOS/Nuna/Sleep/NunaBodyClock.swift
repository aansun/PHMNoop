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

/// Two arcs on one ring: dotted = where the body clock wanted the night, solid = the night slept.
struct NunaBodyClockDial: View {
    let idealBed: Double, idealWake: Double
    let bed: Double, wake: Double
    let tempMin: Double

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
            ctx.stroke(arc(idealBed, idealWake, 88), with: .color(NunaPalette.restText),
                       style: StrokeStyle(lineWidth: 7 * scale, lineCap: .round, dash: [0.1, 9 * scale]))
            ctx.stroke(arc(bed, wake, 70), with: .color(NunaPalette.rest),
                       style: StrokeStyle(lineWidth: 13 * scale, lineCap: .round))
            let m = point(tempMin, 88)
            let dot = Path(ellipseIn: CGRect(x: m.x - 6 * scale, y: m.y - 6 * scale, width: 12 * scale, height: 12 * scale))
            ctx.fill(dot, with: .color(NunaPalette.canvas))
            ctx.stroke(dot, with: .color(NunaPalette.ink), lineWidth: 2.5)
        }
        .frame(width: 248, height: 248)
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

// MARK: - Body clock screen

struct NunaBodyClockView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @StateObject private var sleep = NunaSleepModel()
    @State private var showCoach = false

    var body: some View {
        NunaDetailScreen("Body clock", onAnya: coachEnabled ? { showCoach = true } : nil) {
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
        .sheet(isPresented: $showCoach) { NunaAnyaSheet(context: "body clock") }
    }

    private var night: NunaNight? { sleep.nights.first }

    @ViewBuilder private func content(_ est: CircadianEngine.PhaseEstimate) -> some View {
        let chrono = CircadianEngine.chronotype(est)
        NunaCard(padding: EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your body clock estimate").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                        .foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(est.confidence == .solid ? "Solid" : "Wide range", color: NunaPalette.restText)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: NunaClockHour.text(est.tempMinHour))
                        .font(.nuna(size: 64, weight: .bold, design: NunaType.design)).tracking(nunaTrackingNumber(64)).foregroundStyle(NunaPalette.restText)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("lowest point").font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                Text("You are sleepiest around this time. Good sleep ends about 2.5 hours after it.")
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let chrono {
                    NunaChip(chronoLabel(chrono), systemImage: "moon", color: NunaPalette.restText).padding(.top, 4)
                }
            }
        }
        if let night, let ideal = idealWindow(est, night) {
            dialCard(est, night, ideal)
        }
        HStack(spacing: 12) {
            NunaStatTile(label: "Lowest", value: NunaClockHour.text(est.tempMinHour))
            NunaStatTile(label: "Peak", value: NunaClockHour.text(est.acrophaseHours))
            NunaStatTile(label: "Schedule", value: signed(est.offsetVsScheduleMinutes), unit: "min")
        }
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("24-hour rhythm").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("Estimated shape").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                NunaRhythmCurve(acrophase: est.acrophaseHours, tempMin: est.tempMinHour,
                                bed: night.map { NunaClockHour.hour(of: $0.onset) }, wake: night.map { NunaClockHour.hour(of: $0.wake) })
                HStack {
                    ForEach(["00", "06", "12", "18", "24"], id: \.self) { t in
                        Text(verbatim: t).frame(maxWidth: .infinity)
                    }
                }
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        NunaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Confidence").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    Text("From the last 14 days").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i < (est.confidence == .solid ? 3 : 2) ? NunaPalette.rest : NunaPalette.ink.opacity(0.09)).frame(height: 8)
                    }
                }
                HStack {
                    Text("Hard to read"); Spacer(); Text("Wide range"); Spacer()
                    Text("Solid").foregroundStyle(est.confidence == .solid ? NunaPalette.restText : NunaPalette.textSecondary)
                }
                .font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                Text("It needs at least 7 days of data for a first estimate. More days narrow the range.")
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
        planLink
        if coachEnabled { NunaAnyaCard(title: "Is my sleep timing right for my body clock?") { showCoach = true } }
        NunaExpandRow(title: "How it's calculated", subtitle: "From 14 days of heart-rate rhythm, not a temperature reading",
                      text: "Your heart rate rises and falls over the day. NOOP fits one smooth daily cycle to the last 14 days, finds its lowest and highest points, and places your body-clock low about when your heart-rate rhythm bottoms out. It is an on-device estimate, not a medical measurement or a body temperature reading.")
    }

    private var unreadable: some View {
        VStack(spacing: NunaSpacing.section) {
            NunaCard {
                VStack(alignment: .leading, spacing: 10) {
                    NunaIconTile("clock", tint: NunaPalette.restText)
                    Text("Your body clock is hard to read right now").font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                    Text("It needs at least 7 days of heart-rate data with a clear day and night pattern. Wear your strap day and night and check back.")
                        .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                }
            }
            planLink
        }
    }

    private var planLink: some View {
        NavigationLink(value: NunaTodayRoute.bodyClockPlan) {
            NunaCard(small: true) {
                NunaListRow("Plan a trip or shift", subtitle: "Shift your clock with light and sleep timing", systemImage: "timer",
                            tint: NunaPalette.restText, showsChevron: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func dialCard(_ est: CircadianEngine.PhaseEstimate, _ night: NunaNight, _ ideal: (bed: Double, wake: Double)) -> some View {
        let bed = NunaClockHour.hour(of: night.onset), wake = NunaClockHour.hour(of: night.wake)
        let off = CircadianEngine.sleepWindowOffsetHours(tempMinHour: est.tempMinHour, actualWakeHour: wake)
        let mins = NunaClockHour.minutes(off)
        let aligned = mins <= 30
        return NunaCard {
            VStack(spacing: 12) {
                HStack {
                    Text("Sleep and ideal window").font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                    Spacer()
                    NunaChip(aligned ? "Aligned" : "Off", color: aligned ? NunaPalette.charge : NunaPalette.warning)
                }
                ZStack {
                    NunaBodyClockDial(idealBed: ideal.bed, idealWake: ideal.wake, bed: bed, wake: wake, tempMin: est.tempMinHour)
                    VStack(spacing: 2) {
                        Text("Difference").font(.nuna(size: 10.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: (off <= 0 ? "−" : "+") + "\(mins)").font(.nuna(size: 34, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                            Text("min").font(.nuna(size: 12, weight: .bold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Text(off <= 0 ? "earlier" : "later").font(.nuna(size: 11.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                    }
                }
                HStack(spacing: 14) {
                    legend(AnyView(Text(verbatim: "···").font(.nuna(size: 14, weight: .black)).foregroundStyle(NunaPalette.restText)), "Ideal window")
                    legend(AnyView(Capsule().fill(NunaPalette.rest).frame(width: 14, height: 6)), "Last night")
                    legend(AnyView(Circle().strokeBorder(NunaPalette.ink, lineWidth: 2.5).frame(width: 10, height: 10)), "Lowest point")
                }
                Text(verbatim: String(localized: "Your sleep was \(mins) minutes \(off <= 0 ? String(localized: "earlier") : String(localized: "later")) than the ideal window (\(NunaClockHour.text(ideal.bed)) to \(NunaClockHour.text(ideal.wake))). The night has the same length, so this is about timing, not duration."))
                    .font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).multilineTextAlignment(.center)
            }
        }
    }

    private func legend(_ mark: AnyView, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { mark; Text(text).font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) }
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
                            Text("hours").font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                        }
                        Spacer()
                        stepper("plus", enabled: hours < 12) { hours += 1 }
                    }
                    Rectangle().fill(NunaPalette.hairline).frame(height: 1)
                    HStack {
                        Text("Your sleep window now").font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
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
                .font(.nuna(size: 12, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center)
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
                    .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
                HStack(spacing: 3) {
                    ForEach(plan.days, id: \.dayIndex) { _ in Capsule().fill(NunaPalette.rest).frame(height: 10) }
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
                    .font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
        }
    }

    private func row(_ icon: String, _ tint: Color?, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.nuna(size: 14, weight: .bold)).foregroundStyle(tint ?? NunaPalette.textPrimary)
                .frame(width: 32, height: 32).background((tint.map { NunaPalette.tint($0) }) ?? NunaPalette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.nuna(size: 14.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                Text(verbatim: value).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.nuna(size: 20, weight: .bold))
                .foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted.opacity(0.4))
                .frame(width: 52, height: 52).background(NunaPalette.glassStrong, in: Circle())
                .overlay(Circle().strokeBorder(NunaPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}
#endif

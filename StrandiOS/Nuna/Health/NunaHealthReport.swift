#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import WhoopStore

/// What the health report is made of: the wearer's own daily readings for the last 180 days, gathered once and then drawn as a 30 day page and
/// a 180 day page.
struct NunaHealthReportData {
    var name = ""
    var dateOfBirth: Date?
    var age: Int?
    /// Day key to value.
    var respiratory: [String: Double] = [:]
    var restingHr: [String: Double] = [:]
    /// Hours asleep in the night and in naps, by day key.
    var sleepHours: [String: Double] = [:]
    var napHours: [String: Double] = [:]
    /// Minutes in moderate (50-80% of max HR, zones 1 to 3) and vigorous (80-100%, zones 4 and 5) heart-rate zones during logged activities.
    var moderateMin: [String: Double] = [:]
    var vigorousMin: [String: Double] = [:]
    /// The most frequently logged activities of the last 180 days: display name, asset-name sport and count.
    var topActivities: [(name: String, sport: String, count: Int)] = []

    @MainActor static func gather(repo: Repository, profile: ProfileStore, name: String) async -> NunaHealthReportData {
        var d = NunaHealthReportData()
        d.name = name
        d.dateOfBirth = profile.dateOfBirth
        d.age = profile.age
        for p in await repo.exploreSeries(key: "resp_rate", source: "my-whoop", days: 190) { d.respiratory[p.day] = p.value }
        for p in await repo.exploreSeries(key: "rhr", source: "my-whoop", days: 190) { d.restingHr[p.day] = p.value }
        for m in repo.days { if let min = m.totalSleepMin, min > 0 { d.sleepHours[m.day] = min / 60 } }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -180, to: today) ?? today
        for item in await NunaSleepModel.naps(from: from, to: today.addingTimeInterval(86_400), repo: repo) {
            d.napHours[item.dayKey, default: 0] += item.nap.asleepMin / 60
        }
        let cutoff = Int(from.timeIntervalSince1970)
        var counts: [String: (name: String, n: Int)] = [:]
        for w in await repo.workoutRows(days: 190) where w.startTs >= cutoff {
            let key = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(w.startTs)))
            let minutes = (w.durationS ?? Double(w.endTs - w.startTs)) / 60
            if let z = WorkoutZones.percents(w.zonesJSON), z.count >= 5 {
                d.moderateMin[key, default: 0] += (z[0] + z[1] + z[2]) / 100 * minutes
                d.vigorousMin[key, default: 0] += (z[3] + z[4]) / 100 * minutes
            }
            let shown = WorkoutSource.displaySport(w.sport)
            counts[w.sport, default: (shown, 0)].n += 1
        }
        d.topActivities = counts.sorted { $0.value.n > $1.value.n }.prefix(4).map { (name: $0.value.name, sport: $0.key, count: $0.value.n) }
        return d
    }
}

/// The report as a PDF: Letter size, a page for the last 30 days (a point a day) and a page for the last 180 days (the same four charts, by month).
/// The charts are the wearer's own readings, drawn black on white to print well. It is made on the phone and goes nowhere until it is shared.
enum NunaHealthReportRenderer {
    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 25
    private static let ink = UIColor(white: 0.07, alpha: 1)
    private static let grey = UIColor(white: 0.62, alpha: 1)
    private static let grid = UIColor(white: 0.88, alpha: 1)
    private static let barLight = UIColor(white: 0.80, alpha: 1)
    private static let barDark = UIColor(white: 0.48, alpha: 1)

    private static func font(_ names: [String], _ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        for n in names { if let f = UIFont(name: n, size: size) { return f } }
        return .systemFont(ofSize: size, weight: weight)
    }
    private static func head(_ size: CGFloat) -> UIFont { font(["ProximaNova-Extrabld", "ProximaNova-Semibold"], size, .heavy) }
    private static func body(_ size: CGFloat) -> UIFont { font(["ProximaNova-Regular"], size, .regular) }
    private static func num(_ size: CGFloat, bold: Bool = false) -> UIFont { font([bold ? "DINPro-Bold" : "DINPro-Medium"], size, bold ? .bold : .medium) }

    static func pdf(_ data: NunaHealthReportData, now: Date = Date()) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [kCGPDFContextTitle as String: "Health report", kCGPDFContextCreator as String: "PHMN"]
            return f
        }())
        return renderer.pdfData { ctx in
            for days in [30, 180] {
                ctx.beginPage()
                drawPage(ctx.cgContext, data: data, days: days, now: now)
            }
        }
    }

    // MARK: Text

    private static func draw(_ text: String, at p: CGPoint, font: UIFont, color: UIColor = ink, align: NSTextAlignment = .left, kern: CGFloat = 0, width: CGFloat? = nil) {
        let style = NSMutableParagraphStyle(); style.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: style]
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        switch align {
        case .right: s.draw(at: CGPoint(x: p.x - size.width, y: p.y))
        case .center: s.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y))
        default:
            if let width { s.draw(with: CGRect(x: p.x, y: p.y, width: width, height: 200), options: [.usesLineFragmentOrigin], context: nil) }
            else { s.draw(at: p) }
        }
    }

    private static func dayFormat(_ d: Date, _ f: String) -> String {
        let x = DateFormatter(); x.locale = AppLanguage.activeLocale; x.dateFormat = f; return x.string(from: d)
    }

    // MARK: Page

    private static func drawPage(_ g: CGContext, data: NunaHealthReportData, days: Int, now: Date) {
        let cal = Calendar.current
        let last = cal.startOfDay(for: now)
        let first = cal.date(byAdding: .day, value: -(days - 1), to: last) ?? last
        let slots: [Date] = (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        let keys = slots.map { Repository.localDayKey($0) }

        // Header: who it is for at the left, what it covers at the right.
        draw(data.name.uppercased(), at: CGPoint(x: margin, y: 22), font: head(13), kern: 1)
        var sub: [String] = []
        if let dob = data.dateOfBirth { sub.append("D.O.B. " + dayFormat(dob, "dd/MM/yyyy")) }
        if let age = data.age { sub.append((sub.isEmpty ? "" : "|  ") + "AGE \(age)") }
        draw(sub.joined(separator: "  ").uppercased(), at: CGPoint(x: margin, y: 40), font: head(8.5), color: grey, kern: 0.8)
        draw(String(localized: "\(days) day health report").uppercased(), at: CGPoint(x: page.width - margin, y: 22), font: head(13), align: .right, kern: 1)
        draw(dayFormat(first, "dd/MM/yyyy") + " - " + dayFormat(last, "dd/MM/yyyy"), at: CGPoint(x: page.width - margin, y: 40), font: head(8.5), color: grey, align: .right, kern: 0.8)

        let top: CGFloat = days == 30 ? 74 : 66
        let pitch: CGFloat = days == 30 ? 160 : 141
        let height: CGFloat = days == 30 ? 92 : 83
        let by30 = days == 30

        section(g, y: top, title: String(localized: "Respiratory rate"),
                subtitle: by30 ? String(localized: "Measured as RPM (respirations per minute) during sleep.") : String(localized: "Measured as RPM (respirations per minute) during sleep, averages displayed for months with sufficient data."),
                axis: "RPM", slots: slots, height: height, days: days,
                chart: .line(values: keys.map { data.respiratory[$0] }, decimals: 1))
        section(g, y: top + pitch, title: String(localized: "Resting heart rate"),
                subtitle: by30 ? String(localized: "Measured as BPM (beats per minute) during sleep.") : String(localized: "Measured as BPM (beats per minute) during sleep, averages displayed for months with sufficient data."),
                axis: "BPM", slots: slots, height: height, days: days,
                chart: .line(values: keys.map { data.restingHr[$0] }, decimals: 0))
        section(g, y: top + pitch * 2, title: String(localized: "Sleep duration"),
                subtitle: by30 ? String(localized: "At least 7 hours of sleep is recommended each night for this age group.") : String(localized: "Total daily time spent asleep in hours, averages displayed for months with sufficient data. At least 7 hours of sleep is recommended each night for this age group."),
                axis: "Hours", slots: slots, height: height, days: days,
                chart: .bars(base: keys.map { data.sleepHours[$0] }, extra: keys.map { data.napHours[$0] }, step: 2, minTop: 8, decimals: 2, legend: [(String(localized: "Sleep"), barLight), (String(localized: "Nap"), barDark)]))
        section(g, y: top + pitch * 3, title: String(localized: "Daily aerobic activity"),
                subtitle: by30 ? String(localized: "Total daily minutes spent in upper heart rate zones during logged activities. 150 minutes of moderate aerobic activity (50-80% of max HR) or 75 minutes of vigorous aerobic activity (80-100% of max HR) is recommended per week.")
                    : String(localized: "Total daily minutes spent in upper heart rate zones during logged activities, averages displayed for months with sufficient data. 150 minutes of moderate aerobic activity (50-80% of max HR) or 75 minutes of vigorous aerobic activity (80-100% of max HR) is recommended per week."),
                axis: "Minutes", slots: slots, height: height, days: days,
                chart: .bars(base: keys.map { data.moderateMin[$0] }, extra: keys.map { data.vigorousMin[$0] }, step: 10, minTop: 60, decimals: 0, legend: [(String(localized: "Moderate"), barLight), (String(localized: "Vigorous"), barDark)]))

        if days == 180, !data.topActivities.isEmpty {
            let y = top + pitch * 3 + height + 64
            draw(String(localized: "Most frequently logged activities"), at: CGPoint(x: margin, y: y), font: body(8.5), color: grey)
            var x = margin + 8
            for a in data.topActivities.prefix(4) {
                // The picture is a template: its shape is the alpha, so it is filled in black through it.
                if let asset = NunaActivityIcons.asset(for: a.sport), let cg = UIImage(named: asset)?.cgImage {
                    g.saveGState()
                    let box = CGRect(x: x, y: y + 18, width: 26, height: 26)
                    g.translateBy(x: 0, y: box.minY * 2 + box.height); g.scaleBy(x: 1, y: -1)
                    g.clip(to: box, mask: cg)
                    ink.setFill(); g.fill(box)
                    g.restoreGState()
                }
                draw("\(a.count)x", at: CGPoint(x: x, y: y + 47), font: head(8))
                draw(a.name.uppercased(), at: CGPoint(x: x, y: y + 57), font: head(7.5), color: grey, kern: 0.8, width: 70)
                x += 108
            }
        }

        // Footer: the mark and the usual caution.
        draw("PHMN", at: CGPoint(x: margin, y: 745), font: font(["ProximaNova-Regular"], 17, .light), kern: 4)
        draw(String(localized: "The products and services of PHMN are not medical devices, are not intended to diagnose any disease, and should not be used as a substitute for professional medical advice, diagnosis or treatment. This report is made on this phone from your own data, for general informational purposes only."),
             at: CGPoint(x: margin, y: 767), font: body(6.8), color: grey, width: page.width - margin * 2)
    }

    // MARK: Charts

    /// A scale from `lo` to `hi` in steps of 1, 2, 2.5, 3, 5 or 10 (times a power of ten), with about `count` steps.
    private static func niceScale(_ lo: Double, _ hi: Double, count: Int) -> (Double, Double, Double) {
        let raw = max((hi - lo) / Double(count), 0.0001)
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 2.5 ? 2.5 : norm <= 3 ? 3 : norm <= 5 ? 5 : 10) * mag
        return ((lo / step).rounded(.down) * step, (hi / step).rounded(.up) * step, step)
    }

    private enum Chart {
        case line(values: [Double?], decimals: Int)
        case bars(base: [Double?], extra: [Double?], step: Double, minTop: Double, decimals: Int, legend: [(String, UIColor)])
    }

    private static func section(_ g: CGContext, y: CGFloat, title: String, subtitle: String, axis: String, slots: [Date], height: CGFloat, days: Int, chart: Chart) {
        draw(title.uppercased(), at: CGPoint(x: margin, y: y), font: head(10.5), kern: 1)
        draw(subtitle, at: CGPoint(x: margin, y: y + 15), font: body(6.6), color: grey, width: page.width - margin * 2 - 70)
        if case .bars(_, _, _, _, _, let legend) = chart {
            var x = page.width - margin
            for (label, color) in legend.reversed() {
                let w = (label as NSString).size(withAttributes: [.font: body(7.5)]).width
                draw(label, at: CGPoint(x: x - w, y: y + 1), font: body(7.5), color: ink)
                g.setFillColor(color.cgColor); g.fill(CGRect(x: x - w - 12, y: y + 3, width: 7, height: 7))
                x -= w + 24
            }
        }
        let plotLeft: CGFloat = 49, plotRight: CGFloat = page.width - margin - 34
        // A subtitle that wraps onto a second line pushes the chart down a little.
        let chartTop = y + (subtitle.count > 120 ? 37 : 27), chartBottom = chartTop + height
        let plot = CGRect(x: plotLeft, y: chartTop, width: plotRight - plotLeft, height: height)
        let slotW = plot.width / CGFloat(slots.count)
        func x(_ i: Int) -> CGFloat { plot.minX + slotW * (CGFloat(i) + 0.5) }

        // Scale.
        var lo = 0.0, hi = 1.0, decimals = 0
        var avg: Double?
        var tickStep = 1.0
        switch chart {
        case .line(let values, let dec):
            let v = values.compactMap { $0 }
            decimals = dec
            if let mn = v.min(), let mx = v.max() {
                let span = max(mx - mn, dec == 0 ? 6 : 1.0)
                (lo, hi, tickStep) = niceScale(mn - span * 0.25, mx + span * 0.25, count: 5)
                avg = v.reduce(0, +) / Double(v.count)
            } else { lo = 0; hi = dec == 0 ? 100 : 20; tickStep = dec == 0 ? 20 : 4 }
        case .bars(let base, let extra, _, let minTop, let dec, _):
            decimals = dec
            let totals = zip(base, extra).map { ($0 ?? 0) + ($1 ?? 0) }
            let mx = max(totals.max() ?? 0, minTop)
            (lo, hi, tickStep) = niceScale(0, mx, count: 5)
            // The average counts the days that have a reading; for the activity minutes, every day (a day without a workout is a zero).
            if dec == 0 { avg = totals.reduce(0, +) / Double(max(totals.count, 1)) }
            else {
                let have = zip(base, extra).filter { $0.0 != nil || $0.1 != nil }.map { ($0.0 ?? 0) + ($0.1 ?? 0) }
                avg = have.isEmpty ? nil : have.reduce(0, +) / Double(have.count)
            }
        }
        func yPos(_ v: Double) -> CGFloat { plot.maxY - CGFloat((v - lo) / (hi - lo)) * plot.height }

        // Grid: five steps across, and a line for each day (each month on the long page).
        // The text drawing below resets the stroke colour, so each line sets its own.
        func line(_ a: CGPoint, _ b: CGPoint, _ color: UIColor, _ width: CGFloat) {
            g.setStrokeColor(color.cgColor); g.setLineWidth(width)
            g.move(to: a); g.addLine(to: b); g.strokePath()
        }
        let tickCount = Int(((hi - lo) / tickStep).rounded())
        for t in 0...max(tickCount, 1) {
            let v = lo + tickStep * Double(t)
            let py = yPos(v)
            line(CGPoint(x: plot.minX, y: py), CGPoint(x: plot.maxX, y: py), grid, 0.4)
            let fmt = tickStep < 1 && tickStep.truncatingRemainder(dividingBy: 1) != 0 ? "%.1f" : "%.0f"
            draw(String(format: fmt, v), at: CGPoint(x: plot.minX - 4, y: py - 4.5), font: num(6.8), color: ink, align: .right)
        }
        let cal = Calendar.current
        if days == 30 {
            for i in 0..<slots.count {
                line(CGPoint(x: x(i), y: plot.minY), CGPoint(x: x(i), y: plot.maxY), grid, 0.4)
                draw(dayFormat(slots[i], "d"), at: CGPoint(x: x(i), y: plot.maxY + 6), font: num(6.8), color: ink, align: .center)
            }
        } else {
            var lastMonth = -1
            var starts: [(index: Int, date: Date)] = []
            for (i, d) in slots.enumerated() {
                let m = cal.component(.month, from: d)
                if m != lastMonth { starts.append((i, d)); lastMonth = m }
            }
            for (n, s) in starts.enumerated() {
                let px = plot.minX + slotW * CGFloat(s.index)
                line(CGPoint(x: px, y: plot.minY), CGPoint(x: px, y: plot.maxY), grid, 0.4)
                // The label of a month sits in the middle of it; a month cut short at either end is not named.
                let end = n + 1 < starts.count ? starts[n + 1].index : slots.count
                if end - s.index >= 20 {
                    let mid = plot.minX + slotW * (CGFloat(s.index + end) / 2)
                    draw(dayFormat(s.date, "MMM").uppercased() + ".", at: CGPoint(x: mid, y: plot.maxY + 7), font: head(7.5), align: .center, kern: 0.8)
                }
            }
        }
        // Axes.
        g.setStrokeColor(ink.cgColor); g.setLineWidth(1)
        g.move(to: CGPoint(x: plot.minX, y: plot.minY)); g.addLine(to: CGPoint(x: plot.minX, y: plot.maxY)); g.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY)); g.strokePath()
        // Axis title, turned to read upward.
        g.saveGState(); g.translateBy(x: 16, y: plot.midY); g.rotate(by: -.pi / 2)
        draw(axis, at: CGPoint(x: 0, y: -5), font: head(7.5), align: .center, kern: 0.6)
        g.restoreGState()

        // Data.
        switch chart {
        case .line(let values, _):
            for i in 1..<max(values.count, 1) {
                guard let a = values[i - 1], let b = values[i] else { continue }
                line(CGPoint(x: x(i - 1), y: yPos(a)), CGPoint(x: x(i), y: yPos(b)), UIColor(white: 0.45, alpha: 1), days == 30 ? 1.1 : 0.9)
            }
            if days == 30 {
                for (i, v) in values.enumerated() {
                    guard let v else { continue }
                    let r = CGRect(x: x(i) - 2.6, y: yPos(v) - 2.6, width: 5.2, height: 5.2)
                    g.setFillColor(UIColor.white.cgColor); g.fillEllipse(in: r)
                    g.setStrokeColor(UIColor(white: 0.45, alpha: 1).cgColor); g.setLineWidth(1); g.strokeEllipse(in: r)
                }
            }
        case .bars(let base, let extra, _, _, _, _):
            let w = days == 30 ? slotW * 0.62 : max(slotW * 0.6, 0.9)
            for i in 0..<base.count {
                let b = base[i] ?? 0, e = extra[i] ?? 0
                if b > 0 { g.setFillColor(barLight.cgColor); g.fill(CGRect(x: x(i) - w / 2, y: yPos(b), width: w, height: plot.maxY - yPos(b))) }
                if e > 0 { g.setFillColor(barDark.cgColor); g.fill(CGRect(x: x(i) - w / 2, y: yPos(b + e), width: w, height: yPos(b) - yPos(b + e))) }
            }
        }
        // The average: a dashed line across, and its figure at the right end.
        if let avg, avg >= lo, avg <= hi {
            g.setStrokeColor(UIColor(white: 0.4, alpha: 1).cgColor); g.setLineWidth(0.7); g.setLineDash(phase: 0, lengths: [3, 2])
            g.move(to: CGPoint(x: plot.minX, y: yPos(avg))); g.addLine(to: CGPoint(x: plot.maxX, y: yPos(avg))); g.strokePath(); g.setLineDash(phase: 0, lengths: [])
            let text: String
            switch decimals { case 0: text = String(Int(avg.rounded())); case 1: text = String(format: "%.1f", avg); default: text = String(format: "%.2f", avg) }
            draw(text, at: CGPoint(x: page.width - margin, y: yPos(avg) - 9), font: num(7.5, bold: true), align: .right)
            draw("AVG", at: CGPoint(x: page.width - margin, y: yPos(avg) - 1), font: head(6.8), color: grey, align: .right)
        }
    }
}

/// The sheet behind "Share your health report": who the report is for, a look at the first page and the share button.
struct NunaHealthReportSheet: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage("report.name") private var name = ""
    @State private var fileURL: URL?
    @State private var preview: UIImage?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Health report").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase)
                .foregroundStyle(NunaPalette.textPrimary).frame(maxWidth: .infinity)
            Text("A 30 day page and a 180 day page of your respiratory rate, resting heart rate, sleep and aerobic activity, made on this phone from your own data.")
                .font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Name on the report").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                TextField("", text: $name, prompt: Text("Your name").foregroundStyle(NunaPalette.textMuted))
                    .font(.nuna(size: 16, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(NunaPalette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .submitLabel(.done).onSubmit { Task { await build() } }
            }
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            } else if working {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 120)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { Task { await build() } } label: {
                    Text("Update").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .overlay(RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous).strokeBorder(NunaPalette.textPrimary.opacity(0.5), lineWidth: 1.5))
                }.buttonStyle(.plain).disabled(working)
                if let fileURL {
                    ShareLink(item: fileURL) {
                        HStack(spacing: 8) { Image(systemName: "square.and.arrow.up"); Text("Share") }
                            .font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.onAccent)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                    }
                } else {
                    Text("Share").font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(NunaPalette.tile, in: RoundedRectangle(cornerRadius: NunaRadius.button, style: .continuous))
                }
            }
        }
        .padding(.horizontal, NunaSpacing.screenH).padding(.top, 20).padding(.bottom, 16)
        .background(NunaBackdrop())
        .preferredColorScheme(NunaTheme.colorScheme)
        .task { await build() }
    }

    @MainActor private func build() async {
        working = true
        defer { working = false }
        let data = await NunaHealthReportData.gather(repo: repo, profile: profile, name: name.trimmingCharacters(in: .whitespaces))
        let pdf = NunaHealthReportRenderer.pdf(data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PHMN Health Report.pdf")
        try? pdf.write(to: url, options: .atomic)
        fileURL = url
        if let doc = CGPDFDocument(CGDataProvider(data: pdf as CFData)!), let pg = doc.page(at: 1) {
            let box = pg.getBoxRect(.mediaBox)
            let scale: CGFloat = 1.6
            let r = UIGraphicsImageRenderer(size: CGSize(width: box.width * scale, height: box.height * scale))
            preview = r.image { c in
                UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: CGSize(width: box.width * scale, height: box.height * scale)))
                c.cgContext.translateBy(x: 0, y: box.height * scale); c.cgContext.scaleBy(x: scale, y: -scale)
                c.cgContext.drawPDFPage(pg)
            }
        }
    }
}
#endif

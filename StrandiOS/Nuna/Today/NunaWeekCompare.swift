#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

/// "Charge & Effort": the last seven days of Charge and Effort for each of the seven days ending on the day shown, as a capsule (Charge) with a line across it
/// (Effort), both on the same 0 to 100 height. The colours read exactly as they do on the rings above.
struct NunaWeekCompare: View {
    let endDay: Date
    let effortScale: EffortScale

    @EnvironmentObject private var repo: Repository
    @State private var charge: [String: Double] = [:]
    @State private var effort: [String: Double] = [:]
    @State private var loaded = false
    @State private var selected: String?

    private struct Slot: Identifiable {
        let key: String
        let date: Date
        var id: String { key }
    }

    private var slots: [Slot] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: endDay)
        return (0..<7).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: end).map { Slot(key: Repository.localDayKey($0), date: $0) }
        }
    }

    var body: some View {
        let days = slots
        let hasData = days.contains { charge[$0.key] != nil || effort[$0.key] != nil }
        NavigationLink(value: NunaTodayRoute.chargeEffort) {
            NunaCard {
                VStack(alignment: .leading, spacing: 14) {
                    NunaTitleRow(title: "Charge & Effort") {
                        Image(systemName: "chevron.right").font(.nuna(size: 14, weight: .heavy)).foregroundStyle(NunaPalette.textPrimary)
                    }
                    if loaded && !hasData {
                        Text("No readings in the last 7 days yet").font(.nuna(size: 14, weight: .semibold))
                            .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    } else if NunaThemePrefs.skin == .flow {
                        NunaCapsuleChart(start: days.first?.key ?? Repository.localDayKey(endDay), days: 7,
                                         charge: days.compactMap { s in charge[s.key].map { (s.key, $0) } },
                                         effort: days.compactMap { s in effort[s.key].map { (s.key, $0) } },
                                         effortScale: effortScale, selected: $selected, highlightLast: true)
                        NunaCapsuleLegend()
                    } else {
                        NunaChargeEffortLines(days: days.map { ($0.key, $0.date) }, charge: charge, effort: effort, effortScale: effortScale, selected: $selected)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: "\(repo.refreshSeq)-\(Repository.localDayKey(endDay))") { await load() }
    }

    private func load() async {
        async let c = repo.exploreSeries(key: "recovery", source: "my-whoop", days: 30)
        async let e = repo.exploreSeries(key: "strain", source: "my-whoop", days: 30)
        charge = Dictionary(await c.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        effort = Dictionary(await e.map { ($0.day, $0.value) }, uniquingKeysWith: { _, l in l })
        loaded = true
    }
}

/// Effort (blue, left axis) and Charge (right axis, in its three zone colours) over the last seven days as two lines with a ring on each day, the
/// day that is selected (the latest, until another is touched) standing on a lighter column with its figures in colour.
struct NunaChargeEffortLines: View {
    let days: [(key: String, date: Date)]
    let charge: [String: Double]
    let effort: [String: Double]
    let effortScale: EffortScale
    @Binding var selected: String?

    private let blue = NunaPalette.effortModerate

    private var effortTop: Double { effortScale == .whoop ? 21 : 100 }
    private var effortTicks: [Double] { effortScale == .whoop ? [0, 7, 14, 21] : [0, 25, 50, 75, 100] }
    private var litKey: String? { selected ?? days.last(where: { charge[$0.key] != nil || effort[$0.key] != nil })?.key ?? days.last?.key }

    private func weekday(_ d: Date, _ template: String) -> String {
        let f = DateFormatter(); f.locale = AppLanguage.activeLocale; f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    var body: some View {
        GeometryReader { geo in
            let left: CGFloat = 34, right: CGFloat = 50, top: CGFloat = 14, bottom: CGFloat = 52
            let w = geo.size.width, h = geo.size.height
            let plot = CGRect(x: left, y: top, width: w - left - right, height: h - top - bottom)
            let col = plot.width / CGFloat(max(days.count, 1))
            let cx: (Int) -> CGFloat = { plot.minX + (CGFloat($0) + 0.5) * col }
            let yc: (Double) -> CGFloat = { plot.maxY - CGFloat(min(max($0, 0), 100) / 100) * plot.height }
            let ye: (Double) -> CGFloat = { plot.maxY - CGFloat(min(max($0, 0), effortTop) / effortTop) * plot.height }
            let lit = days.firstIndex { $0.key == litKey }
            ZStack(alignment: .topLeading) {
                if let lit {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.09))
                        .frame(width: col - 4, height: h - 4).position(x: cx(lit), y: h / 2)
                }
                ForEach(0..<4, id: \.self) { i in
                    Rectangle().fill(NunaPalette.hairline.opacity(0.7)).frame(width: plot.width, height: 1)
                        .position(x: plot.midX, y: plot.minY + CGFloat(i) / 3 * plot.height)
                }
                // Effort's scale on the left in blue, Charge's on the right in the colour of each zone.
                ForEach(effortTicks, id: \.self) { t in
                    Text(verbatim: "\(Int(t))").font(.nuna(size: 13, weight: .heavy)).foregroundStyle(blue).position(x: left / 2 - 2, y: ye(t))
                }
                ForEach([(100.0, "100%", 100.0), (66.0, "66%", 50.0), (33.0, "33%", 10.0), (0.0, "0%", 10.0)], id: \.0) { t in
                    Text(verbatim: t.1).font(.nuna(size: 13, weight: .heavy)).foregroundStyle(nunaChargeColor(t.2)).position(x: w - right / 2 + 4, y: yc(t.0))
                }
                chargeLine(cx, yc, ye)
                effortLine(cx, ye, yc)
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    let on = day.key == litKey
                    VStack(spacing: 1) {
                        Text(verbatim: weekday(day.date, "EEE")).font(.nuna(size: 13.5, weight: on ? .heavy : .semibold)).textCase(nil)
                        Text(verbatim: weekday(day.date, "d")).font(.nuna(size: 13.5, weight: on ? .heavy : .semibold))
                    }
                    .foregroundStyle(on ? NunaPalette.textPrimary : NunaPalette.textSecondary)
                    .position(x: cx(i), y: plot.maxY + 30)
                    Color.clear.frame(width: col, height: h).contentShape(Rectangle()).position(x: cx(i), y: h / 2)
                        .onTapGesture { selected = (selected == day.key) ? nil : day.key }
                }
            }
        }
        .frame(height: 290)
    }

    @ViewBuilder private func chargeLine(_ cx: @escaping (Int) -> CGFloat, _ yc: @escaping (Double) -> CGFloat, _ ye: @escaping (Double) -> CGFloat) -> some View {
        let pts = days.enumerated().compactMap { i, d in charge[d.key].map { (i, d.key, $0) } }
        Path { p in for (n, pt) in pts.enumerated() { let c = CGPoint(x: cx(pt.0), y: yc(pt.2)); n == 0 ? p.move(to: c) : p.addLine(to: c) } }
            .stroke(NunaPalette.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        ForEach(pts, id: \.0) { pt in
            let on = pt.1 == litKey
            ring(on ? nunaChargeColor(pt.2) : NunaPalette.textPrimary).position(x: cx(pt.0), y: yc(pt.2))
            Text(verbatim: String(format: "%.0f%%", pt.2)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design))
                .foregroundStyle(on ? nunaChargeColor(pt.2) : NunaPalette.textPrimary).fixedSize()
                .position(x: cx(pt.0), y: yc(pt.2) + (chargeIsHigher(pt.1, yc, ye) ? -20 : 22))
        }
    }

    @ViewBuilder private func effortLine(_ cx: @escaping (Int) -> CGFloat, _ ye: @escaping (Double) -> CGFloat, _ yc: @escaping (Double) -> CGFloat) -> some View {
        let pts = days.enumerated().compactMap { i, d in effort[d.key].map { (i, UnitFormatter.effortValue($0, scale: effortScale)) } }
        Path { p in for (n, pt) in pts.enumerated() { let c = CGPoint(x: cx(pt.0), y: ye(pt.1)); n == 0 ? p.move(to: c) : p.addLine(to: c) } }
            .stroke(blue.opacity(0.7), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        ForEach(pts, id: \.0) { pt in
            ring(blue).position(x: cx(pt.0), y: ye(pt.1))
            Text(verbatim: String(format: "%.1f", locale: AppLanguage.activeLocale, pt.1)).font(.nuna(size: 14, weight: .heavy, design: NunaType.design))
                .foregroundStyle(blue).fixedSize()
                .position(x: cx(pt.0), y: ye(pt.1) + (effortIsHigher(pt.0, ye, yc) ? -20 : 22))
        }
    }

    /// On a day with both figures, the higher point takes its figure above it and the lower one below, so the two never sit on each other.
    private func chargeIsHigher(_ key: String, _ yc: (Double) -> CGFloat, _ ye: (Double) -> CGFloat) -> Bool {
        guard let c = charge[key], let e = effort[key] else { return true }
        return yc(c) <= ye(UnitFormatter.effortValue(e, scale: effortScale))
    }

    private func effortIsHigher(_ index: Int, _ ye: (Double) -> CGFloat, _ yc: (Double) -> CGFloat) -> Bool {
        let key = days[index].key
        guard let c = charge[key], let e = effort[key] else { return false }
        return ye(UnitFormatter.effortValue(e, scale: effortScale)) < yc(c)
    }

    private func ring(_ color: Color) -> some View {
        Circle().fill(NunaPalette.card).overlay(Circle().stroke(color, lineWidth: 3)).frame(width: 14, height: 14)
    }
}
#endif

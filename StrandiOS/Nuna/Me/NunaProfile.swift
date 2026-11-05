#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Levels

/// Levels climb with the number of days the strap scored a Recovery. The first is the start; each next one asks for more days than the one before.
enum NunaLevels {
    /// Recoveries needed for level 1 to 30.
    static let thresholds: [Int] = [0, 4, 7, 14, 21, 30, 40, 50, 65, 80, 100, 125, 150, 200, 250, 300, 400, 500, 650, 800,
                                    1000, 1200, 1400, 1600, 1800, 2000, 2250, 2500, 2750, 3000]
    static let top = thresholds.count

    static func level(for recoveries: Int) -> Int { (thresholds.lastIndex { $0 <= recoveries } ?? 0) + 1 }

    enum Tier: String { case carbon, iron, steel, gunmetal, titanium, bronze, silver, gold, platinum, diamond
        var name: LocalizedStringKey {
            switch self {
            case .carbon: "Carbon"; case .iron: "Iron"; case .steel: "Steel"; case .gunmetal: "Gunmetal"; case .titanium: "Titanium"
            case .bronze: "Bronze"; case .silver: "Silver"; case .gold: "Gold"; case .platinum: "Platinum"; case .diamond: "Diamond"
            }
        }
        /// The ring and the stars round a locked level: bronze none, silver two, gold and platinum three, diamond four.
        var stars: Int { switch self { case .bronze: 1; case .silver: 2; case .gold, .platinum: 3; case .diamond: 4; default: 0 } }
        var hasRing: Bool { stars > 0 }
        var color: Color {
            switch self {
            case .carbon: Color(red: 0.20, green: 0.20, blue: 0.21); case .iron: Color(red: 0.34, green: 0.35, blue: 0.37)
            case .steel: Color(red: 0.45, green: 0.46, blue: 0.48); case .gunmetal: Color(red: 0.27, green: 0.29, blue: 0.31)
            case .titanium: Color(red: 0.30, green: 0.31, blue: 0.33); case .bronze: Color(red: 0.47, green: 0.33, blue: 0.25)
            case .silver: Color(red: 0.50, green: 0.52, blue: 0.55); case .gold: Color(red: 0.68, green: 0.55, blue: 0.27)
            case .platinum: Color(red: 0.47, green: 0.49, blue: 0.52); case .diamond: Color(red: 0.24, green: 0.40, blue: 0.43)
            }
        }
    }

    static func tier(_ level: Int) -> Tier {
        switch level {
        case ...1: .carbon; case 2: .iron; case 3: .steel; case 4: .gunmetal; case 5: .titanium
        case 6...10: .bronze; case 11...15: .silver; case 16...20: .gold; case 21...25: .platinum; default: .diamond
        }
    }
}

/// A level as a band with its number: a plate of the tier's metal, or a dark one with a lock when it is still ahead.
struct NunaLevelBadge: View {
    let level: Int
    var locked = false
    var size: CGFloat = 72

    var body: some View {
        let tier = NunaLevels.tier(level)
        ZStack {
            if locked, tier.hasRing {
                Circle().strokeBorder(tier.color.opacity(0.45), lineWidth: 1).frame(width: size * 1.55, height: size * 1.55)
                if tier.stars >= 3 { Circle().strokeBorder(tier.color.opacity(0.3), lineWidth: 1).frame(width: size * 1.3, height: size * 1.3) }
            }
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(LinearGradient(colors: locked ? [Color(red: 0.23, green: 0.25, blue: 0.28), Color(red: 0.17, green: 0.19, blue: 0.21)]
                                                    : [tier.color.opacity(0.95), tier.color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.62, height: size)
                .overlay(alignment: .bottom) {
                    if !locked { RoundedRectangle(cornerRadius: size * 0.05, style: .continuous).fill(Color.white.opacity(0.28)).frame(height: size * 0.2).padding(.horizontal, 2).padding(.bottom, 4) }
                }
            if locked {
                Image(systemName: "lock").font(.system(size: size * 0.34, weight: .regular)).foregroundStyle(.white)
            } else {
                Text(verbatim: "\(level)").font(.nunaBoldFigure(size: size * 0.4)).foregroundStyle(.white).offset(y: -size * 0.08)
            }
            if locked, tier.hasRing {
                HStack(spacing: 2) { ForEach(0..<tier.stars, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: size * 0.11)) } }
                    .foregroundStyle(tier.color.opacity(0.8)).offset(y: size * 0.74)
            }
        }
        .frame(width: size * (locked && tier.hasRing ? 1.55 : 0.8), height: size * (locked && tier.hasRing ? 1.55 : 1.05))
    }
}

struct NunaLevelsView: View {
    @EnvironmentObject private var repo: Repository
    private var recoveries: Int { repo.days.filter { $0.recovery != nil }.count }
    private var level: Int { NunaLevels.level(for: recoveries) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NunaDetailScreen("Levels", centersTitle: true) {
            current
            LazyVGrid(columns: columns, spacing: 30) {
                ForEach(1...NunaLevels.top, id: \.self) { n in cell(n) }
            }
            .padding(.top, 14)
        }
    }

    private var current: some View {
        let tier = NunaLevels.tier(level)
        let next = level < NunaLevels.top ? NunaLevels.thresholds[level] : nil
        let from = NunaLevels.thresholds[level - 1]
        let fraction = next.map { Double(recoveries - from) / Double(max($0 - from, 1)) } ?? 1
        return VStack(spacing: 8) {
            NunaLevelBadge(level: level, size: 150).padding(.top, 20).padding(.bottom, 14)
            Text(tier.name).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel * 1.4).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Text(verbatim: String(localized: "Level \(level)")).font(.nuna(size: 30, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
            if let next {
                HStack(spacing: 12) {
                    NunaLevelBadge(level: level, size: 26)
                    GeometryReader { g in
                        Capsule().fill(Color.black.opacity(0.55)).overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, g.size.width * CGFloat(min(max(fraction, 0), 1))))
                        }
                    }.frame(height: 10)
                    NunaLevelBadge(level: level + 1, locked: false, size: 26).opacity(0.7)
                }
                .padding(.top, 8)
                Text(verbatim: String(localized: "\(next - recoveries) more Recoveries to Level \(level + 1)")).font(.nuna(size: 14, weight: .regular))
                    .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ n: Int) -> some View {
        let unlocked = n <= level
        let tier = NunaLevels.tier(n)
        return VStack(spacing: 8) {
            NunaLevelBadge(level: n, locked: !unlocked, size: 66).frame(height: 104)
            VStack(spacing: 5) {
                Text(tier.name).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textMuted)
                Text(verbatim: String(localized: "Level \(n)")).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase)
                    .foregroundStyle(unlocked ? NunaPalette.textPrimary : NunaPalette.textMuted)
                Text(verbatim: n == 1 ? String(localized: "Membership starts") : String(localized: "\(NunaLevels.thresholds[n - 1]) Recoveries"))
                    .font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(unlocked ? NunaPalette.textSecondary : NunaPalette.textMuted).textCase(nil)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shapes for the badges

/// A circle with a gently scalloped edge, the seal behind an activity badge and a notable stat.
struct NunaSealShape: Shape {
    var bumps = 24
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2 * 0.96
        let n = 240
        for i in 0...n {
            let t = Double(i) / Double(n) * 2 * .pi
            let rad = r * (1 + 0.035 * cos(Double(bumps) * t))
            let pt = CGPoint(x: c.x + CGFloat(cos(t) * rad), y: c.y + CGFloat(sin(t) * rad))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
}

struct NunaHexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let t = Double(i) / 6 * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(t)) * r, y: c.y + CGFloat(sin(t)) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath(); return p
    }
}

struct NunaShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        p.move(to: CGPoint(x: x + w * 0.12, y: y))
        p.addLine(to: CGPoint(x: x + w * 0.88, y: y))
        p.addQuadCurve(to: CGPoint(x: x + w, y: y + h * 0.12), control: CGPoint(x: x + w, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y + h * 0.5))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h), control: CGPoint(x: x + w, y: y + h * 0.82))
        p.addQuadCurve(to: CGPoint(x: x, y: y + h * 0.5), control: CGPoint(x: x, y: y + h * 0.82))
        p.addLine(to: CGPoint(x: x, y: y + h * 0.12))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.12, y: y), control: CGPoint(x: x, y: y))
        p.closeSubpath(); return p
    }
}

struct NunaDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); p.closeSubpath()
        return p
    }
}

/// One achievement: a dark badge in the shape of its group, the glyph of what it counts, a lock until the first level, and the level it has reached.
struct NunaAchievementBadge: View {
    enum Shape { case hexagon, shield, diamond, seal }
    let shape: Shape
    let icon: String
    let level: Int

    private var earned: Bool { level >= 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                badge.frame(width: 70, height: 70)
                Image(systemName: earned ? icon : "lock.fill").font(.system(size: earned ? 28 : 22, weight: earned ? .semibold : .regular))
                    .foregroundStyle(earned ? Color.white : Color(red: 0.42, green: 0.43, blue: 0.45))
            }
            Text(verbatim: "\(level)").font(.nunaBoldFigure(size: 30)).foregroundStyle(earned ? Color.white : Color(red: 0.55, green: 0.56, blue: 0.58))
                .offset(y: 14).shadow(color: .black.opacity(0.6), radius: 4)
        }
        .frame(width: 74, height: 90)
    }

    @ViewBuilder private var badge: some View {
        let fill = LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.13, green: 0.12, blue: 0.16)], startPoint: .top, endPoint: .bottom)
        let edge = earned ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.75, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color(red: 0.45, green: 0.46, blue: 0.48))
        switch shape {
        case .hexagon: NunaHexagonShape().fill(fill).overlay(NunaHexagonShape().stroke(edge, lineWidth: 1.2))
        case .shield: NunaShieldShape().fill(fill).overlay(NunaShieldShape().stroke(edge, lineWidth: 1.2))
        case .diamond: NunaDiamondShape().fill(fill).overlay(NunaDiamondShape().stroke(edge, lineWidth: 1.2))
        case .seal: NunaSealShape().fill(fill).overlay(NunaSealShape().stroke(edge, lineWidth: 1.2))
        }
    }
}

// MARK: - Profile

/// My Account: who the profile is, its level, what the days add up to. The numbers are worked out here from the stored days and saved workouts.
struct NunaProfileView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var updateStore: UpdateStore
    @State private var showInbox = false
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @State private var workouts: [WorkoutRow] = []
    @State private var fitnessAge: Double?
    @State private var highlightsPeriod = Period.all
    @State private var summaryPeriod = Period.all

    enum Period: Hashable { case month, quarter, all
        var days: Int? { switch self { case .month: 30; case .quarter: 90; case .all: nil } }
    }

    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var cal: Calendar { Calendar.current }
    private var allDays: [DailyMetric] { repo.days.sorted { $0.day < $1.day } }
    private var recoveries: Int { allDays.filter { $0.recovery != nil }.count }
    private var level: Int { NunaLevels.level(for: recoveries) }

    private func days(_ p: Period) -> [DailyMetric] {
        guard let n = p.days, let from = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: Date())) else { return allDays }
        let key = Repository.localDayKey(from)
        return allDays.filter { $0.day >= key }
    }

    private func sessions(_ p: Period) -> [WorkoutRow] {
        guard let n = p.days, let from = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: Date())) else { return workouts }
        let ts = Int(from.timeIntervalSince1970)
        return workouts.filter { $0.startTs >= ts }
    }

    // MARK: Body

    var body: some View {
        NunaDetailScreen("Profile", trailing: AnyView(headerActions), centersTitle: true) {
            identity
            memberSince
            levelAndAge
            streakRow
            memoryRow
            achievements
            highlights
            activitySummary
        }
        .background(alignment: .top) {
            // A warm glow behind the avatar and the header, fading out by the level cards.
            RadialGradient(colors: [Color(red: 0.62, green: 0.30, blue: 0.28).opacity(0.6), .clear], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 330)
                .frame(height: 440).ignoresSafeArea().allowsHitTesting(false)
        }
        .sheet(isPresented: $showInbox) { NunaUpdatesInbox(onClose: { showInbox = false }).nunaSheetChrome(detents: [.large]) }
        .task(id: repo.refreshSeq) {
            workouts = await repo.workoutRows()
            let m = NunaTodayModel(); await m.load(repo: repo, profile: profile)
            fitnessAge = m.extras["fitness_age"]
        }
    }

    // MARK: Identity

    private var avatar: some View { NunaProfileAvatar(size: 98) }

    /// The updates inbox (the bell that used to sit on Today) and the way into Settings.
    private var headerActions: some View {
        HStack(spacing: 0) {
            Button { showInbox = true } label: {
                Image(systemName: "bell").font(.system(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if updateStore.unreadCount > 0 { Circle().fill(NunaPalette.alert).frame(width: 9, height: 9).offset(x: -9, y: 10) }
                    }
            }
            .accessibilityLabel(Text("Updates"))
            NavigationLink(value: NunaMeRoute.settings) {
                Image(systemName: "gearshape").font(.system(size: 22, weight: .regular)).foregroundStyle(NunaPalette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Settings"))
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 18) {
            avatar.padding(.top, 8)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: profile.displayName.isEmpty ? String(localized: "Your name") : profile.displayName)
                        .font(.nuna(size: 26, weight: .heavy)).foregroundStyle(profile.displayName.isEmpty ? NunaPalette.textSecondary : NunaPalette.textPrimary).textCase(nil).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: "\(profile.age) • " + (Locale.current.region?.identifier ?? "")).font(.nuna(size: 14.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                Spacer(minLength: 8)
                NavigationLink(value: NunaMeRoute.persona) {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .regular))
                        Text("Edit").font(.nuna(size: 13, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                    }
                    .foregroundStyle(NunaPalette.textPrimary).padding(.horizontal, 22).frame(height: 45)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memberSince: some View {
        let first = allDays.first.flatMap { d -> String? in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            guard let date = f.date(from: d.day) else { return nil }
            let o = DateFormatter(); o.locale = AppLanguage.activeLocale; o.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return o.string(from: date)
        }
        return HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 11, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 24, height: 24).overlay(Circle().strokeBorder(NunaPalette.textPrimary, lineWidth: 1.2))
            Text("Data since").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            Text(verbatim: first ?? "–").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 44).frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Level and fitness age

    private var levelAndAge: some View {
        HStack(spacing: 12) {
            NavigationLink(value: NunaMeRoute.levels) {
                profileCard(title: "Level \(level)", subtitle: String(localized: "\(recoveries) Recoveries"), chevron: true) {
                    NunaLevelBadge(level: level, size: 66).frame(height: 78)
                }
            }.buttonStyle(.plain)
            Button { router.pendingMetricKey = "fitness_age" } label: {
                profileCard(title: "Fitness age", subtitle: fitnessAge.map { String(localized: "\(Int($0.rounded())) years") } ?? String(localized: "Needs a few more days of data before it can be worked out."),
                            chevron: true) {
                    Circle().fill(RadialGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.22), Color(red: 0.62, green: 0.28, blue: 0.75).opacity(0.85)], center: .center, startRadius: 12, endRadius: 36))
                        .overlay(Circle().strokeBorder(Color(red: 0.75, green: 0.35, blue: 0.9), lineWidth: 1.5)).frame(width: 66, height: 66)
                        .overlay { if let a = fitnessAge { Text(verbatim: "\(Int(a.rounded()))").font(.nunaBoldFigure(size: 26)).foregroundStyle(.white) } }
                        .frame(height: 78)
                }
            }.buttonStyle(.plain)
        }
    }

    private func profileCard<Art: View>(title: LocalizedStringKey, subtitle: String, chevron: Bool, @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 10) {
            HStack { Spacer(); if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary) } }.frame(height: 14)
            art()
            Text(title).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).padding(.top, 6)
            Text(verbatim: subtitle).font(.nuna(size: 13.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 190)
        .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Streak and memory

    private var dayStreak: Int { NunaStreak.compute(days: allDays).current }

    private var streakRow: some View {
        NavigationLink(value: NunaMeRoute.dayStreak) {
            HStack(spacing: 12) {
                Text("Day streak").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "flame.fill").font(.system(size: 18)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.2))
                Text(verbatim: String(localized: "\(dayStreak) Days")).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.horizontal, 20).frame(height: 52).frame(maxWidth: .infinity)
            .background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var memoryRow: some View {
        NavigationLink { NunaAnyaMemoryView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "lightbulb.max").font(.system(size: 20)).foregroundStyle(Color(red: 0.55, green: 0.55, blue: 0.98))
                Text("My Memory").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary)
            }
            .padding(.horizontal, 20).frame(height: 54).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.36), Color(red: 0.12, green: 0.19, blue: 0.27)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Achievements

    private func rest(_ d: DailyMetric) -> Double { AnalyticsEngine.Rest.composite(daily: d) ?? 0 }

    private var achievements: some View {
        let list = NunaAchievementCatalog.build(days: allDays, workouts: workouts)
        // The earned ones first, then the nearest to a first level, so the row opens on what is going on.
        let shown = list.sorted { ($0.level > 0 ? 1000 + $0.count : $0.count) > ($1.level > 0 ? 1000 + $1.count : $1.count) }.prefix(6)
        let earned = list.filter { $0.level > 0 }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Achievements") + Text(verbatim: " (\(earned))").foregroundStyle(NunaPalette.textSecondary)).font(.nuna(size: 21, weight: .semibold)).textCase(nil)
                Spacer(minLength: 8)
                NavigationLink(value: NunaMeRoute.achievements) {
                    HStack(spacing: 8) {
                        Text("View all").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                        Image(systemName: "arrow.right").font(.system(size: 15))
                    }.foregroundStyle(NunaPalette.textPrimary).frame(minHeight: 36)
                }.buttonStyle(.plain)
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(shown)) { a in
                        VStack(spacing: 8) {
                            NunaAchievementBadge(shape: a.shape, icon: a.icon, level: a.level)
                            Text(a.title).font(.nuna(size: 13.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).lineLimit(1)
                        }.frame(width: 104)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
    }

    // MARK: Data highlights

    private func longestRun(_ list: [DailyMetric], _ test: (DailyMetric) -> Bool) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var best = 0, run = 0
        var previous: Date?
        for d in list {
            guard let when = f.date(from: d.day) else { continue }
            if test(d) {
                if let p = previous, cal.dateComponents([.day], from: p, to: when).day == 1, run > 0 { run += 1 } else { run = 1 }
                previous = when; best = max(best, run)
            } else { run = 0; previous = nil }
        }
        return best
    }

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.nuna(size: 21, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }

    private func periodPicker(_ binding: Binding<Period>) -> some View {
        NunaSegmented([(value: Period.month, title: "1M"), (value: Period.quarter, title: "3M"), (value: Period.all, title: "All time")], selection: binding)
    }

    private func ruled(_ t: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Text(t).font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
            Rectangle().fill(NunaPalette.hairline).frame(height: 1)
        }
    }

    private var highlights: some View {
        let list = days(highlightsPeriod)
        let bestSleep = list.map(rest).max().flatMap { $0 > 0 ? $0 : nil }
        let peakRecovery = list.compactMap(\.recovery).max()
        let maxStrain = list.compactMap(\.strain).max()
        let rhr = list.compactMap { $0.restingHr.map(Double.init) }
        let hrv = list.compactMap(\.avgHrv)
        let maxHr = sessions(highlightsPeriod).compactMap(\.maxHr).max()
        let longest = list.compactMap(\.totalSleepMin).max()
        let lowestRecovery = list.compactMap(\.recovery).min()
        let working = 10.0 / 21 * 100
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Data Highlights")
            VStack(alignment: .leading, spacing: 20) {
                periodPicker($highlightsPeriod)
                HStack(alignment: .top, spacing: 4) {
                    ring(bestSleep.map { "\(Int($0.rounded()))%" } ?? "–", fraction: (bestSleep ?? 0) / 100, color: NunaPalette.restText, label: "Best Sleep")
                    ring(peakRecovery.map { "\(Int($0.rounded()))%" } ?? "–", fraction: (peakRecovery ?? 0) / 100, color: peakRecovery.map(nunaChargeColor) ?? NunaPalette.charge, label: "Peak Recovery")
                    ring(maxStrain.map { UnitFormatter.effortDisplay($0, scale: scale) } ?? "–", fraction: (maxStrain ?? 0) / 100, color: NunaPalette.effortModerate, label: "Max Strain")
                }
                ruled("Streaks")
                HStack(alignment: .top, spacing: 0) {
                    streak("moon", longestRun(list) { rest($0) >= 70 }, "70%+ Sleep", NunaPalette.restText)
                    streak("figure.mind.and.body", longestRun(list) { ($0.recovery ?? 0) >= 67 }, "Green Recovery", NunaPalette.scoreHigh)
                    streak("dumbbell", longestRun(list) { ($0.strain ?? 0) >= working }, "10+ Strain", NunaPalette.effortModerate)
                }
                ruled("Notable stats")
                VStack(spacing: 0) {
                    stat("heart.text.square", "Lowest RHR", rhr.min().map { "\(Int($0))" }, "bpm")
                    stat("heart.text.square", "Highest RHR", rhr.max().map { "\(Int($0))" }, "bpm")
                    stat("waveform.path.ecg", "Lowest HRV", hrv.min().map { "\(Int($0.rounded()))" }, "ms")
                    stat("waveform.path.ecg", "Highest HRV", hrv.max().map { "\(Int($0.rounded()))" }, "ms")
                    stat("heart", "Max Heart Rate", maxHr.map(String.init), "bpm")
                    stat("moon", "Longest Sleep", longest.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }, "hr")
                    stat("figure.mind.and.body", "Lowest Recovery", lowestRecovery.map { "\(Int($0.rounded()))" }, "%", last: true)
                }
            }
            .padding(18).background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func ring(_ value: String, fraction: Double, color: Color, label: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            NunaRingGauge(fraction: min(max(fraction, 0), 1), color: color, size: 72, lineWidth: 4.5) {
                Text(verbatim: value).font(.nunaBoldFigure(size: 21)).foregroundStyle(NunaPalette.textPrimary).minimumScaleFactor(0.6).lineLimit(1)
            }
            Text(label).font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private func seal(_ icon: String, _ color: Color, size: CGFloat = 42) -> some View {
        NunaSealShape().stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 1.5])).frame(width: size, height: size)
            .overlay(Image(systemName: icon).font(.system(size: size * 0.42, weight: .regular)).foregroundStyle(color))
    }

    private func streak(_ icon: String, _ n: Int, _ label: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            seal(icon, tint.opacity(0.9))
            Text(verbatim: String(localized: "\(n) Days")).font(.nuna(size: 15.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
            Text(label).font(.nuna(size: 12.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private func stat(_ icon: String, _ title: LocalizedStringKey, _ value: String?, _ unit: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                seal(icon, Color(red: 0.84, green: 0.70, blue: 0.40), size: 40)
                Text(title).font(.nuna(size: 15.5, weight: .regular)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: value ?? "–").font(.nunaBoldFigure(size: 22)).foregroundStyle(NunaPalette.textPrimary)
                    if value != nil { Text(verbatim: unit).font(.nuna(size: 13.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                }
            }
            .padding(.vertical, 12)
            if !last { Rectangle().fill(NunaPalette.hairline).frame(height: 1) }
        }
    }

    // MARK: Activity summary

    private var activitySummary: some View {
        let ws = sessions(summaryPeriod)
        struct Row: Identifiable { let id: String; let count: Int; let avg: Double? }
        let rows = Dictionary(grouping: ws) { WorkoutSource.displaySport($0.sport) }
            .map { g -> Row in let s = g.value.compactMap(\.strain); return Row(id: g.key, count: g.value.count, avg: s.isEmpty ? nil : s.reduce(0, +) / Double(s.count)) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
        let top = max(rows.first?.count ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Activity Summary")
            VStack(alignment: .leading, spacing: 18) {
                periodPicker($summaryPeriod)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(ws.count)x").font(.nunaBoldFigure(size: 34)).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                    Text("Total activities").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.3).textCase(.uppercase).foregroundStyle(NunaPalette.textSecondary)
                }
                HStack {
                    Text("Activity | Avg. strain").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                    Spacer()
                    Text("Total").font(.nuna(size: 12.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase)
                }.foregroundStyle(NunaPalette.textSecondary)
                if rows.isEmpty {
                    Text("No activities in this period").font(.nuna(size: 14, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    VStack(alignment: .leading, spacing: 14) {
                        if i > 0 { Rectangle().fill(NunaPalette.hairline).frame(height: 1) }
                        HStack(spacing: 12) {
                            Image(systemName: sportSymbol(r.id)).font(.system(size: 20, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).frame(width: 26)
                            Text(verbatim: r.id).font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingLabel * 1.2).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary).lineLimit(1)
                            if let a = r.avg { Text(verbatim: UnitFormatter.effortDisplay(a, scale: scale)).font(.nunaBoldFigure(size: 15)).foregroundStyle(NunaPalette.textSecondary) }
                            Spacer(minLength: 6)
                            Text(verbatim: "\(r.count)x").font(.nunaBoldFigure(size: 23)).textCase(nil).foregroundStyle(Color(red: 0.27, green: 0.57, blue: 0.88))
                        }
                        NunaHatchBar(fraction: Double(r.count) / Double(top))
                    }
                }
            }
            .padding(18).background(NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// A bar in the Effort blue that fills part of its track; the rest of the track is hatched.
struct NunaHatchBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            let filled = g.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    var p = Path()
                    var x: CGFloat = -size.height
                    while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 7 }
                    ctx.stroke(p, with: .color(Color.white.opacity(0.28)), lineWidth: 1.6)
                }
                .clipShape(Capsule())
                Capsule().fill(Color(red: 0.24, green: 0.52, blue: 0.88)).frame(width: max(filled, 8))
            }
        }
        .frame(height: 9)
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - What's new (About.dc › What's new)

struct NunaWhatsNewView: View {
    @State private var shown = 6

    var body: some View {
        NunaDetailScreen("What's new") {
            NunaCard(small: true) {
                VStack(alignment: .leading, spacing: 14) {
                    nunaTrendsCap("What to expect")
                    ForEach(AppChangelog.expectations) { e in
                        HStack(alignment: .top, spacing: 12) {
                            NunaIconTile(e.icon)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: e.title).font(.nuna(size: 15.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                                Text(verbatim: e.body).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(AppChangelog.releases.prefix(shown).enumerated()), id: \.element.id) { i, r in
                NunaCard(highlight: i == 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            NunaChip(verbatim: "v\(r.version)", color: i == 0 ? NunaPalette.charge : nil)
                            Spacer()
                            Text(verbatim: r.date).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textMuted).textCase(nil)
                        }
                        Text(verbatim: r.title).font(.nuna(size: 18, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        ForEach(Array(r.items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(NunaPalette.accent).frame(width: 5, height: 5).padding(.top, 8)
                                Text(Self.styled(item)).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if shown < AppChangelog.releases.count {
                Button { shown = min(shown + 8, AppChangelog.releases.count) } label: {
                    Text("Show older releases").font(.nuna(size: 15, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 50).background(NunaPalette.glassStrong, in: RoundedRectangle(cornerRadius: NunaRadius.pill, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private static func styled(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - How the app works (About.dc › How it works)

struct NunaHowItWorksView: View {
    private func tint(_ s: HowNoopWorksView.Section) -> Color {
        switch s {
        case .sleepSorting: return NunaPalette.rest
        case .scores: return NunaPalette.charge
        case .recording: return NunaPalette.effort
        case .provenance: return NunaPalette.accent
        }
    }
    private func methodTint(_ m: HowNoopWorksView.ScoreMethod) -> Color {
        switch m {
        case .charge: return NunaPalette.charge
        case .effort: return NunaPalette.effort
        case .rest: return NunaPalette.rest
        case .fitnessAge: return NunaPalette.accent
        }
    }

    var body: some View {
        NunaDetailScreen("How the app works") {
            NunaCard(highlight: true) {
                VStack(alignment: .leading, spacing: 8) {
                    nunaTrendsCap("The one rule")
                    Text("NOOP never shows you a number it had to make up. If a score isn't ready, it tells you why and what to do next. Everything here runs on your device, from your strap.")
                        .font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(HowNoopWorksView.Section.allCases) { s in
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            NunaIconTile(s.icon, tint: tint(s))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: s.overline).font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).foregroundStyle(tint(s))
                                Text(verbatim: s.title).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }
                        Text(verbatim: s.body).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NunaSettingsGroup("How your scores are computed") {
                Text("Each score follows a published method, computed on your device. We name the method family so you can read up on it, and we never claim to reproduce another company's number exactly.")
                    .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                ForEach(HowNoopWorksView.ScoreMethod.allCases) { m in
                    NunaDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: m.name).font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Text(verbatim: m.family).font(.nuna(size: 10.5, weight: .heavy)).tracking(0.4).foregroundStyle(methodTint(m))
                        }
                        Text(verbatim: m.method).font(.nuna(size: 13, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
            }
            NavigationLink { NunaScoringGuideView() } label: {
                NunaCard(small: true) { NunaListRow("How scores are worked out", subtitle: "Charge, Effort and Rest", systemImage: "chart.bar.doc.horizontal", showsChevron: true) }
            }.buttonStyle(.plain)
            nunaFootnote("NOOP never makes up a number. When it can't compute one honestly it tells you what's missing and what to do, rather than showing a fake value.")
        }
    }
}

// MARK: - How scores are worked out (About.dc › Scores)

struct NunaScoringGuideView: View {
    var initialSection: ScoreSection?

    private func color(_ s: ScoreSection) -> Color {
        switch s {
        case .charge: return NunaPalette.charge
        case .effort: return NunaPalette.effort
        case .rest: return NunaPalette.rest
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            NunaDetailScreen("How scores are worked out") {
                NunaCard(highlight: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        nunaTrendsCap("The three scores")
                        Text("NOOP gives you three daily scores (Charge, Effort and Rest), each on a 0-100 scale. They're built from your strap's raw signals using published, peer-reviewed sport science, and computed entirely on your device. They are NOT WHOOP's scores: we don't have WHOOP's private algorithms and don't pretend to. They aim at the same three questions using open science, so they'll usually track WHOOP's in direction, but won't match number-for-number. And that's the point.")
                            .font(.nuna(size: 14.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            ForEach(ScoreSection.allCases) { s in
                                HStack(spacing: 6) { Circle().fill(color(s)).frame(width: 8, height: 8); Text(verbatim: s.displayName).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil) }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(ScoreSection.allCases) { s in
                    NunaCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 16) {
                                NunaRingGauge(fraction: s.sampleFraction, color: color(s), size: 76, lineWidth: 8) {
                                    Text(verbatim: s.sampleNumber).font(.nuna(size: 22, weight: .bold, design: NunaType.design)).foregroundStyle(NunaPalette.textPrimary)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: s.displayName).font(.nuna(size: 11.5, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(color(s))
                                    Text(verbatim: s.headline).font(.nuna(size: 17, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                                }
                            }
                            Text(verbatim: s.bodyText).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            NunaDivider()
                            HStack(alignment: .top, spacing: 8) {
                                Text("vs WHOOP").font(.nuna(size: 11, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(color(s)).padding(.top, 1)
                                Text(verbatim: s.vsWhoop).font(.nuna(size: 12.5, weight: .semibold)).italic().foregroundStyle(NunaPalette.textMuted).fixedSize(horizontal: false, vertical: true).textCase(nil)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.id(s.id)
                }
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How sure is NOOP?  ·  Solid · Building · Calibrating").font(.nuna(size: 16, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        HStack(spacing: 8) {
                            NunaChip("Solid", color: NunaPalette.charge)
                            NunaChip("Building", color: NunaPalette.warning)
                            NunaChip("Calibrating")
                        }
                        Text("Every score carries a small honesty label. Calibrating means NOOP is still learning your baseline, or doesn't have enough data yet. Building means there's enough to show, but it's thin. Solid means full inputs are present. When NOOP can't compute a score honestly, it shows nothing rather than a fake number.")
                            .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                nunaFootnote("These are independent approximations from a consumer strap, built on open science: not medical advice, and not WHOOP's official scores.")
            }
            .onAppear {
                guard let s = initialSection else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation { proxy.scrollTo(s.id, anchor: .top) } }
            }
        }
    }
}
#endif

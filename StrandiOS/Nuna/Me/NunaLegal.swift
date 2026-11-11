#if os(iOS)
import SwiftUI
import MarkdownUI
import StrandDesign

// MARK: - The version, shown at the bottom of Settings

enum NunaAppVersion {
    /// "App version: 2.0.0 (build 416)".
    static var text: String {
        let version = UpdateWatch.installedVersion
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "–"
        return String(localized: "App version: \(version) (build \(build))")
    }
}

// MARK: - About

/// Settings > About: four rows, as the reference has them. What each opens is a document the project already keeps and the app ships: the licences
/// of what PHMN is built on (`Tools/build-open-source-licenses.py` and the list below), the disclaimer, the privacy and security notes, and the terms.
/// The reference's "Patents" row has no counterpart here; the disclaimer takes its place.
struct NunaAboutView: View {
    var body: some View {
        NunaDetailScreen("About", centersTitle: true) {
            VStack(spacing: 10) {
                NunaSettingsLink(route: .licenses, icon: "doc.plaintext", title: "Open source licenses")
                NunaSettingsLink(route: .legal(NunaLegalDoc.disclaimer.rawValue), icon: "doc.text", title: "Disclaimer")
                NunaSettingsLink(route: .legal(NunaLegalDoc.privacy.rawValue), icon: NunaIcons.privacy, title: "Privacy policy")
                NunaSettingsLink(route: .legal(NunaLegalDoc.terms.rawValue), icon: "doc.plaintext", title: "Terms of use")
            }
            .padding(.top, 10)
            VStack(spacing: 12) {
                Text("PHMN is an internal fork of NOOP by ryanbr, with an iOS layer, Apple Health integration and on-device Anya. The Nes 2011 (HUNT) non-exercise model is used for fitness age.")
                Text("Not a medical device. It does not diagnose or detect disease and does not replace a professional. Not affiliated with WHOOP, Inc.")
            }
            .font(.nuna(size: 12.5, weight: .semibold)).tracking(0).foregroundStyle(NunaPalette.textMuted).multilineTextAlignment(.center).textCase(nil)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.top, 14)
        }
    }
}

// MARK: - The documents

extension Theme {
    /// The reading style of the documents in About: the Coach theme with the text at 14, smaller than the 18 of the page's title (its own headings stay at 17 or less).
    static var nunaReader: Theme {
        Theme.strand.text { ForegroundColor(NunaPalette.textPrimary); FontSize(14) }
    }
}

/// The project's own documents, shipped in the app as they are in the repository (`project.yml` lists them as resources), so what is read here is what is kept there.
enum NunaLegalDoc: String {
    case privacy, terms, disclaimer

    var title: LocalizedStringKey {
        switch self { case .privacy: "Privacy policy"; case .terms: "Terms of use"; case .disclaimer: "Disclaimer" }
    }
    var fileName: String {
        switch self { case .privacy: "PRIVACY_SECURITY"; case .terms: "TERMS"; case .disclaimer: "DISCLAIMER" }
    }
    var text: String? { NunaLegalText.load(fileName, ext: "md") }
}

enum NunaLegalText {
    static func load(_ name: String, ext: String?) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// One of those documents, set in the app's reading style.
struct NunaLegalDocView: View {
    let doc: NunaLegalDoc

    var body: some View {
        NunaDetailScreen(doc.title, centersTitle: true) {
            if let text = doc.text {
                Markdown(text).markdownTheme(.nunaReader).textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("This document is not in this build.").font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
            }
        }
    }
}

// MARK: - Open source licenses

struct NunaOpenSource: Identifiable, Decodable {
    let id: String
    let name: String
    let author: String
    let license: String
    let version: String?
    let url: String
    let used: String
    let text: String

    /// The Swift packages come from the JSON the build script writes from their checkouts; the rest is listed here.
    static let all: [NunaOpenSource] = {
        var list: [NunaOpenSource] = []
        if let url = Bundle.main.url(forResource: "open-source-licenses", withExtension: "json"),
           let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([NunaOpenSource].self, from: data) {
            list += decoded
        }
        list += [
            NunaOpenSource(id: "noop", name: "NOOP", author: "ryanbr and contributors", license: "PolyForm Noncommercial 1.0.0", version: nil,
                           url: "https://github.com/ryanbr/noop", used: "PHMN is a fork of NOOP and keeps its licence. The protocol facts come from community reverse-engineering research, see the notes in the project.",
                           text: NunaLegalText.load("LICENSE", ext: nil) ?? "PolyForm Noncommercial License 1.0.0. The text is at https://polyformproject.org/licenses/noncommercial/1.0.0/"),
            NunaOpenSource(id: "fed", name: "free-exercise-db", author: "yuhonas", license: "The Unlicense (public domain)", version: nil,
                           url: "https://github.com/yuhonas/free-exercise-db", used: "The exercise library: names, muscles, instructions and the two photos of each exercise.",
                           text: "This is free and unencumbered software released into the public domain. Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means. For more information, see https://unlicense.org"),
            NunaOpenSource(id: "opengym", name: "openGym", author: "Duarte Santos", license: "GNU AGPL-3.0", version: nil,
                           url: "https://github.com/DuarteSantos8/openGym",
                           used: "The idea of a body map showing which muscles are trained and which are still tired. No openGym code, data, photos or animations are in PHMN: the muscle readings and the library here are written from scratch or come from the projects above.",
                           text: "openGym is licensed under the GNU Affero General Public License v3.0. Its text is at https://www.gnu.org/licenses/agpl-3.0.html. Because none of its code is included, PHMN is not a derivative work of openGym and keeps NOOP's PolyForm Noncommercial licence."),
            NunaOpenSource(id: "fonts", name: "D-DIN-PRO, Montserrat, Fraunces and Plus Jakarta Sans",
                           author: "Datto; The Montserrat Project Authors; The Fraunces Project Authors; The Plus Jakarta Sans Project Authors",
                           license: "SIL Open Font License 1.1", version: nil, url: "https://openfontlicense.org",
                           used: "The typefaces of the WHP and Flow styles. The full licence texts ship with the app's font files.",
                           text: "These fonts are licensed under the SIL Open Font License, Version 1.1. The licence is at https://openfontlicense.org."),
        ]
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func find(_ id: String) -> NunaOpenSource? { all.first { $0.id == id } }
}

struct NunaLicensesView: View {
    var body: some View {
        NunaDetailScreen("Open source licenses", centersTitle: true) {
            Text("PHMN is a fork of NOOP (PolyForm Noncommercial 1.0.0). It also uses the projects below, under their own licences.")
                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            NunaSettingsGroup {
                ForEach(Array(NunaOpenSource.all.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { NunaDivider() }
                    NavigationLink(value: NunaMeRoute.license(n.id)) {
                        // The name as its makers write it (MarkdownUI, GRDB.swift), not in capitals.
                        HStack(spacing: 12) {
                            Text(verbatim: n.name).font(.nuna(size: 15, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.nuna(size: 13, weight: .bold)).foregroundStyle(NunaPalette.textMuted)
                        }
                        .padding(.vertical, 17).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// One licence: who made it, what PHMN uses it for, and the text as the project ships it.
struct NunaLicenseDetailView: View {
    let id: String

    var body: some View {
        if let n = NunaOpenSource.find(id) {
            NunaDetailScreen(LocalizedStringKey(n.name), centersTitle: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: n.license).font(.nuna(size: 14, weight: .heavy)).tracking(nunaTrackingLabel).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                    Text(verbatim: [n.author, n.version].compactMap { $0 }.joined(separator: " · ")).font(.nuna(size: 13.5, weight: .semibold))
                        .foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    Text(verbatim: n.used).font(.nuna(size: 14, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).textCase(nil)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    if let u = URL(string: n.url) {
                        Link(destination: u) { Text("Open the project").font(.nuna(size: 14, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).underline() }.padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: n.text).font(.nuna(size: 13, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
        } else {
            NunaDetailScreen("Open source licenses", centersTitle: true) { EmptyView() }
        }
    }
}
#endif

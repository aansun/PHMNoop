#if os(iOS)
import SwiftUI
import StrandDesign

/// About › Open-source notices: what the app uses from other projects, under which licence, and the notices those licences ask for.
/// The same texts are in THIRD_PARTY_NOTICES.md at the root of the repository.
struct NunaLicensesView: View {
    private struct Notice: Identifiable {
        let id: String
        let name: String
        let author: String
        let licence: String
        let url: String
        let used: LocalizedStringKey
        let text: String
    }

    private static let mit = { (year: String, holder: String) in
        """
        MIT License

        Copyright (c) \(year) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }

    private static let notices: [Notice] = [
        Notice(id: "musclemap", name: "MuscleMap", author: "Melih Colpan", licence: "MIT", url: "https://github.com/melihcolpan/MuscleMap",
               used: "The body map in the Gym screens, with its heat colouring.", text: mit("2026", "Melih Colpan")),
        Notice(id: "fed", name: "free-exercise-db", author: "yuhonas", licence: "The Unlicense (public domain)", url: "https://github.com/yuhonas/free-exercise-db",
               used: "The exercise library: names, muscles, instructions and the two photos of each exercise.",
               text: "This is free and unencumbered software released into the public domain. Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means. For more information, see https://unlicense.org"),
        Notice(id: "opengym", name: "openGym", author: "Duarte Santos", licence: "GNU AGPL-3.0", url: "https://github.com/DuarteSantos8/openGym",
               used: "The idea of a body map showing which muscles are trained and which are still tired. No openGym code, data, photos or animations are in PHMN: the muscle readings and the library here are written from scratch or come from the projects above.",
               text: "openGym is licensed under the GNU Affero General Public License v3.0. Its text is at https://www.gnu.org/licenses/agpl-3.0.html. Because none of its code is included, PHMN is not a derivative work of openGym and keeps NOOP's PolyForm Noncommercial licence."),
        Notice(id: "markdown", name: "MarkdownUI", author: "Guillermo Gonzalez", licence: "MIT", url: "https://github.com/gonzalezreal/swift-markdown-ui",
               used: "Formatting of Anya's replies.", text: mit("2020", "Guillermo Gonzalez")),
        Notice(id: "fonts", name: "D-DIN-PRO and Montserrat", author: "Datto; The Montserrat Project Authors", licence: "SIL Open Font License 1.1", url: "https://openfontlicense.org",
               used: "The typefaces of the WHP style. The full licence texts ship with the app's font files.", text: "These fonts are licensed under the SIL Open Font License, Version 1.1. The licence is at https://openfontlicense.org."),
    ]

    @State private var open: String?

    var body: some View {
        NunaDetailScreen("Open-source notices") {
            Text("PHMN is a fork of NOOP (PolyForm Noncommercial 1.0.0). It also uses the projects below, under their own licences.")
                .font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
            ForEach(Self.notices) { n in
                NunaCard(small: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: n.name).font(.nuna(size: 16.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary)
                            Spacer()
                            NunaChip(verbatim: n.licence)
                        }
                        Text(verbatim: n.author).font(.nuna(size: 12.5, weight: .semibold)).foregroundStyle(NunaPalette.textSecondary).textCase(nil)
                        Text(n.used).font(.nuna(size: 13.5, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        HStack(spacing: 12) {
                            if let u = URL(string: n.url) {
                                Link(destination: u) { Text("Open the project").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).underline() }
                            }
                            Button { withAnimation(.easeInOut(duration: 0.2)) { open = open == n.id ? nil : n.id } } label: {
                                Text(open == n.id ? "Hide the licence" : "Show the licence").font(.nuna(size: 13.5, weight: .bold)).foregroundStyle(NunaPalette.textPrimary).underline()
                            }.buttonStyle(.plain)
                        }
                        if open == n.id {
                            Text(verbatim: n.text).font(.nuna(size: 11.5, weight: .regular)).foregroundStyle(NunaPalette.textSecondary).fixedSize(horizontal: false, vertical: true).textCase(nil)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
#endif

#if os(iOS)
import SwiftUI
import StrandDesign

/// What the GLP-1 setup learned: where the wearer is with the medication, which one, how it is taken, the dose and the schedule. Kept on this phone.
struct NunaGLP1Setup: Codable, Equatable {
    /// 0 taking one, 1 prescribed and not started, 2 getting one.
    var status: Int
    var medication: String?
    var form: String?
    var doseMg: Double?
    /// Days a week the medication is taken.
    var days: Int

    static let key = "nuna.glp1.setup.v1"
    static func load() -> NunaGLP1Setup? {
        UserDefaults.standard.string(forKey: key).flatMap { try? JSONDecoder().decode(NunaGLP1Setup.self, from: Data($0.utf8)) }
    }
    func save() {
        if let data = try? JSONEncoder().encode(self), let s = String(data: data, encoding: .utf8) { UserDefaults.standard.set(s, forKey: Self.key) }
    }
}

extension NunaPlanDraft {
    /// The GLP-1 plan with the medication check at the schedule the setup gave.
    convenience init(glp1 setup: NunaGLP1Setup) {
        self.init(starting: .glp1Companion)
        behaviors.insert(NunaPlanBehavior.glp1Medication(days: setup.days), at: 0)
    }
}

/// The questions in front of the GLP-1 plan: an introduction, then one question to a page with a ring that fills as the answers come in.
struct NunaGLP1Flow: View {
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable { case intro, status, medication, form, dose, schedule, ready }
    @State private var step = Step.intro
    @State private var status: Int?
    @State private var medication: Int?
    @State private var form: Int?
    @State private var dose: Int?
    @State private var schedule: Int?
    @State private var otherDose: Double = 5
    @State private var otherDays = 2
    @State private var showSkip = false
    @State private var showDoseSheet = false
    @State private var showDaysSheet = false
    @State private var draft: NunaPlanDraft?
    @State private var showDetails = false

    private static let statuses = ["Yes, I'm currently taking one", "I've been prescribed one, but haven't started", "I'm in the process of getting one", "No, not currently"]
    private static let medications: [(String, String?)] = [("Wegovy®", "Semaglutide"), ("Ozempic®", "Semaglutide"), ("Mounjaro®", "Tirzepatide"), ("Zepbound®", "Tirzepatide"), ("Other", nil)]
    private static let forms = ["Injection", "Pill"]
    private static let doses: [Double] = [2.5, 5, 7.5, 10]
    private static let schedules = ["Once a week", "Once a day", "Another schedule"]

    var body: some View {
        ZStack {
            NunaBackdrop().ignoresSafeArea()
            Group {
                switch step {
                case .intro: intro
                case .status: question("Are you currently taking a GLP-1 medication?", sub: "This includes medications like Ozempic, Wegovy, Mounjaro, Zepbound, and others.",
                                       options: Self.statuses.map { ($0, nil) }, selection: $status, progress: 1.0 / 7)
                case .medication: question("Which medication are you taking?", sub: nil, options: Self.medications.map { ($0.0, $0.1) }, selection: $medication, progress: 2.0 / 7)
                case .form: question("How do you take your medication?", sub: nil, options: Self.forms.map { ($0, nil) }, selection: $form, progress: 3.0 / 7)
                case .dose: question("What's your current dose?", sub: "We'll use this to keep your Journal up to date.",
                                     options: Self.doses.map { (Self.doseText($0), nil) } + [("Other dose", nil)], selection: $dose, progress: 4.0 / 7)
                case .schedule: question("How often do you take your medication?", sub: nil, options: Self.schedules.map { ($0, nil) }, selection: $schedule, progress: 5.0 / 7)
                case .ready: ready
                }
            }
            .transition(.opacity)
            if showSkip { skipDialog }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .animation(.easeInOut(duration: 0.2), value: showSkip)
        .navigationDestination(isPresented: $showDetails) {
            if let draft { NunaPlanDetailsView(draft: draft, startsTemplate: true, onClose: onClose).toolbar(.hidden, for: .navigationBar) }
        }
        .sheet(isPresented: $showDoseSheet) {
            NunaNumberSheet(title: "Other dose", unit: "mg", initial: otherDose, range: 0.25...30, step: 0.25, decimals: 2) { otherDose = $0 }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showDaysSheet) {
            NunaNumberSheet(title: "Days a week", unit: String(localized: "days"), initial: Double(otherDays), range: 1...7, step: 1, decimals: 0) { otherDays = Int($0) }.presentationDetents([.medium])
        }
    }

    private static func doseText(_ v: Double) -> String { (v == v.rounded() ? String(Int(v)) : String(v)) + " mg" }

    // MARK: Pieces

    private var backButton: some View {
        Button { goBack() } label: {
            Image(systemName: step == .intro ? "xmark" : "chevron.left").font(.system(size: step == .intro ? 20 : 22, weight: .semibold)).foregroundStyle(NunaPalette.textPrimary)
                .frame(width: 48, height: 44, alignment: .leading)
        }
        .buttonStyle(.plain).accessibilityLabel(Text(step == .intro ? "Close" : "Back"))
    }

    private func goBack() {
        if step == .intro { dismiss(); return }
        step = Step(rawValue: step.rawValue - 1) ?? .intro
    }

    private var intro: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: "#6B5A47"), Color(hex: "#2C2A2B"), NunaPalette.canvas], startPoint: .top, endPoint: .init(x: 0.5, y: 0.62)).ignoresSafeArea()
            NunaIcon(name: "syringe", size: 120).symbolVariant(.none).foregroundStyle(Color.white.opacity(0.14)).frame(maxWidth: .infinity).padding(.top, 170)
            VStack(alignment: .leading, spacing: 0) {
                backButton.padding(.horizontal, 28).padding(.top, 8)
                Spacer(minLength: 0)
                Text("Understand your body on GLP-1").font(.nunaWords(size: 27)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH)
                Text("Track your medication alongside your PHMN data to see a more complete picture of your weight, sleep, recovery, activity, and health over time.")
                    .font(.nunaWords(size: 15.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH).padding(.top, 12)
                HStack {
                    Spacer()
                    Button { step = .status } label: {
                        HStack(spacing: 22) {
                            Text("Get started").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                            Image(systemName: "arrow.right").font(.system(size: 26, weight: .regular)).foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(LinearGradient(colors: [Color(hex: "#F7A27C"), Color(hex: "#9B4DEB")], startPoint: .leading, endPoint: .trailing), in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, NunaSpacing.screenH).padding(.trailing, 30).padding(.top, 26).padding(.bottom, 18)
            }
        }
    }

    /// The last page: what the answers are for, and the button that opens the plan.
    private var ready: some View {
        ZStack(alignment: .bottomTrailing) {
            RadialGradient(colors: [Color(hex: "#0E4A38"), NunaPalette.canvas.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 330).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                backButton.padding(.horizontal, 28).padding(.top, 8)
                Spacer(minLength: 0)
                Text("You're ready to start tracking").font(.nunaWords(size: 27)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH)
                Text("PHMN will use your GLP-1 information to personalize your tracking and help you see it alongside your weight, sleep, Recovery, activity, and other health trends.")
                    .font(.nunaWords(size: 15.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH).padding(.top, 12)
                HStack {
                    Spacer()
                    Button { next() } label: {
                        HStack(spacing: 22) {
                            Text("Finish").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                            Image(systemName: "checkmark").font(.system(size: 28, weight: .regular)).foregroundStyle(Color(red: 0.03, green: 0.04, blue: 0.07))
                                .frame(width: 72, height: 72).background(NunaPalette.charge, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, NunaSpacing.screenH).padding(.trailing, 30).padding(.top, 26).padding(.bottom, 18)
            }
        }
    }

    /// One question: the clipboard, the question, its answers (a ring button moves on once one is chosen).
    private func question(_ title: String, sub: String?, options: [(String, String?)], selection: Binding<Int?>, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton.padding(.horizontal, 28).padding(.top, 8)
            Spacer(minLength: 0)
            NunaGLP1Clipboard().frame(width: 76, height: 92).padding(.leading, 28).padding(.bottom, 26)
            Text(verbatim: NSLocalizedString(title, comment: "")).font(.nunaWords(size: 24)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH)
            if let sub {
                Text(verbatim: NSLocalizedString(sub, comment: "")).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, NunaSpacing.screenH).padding(.top, 8)
            }
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    let on = selection.wrappedValue == i
                    Button { choose(i, in: selection) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: NSLocalizedString(option.0, comment: "")).font(.nunaWords(size: 16.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary)
                            if let note = option.1 { Text(verbatim: note).font(.nunaWords(size: 14)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textSecondary) }
                        }
                        .padding(.horizontal, 17).frame(maxWidth: .infinity, minHeight: option.1 == nil ? 56 : 60, alignment: .leading)
                        .background(on ? Color(hex: "#1E2B3A") : NunaPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? NunaPalette.recoveryBlue : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NunaSpacing.screenH).padding(.top, 26)
            HStack {
                Spacer()
                nextButton(enabled: selection.wrappedValue != nil, progress: progress)
            }
            .padding(.leading, NunaSpacing.screenH).padding(.trailing, 30).padding(.top, 22).padding(.bottom, 18)
        }
    }

    private func nextButton(enabled: Bool, progress: Double) -> some View {
        Button { next() } label: {
            HStack(spacing: 22) {
                Text("Next").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted)
                ZStack {
                    Circle().stroke(NunaPalette.ringTrack, lineWidth: 5)
                    Circle().trim(from: 0, to: progress).stroke(NunaPalette.recoveryBlue, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.right").font(.system(size: 26, weight: .regular)).foregroundStyle(enabled ? NunaPalette.textPrimary : NunaPalette.textMuted)
                }
                .frame(width: 74, height: 74)
            }
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private var skipDialog: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea().onTapGesture { showSkip = false }
            VStack(spacing: 18) {
                Text("Skip GLP-1 setup?").font(.nuna(size: 15, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                Text("You can always come back and set this up later from the Discover More section on Home.")
                    .font(.nunaWords(size: 14.5)).tracking(0).textCase(nil).foregroundStyle(NunaPalette.textPrimary).multilineTextAlignment(.center).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showSkip = false; onClose() } label: {
                    Text("Skip setup").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 44).background(NunaPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { showSkip = false } label: {
                    Text("Go back").font(.nuna(size: 13.5, weight: .heavy)).tracking(nunaTrackingHead(1.4)).textCase(.uppercase).foregroundStyle(NunaPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NunaPalette.textMuted, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(22).frame(maxWidth: 322)
            .background(LinearGradient(colors: [Color(hex: "#2B3E48"), Color(hex: "#1D2A33")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Moving on

    private func choose(_ i: Int, in selection: Binding<Int?>) {
        selection.wrappedValue = i
        switch step {
        case .status where i == 3: showSkip = true
        case .dose where i == Self.doses.count: showDoseSheet = true
        case .schedule where i == Self.schedules.count - 1: showDaysSheet = true
        default: break
        }
    }

    private func next() {
        switch step {
        case .intro: step = .status
        case .status: step = .medication
        case .medication: step = .form
        case .form: step = .dose
        case .dose: step = .schedule
        case .schedule: step = .ready
        case .ready: finish()
        }
    }

    /// The answers are kept and the plan opens, with the medication check at the days the schedule gave.
    private func finish() {
        let days: Int
        switch schedule {
        case 0: days = 1
        case 1: days = 7
        default: days = otherDays
        }
        let setup = NunaGLP1Setup(status: status ?? 0, medication: medication.map { Self.medications[$0].0 }, form: form.map { Self.forms[$0] },
                                  doseMg: dose.map { $0 < Self.doses.count ? Self.doses[$0] : otherDose }, days: days)
        setup.save()
        draft = NunaPlanDraft(glp1: setup)
        showDetails = true
    }
}

/// A clipboard with a card on it, drawn in the greys and blues of the page.
private struct NunaGLP1Clipboard: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#4B5058"), Color(hex: "#30343A")], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(hex: "#3A3F46")).padding(7)
            Circle().fill(Color(hex: "#555B63")).frame(width: 17, height: 17).offset(x: -16, y: -26)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 5) {
                        Capsule().fill(i < 3 ? Color(hex: "#2F8CE0") : Color(hex: "#2F8CE0")).frame(width: 10, height: 4)
                        Capsule().fill(Color(hex: "#555B63")).frame(width: 26, height: 3)
                    }
                }
            }
            .offset(x: -3, y: 12)
            Capsule().fill(Color(hex: "#262A30")).frame(width: 26, height: 7).offset(y: -44)
        }
        .rotationEffect(.degrees(-7))
        .accessibilityHidden(true)
    }
}
#endif

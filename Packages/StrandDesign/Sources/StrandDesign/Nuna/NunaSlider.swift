#if os(iOS) && canImport(UIKit)
import SwiftUI
import UIKit

/// A native stepped slider with a wider track and a standard accessible touch target.
public struct NunaSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let accessibilityValue: String
    @Environment(\.isEnabled) private var isEnabled

    public init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double, accessibilityValue: String) {
        self._value = value
        self.range = range
        self.step = step
        self.accessibilityValue = accessibilityValue
    }

    public var body: some View {
        NunaSliderControl(value: $value, range: range, step: step, accessibilityValue: accessibilityValue, isEnabled: isEnabled)
            .frame(height: NoopButtonMetrics.minHitTarget)
    }
}

private struct NunaSliderControl: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityValue: String
    let isEnabled: Bool

    func makeUIView(context: Context) -> NunaSliderTrack {
        let slider = NunaSliderTrack()
        slider.isContinuous = true
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        return slider
    }

    func updateUIView(_ slider: NunaSliderTrack, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.stepSize = Float(step)
        slider.value = Float(min(max(value, range.lowerBound), range.upperBound))
        slider.minimumTrackTintColor = UIColor(NunaPalette.effortModerate)
        slider.maximumTrackTintColor = UIColor(NunaPalette.glassStrong)
        slider.accessibilityValue = accessibilityValue
        slider.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: NunaSliderControl

        init(parent: NunaSliderControl) { self.parent = parent }

        @objc func valueChanged(_ slider: NunaSliderTrack) {
            let lower = parent.range.lowerBound
            let steps = ((Double(slider.value) - lower) / parent.step).rounded()
            let snapped = min(max(lower + steps * parent.step, lower), parent.range.upperBound)
            slider.value = Float(snapped)
            if parent.value != snapped { parent.value = snapped }
        }
    }
}

private final class NunaSliderTrack: UISlider {
    var stepSize: Float = 1

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var track = super.trackRect(forBounds: bounds)
        track.size.height = NoopMetrics.space3
        track.origin.y = bounds.midY - track.height / 2
        return track
    }

    override func accessibilityIncrement() {
        value = min(maximumValue, value + stepSize)
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        value = max(minimumValue, value - stepSize)
        sendActions(for: .valueChanged)
    }
}

#if DEBUG
#Preview("Wide target slider") {
    NunaSlider(value: .constant(30), in: 5...300, step: 5, accessibilityValue: "30 min")
        .padding(NunaSpacing.screenH)
        .background(NunaPalette.card)
        .preferredColorScheme(.dark)
}
#endif
#endif

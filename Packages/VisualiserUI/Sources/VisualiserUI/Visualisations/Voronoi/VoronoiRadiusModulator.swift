import Foundation

/// Maps the runner's effort onto the radii of the voronoi density field.
///
/// In `.fixed` mode the configured radii are returned unchanged. In `.dynamic`
/// mode they are the baseline at average effort and move with two signals
/// derived from the heart rate (`h`) and speed (`p`) deviations:
///
/// - **Effort** `(h + p) / 2` — both up is a hard effort, both down an easy one.
/// - **Strain** `(h − p) / 2` — heart rate up with pace down is a blown up
///   runner, heart rate down with pace up a flowing one (e.g. downhill).
///
/// | State    | Min radius          | Max radius            |
/// |----------|---------------------|-----------------------|
/// | Easy     | falls to the floor  | baseline              |
/// | Hard     | rises to midpoint   | shrinks to midpoint   |
/// | Blown up | baseline            | expands               |
/// | Flowing  | opens a bit         | baseline              |
///
/// A small min radius reveals little detail (mellow), while radii that meet
/// produce a sharp edge between low and high density (focused).
///
struct VoronoiRadiusModulator {

    /// The radii of the density field, in normalised coordinate space.
    struct Radii: Equatable {

        /// Radius of the density increase at the coarsest level.
        let max: Double

        /// Radius of the density increase at the deepest subdivision level.
        let min: Double
    }

    /// Scales effort and strain before they are clamped to (-1, 1).
    let gain: Double

    /// Lowest min radius, reached on the easiest effort.
    let minRadiusFloor: Double

    /// Highest max radius the expansion can reach.
    let maxRadiusCeiling: Double

    /// Factor the max radius grows by when the runner is fully blown up.
    let maxRadiusExpansion: Double

    /// Fraction of the way the min radius opens towards
    /// the max radius when the runner is fully flowing.
    let flowOpening: Double

    init(
        gain: Double = 1.0,
        minRadiusFloor: Double = 0.05,
        maxRadiusCeiling: Double = 1.5,
        maxRadiusExpansion: Double = 1.5,
        flowOpening: Double = 0.25
    ) {
        self.gain = gain
        self.minRadiusFloor = minRadiusFloor
        self.maxRadiusCeiling = maxRadiusCeiling
        self.maxRadiusExpansion = maxRadiusExpansion
        self.flowOpening = flowOpening
    }

    /// Returns the radii for the given configuration at the current state of the run.
    func radii(for configuration: Voronoi, state: VisualiserState) -> Radii {
        let baseline = Radii(max: configuration.maxRadius, min: configuration.minRadius)
        switch configuration.mode {
        case .fixed:
            return baseline
        case .dynamic:
            return modulated(baseline, effort: effort(of: state), strain: strain(of: state))
        }
    }

    // MARK: - Private

    /// Combined heart rate and speed deviation (-1, 1): easy to hard.
    private func effort(of state: VisualiserState) -> Double {
        let sum = Double(state.heartRateDeviation + state.speedDeviation)
        return clamped(sum / 2 * gain)
    }

    /// Disagreement of heart rate and speed deviation (-1, 1): flowing to blown up.
    private func strain(of state: VisualiserState) -> Double {
        let difference = Double(state.heartRateDeviation - state.speedDeviation)
        return clamped(difference / 2 * gain)
    }

    private func modulated(_ baseline: Radii, effort: Double, strain: Double) -> Radii {
        let outer = maxRadius(from: baseline, effort: effort, strain: strain)
        let inner = minRadius(from: baseline, effort: effort, strain: strain)
        return Radii(max: outer, min: min(inner, outer))
    }

    private func minRadius(from baseline: Radii, effort: Double, strain: Double) -> Double {
        let floor = min(minRadiusFloor, baseline.min)
        let rise = max(effort, 0) * (midpoint(of: baseline) - baseline.min)
        let fall = max(-effort, 0) * (baseline.min - floor)
        let opening = max(-strain, 0) * flowOpening * (baseline.max - baseline.min)
        return baseline.min + rise - fall + opening
    }

    private func maxRadius(from baseline: Radii, effort: Double, strain: Double) -> Double {
        let expanded = max(baseline.max, min(baseline.max * maxRadiusExpansion, maxRadiusCeiling))
        let shrink = max(effort, 0) * (baseline.max - midpoint(of: baseline))
        let expansion = max(strain, 0) * (expanded - baseline.max)
        return baseline.max - shrink + expansion
    }

    private func midpoint(of radii: Radii) -> Double {
        (radii.max + radii.min) / 2
    }

    private func clamped(_ value: Double) -> Double {
        max(-1, min(1, value))
    }
}

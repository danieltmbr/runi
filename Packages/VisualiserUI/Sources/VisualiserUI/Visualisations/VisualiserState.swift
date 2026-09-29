import Foundation

/// All run-derived values the animation shader needs each frame.
///
/// Construct from `RunPlayer` state in the app layer and pass to `WarpView`.
/// Keeps the Visualiser package independent of RunKit.
///
public struct VisualiserState: Sendable {

    /// Normalised average heart rate of the whole run (0, 1).
    ///
    public var averageHeartRate: Float

    /// Normalised average running speed of the whole run (0, 1).
    ///
    public var averageSpeed: Float

    /// Normalised coordinates (-1, 1)
    ///
    public var coordinates: SIMD2<Float>

    /// Normalised heading unit vector (-1, 1).
    ///
    public var direction: SIMD2<Float>

    /// Normalised elevation (0, 1).
    ///
    public var elevation: Float

    /// Normalised heart rate (0, 1).
    ///
    public var heartRate: Float

    /// A list of normalised coordinates,
    /// representing the full path of the run.  (-1, 1).
    ///
    public var path: [SIMD2<Float>]

    /// Normalised running speed (0, 1).
    ///
    public var speed: Float

    /// Pace-weighted animation clock (seconds).
    ///
    public var time: Float

    /// Deviation of the current heart rate from the run's average (-1, 1).
    ///
    /// -1 is the lowest heart rate of the run, 0 the average and 1 the highest.
    ///
    public var heartRateDeviation: Float {
        deviation(of: heartRate, from: averageHeartRate)
    }

    /// Deviation of the current speed from the run's average (-1, 1).
    ///
    /// -1 is the slowest speed of the run, 0 the average and 1 the fastest.
    ///
    public var speedDeviation: Float {
        deviation(of: speed, from: averageSpeed)
    }

    public static let zero = VisualiserState(
        averageHeartRate: 0,
        averageSpeed: 0,
        coordinates: SIMD2<Float>(0, 0),
        direction: .zero,
        elevation: 0,
        heartRate: 0,
        path: [],
        speed: 0,
        time: 0
    )

    public init(
        averageHeartRate: Float,
        averageSpeed: Float,
        coordinates: SIMD2<Float>,
        direction: SIMD2<Float>,
        elevation: Float,
        heartRate: Float,
        path: [SIMD2<Float>],
        speed: Float,
        time: Float
    ) {
        self.averageHeartRate = averageHeartRate
        self.averageSpeed = averageSpeed
        self.coordinates = coordinates
        self.direction = direction
        self.elevation = elevation
        self.heartRate = heartRate
        self.path = path
        self.speed = speed
        self.time = time
    }

    // MARK: - Private

    /// Maps a normalised value to its range-relative deviation from the average.
    ///
    /// Each side of the average is scaled by its own span, so both extremes of
    /// the run reach the ends of (-1, 1) even when the average is off-centre.
    ///
    private func deviation(of value: Float, from average: Float) -> Float {
        let span = value >= average ? 1 - average : average
        guard span > 0 else { return 0 }
        return max(-1, min(1, (value - average) / span))
    }
}

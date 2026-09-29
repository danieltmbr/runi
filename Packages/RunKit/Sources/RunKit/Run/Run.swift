import Foundation
import CoreGraphics

public struct Run: Equatable, Identifiable, Sendable {

    /// Segment of a run
    ///
    public struct Segment: Equatable, Sendable {

        /// Steps per minute. Zero indicates missing sensor data.
        ///
        public let cadence: Double

        /// Geographic position of the segment's endpoint.
        ///
        /// X: longitude (degrees)
        /// Y: latitude (degrees)
        ///
        public let coordinate: CGPoint

        /// Direction of the run
        ///
        /// X: east+, west-
        /// Y: north+, south-
        ///
        public let direction: CGPoint
        
        /// Distance covered in this segment, in meters.
        ///
        public var distance: Double { speed * duration }
        
        
        /// Duration of the segment
        ///
        public var duration: TimeInterval {
            time.duration
        }

        /// Elevation in meter
        public let elevation: Double

        /// Change in elevation: m/s
        ///
        public let elevationRate: Double

        /// BPM
        ///
        public let heartRate: Double

        /// Speed in m/s
        ///
        public let speed: Double

        /// Time stamps from which the metrics of
        /// the segment were sampled
        ///
        public let time: DateInterval

        /// A segment with all zero values and current time.
        ///
        public static let zero = Segment(
            cadence: 0,
            coordinate: .zero,
            direction: .zero,
            elevation: 0,
            elevationRate: 0,
            heartRate: 0,
            speed: 0,
            time: .init()
        )
    }

    /// [min, max] ranges of the metrics of the run
    ///
    /// Helps normalising the data and accessing the end of the spectrums quickly.
    ///
    public struct Spectrum: Equatable, Sendable {

        /// Minimum to maximum non-zero cadence (spm). Zero values are excluded
        /// as they indicate missing sensor data.
        ///
        public let cadence: ClosedRange<Double>

        /// Bounding box of all segment coordinates in raw lat/lon degrees.
        ///
        public let coordinateBounds: CGRect

        /// Total distance of the run: 0...totalMeters
        ///
        public let distance: ClosedRange<Double>

        public let elevation: ClosedRange<Double>

        /// Rate of elevation change in m/s. Negative = descending, positive = ascending.
        ///
        public let elevationRate: ClosedRange<Double>

        public let heartRate: ClosedRange<Double>

        /// Minimum non zero speed to maximum speed
        ///
        public let speed: ClosedRange<Double>

        public let time: ClosedRange<TimeInterval>

        /// A spectrum where each range's magnitude is zero
        ///
        public static let zero = Spectrum(
            cadence: 0...0,
            coordinateBounds: .zero,
            distance: 0...0,
            elevation: 0...0,
            elevationRate: 0...0,
            heartRate: 0...0,
            speed: 0...0,
            time: 0...0
        )
    }

    /// Time-weighted averages of the metrics of the run
    ///
    /// Expressed in the same units as the segments they were derived from,
    /// so a normalised run carries normalised averages. Helps measuring how
    /// far the current segment deviates from the run's typical effort.
    ///
    public struct Averages: Equatable, Sendable {

        /// Average heart rate. Zero readings are excluded
        /// as they indicate missing sensor data.
        ///
        public let heartRate: Double

        /// Average speed.
        ///
        public let speed: Double

        /// Averages where each value is zero
        ///
        public static let zero = Averages(heartRate: 0, speed: 0)
    }

    /// Unique identifier linking this runtime value back to its `RunRecord`.
    ///
    public let id: RunID

    /// Averages of the metrics during the run
    ///
    public let averages: Averages

    /// Flat array of segment coordinates, pre-extracted for efficient rendering.
    ///
    /// Equivalent to `segments.map(\.coordinate)` but computed once at init time
    /// so 30fps views can read it without remapping on every frame.
    ///
    public let coordinates: [CGPoint]

    /// Start date of the run.
    ///
    public let date: Date

    /// Display name of the run (e.g. from GPX `<name>` or Strava activity name).
    ///
    public let name: String

    /// Total run distance in meters.
    ///
    public var distance: Double {
        spectrum.distance.upperBound
    }

    /// Total run duration in seconds.
    ///
    public var duration: TimeInterval {
        spectrum.time.upperBound - spectrum.time.lowerBound
    }

    /// Segments of the run
    ///
    public let segments: [Segment]

    /// Spectrum of the metrics during the run
    ///
    public let spectrum: Spectrum

    /// Designated initialiser — allows interpolators to preserve the original
    /// geographic path independently of the densified segments.
    ///
    /// `averages` are always derived from `segments`, so they stay consistent
    /// with whatever transformation produced them.
    ///
    /// Prefer `init(id:date:name:segments:spectrum:)` for transformers and the parser.
    /// See `RunInterpolator` for the full rationale.
    ///
    init(
        id: RunID = RunID(),
        coordinates: [CGPoint],
        date: Date = .now,
        name: String = "",
        segments: [Segment],
        spectrum: Spectrum
    ) {
        self.id = id
        self.averages = Averages(from: segments)
        self.coordinates = coordinates
        self.date = date
        self.name = name
        self.segments = segments
        self.spectrum = spectrum
    }

    /// Convenience initialiser — derives `coordinates` from `segments`.
    ///
    /// Use for transformers and the parser, where the output segments
    /// define the geographic path.
    ///
    /// > Warning: Do **not** use in interpolators.
    ///
    init(
        id: RunID = RunID(),
        date: Date = .now,
        name: String = "",
        segments: [Segment],
        spectrum: Spectrum
    ) {
        self.init(
            id: id,
            coordinates: segments.map(\.coordinate),
            date: date,
            name: name,
            segments: segments,
            spectrum: spectrum
        )
    }

    /// Fixed identifier for the sedentary (no-run) state.
    ///
    public static let sedentaryID = RunID(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

    /// A run with no segments representing the idle state before any run is selected.
    ///
    public static let sedentary = Run(id: sedentaryID, segments: [], spectrum: .zero)
}

extension Run.Spectrum {

    /// Builds a spectrum by computing the min/max of each metric across all segments.
    ///
    /// Zero values for heart rate and cadence are excluded as they indicate
    /// missing sensor data, not actual readings.
    ///
    init(from segments: [Run.Segment], time: ClosedRange<TimeInterval>) {
        let speeds = segments.map(\.speed)
        let elevations = segments.map(\.elevation)
        let elevationRates = segments.map(\.elevationRate)
        let nonZeroHR = segments.map(\.heartRate).filter { $0 > 0 }
        let nonZeroCadence = segments.map(\.cadence).filter { $0 > 0 }
        let totalDistance = segments.reduce(0.0) { $0 + $1.distance }
        let xs = segments.map(\.coordinate.x)
        let ys = segments.map(\.coordinate.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        self.init(
            cadence: (nonZeroCadence.min() ?? 0)...(nonZeroCadence.max() ?? 0),
            coordinateBounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            distance: 0...totalDistance,
            elevation: (elevations.min() ?? 0)...(elevations.max() ?? 0),
            elevationRate: (elevationRates.min() ?? 0)...(elevationRates.max() ?? 0),
            heartRate: (nonZeroHR.min() ?? 0)...(nonZeroHR.max() ?? 0),
            speed: (speeds.min() ?? 0)...(speeds.max() ?? 0),
            time: time
        )
    }
}

extension Run.Averages {

    /// Builds the averages by weighting each segment's metrics with its duration.
    ///
    /// Zero (or negative) values for heart rate are excluded as they indicate
    /// missing sensor data, not actual readings.
    ///
    init(from segments: [Run.Segment]) {
        self.init(
            heartRate: Self.mean(of: \.heartRate, in: segments.filter { $0.heartRate > 0 }),
            speed: Self.mean(of: \.speed, in: segments)
        )
    }

    /// Returns the duration-weighted mean of the metric.
    ///
    /// Falls back to the plain mean when the segments have no duration,
    /// and to zero when there are no segments.
    ///
    private static func mean(
        of metric: KeyPath<Run.Segment, Double>,
        in segments: [Run.Segment]
    ) -> Double {
        guard !segments.isEmpty else { return 0 }
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else {
            return segments.reduce(0.0) { $0 + $1[keyPath: metric] } / Double(segments.count)
        }
        return segments.reduce(0.0) { $0 + $1[keyPath: metric] * $1.duration } / totalDuration
    }
}

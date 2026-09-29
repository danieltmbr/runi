import Foundation
import Testing
@testable import RunKit

/// Verifies how `Run.Averages` are derived from the segments of a run.
///
struct RunAveragesTests {

    @Test func weightsMetricsBySegmentDuration() {
        let averages = Run.Averages(from: [
            segment(heartRate: 120, speed: 2, offset: 0, duration: 30),
            segment(heartRate: 160, speed: 4, offset: 30, duration: 10),
        ])

        #expect(averages.heartRate == 130)
        #expect(averages.speed == 2.5)
    }

    @Test func skipsMissingHeartRateReadings() {
        let averages = Run.Averages(from: [
            segment(heartRate: 0, speed: 2, offset: 0, duration: 10),
            segment(heartRate: 150, speed: 4, offset: 10, duration: 10),
        ])

        #expect(averages.heartRate == 150)
        #expect(averages.speed == 3)
    }

    @Test func fallsBackToPlainMeanWithoutDuration() {
        let averages = Run.Averages(from: [
            segment(heartRate: 100, speed: 1, offset: 0, duration: 0),
            segment(heartRate: 140, speed: 3, offset: 0, duration: 0),
        ])

        #expect(averages.heartRate == 120)
        #expect(averages.speed == 2)
    }

    @Test func isZeroWithoutSegments() {
        #expect(Run.Averages(from: []) == .zero)
    }

    @Test func runDerivesAveragesFromItsSegments() {
        let segments = [
            segment(heartRate: 120, speed: 2, offset: 0, duration: 10),
            segment(heartRate: 140, speed: 4, offset: 10, duration: 10),
        ]
        let run = Run(segments: segments, spectrum: Run.Spectrum(from: segments, time: 0...20))

        #expect(run.averages == Run.Averages(heartRate: 130, speed: 3))
    }

    @Test func normalisedRunCarriesNormalisedAverages() {
        let segments = [
            segment(heartRate: 100, speed: 2, offset: 0, duration: 10),
            segment(heartRate: 120, speed: 3, offset: 10, duration: 10),
            segment(heartRate: 180, speed: 6, offset: 20, duration: 10),
        ]
        let run = Run(segments: segments, spectrum: Run.Spectrum(from: segments, time: 0...30))
        let normalised = NormalisedRun().transform(run)

        // Speed normalises to 0, 0.25 and 1.
        #expect(abs(normalised.averages.speed - 1.25 / 3) < 1e-9)
        // Heart rate normalises to 0, 0.25 and 1; the lowest reading maps to
        // exactly 0 and is skipped like a missing one.
        #expect(abs(normalised.averages.heartRate - 0.625) < 1e-9)
    }

    // MARK: - Private

    private func segment(
        heartRate: Double,
        speed: Double,
        offset: TimeInterval,
        duration: TimeInterval
    ) -> Run.Segment {
        Run.Segment(
            cadence: 0,
            coordinate: .zero,
            direction: .zero,
            elevation: 0,
            elevationRate: 0,
            heartRate: heartRate,
            speed: speed,
            time: DateInterval(start: Date(timeIntervalSinceReferenceDate: offset), duration: duration)
        )
    }
}

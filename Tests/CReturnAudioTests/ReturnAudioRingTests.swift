import CReturnAudio
import XCTest

final class ReturnAudioRingTests: XCTestCase {
    func testWaitsForTargetFillBeforeRendering() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(128, 8))
        defer { return_audio_ring_destroy(ring) }

        let input = [Float](repeating: 0.5, count: 4)
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 4) }

        var output = [Float](repeating: 1, count: 4)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [0, 0, 0, 0])

        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 4) }
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [0.5, 0.5, 0.5, 0.5])
    }

    func testAppliesVolumeWithoutAllocatingAnotherAudioStage() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(128, 4))
        defer { return_audio_ring_destroy(ring) }
        return_audio_ring_set_volume(ring, 0.25)

        let input: [Float] = [1, -1, 0.5, -0.5]
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 4) }

        var output = [Float](repeating: 0, count: 4)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [0.25, -0.25, 0.125, -0.125])
    }

    func testConsumesOneExtraFrameWhenInputClockRunsAhead() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(256, 32))
        defer { return_audio_ring_destroy(ring) }

        let input = (0..<64).map(Float.init)
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 64) }
        var output = [Float](repeating: 0, count: 16)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 16) }

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.shortened_reads, 1)
        XCTAssertEqual(stats.fill_frames, 47)
        XCTAssertEqual(output.first, 0)
        XCTAssertEqual(output.last, 16)
    }

    func testStretchesWhenOutputClockRunsAhead() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(256, 32))
        defer { return_audio_ring_destroy(ring) }

        let input = [Float](repeating: 0.5, count: 32)
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 32) }

        var output = [Float](repeating: 0, count: 16)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 16) }
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 16) }

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.stretched_reads, 1)
        XCTAssertEqual(stats.fill_frames, 1)
    }

    func testUnderrunHoldsLastSampleInsteadOfSilence() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(128, 4))
        defer { return_audio_ring_destroy(ring) }

        let input: [Float] = [0.25, 0.5, 0.75, 1.0]
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 4) }

        var output = [Float](repeating: 0, count: 4)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [0.25, 0.5, 0.75, 1.0])

        output = [Float](repeating: 0, count: 4)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [1.0, 1.0, 1.0, 1.0])

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.underflows, 1)
    }

    func testUnderflowGrowsTargetAndReprimes() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(128, 8))
        defer { return_audio_ring_destroy(ring) }

        let input = [Float](repeating: 0.5, count: 8)
        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 8) }

        var output = [Float](repeating: 0, count: 8)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 8) }
        XCTAssertEqual(output, [Float](repeating: 0.5, count: 8))

        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 8) }
        var stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.underflows, 1)
        XCTAssertEqual(stats.target_frames, 12)

        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 8) }
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 8) }
        XCTAssertEqual(output, [Float](repeating: 0.5, count: 8), "8 < new target 12, must hold last sample")

        input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 8) }
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 8) }
        stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.underflows, 1, "fill 16 >= target 12 resumes real playback")
        XCTAssertGreaterThan(stats.fill_frames, 0)
    }

    func testTargetGrowthIsCappedAtHalfCapacity() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(64, 30))
        defer { return_audio_ring_destroy(ring) }

        let input = [Float](repeating: 0.5, count: 30)
        for _ in 0..<4 {
            input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 30) }
            var output = [Float](repeating: 0, count: 32)
            output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 32) }
        }

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.target_frames, 32)
    }

    func testZeroTargetPassesThroughSameCycleExactly() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(64, 0))
        defer { return_audio_ring_destroy(ring) }

        let input: [Float] = [0.25, -0.5, 0.75, -1.0]
        for _ in 0..<3 {
            input.withUnsafeBufferPointer { return_audio_ring_write(ring, $0.baseAddress, 4) }
            var output = [Float](repeating: 0, count: 4)
            output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
            XCTAssertEqual(output, input)
        }

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.fill_frames, 0)
        XCTAssertEqual(stats.underflows, 0)
        XCTAssertEqual(stats.shortened_reads, 0)
        XCTAssertEqual(stats.stretched_reads, 0)
    }

    func testZeroTargetUnderflowStaysZeroAndKeepsSilence() throws {
        let ring = try XCTUnwrap(return_audio_ring_create(64, 0))
        defer { return_audio_ring_destroy(ring) }

        var output = [Float](repeating: 1, count: 4)
        output.withUnsafeMutableBufferPointer { return_audio_ring_render(ring, $0.baseAddress, 4) }
        XCTAssertEqual(output, [0, 0, 0, 0])

        let stats = return_audio_ring_stats(ring)
        XCTAssertEqual(stats.underflows, 1)
        XCTAssertEqual(stats.target_frames, 0, "passthrough mode has no jitter margin to grow")
    }

    func testRejectsTargetAtOrAboveHalfCapacity() {
        XCTAssertNil(return_audio_ring_create(64, 32))
        let ring = return_audio_ring_create(64, 31)
        XCTAssertNotNil(ring)
        return_audio_ring_destroy(ring)
    }
}

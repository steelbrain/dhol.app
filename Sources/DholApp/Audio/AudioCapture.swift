import AVFoundation

/// Records the microphone and delivers 16 kHz mono float samples, the format
/// the speech model expects.
///
/// Rate conversion goes through `AVAudioConverter` rather than hand-rolled
/// interpolation so that downsampling from the hardware rate is properly
/// band-limited; aliased audio measurably hurts recognition accuracy.
final class AudioCapture: @unchecked Sendable {
    enum Failure: LocalizedError {
        case noInputDevice
        case conversionUnavailable

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No microphone is available."
            case .conversionUnavailable: "This microphone's audio format isn't supported."
            }
        }
    }

    static let sampleRate = 16_000.0

    /// Backstop for a hot key release that never arrives — for example because
    /// the app lost focus mid-press. Long enough that no real dictation reaches
    /// it. Reaching it ends the session; see `isAtCapacity`.
    private static let sampleLimit = Int(sampleRate * 600)

    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var smoothedLevel: Float = 0
    private var converter: AVAudioConverter?
    private var isCapturing = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    static var isPermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Everything captured so far, resampled to 16 kHz.
    ///
    /// Copied out element by element rather than handed over as-is: sharing the
    /// storage leaves it non-uniquely referenced, so the next tap callback pays
    /// for a copy-on-write of the entire recording — a growing malloc and memcpy
    /// on the audio thread, twice a second, for as long as the dictation runs.
    var capturedSamples: [Float] {
        lock.withLock { samples.withUnsafeBufferPointer(Array.init) }
    }

    /// True once the recording has hit its length backstop. The controller
    /// finishes the dictation on this rather than letting the engine run on.
    var isAtCapacity: Bool {
        lock.withLock { samples.count >= Self.sampleLimit }
    }

    /// Recent loudness as a 0...1 value, smoothed for display.
    var level: Float {
        lock.withLock { smoothedLevel }
    }

    func start() throws {
        stop()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw Failure.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat) else {
            throw Failure.conversionUnavailable
        }

        lock.withLock {
            samples = []
            samples.reserveCapacity(Int(Self.sampleRate) * 16)
            smoothedLevel = 0
            self.converter = converter
        }

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.absorb(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isCapturing = true
    }

    /// Stops the engine and returns everything captured.
    @discardableResult
    func stop() -> [Float] {
        guard isCapturing else { return [] }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock {
            converter = nil
            smoothedLevel = 0
            // Hand the recording over rather than keeping a second reference to
            // it. The backstop is ten minutes, so this array can be 38 MB, and
            // holding it until the next start() keeps that resident for as long
            // as the app runs — which, for a menu bar app, is all day. Clearing
            // also stops isAtCapacity reporting the finished recording's length.
            let captured = samples
            samples = []
            return captured
        }
    }

    private func absorb(_ buffer: AVAudioPCMBuffer) {
        let frames = AVAudioFrameCount(
            Double(buffer.frameLength) * Self.sampleRate / buffer.format.sampleRate
        ) + 16
        guard frames > 0,
              let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: frames)
        else { return }

        let converter = lock.withLock { self.converter }
        guard let converter else { return }

        // The converter pulls input through this block. It gets the buffer once;
        // every later pull within this call reports that no more is available.
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, output.frameLength > 0,
              let channel = output.floatChannelData?.pointee
        else { return }

        let converted = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))
        let meanSquare = converted.reduce(Float(0)) { $0 + $1 * $1 } / Float(converted.count)
        let loudness = min(1, sqrt(meanSquare) * 12)

        lock.withLock {
            // The backstop gates the recording, not the meter: the controller
            // only notices capacity on its next live pass, and bailing out here
            // froze the level ring at its last value for up to that long.
            if samples.count < Self.sampleLimit { samples.append(contentsOf: converted) }
            // Rise quickly so speech registers immediately, fall slowly so the
            // meter does not flicker between syllables.
            smoothedLevel = loudness > smoothedLevel
                ? loudness
                : smoothedLevel * 0.82 + loudness * 0.18
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

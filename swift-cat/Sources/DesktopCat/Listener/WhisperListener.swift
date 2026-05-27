import AVFoundation
import Foundation

/// Network speech-to-text via OpenAI Whisper. Fallback for locales without
/// on-device `SFSpeechRecognizer` support.
///
/// Capture model:
/// - `AVAudioEngine` taps the input node, accumulates PCM buffers in memory.
/// - On `stop`, we encode the buffer to a WAV file and POST it as multipart
///   `audio/wav` to `/v1/audio/transcriptions`.
/// - Partials are not supported (Whisper is one-shot). The coordinator
///   should show a "transcribing…" hint while we wait.
///
/// Capture is hard-capped at `maxCaptureSec` so a stuck `stop` never lets the
/// in-memory buffer grow without bound.
@MainActor
final class WhisperListener: NSObject, ListenerEngine {
    let name = "whisper"

    private let apiKey: String?
    private let session: URLSession
    private let audioEngine = AVAudioEngine()
    private let accumulator = BufferAccumulator()
    private var format: AVAudioFormat?
    private var callbacks: ListenerCallbacks?
    private var captureCap: Task<Void, Never>?
    private(set) var isListening: Bool = false

    /// 60 s mirrors Electron's hold-the-mic safety cap (`renderer.js`).
    private let maxCaptureSec: TimeInterval = 60

    init(
        apiKey: String? =
            ProcessInfo.processInfo.environment["WHISPER_API_KEY"]
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey?.isEmpty == false ? apiKey : nil
        self.session = session
        super.init()
    }

    nonisolated var isAvailable: Bool {
        get async { apiKey != nil }
    }

    func start(callbacks: ListenerCallbacks) async throws {
        guard !isListening else { return }
        guard apiKey != nil else { throw ListenerError.apiKeyMissing }

        let micGranted = await Self.requestMicAccess()
        guard micGranted else { throw ListenerError.micDenied }

        accumulator.clear()
        self.callbacks = callbacks

        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        self.format = inputFormat

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // Copy the buffer — the tap reuses storage between callbacks.
            guard let copy = Self.copyBuffer(buffer) else { return }
            Task { @MainActor in self?.accumulator.append(copy) }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.callbacks = nil
            throw ListenerError.audioEngineFailed(error.localizedDescription)
        }

        isListening = true

        // Hard cap: trigger a stop if the caller forgets.
        captureCap = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.maxCaptureSec ?? 60) * 1_000_000_000)
            await MainActor.run {
                guard let self, self.isListening else { return }
                self.callbacks?.onError("whisper: hit \(Int(self.maxCaptureSec))s cap, stopping")
                self.stop()
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        captureCap?.cancel()
        captureCap = nil

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        let captured = accumulator.retrieveAndClear()
        let captureFormat = format
        let cb = callbacks
        format = nil
        callbacks = nil

        Task { [weak self] in
            let text = await self?.transcribe(buffers: captured, format: captureFormat) ?? ""
            await MainActor.run { cb?.onFinal(text) }
        }
    }

    // MARK: - Transcription

    private func transcribe(buffers: [AVAudioPCMBuffer], format: AVAudioFormat?) async -> String {
        guard !buffers.isEmpty, let format, let apiKey else { return "" }

        guard let wav = Self.encodeWAV(buffers: buffers, format: format) else {
            await MainActor.run { self.callbacks?.onError("whisper: failed to encode WAV") }
            return ""
        }
        // Whisper rejects empty / sub-100-byte uploads with 400. Catch early.
        guard wav.count > 1000 else { return "" }

        let boundary = "----DesktopCat-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[listener] whisper network error:", error.localizedDescription)
            return ""
        }

        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            print("[listener] whisper \(status):", detail)
            return ""
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Audio helpers

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameCapacity
            )
        else { return nil }
        copy.frameLength = buffer.frameLength

        let channels = Int(buffer.format.channelCount)
        if let src32 = buffer.floatChannelData, let dst32 = copy.floatChannelData {
            for ch in 0..<channels {
                memcpy(dst32[ch], src32[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        } else if let src16 = buffer.int16ChannelData, let dst16 = copy.int16ChannelData {
            for ch in 0..<channels {
                memcpy(dst16[ch], src16[ch], Int(buffer.frameLength) * MemoryLayout<Int16>.size)
            }
        }
        return copy
    }

    /// Encode PCM buffers to a 16-bit mono WAV. Whisper accepts a wide range
    /// of formats but the cleanest path is "downmix to mono, convert to
    /// Int16, prepend a 44-byte WAV header."
    private static func encodeWAV(buffers: [AVAudioPCMBuffer], format: AVAudioFormat) -> Data? {
        let sampleRate = UInt32(format.sampleRate)
        let inputChannels = Int(format.channelCount)
        var samples: [Int16] = []

        for buf in buffers {
            let frames = Int(buf.frameLength)
            if let floats = buf.floatChannelData {
                samples.reserveCapacity(samples.count + frames)
                for i in 0..<frames {
                    var sum: Float = 0
                    for ch in 0..<inputChannels { sum += floats[ch][i] }
                    let avg = sum / Float(max(inputChannels, 1))
                    let clamped = max(-1.0, min(1.0, avg))
                    samples.append(Int16(clamped * 32767))
                }
            } else if let ints = buf.int16ChannelData {
                samples.reserveCapacity(samples.count + frames)
                for i in 0..<frames {
                    var sum: Int32 = 0
                    for ch in 0..<inputChannels { sum += Int32(ints[ch][i]) }
                    samples.append(Int16(clamping: sum / Int32(max(inputChannels, 1))))
                }
            }
        }

        guard !samples.isEmpty else { return nil }

        let byteCount = samples.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + byteCount)

        // RIFF header.
        data.append("RIFF".data(using: .ascii) ?? Data())
        data.append(uint32LE(UInt32(36 + byteCount)))
        data.append("WAVE".data(using: .ascii) ?? Data())

        // fmt chunk — PCM, mono, 16-bit.
        data.append("fmt ".data(using: .ascii) ?? Data())
        data.append(uint32LE(16))           // chunk size
        data.append(uint16LE(1))            // audio format (PCM)
        data.append(uint16LE(1))            // channels (mono)
        data.append(uint32LE(sampleRate))   // sample rate
        data.append(uint32LE(sampleRate * 2)) // byte rate
        data.append(uint16LE(2))            // block align
        data.append(uint16LE(16))           // bits per sample

        // data chunk.
        data.append("data".data(using: .ascii) ?? Data())
        data.append(uint32LE(UInt32(byteCount)))
        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                data.append(UnsafeBufferPointer(start: base, count: ptr.count))
            }
        }

        return data
    }

    private static func uint16LE(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])
    }

    private static func uint32LE(_ v: UInt32) -> Data {
        Data([
            UInt8(v & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 24) & 0xff),
        ])
    }

    // MARK: - Authorization

    private static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }
}

private final class BufferAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { buffers.append(buffer) }
    }

    func clear() {
        lock.withLock { buffers.removeAll() }
    }

    func retrieveAndClear() -> [AVAudioPCMBuffer] {
        lock.withLock {
            let result = buffers
            buffers.removeAll()
            return result
        }
    }
}

private extension Data {
    mutating func append(_ buffer: UnsafeBufferPointer<Int16>) {
        let byteCount = buffer.count * MemoryLayout<Int16>.size
        buffer.baseAddress.map { base in
            self.append(
                UnsafeBufferPointer(
                    start: UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
                    count: byteCount
                )
            )
        }
    }
}

import Foundation
import AppKit

/// Protocol so Phase 3 can swap in a ScreenCaptureKit-backed implementation
/// without touching anything that currently calls it.
protocol ScreenCapturing: Sendable {
    func capturePrimary() async throws -> Data
    func captureRegion(at point: CGPoint, size: CGSize) async throws -> Data
}

/// Phase-2 implementation: shells out to `/usr/sbin/screencapture`. Works
/// without ScreenCaptureKit bindings and matches the Electron version's path
/// 1:1 so the same TCC permission grant covers both.
struct ShellScreenCapture: ScreenCapturing {
    enum CaptureError: Error {
        case captureFailed(exitCode: Int32)
        case binaryMissing
    }

    func capturePrimary() async throws -> Data {
        let tmp = makeTempURL()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await runScreencapture(args: ["-x", "-t", "png", tmp.path])
        return try Data(contentsOf: tmp)
    }

    func captureRegion(at point: CGPoint, size: CGSize) async throws -> Data {
        let tmp = makeTempURL()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let rect = "\(Int(point.x)),\(Int(point.y)),\(Int(size.width)),\(Int(size.height))"
        try await runScreencapture(args: ["-x", "-t", "png", "-R", rect, tmp.path])
        return try Data(contentsOf: tmp)
    }

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("desktopcat-\(UUID().uuidString).png")
    }

    private func runScreencapture(args: [String]) async throws {
        let exe = URL(fileURLWithPath: "/usr/sbin/screencapture")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw CaptureError.binaryMissing
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = Process()
            task.executableURL = exe
            task.arguments = args
            task.standardError = Pipe()
            task.standardOutput = Pipe()
            task.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: CaptureError.captureFailed(exitCode: proc.terminationStatus))
                }
            }
            do {
                try task.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

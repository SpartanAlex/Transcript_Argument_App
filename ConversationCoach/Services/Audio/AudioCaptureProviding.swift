import Foundation

protocol AudioCaptureProviding: Sendable {
    func start() async throws
    func stop() async
}


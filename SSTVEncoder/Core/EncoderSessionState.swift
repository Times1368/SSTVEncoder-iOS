import Combine
import Foundation

enum EncodingInputChange: Sendable {
    case image
    case mode
    case crop
}

/// Owns the lifecycle of a single logical encoding operation.
///
/// Every new operation and every invalidation advances a generation token, so
/// asynchronous work that finishes late cannot replace the current result.
@MainActor
final class EncoderSessionState<Result>: ObservableObject {
    typealias Generation = UInt64

    @Published private(set) var result: Result?
    @Published private(set) var isEncoding = false
    @Published private(set) var progress = 0.0

    private var generation: Generation = 0

    @discardableResult
    func beginEncoding() -> Generation {
        advanceGeneration()
        result = nil
        isEncoding = true
        progress = 0
        return generation
    }

    /// Accepts progress only from the active operation. Progress is clamped to
    /// 0...1 and never moves backwards.
    @discardableResult
    func updateProgress(_ value: Double, for candidate: Generation) -> Bool {
        guard candidate == generation, isEncoding else { return false }

        let finiteValue = value.isFinite ? value : 0
        progress = max(progress, min(max(finiteValue, 0), 1))
        return true
    }

    /// Publishes a result only if it belongs to the active operation.
    @discardableResult
    func publish(result newResult: Result, for candidate: Generation) -> Bool {
        guard candidate == generation, isEncoding else { return false }

        result = newResult
        progress = 1
        isEncoding = false
        return true
    }

    func cancelEncoding() {
        resetAndInvalidate()
    }

    /// Clears a failed operation only when it is still the active generation.
    /// A late failure from superseded work must not cancel a newer encoding.
    @discardableResult
    func failEncoding(for candidate: Generation) -> Bool {
        guard candidate == generation, isEncoding else { return false }
        resetAndInvalidate()
        return true
    }

    func invalidate(for _: EncodingInputChange) {
        resetAndInvalidate()
    }

    private func resetAndInvalidate() {
        advanceGeneration()
        result = nil
        isEncoding = false
        progress = 0
    }

    private func advanceGeneration() {
        generation &+= 1
    }
}

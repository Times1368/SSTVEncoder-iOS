import Foundation

enum ReceiverInput: Sendable, Equatable {
    case audioFile
    case microphone
}

@MainActor
final class ReceiverSessionState<Result> {
    struct Generation: Equatable, Sendable {
        fileprivate let rawValue: UInt64
    }

    private(set) var result: Result?
    private(set) var input: ReceiverInput?
    private(set) var isActive = false
    private(set) var progress = 0.0

    private var generation = Generation(rawValue: 0)

    @discardableResult
    func begin(input: ReceiverInput) -> Generation {
        generation = Generation(rawValue: generation.rawValue &+ 1)
        result = nil
        self.input = input
        isActive = true
        progress = 0
        return generation
    }

    @discardableResult
    func publish(
        result: Result,
        progress: Double,
        for candidate: Generation
    ) -> Bool {
        guard candidate == generation, isActive else { return false }
        self.result = result
        self.progress = max(self.progress, min(1, max(0, progress)))
        return true
    }

    @discardableResult
    func finish(result: Result, for candidate: Generation) -> Bool {
        guard publish(result: result, progress: 1, for: candidate) else { return false }
        input = nil
        isActive = false
        return true
    }

    @discardableResult
    func stop(for candidate: Generation) -> Bool {
        guard candidate == generation, isActive else { return false }
        input = nil
        isActive = false
        return true
    }

    func cancel(clearResult: Bool) {
        generation = Generation(rawValue: generation.rawValue &+ 1)
        if clearResult {
            result = nil
            progress = 0
        }
        input = nil
        isActive = false
    }

    @discardableResult
    func fail(for candidate: Generation) -> Bool {
        guard candidate == generation, isActive else { return false }
        input = nil
        isActive = false
        return true
    }
}

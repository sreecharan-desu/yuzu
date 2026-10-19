import Foundation

/// Runs modern async AVFoundation calls from synchronous job code. Jobs run on GCD worker threads, never on
/// Swift's cooperative pool, so blocking here cannot starve the tasks being waited on.
enum AsyncBridge {
    private final class Box<T>: @unchecked Sendable { var value: Result<T, Error>? }

    static func run<T>(_ op: @escaping @Sendable () async throws -> T) throws -> T {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do { box.value = .success(try await op()) } catch { box.value = .failure(error) }
            done.signal()
        }
        done.wait()
        return try box.value!.get()
    }
}

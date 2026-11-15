import Foundation

/// Runs all traffic to one screen keyboard on a background queue, one transaction at a time.
public final class ScreenKeyboardSession: @unchecked Sendable {
    public let channel: ScreenKeyboardChannel
    private let link: AMG65Link
    private let queue: DispatchQueue

    /// Opens the vendor channel. Throws `ScreenKeyboardError.busy` while another program holds it.
    public init(channel: ScreenKeyboardChannel) throws {
        self.channel = channel
        self.link = try AMG65Link(channel: channel)
        self.queue = DispatchQueue(label: "keymapper.screen.\(channel.registryID)")
    }

    public var isClosed: Bool { link.isClosed }

    public func perform<T>(_ work: @escaping (AMG65Link) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [link] in
                do { continuation.resume(returning: try work(link)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func close() {
        queue.async { [link] in link.close() }
    }

    /// For quitting: waits up to `timeout` for the work already queued (the transaction in progress), then closes the
    /// channel. Sends nothing new.
    public func finish(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        queue.async { [link] in
            link.close()
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }
}

extension AMG65Effect {
    /// Turkish source names (translated with `L`) for the vendor's effect names.
    public static let titleKeys: [UInt8: String] = [
        1: "Sabit", 2: "Tek tek yanan", 3: "Tek tek sönen", 4: "Işıltı", 5: "Yağmur", 6: "Renkli",
        7: "Nefes", 8: "Spektrum", 9: "Dışa doğru", 10: "Kayan", 11: "Yuvarlanan", 12: "Dönen",
        13: "Patlama", 14: "Fırlatma", 15: "Dalgalar", 16: "Akış", 17: "Nabız", 18: "Eğim", 19: "Mekik",
        20: "Arka ışık kapalı",
    ]

    public var title: String { Self.titleKeys[id].map { L($0) } ?? name }
}

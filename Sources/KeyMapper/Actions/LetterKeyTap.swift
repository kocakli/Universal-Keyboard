import CoreGraphics
import Foundation
import KeyMapperCore
import os

/// Types letter keys: an active event tap on its own thread catches a letter key's code, drops it and
/// inserts the letter at the same point of the event stream, so fast typing keeps its order.
/// Needs Accessibility; without it the tap cannot be created and `start` is retried later.
final class LetterKeyTap: @unchecked Sendable {
    /// Shared with the tap thread; the main thread only replaces the letter table.
    private let filter = OSAllocatedUnfairLock(initialState: LetterKeyFilter())
    /// Main thread only.
    private var session: Session?

    var isRunning: Bool { session != nil }

    /// Applies the letter table and starts or stops the tap.
    func update(letters: [LetterKey], enabled: Bool) {
        filter.withLock { $0.update(letters: letters) }
        if enabled && !letters.isEmpty { start() } else { stop() }
    }

    private func start() {
        guard session == nil else { return }
        session = Session.start(filter: filter)
    }

    private func stop() {
        session?.stop()
        session = nil
    }

    /// One tap and the thread that runs it.
    private final class Session: @unchecked Sendable {
        private let filter: OSAllocatedUnfairLock<LetterKeyFilter>
        private var port: CFMachPort?
        private let loop = OSAllocatedUnfairLock<CFRunLoop?>(initialState: nil)

        private init(filter: OSAllocatedUnfairLock<LetterKeyFilter>) { self.filter = filter }

        static func start(filter: OSAllocatedUnfairLock<LetterKeyFilter>) -> Session? {
            let session = Session(filter: filter)
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: Session.callback,
                                               userInfo: Unmanaged.passUnretained(session).toOpaque()) else { return nil }
            session.port = port
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                CFMachPortInvalidate(port)
                return nil
            }
            let ready = DispatchSemaphore(value: 0)
            // The thread keeps the session alive until its run loop ends.
            let thread = Thread {
                let loop = CFRunLoopGetCurrent()
                session.loop.withLock { $0 = loop }
                CFRunLoopAddSource(loop, source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
                ready.signal()
                CFRunLoopRun()
                _ = session
            }
            thread.name = "KeyMapper letter keys"
            thread.qualityOfService = .userInteractive
            thread.start()
            ready.wait()
            return session
        }

        func stop() {
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
            }
            if let loop = loop.withLock({ $0 }) { CFRunLoopStop(loop) }
        }

        private static let callback: CGEventTapCallBack = { proxy, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<Session>.fromOpaque(info).takeUnretainedValue().handle(proxy: proxy, type: type, event: event)
        }

        private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS switches a slow or interrupted tap off; letters would silently stop.
                if let port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            case .keyDown, .keyUp:
                let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                let decision = filter.withLock {
                    $0.handle(keyCode: keyCode, isDown: type == .keyDown, modifiers: Self.modifiers(event.flags))
                }
                switch decision {
                case .pass: return Unmanaged.passUnretained(event)
                case .swallow: return nil
                case let .type(text):
                    Self.post(text, proxy: proxy)
                    return nil
                }
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        private static func modifiers(_ flags: CGEventFlags) -> LetterKeyFilter.Modifiers {
            var out: LetterKeyFilter.Modifiers = []
            if flags.contains(.maskControl) { out.insert(.control) }
            if flags.contains(.maskAlternate) { out.insert(.option) }
            if flags.contains(.maskCommand) { out.insert(.command) }
            if flags.contains(.maskShift) { out.insert(.shift) }
            if flags.contains(.maskAlphaShift) { out.insert(.capsLock) }
            return out
        }

        /// The keyboard still holds the slot's modifiers, so the letter goes out with no flags at all;
        /// otherwise apps would read it as a ⌃⌥⌘ shortcut.
        private static func post(_ text: String, proxy: CGEventTapProxy) {
            let units = Array(text.utf16)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.tapPostEvent(proxy)
            }
        }
    }
}

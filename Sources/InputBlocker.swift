import CoreGraphics
import Foundation
import Synchronization
import Carbon.HIToolbox

/// 有効な間、キーボードとトラックパッドの入力を HID レベルですべて捨てる。
///
/// タップは専用スレッドで動かす。メインスレッドが描画などで詰まって応答が遅れると、
/// macOS はタップを無効化し、その間の入力が素通りしてしまうため。
///
/// 検証用に、HID タップより後段（セッション）に聞き取り専用のタップも張る。
/// ロック中にそこへ届いた入力は「すり抜け」なので、解除時に ~/Library/Logs/Still.log に記録する。
final class InputBlocker: @unchecked Sendable {
    /// 解除キーが押されたとき（メインスレッドで呼ばれる）
    var onUnlock: @MainActor () -> Void = {}
    /// 捨てたキー入力ごと（メインスレッドで呼ばれる）
    var onKeyBlocked: @MainActor () -> Void = {}

    private let active = Atomic<Bool>(false)
    private var blockTap: CFMachPort?
    private var watchTap: CFMachPort?
    private var runLoop: CFRunLoop?
    // 以下はタップのスレッドからだけ触る
    private var leaks: [String: Int] = [:]

    private static let mask: CGEventMask = [
        1, 2, 3, 4, 5, 6, 7,        // マウスのクリック・移動・ドラッグ
        10, 11, 12,                 // keyDown / keyUp / flagsChanged
        14,                         // systemDefined（音量・明るさなど）
        18, 19, 20, 22,             // rotate / beginGesture / endGesture / scrollWheel
        25, 26, 27,                 // その他のボタン
        29, 30, 31, 32, 34,         // gesture / magnify / swipe / smartMagnify / pressure
    ].reduce(0) { $0 | (1 << $1) }

    /// 有効化する。権限がなくタップを張れなければ false。
    func start() -> Bool {
        guard prepare(), let blockTap else { return false }
        active.store(true, ordering: .sequentiallyConsistent)
        CGEvent.tapEnable(tap: blockTap, enable: true)
        if let watchTap { CGEvent.tapEnable(tap: watchTap, enable: true) }
        return true
    }

    func stop() {
        active.store(false, ordering: .sequentiallyConsistent)
        if let blockTap { CGEvent.tapEnable(tap: blockTap, enable: false) }
        if let watchTap { CGEvent.tapEnable(tap: watchTap, enable: false) }
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in flushLeaks() }
            CFRunLoopWakeUp(runLoop)
        }
    }

    // MARK: - Tap thread

    private func prepare() -> Bool {
        if blockTap != nil { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let info = Unmanaged.passUnretained(self).toOpaque()
            blockTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: Self.mask, callback: blockCallback, userInfo: info)
            guard let blockTap else { ready.signal(); return }
            watchTap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                         eventsOfInterest: Self.mask, callback: watchCallback, userInfo: info)
            runLoop = CFRunLoopGetCurrent()
            for tap in [blockTap, watchTap].compactMap({ $0 }) {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Still.InputBlocker"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return blockTap != nil
    }

    fileprivate func block(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isActive, let blockTap {
                CGEvent.tapEnable(tap: blockTap, enable: true)
                leaks["tap-disabled", default: 0] += 1
            }
            return Unmanaged.passUnretained(event)
        }
        guard isActive else { return Unmanaged.passUnretained(event) }

        if type == .keyDown {
            if event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_L,
               event.flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
                active.store(false, ordering: .sequentiallyConsistent)
                DispatchQueue.main.async { [onUnlock] in MainActor.assumeIsolated { onUnlock() } }
                return nil
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [onKeyBlocked] in MainActor.assumeIsolated { onKeyBlocked() } }
            }
        }
        return nil
    }

    fileprivate func watch(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isActive, let watchTap { CGEvent.tapEnable(tap: watchTap, enable: true) }
            return
        }
        guard isActive else { return }
        var name = "type\(type.rawValue)"
        if type == .keyDown || type == .keyUp {
            name += "(key\(event.getIntegerValueField(.keyboardEventKeycode)))"
        }
        leaks[name, default: 0] += 1
    }

    private var isActive: Bool { active.load(ordering: .relaxed) }

    private func flushLeaks() {
        let summary = leaks.isEmpty
            ? "ok: no leaks"
            : "LEAK: " + leaks.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
        leaks = [:]
        let line = "\(Date().ISO8601Format()) \(summary)\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Still.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

private let blockCallback: CGEventTapCallBack = { _, type, event, info in
    Unmanaged<InputBlocker>.fromOpaque(info!).takeUnretainedValue().block(type, event)
}

private let watchCallback: CGEventTapCallBack = { _, type, event, info in
    Unmanaged<InputBlocker>.fromOpaque(info!).takeUnretainedValue().watch(type, event)
    return Unmanaged.passUnretained(event)
}

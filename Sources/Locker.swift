import AppKit
import SwiftUI
import ApplicationServices

/// ロック状態と画面表示を受け持つ。入力を止める処理そのものは InputBlocker。
@MainActor
@Observable
final class Locker {
    private(set) var isLocked = false
    private(set) var isTrusted = AXIsProcessTrusted()
    /// ロック中に捨てたキーの数。HUD の鍵が跳ねるきっかけに使う。
    private(set) var blockedCount = 0
    /// HUD の出現アニメーション用
    private(set) var hudShown = false

    @ObservationIgnored private let blocker = InputBlocker()
    @ObservationIgnored private var overlays: [NSWindow] = []
    @ObservationIgnored private var trustTimer: Timer?

    init() {
        blocker.onUnlock = { [weak self] in self?.unlock() }
        blocker.onKeyBlocked = { [weak self] in self?.blockedCount += 1 }
        if !isTrusted { watchTrust() }
    }

    func lock() {
        guard !isLocked else { return }
        guard AXIsProcessTrusted(), blocker.start() else {
            isTrusted = false
            openAccessibilitySettings()
            return
        }
        blockedCount = 0
        isLocked = true
        showOverlays()
    }

    func unlock() {
        blocker.stop()
        guard isLocked else { return }
        isLocked = false
        NSCursor.unhide()
        // 鍵が開くところを少し見せてから消す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.hideOverlays() }
    }

    func openAccessibilitySettings() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        watchTrust()
    }

    private func watchTrust() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.isTrusted = true
                timer.invalidate()
                self.trustTimer = nil
            }
        }
    }

    // MARK: - Overlay

    private func showOverlays() {
        hudShown = false
        let main = NSScreen.main
        overlays = NSScreen.screens.map { makeOverlay(on: $0, showsHUD: $0 == main) }
        NSApp.activate()
        NSCursor.hide()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            overlays.forEach { $0.animator().alphaValue = 1 }
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.22)) { hudShown = true }
    }

    private func hideOverlays() {
        let windows = overlays
        overlays = []
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            windows.forEach { $0.orderOut(nil) }
        }
    }

    private func makeOverlay(on screen: NSScreen, showsHUD: Bool) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let hosting = NSHostingView(rootView: OverlayView(showsHUD: showsHUD).environment(self))
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)

        window.contentView = blur
        window.setFrame(screen.frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        return window
    }
}

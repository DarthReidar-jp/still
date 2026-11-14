import SwiftUI
import Carbon.HIToolbox

@main
struct StillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Still", id: "main") {
            MainView().environment(delegate.locker)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let locker = Locker()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌃⌥⌘L でロック。解除は InputBlocker 側で同じ組み合わせを判定する。
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey | controlKey)) {
            [weak self] in self?.locker.lock()
        }
    }

    // ウィンドウを閉じてもホットキーを効かせるため常駐する
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Carbon のグローバルホットキー（アクセシビリティ権限なしで動く）
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, info in
            Unmanaged<HotKey>.fromOpaque(info!).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x5354_4C4C, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

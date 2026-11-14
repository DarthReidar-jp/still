import SwiftUI

private let lockKeys = ["⌃", "⌥", "⌘", "L"]

struct MainView: View {
    @Environment(Locker.self) private var locker

    var body: some View {
        VStack(spacing: 0) {
            Button(action: locker.lock) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 96, height: 96)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .keyboardShortcut(.defaultAction)
            .disabled(!locker.isTrusted)
            .opacity(locker.isTrusted ? 1 : 0.4)

            Text("ロック")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 18)

            Group {
                if locker.isTrusted {
                    HStack(spacing: 4) {
                        KeyCaps(size: 22)
                        Text("でも").foregroundStyle(.secondary)
                    }
                } else {
                    Button("アクセシビリティを許可…", action: locker.openAccessibilitySettings)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            .font(.system(size: 12))
            .padding(.top, 10)
        }
        .frame(width: 260, height: 290)
        .padding(.top, -14) // 隠したタイトルバーのぶん視覚的な中心を上げる
        .containerBackground(.thinMaterial, for: .window)
    }
}

struct OverlayView: View {
    @Environment(Locker.self) private var locker
    let showsHUD: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
            if showsHUD { hud }
        }
        .ignoresSafeArea()
    }

    private var hud: some View {
        VStack(spacing: 0) {
            Image(systemName: locker.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 46, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: locker.blockedCount)
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .glassEffect(.clear, in: .circle)

            Text(locker.isLocked ? "ロック中" : "解除")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .padding(.top, 28)

            HStack(spacing: 6) {
                KeyCaps(size: 26, onDark: true)
                Text("で解除").foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 14))
            .padding(.top, 14)
            .opacity(locker.isLocked ? 1 : 0)
        }
        .scaleEffect(locker.hudShown ? 1 : 0.94)
        .opacity(locker.hudShown ? 1 : 0)
        .animation(.smooth(duration: 0.3), value: locker.isLocked)
    }
}

struct KeyCaps: View {
    var size: CGFloat
    var onDark = false

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(lockKeys, id: \.self) { key in
                Text(key)
                    .font(.system(size: size * 0.5, weight: .medium, design: .rounded))
                    .foregroundStyle(onDark ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(minWidth: size, minHeight: size)
                    .glassEffect(onDark ? .clear : .regular, in: .rect(cornerRadius: size * 0.28))
            }
        }
    }
}

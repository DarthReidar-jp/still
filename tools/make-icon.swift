// Still のアイコンを描き、.iconset を作る。使い方: swift tools/make-icon.swift <out.iconset>
// 各サイズをそのピクセル数で直接描く（縮小しないので小さいサイズもにじまない）。
//
// モチーフは Mac の修飾キー。⌘ キーの「右上に記号・左下に名前」と同じ配置で、
// 右上に鍵、左下に「still」と印字したスモークガラスのキーを、アルミの台に置く。
//
// 寸法は黄金比 φ で揃える。
//   キー幅 = キャンバス / φ
//   キー側面の厚み（上 : 横 : 下）= 1 : φ : φ²
//   キーと天面の角丸は、台の角と同心になるよう余白ぶんずつ小さくする
//   見た目の重心（キー＋影）が台の中心に来るよう、キーをわずかに下げる
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let S: CGFloat = 1024
let phi: CGFloat = 1.618

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func white(_ a: CGFloat) -> CGColor { rgb(0xFFFFFF, a) }
func black(_ a: CGFloat) -> CGColor { rgb(0x000000, a) }

func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
}

extension CGContext {
    func vertical(_ g: CGGradient, _ r: CGRect) {
        drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
    }
    /// パスの内側に沿った細い線を、グラデーションで塗る
    func rim(_ path: CGPath, width: CGFloat, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        saveGState()
        addPath(path); clip()
        addPath(path); setLineWidth(width * 2); replacePathWithStrokedPath(); clip()
        drawLinearGradient(g, start: from, end: to, options: [])
        restoreGState()
    }
}

/// Apple のアイコン外形に近いスーパー楕円
func squircle(_ r: CGRect, n: CGFloat = 4.2) -> CGPath {
    let p = CGMutablePath()
    for i in 0...1440 {
        let t = CGFloat(i) / 1440 * 2 * .pi
        let c = cos(t), s = sin(t)
        let pt = CGPoint(x: r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c),
                         y: r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - Layout（1024 基準。小さいサイズは座標系ごと縮める）

let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 186                                    // スーパー楕円の見かけの角丸
let keyW = (S / phi).rounded()                                    // 633
let key = CGRect(x: S / 2 - keyW / 2, y: S / 2 - keyW / 2 - 8, width: keyW, height: keyW)
let lipTop = (keyW * 0.025).rounded()                             // 16
let lipSide = (lipTop * phi).rounded()                            // 26
let lipBottom = (lipTop * phi * phi).rounded()                    // 42
let keyRadius = plateRadius - (key.minX - plate.minX)             // 台と同心
let face = CGRect(x: key.minX + lipSide, y: key.minY + lipBottom,
                  width: key.width - lipSide * 2, height: key.height - lipTop - lipBottom)
let faceRadius = keyRadius - lipSide                              // キーと同心

func draw(_ ctx: CGContext, px: Int) {
    let compact = px <= 32
    let platePath = squircle(plate)

    // 台の落ち影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: black(0.22))
    ctx.addPath(platePath); ctx.setFillColor(rgb(0xDADBDD)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath); ctx.clip()

    // 台：アルミ。ごく低いコントラストの縦グラデーションと、斜めの鈍い照り
    ctx.vertical(gradient([rgb(0xF4F4F3), rgb(0xE3E4E6), rgb(0xD1D2D5)], [0, 0.5, 1]), plate)
    ctx.drawLinearGradient(gradient([white(0), white(0.32), white(0), white(0.18), white(0)], [0, 0.3, 0.5, 0.72, 1]),
                           start: CGPoint(x: plate.minX, y: plate.maxY), end: CGPoint(x: plate.maxX, y: plate.minY), options: [])

    // キーの影：広く薄い環境影と、狭く濃い接地影（台の外にははみ出さない）
    let keyPath = rounded(key, keyRadius)
    for (dy, blur, a) in [(CGFloat(-18), CGFloat(40), CGFloat(0.24)), (-4, 8, 0.36)] {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: black(a))
        ctx.addPath(keyPath); ctx.setFillColor(rgb(0x1A1B1E)); ctx.fillPath()
        ctx.restoreGState()
    }

    // キーの側面：黒に近いグラファイト。手前の縁にだけ金属の照り返し
    ctx.saveGState()
    ctx.addPath(keyPath); ctx.clip()
    ctx.vertical(gradient([rgb(0x34363B), rgb(0x1B1C1F), rgb(0x0E0F11)], [0, 0.55, 1]), key)
    ctx.drawLinearGradient(gradient([white(0), white(0.10), white(0)]),
                           start: CGPoint(x: 0, y: key.minY + lipBottom * 0.85), end: CGPoint(x: 0, y: key.minY + 2), options: [])
    ctx.restoreGState()
    ctx.rim(keyPath, width: 1.5, gradient([white(0.38), white(0.04), white(0.14)], [0, 0.55, 1]),
            from: CGPoint(x: key.minX, y: key.maxY), to: CGPoint(x: key.maxX, y: key.minY))

    // 天面：スモークガラス
    let facePath = rounded(face, faceRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: black(0.45))
    ctx.addPath(facePath); ctx.setFillColor(rgb(0x2A2C30)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(facePath); ctx.clip()
    ctx.vertical(gradient([rgb(0x46484E), rgb(0x2F3135), rgb(0x26282B)], [0, 0.5, 1]), face)
    let glow = CGPoint(x: face.minX + face.width * 0.3, y: face.maxY - face.height * 0.2)
    ctx.drawRadialGradient(gradient([white(0.10), white(0)]), startCenter: glow, startRadius: 0,
                           endCenter: glow, endRadius: face.width * 0.75, options: [])
    ctx.drawLinearGradient(gradient([white(0.075), white(0.03), white(0)], [0, 0.5, 1]),
                           start: CGPoint(x: face.minX, y: face.maxY),
                           end: CGPoint(x: face.minX + face.width / (phi * phi) * 0.9, y: face.maxY - face.height / (phi * phi) * 1.6),
                           options: [])
    ctx.restoreGState()

    // 天面の縁：Liquid Glass のように左上と右下だけが光る
    ctx.rim(facePath, width: 2, gradient([white(0.55), white(0.0), white(0.0), white(0.18)], [0, 0.4, 0.7, 1]),
            from: CGPoint(x: face.minX, y: face.maxY), to: CGPoint(x: face.maxX, y: face.minY))

    // 印字：右上に鍵、左下に still。小さいサイズでは鍵だけを中央に大きく
    let legend = NSColor(white: 0.92, alpha: 0.95)
    let glyph = face.width * (compact ? 0.52 : 0.125)
    let cfg = NSImage.SymbolConfiguration(pointSize: glyph, weight: compact ? .semibold : .regular)
        .applying(.init(paletteColors: [legend]))
    let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let pad = (face.width / pow(phi, 4) * 0.72).rounded()
    let origin = compact
        ? CGPoint(x: face.midX - lock.size.width / 2, y: face.midY - lock.size.height / 2)
        : CGPoint(x: face.maxX - pad - lock.size.width, y: face.maxY - pad - lock.size.height)
    lock.draw(in: CGRect(origin: origin, size: lock.size))
    if !compact {
        let font = NSFont.systemFont(ofSize: glyph, weight: .regular)
        NSAttributedString(string: "still", attributes: [.font: font, .foregroundColor: legend, .kern: 0.5])
            .draw(at: CGPoint(x: face.minX + pad, y: face.minY + pad + font.descender))
    }

    ctx.restoreGState()

    // 台の縁：上は光、下はわずかに沈む
    ctx.rim(platePath, width: 2.5, gradient([white(1), white(0.2), black(0.10)], [0, 0.5, 1]),
            from: CGPoint(x: 0, y: plate.maxY), to: CGPoint(x: 0, y: plate.minY))
}

// MARK: - Output

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let g = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = g
        g.cgContext.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
        draw(g.cgContext, px: px)
        NSGraphicsContext.current = nil
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
print("iconset: \(out)")

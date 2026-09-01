import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let src = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: src) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("cannot read \(src)"); exit(1)
}

let width = image.width, height = image.height
print("source: \(width)x\(height)")

// ---- 1. Find the artwork: the saturated teal square, ignoring the white page and its shadow ----
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
guard let scan = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                           bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(2) }
scan.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

// Count saturated pixels per row and per column. The solid body of the tile scores
// near-maximum; the soft glow and reflection underneath it score far lower, so a density
// threshold finds the real edges where a plain bounding box picks up the glow.
var rowCounts = [Int](repeating: 0, count: height)
var colCounts = [Int](repeating: 0, count: width)
for y in 0..<height {
    for x in 0..<width {
        let i = y * bytesPerRow + x * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        let chroma = max(r, max(g, b)) - min(r, min(g, b))
        if chroma > 40 {
            rowCounts[y] += 1
            colCounts[x] += 1
        }
    }
}

func denseRange(_ counts: [Int]) -> (Int, Int) {
    let threshold = Int(Double(counts.max() ?? 0) * 0.6)
    let first = counts.firstIndex { $0 >= threshold } ?? 0
    let last = counts.lastIndex { $0 >= threshold } ?? (counts.count - 1)
    return (first, last)
}

let (minX, maxX) = denseRange(colCounts)
let (minY, maxY) = denseRange(rowCounts)
guard maxX > minX, maxY > minY else { print("no artwork found"); exit(3) }

// The tile is square in reality; take the smaller axis so nothing outside it creeps in,
// then trim a hair more to drop the antialiased edge against the white page.
let rawSide = min(maxX - minX, maxY - minY) + 1
let trim = Int(Double(rawSide) * 0.012)
let side = rawSide - trim * 2
let cropRect = CGRect(
    x: minX + (maxX - minX + 1 - rawSide) / 2 + trim,
    y: minY + (maxY - minY + 1 - rawSide) / 2 + trim,
    width: side, height: side
)
print("dense bounds: x \(minX)…\(maxX), y \(minY)…\(maxY)  → crop \(Int(cropRect.width))x\(Int(cropRect.height)) at (\(Int(cropRect.minX)),\(Int(cropRect.minY)))")

guard let cropped = image.cropping(to: cropRect) else { print("crop failed"); exit(4) }

// ---- 2. Master at 1024, on the macOS icon grid: 824pt of art inside a 1024 canvas ----
let canvas = 1024.0
let art = 824.0
let inset = (canvas - art) / 2
let radius = art * 0.235       // a touch tighter than Apple's 0.2255, which shaves the source's own light rim off the corners

func render(_ size: Int) -> Data? {
    let scale = Double(size) / canvas
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let frame = CGRect(x: inset * scale, y: inset * scale, width: art * scale, height: art * scale)
    let path = CGPath(roundedRect: frame, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)

    // Soft contact shadow, the way Apple's own icons sit on the Dock.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -art * scale * 0.012),
                  blur: art * scale * 0.035,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(cropped, in: frame)
    ctx.restoreGState()

    guard let out = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let data = render(size) else { print("render \(size) failed"); continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
}
print("rendered 16/32/64/128/256/512/1024")

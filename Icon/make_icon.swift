// Draws the LockShield mark by the Quinde Studio logo system (Design logic/LOGO-SYSTEM.md)
// and exports the SVGs, the press PNG and AppIcon.icns next to this file.
//
// Run: swift Icon/make_icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - System constants (LOGO-SYSTEM.md)

let canvas: CGFloat = 610          // section 3.1
let gap: CGFloat = 13              // section 3.3
let phi: CGFloat = 1.618_033_988_75
let tileRadiusFraction: CGFloat = 0.236   // section 5
let blueHex = "#1030ff"
let blue = CGColor(srgbRed: 16 / 255, green: 48 / 255, blue: 1, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// MARK: - The mark

/// One flat facet, drawn on the Fibonacci lattice (y grows downwards).
/// `shared` lists the edges (edge i runs from point i to point i + 1) that face another
/// facet; only those are inset by half the gap.
struct Facet {
    let name: String
    let lattice: [CGPoint]
    let shared: Set<Int>
}

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// Subject: a padlock whose body is a shield, cut once on the diagonal.
let facets = [
    Facet(name: "Body right",
          lattice: [p(288, 199), p(555, 199), p(555, 466), p(411, 610), p(220, 610)],
          shared: [0, 4]),
    Facet(name: "Body left",
          lattice: [p(55, 199), p(288, 199), p(220, 610), p(199, 610), p(55, 466)],
          shared: [0, 1]),
    Facet(name: "Shackle",
          lattice: [p(165, 199), p(165, 55), p(220, 0), p(390, 0), p(445, 55), p(445, 199),
                    p(356, 199), p(356, 123), p(322, 89), p(288, 89), p(254, 123), p(254, 199)],
          shared: [5, 11]),
]

// MARK: - Geometry

func signedArea(_ points: [CGPoint]) -> CGFloat {
    var sum: CGFloat = 0
    for i in points.indices {
        let a = points[i], b = points[(i + 1) % points.count]
        sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
}

/// Moves each shared edge inwards by half the gap and rejoins the corners.
func cutGap(_ facet: Facet) -> [CGPoint] {
    let points = facet.lattice
    let count = points.count
    let winding: CGFloat = signedArea(points) > 0 ? 1 : -1

    // Each edge as a point on its (possibly shifted) line plus a direction.
    let lines: [(origin: CGPoint, direction: CGPoint)] = points.indices.map { i in
        let a = points[i], b = points[(i + 1) % count]
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        let shift = facet.shared.contains(i) ? gap / 2 : 0
        let inward = p(-dy / length * winding, dx / length * winding)
        return (p(a.x + inward.x * shift, a.y + inward.y * shift), p(dx, dy))
    }

    return points.indices.map { i in
        let (o1, d1) = lines[(i + count - 1) % count]
        let (o2, d2) = lines[i]
        let denominator = d1.x * d2.y - d1.y * d2.x
        let t = ((o2.x - o1.x) * d2.y - (o2.y - o1.y) * d2.x) / denominator
        return p(o1.x + d1.x * t, o1.y + d1.y * t)
    }
}

/// Every position a Fibonacci subdivision of the 610 square can produce, down to 21 units.
func latticeLines() -> Set<Int> {
    let fibonacci = [21, 34, 55, 89, 144, 233, 377, 610]
    var lines: Set<Int> = []
    func split(_ start: Int, _ n: Int) {
        lines.insert(start)
        lines.insert(start + fibonacci[n])
        guard n >= 2 else { return }
        split(start, n - 2); split(start + fibonacci[n - 2], n - 1)
        split(start, n - 1); split(start + fibonacci[n - 1], n - 2)
    }
    split(0, fibonacci.count - 1)
    return lines
}

// MARK: - Checks (LOGO-SYSTEM.md section 8, steps 4, 5 and 7)

let outlines = facets.map(cutGap)
let areas = outlines.map { abs(signedArea($0)) }
var failed = false

let lattice = latticeLines()
for facet in facets {
    for point in facet.lattice where !lattice.contains(Int(point.x)) || !lattice.contains(Int(point.y)) {
        print("Off lattice: \(facet.name) (\(Int(point.x)), \(Int(point.y)))")
        failed = true
    }
}

print("Area log")
for (i, facet) in facets.enumerated() {
    var line = "  \(facet.name): \(Int(areas[i].rounded()))"
    if i + 1 < facets.count {
        let ratio = areas[i] / areas[i + 1]
        line += String(format: "  ratio to the next %.3f", ratio)
        if abs(ratio / phi - 1) > 0.01 { line += "  (not within 1 % of φ)"; failed = true }
    }
    print(line)
}
if failed { print("The mark is off-system; nothing exported."); exit(1) }

// MARK: - SVG export

func number(_ value: CGFloat) -> String {
    let text = String(format: "%.2f", value)
    return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
}

func polygons(fill: String, scale: CGFloat = 1, offset: CGFloat = 0) -> String {
    outlines.map { outline in
        let points = outline.map { "\(number($0.x * scale + offset)),\(number($0.y * scale + offset))" }
        return "  <polygon fill=\"\(fill)\" points=\"\(points.joined(separator: " "))\"/>"
    }.joined(separator: "\n")
}

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func write(_ text: String, to name: String) throws {
    try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    print("Wrote Icon/\(name)")
}

let markSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 610 610">
    \(polygons(fill: blueHex))
    </svg>

    """

let tileSide: CGFloat = 1024
let pressMark = tileSide * 0.62
let tileSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
      <rect width="1024" height="1024" rx="\(number(tileSide * tileRadiusFraction))" fill="\(blueHex)"/>
    \(polygons(fill: "#ffffff", scale: pressMark / canvas, offset: (tileSide - pressMark) / 2))
    </svg>

    """

// MARK: - PNG export

/// A blue tile with the white mark centred on it.
/// - Parameters:
///   - pixels: side of the square image.
///   - tileFraction: side of the tile as a fraction of the image (1 = full image).
///   - markFraction: side of the mark's 610 square as a fraction of the tile.
func renderTile(pixels: Int, tileFraction: CGFloat, markFraction: CGFloat) -> CGImage {
    let side = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)

    let tile = side * tileFraction
    let tileOrigin = (side - tile) / 2
    let radius = tile * tileRadiusFraction
    context.addPath(CGPath(roundedRect: CGRect(x: tileOrigin, y: tileOrigin, width: tile, height: tile),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(blue)
    context.fillPath()

    let mark = tile * markFraction
    let markOrigin = (side - mark) / 2
    let scale = mark / canvas
    context.setFillColor(white)
    for outline in outlines {
        context.addLines(between: outline.map { p($0.x * scale + markOrigin, $0.y * scale + markOrigin) })
        context.closePath()
        context.fillPath()
    }
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

// MARK: - Export

try write(markSVG, to: "lockshield-mark.svg")
try write(tileSVG, to: "lockshield-tile.svg")

writePNG(renderTile(pixels: 1024, tileFraction: 1, markFraction: 0.62),
         to: folder.appendingPathComponent("lockshield-tile-1024.png"))
print("Wrote Icon/lockshield-tile-1024.png")

// macOS draws no mask of its own, so the tile carries the radius and sits on the
// standard macOS icon grid (824 of 1024) with a clear margin around it.
let macTileFraction: CGFloat = 824 / 1024
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("LockShield-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        // Section 5: the mark is a little larger on the smallest sizes.
        let markFraction: CGFloat = pixels <= 64 ? 0.66 : 0.62
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(renderTile(pixels: pixels, tileFraction: macTileFraction, markFraction: markFraction),
                 to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", folder.appendingPathComponent("AppIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("Wrote Icon/AppIcon.icns")

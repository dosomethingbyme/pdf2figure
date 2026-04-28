import AppKit
import Foundation

let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let projectRoot = resources.deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = projectRoot.appendingPathComponent("logo.png")
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Cannot load logo source: \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let bundledLogo = resources.appendingPathComponent("logo.png")
try? FileManager.default.removeItem(at: bundledLogo)

func savePNG(_ image: NSImage, size: CGFloat, to url: URL) throws {
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    canvas.fill()

    let iconRect = canvas.insetBy(dx: size * 0.035, dy: size * 0.035)
    let radius = size * 0.2237
    let roundedPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    roundedPath.addClip()
    image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.12).setStroke()
    roundedPath.lineWidth = max(1, size * 0.006)
    roundedPath.stroke()
    output.unlockFocus()

    guard
        let tiff = output.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "FigraIcon", code: 1)
    }
    try png.write(to: url)
}

try savePNG(sourceImage, size: 1024, to: bundledLogo)

let outputs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in outputs {
    try savePNG(sourceImage, size: size, to: iconset.appendingPathComponent(name))
}

func appendUInt16(_ value: UInt16, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

let icoSources: [(UInt8, UInt8, URL)] = [
    (16, 16, iconset.appendingPathComponent("icon_16x16.png")),
    (32, 32, iconset.appendingPathComponent("icon_32x32.png")),
    (0, 0, iconset.appendingPathComponent("icon_256x256.png"))
]
let icoImages = try icoSources.map { width, height, url in
    (width: width, height: height, data: try Data(contentsOf: url))
}

var ico = Data()
appendUInt16(0, to: &ico)
appendUInt16(1, to: &ico)
appendUInt16(UInt16(icoImages.count), to: &ico)

var imageOffset = 6 + icoImages.count * 16
for image in icoImages {
    ico.append(image.width)
    ico.append(image.height)
    ico.append(0)
    ico.append(0)
    appendUInt16(1, to: &ico)
    appendUInt16(32, to: &ico)
    appendUInt32(UInt32(image.data.count), to: &ico)
    appendUInt32(UInt32(imageOffset), to: &ico)
    imageOffset += image.data.count
}
for image in icoImages {
    ico.append(image.data)
}
try ico.write(to: resources.appendingPathComponent("AppIcon.ico"))

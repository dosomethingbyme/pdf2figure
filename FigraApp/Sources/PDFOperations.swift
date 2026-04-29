import AppKit
import PDFKit
import UniformTypeIdentifiers

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func makePageItems(document: PDFDocument) -> [PageItem] {
    makePagePlaceholders(pageCount: document.pageCount)
}

func makePagePlaceholders(pageCount: Int) -> [PageItem] {
    (0..<pageCount).map { index in
        PageItem(index: index, thumbnail: nil)
    }
}

func makePageThumbnail(document: PDFDocument, pageIndex: Int, size: NSSize = NSSize(width: 220, height: 300)) -> PageItem? {
    guard let page = document.page(at: pageIndex) else { return nil }
    return PageItem(index: pageIndex, thumbnail: page.thumbnail(of: size, for: .mediaBox))
}

func parsePageRanges(_ value: String, pageCount: Int) throws -> [Int] {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return [] }
    var pages: [Int] = []
    for rawPart in cleaned.split(separator: ",") {
        let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if part.contains("-") {
            let bounds = part.split(separator: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), start > 0, end >= start, end <= pageCount else {
                throw AppError("页码范围无效：\(part)")
            }
            pages.append(contentsOf: (start - 1)...(end - 1))
        } else {
            guard let page = Int(part), page > 0, page <= pageCount else {
                throw AppError("页码无效：\(part)")
            }
            pages.append(page - 1)
        }
    }
    return Array(NSOrderedSet(array: pages).compactMap { $0 as? Int })
}

func formatPageSet(_ set: Set<Int>) -> String {
    set.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
}

func applySelection(_ index: Int, selectedPages: inout Set<Int>, lastSelection: inout Int?, command: Bool, shift: Bool) {
    if shift, let lastSelection {
        let range = min(lastSelection, index)...max(lastSelection, index)
        selectedPages.formUnion(range)
    } else if command {
        if selectedPages.contains(index) {
            selectedPages.remove(index)
        } else {
            selectedPages.insert(index)
        }
        lastSelection = index
    } else {
        selectedPages = [index]
        lastSelection = index
    }
}

func contiguousGroups(_ pages: [Int]) -> [[Int]] {
    guard let first = pages.first else { return [] }
    var groups: [[Int]] = [[first]]
    for page in pages.dropFirst() {
        if page == (groups[groups.count - 1].last ?? -2) + 1 {
            groups[groups.count - 1].append(page)
        } else {
            groups.append([page])
        }
    }
    return groups
}

func writePDF(document: PDFDocument, pageIndexes: [Int], to url: URL) throws {
    let output = PDFDocument()
    for pageIndex in pageIndexes {
        guard let page = document.page(at: pageIndex) else { continue }
        output.insert(page, at: output.pageCount)
    }
    guard output.write(to: url) else { throw AppError("写入 PDF 失败。") }
}

func writeSanitizedPDFCopy(document: PDFDocument, to url: URL) throws {
    let output = PDFDocument()
    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex) else { continue }
        let copiedPage = (page.copy() as? PDFPage) ?? page
        output.insert(copiedPage, at: output.pageCount)
    }
    output.documentAttributes = [:]

    let temporaryURL = url
        .deletingLastPathComponent()
        .appendingPathComponent(".\(UUID().uuidString)-\(url.lastPathComponent)", isDirectory: false)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }

    guard output.write(to: temporaryURL) else { throw AppError("写入 PDF 失败。") }
    try stripPDFDocumentInfoTrailer(from: temporaryURL)
    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: url)
}

private func stripPDFDocumentInfoTrailer(from url: URL) throws {
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .isoLatin1) else {
        throw AppError("无法解析 PDF trailer。")
    }
    guard
        let startXrefRange = text.range(of: "startxref", options: .backwards),
        let trailerRange = text.range(of: "trailer", options: .backwards, range: text.startIndex..<startXrefRange.lowerBound),
        let dictionaryStart = text.range(of: "<<", range: trailerRange.upperBound..<startXrefRange.lowerBound),
        let dictionaryEnd = text.range(of: ">>", range: dictionaryStart.upperBound..<startXrefRange.lowerBound)
    else {
        throw AppError("无法定位 PDF trailer。")
    }

    let trailer = String(text[dictionaryStart.lowerBound..<dictionaryEnd.upperBound])
    guard
        let previousXref = firstMatch(in: String(text[startXrefRange.upperBound...]), pattern: #"^\s*(\d+)"#),
        let size = firstMatch(in: trailer, pattern: #"/Size\s+(\d+)"#),
        let root = firstMatch(in: trailer, pattern: #"/Root\s+(\d+\s+\d+\s+R)"#)
    else {
        throw AppError("无法读取 PDF trailer。")
    }

    let id = firstMatch(in: trailer, pattern: #"/ID\s*\[\s*<[^>]*>\s*<[^>]*>\s*\]"#)
    let xrefOffset = data.count + 1
    var replacement = "\nxref\n0 1\n0000000000 65535 f \ntrailer\n<< /Size \(size) /Root \(root)"
    if let id {
        replacement += " \(id)"
    }
    replacement += " /Prev \(previousXref) >>\nstartxref\n\(xrefOffset)\n%%EOF\n"

    guard let replacementData = replacement.data(using: .isoLatin1) else {
        throw AppError("无法生成 PDF trailer。")
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: replacementData)
}

private func firstMatch(in text: String, pattern: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: range) else { return nil }
    let captureIndex = match.numberOfRanges > 1 ? 1 : 0
    guard let captureRange = Range(match.range(at: captureIndex), in: text) else { return nil }
    return String(text[captureRange])
}

func writeIndividualPDFs(document: PDFDocument, pageIndexes: [Int], sourceURL: URL, directory: URL) throws {
    let stem = safeName(sourceURL.deletingPathExtension().lastPathComponent)
    for pageIndex in pageIndexes {
        let outputURL = uniqueFileURL(in: directory, fileName: "\(stem)_p\(pageIndex + 1).pdf")
        try writePDF(document: document, pageIndexes: [pageIndex], to: outputURL)
    }
}

func writeGroupedPDFs(document: PDFDocument, groups: [[Int]], sourceURL: URL, directory: URL) throws {
    let stem = safeName(sourceURL.deletingPathExtension().lastPathComponent)
    for (index, group) in groups.enumerated() {
        let suffix = group.count == 1 ? "p\(group[0] + 1)" : "p\(group.first! + 1)-\(group.last! + 1)"
        let outputURL = uniqueFileURL(in: directory, fileName: "\(stem)_\(suffix)_part\(index + 1).pdf")
        try writePDF(document: document, pageIndexes: group, to: outputURL)
    }
}

func exportPagesAsImages(document: PDFDocument, pageIndexes: [Int], sourceURL: URL, dpi: Int, directory: URL) throws {
    let stem = safeName(sourceURL.deletingPathExtension().lastPathComponent)
    for pageIndex in pageIndexes {
        guard let page = document.page(at: pageIndex) else { continue }
        let image = render(page: page, dpi: dpi)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else {
            throw AppError("页面 \(pageIndex + 1) 渲染失败。")
        }
        let outputURL = uniqueFileURL(in: directory, fileName: "\(stem)_p\(pageIndex + 1)_\(dpi)dpi.png")
        try data.write(to: outputURL)
    }
}

func render(page: PDFPage, dpi: Int) -> NSImage {
    let bounds = page.bounds(for: .mediaBox)
    let scale = CGFloat(dpi) / 72.0
    let pixelSize = NSSize(width: bounds.width * scale, height: bounds.height * scale)
    let image = NSImage(size: pixelSize)
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    NSColor.white.setFill()
    context.fill(CGRect(origin: .zero, size: pixelSize))
    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()
    image.unlockFocus()
    return image
}

func copyPageToPasteboard(document: PDFDocument, pageIndex: Int, dpi: Int) -> Bool {
    guard let page = document.page(at: pageIndex) else { return false }
    let image = render(page: page, dpi: dpi)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return false
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.declareTypes([.png, .tiff], owner: nil)
    let wrotePNG = pasteboard.setData(pngData, forType: .png)
    let wroteTIFF = pasteboard.setData(tiffData, forType: .tiff)
    return wrotePNG || wroteTIFF
}

func choosePDF() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.pdf]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}

func choosePDFs() -> [URL] {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.pdf]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.urls : []
}

func chooseDirectory(defaultURL: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = defaultURL
    return panel.runModal() == .OK ? panel.url : nil
}

func chooseSavePDF(defaultName: String, defaultDirectory: URL? = nil) -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType.pdf]
    panel.nameFieldStringValue = defaultName
    panel.directoryURL = defaultDirectory
    return panel.runModal() == .OK ? panel.url : nil
}

func loadPDFURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()

    func append(_ url: URL?) {
        guard let url, url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
        lock.lock()
        if !urls.contains(url) {
            urls.append(url)
        }
        lock.unlock()
    }

    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                append(urlFromDroppedItem(item))
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                defer { group.leave() }
                append(urlFromDroppedItem(item))
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FigraDroppedPDFs", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                do {
                    try FileManager.default.createDirectory(at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: temporaryURL.path) {
                        try FileManager.default.removeItem(at: temporaryURL)
                    }
                    try FileManager.default.copyItem(at: url, to: temporaryURL)
                    append(temporaryURL)
                } catch {
                    append(url)
                }
            }
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

private func urlFromDroppedItem(_ item: Any?) -> URL? {
    if let url = item as? URL {
        return url
    }
    if let url = item as? NSURL {
        return url as URL
    }
    if let data = item as? Data {
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let value = String(data: data, encoding: .utf8) {
            return urlFromDroppedString(value)
        }
    }
    if let value = item as? String {
        return urlFromDroppedString(value)
    }
    return nil
}

private func urlFromDroppedString(_ value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") {
        return URL(fileURLWithPath: trimmed)
    }
    return URL(string: trimmed)
}

func copyImage(_ url: URL) {
    guard let image = NSImage(contentsOf: url) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
}

func exportFigureCSV(_ figures: [FigureResult]) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "figra_results.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    var rows = ["image_file,kind,width,height,output_path"]
    for figure in figures {
        let image = NSImage(contentsOf: figure.url)
        let width = Int(image?.representations.first?.pixelsWide ?? Int(image?.size.width ?? 0))
        let height = Int(image?.representations.first?.pixelsHigh ?? Int(image?.size.height ?? 0))
        let kind = figure.kind == .table ? "Table" : "Figure"
        rows.append([figure.name, kind, "\(width)", "\(height)", figure.url.path].map(csvField).joined(separator: ","))
    }
    try? (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

func csvField(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

func inferFigureKind(from name: String) -> FigureKind {
    let lowered = name.lowercased()
    if lowered.contains("table") || lowered.contains("tab") {
        return .table
    }
    return .figure
}

func safeName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return name.isEmpty ? "pdf" : name
}

func uniqueFileURL(in directory: URL, fileName: String) -> URL {
    let base = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: base.path) else { return base }
    let stem = base.deletingPathExtension().lastPathComponent
    let ext = base.pathExtension
    var index = 2
    while true {
        let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
        let candidate = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        index += 1
    }
}

func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
}

func formatFileSize(_ size: Int) -> String {
    if size >= 1_048_576 {
        return String(format: "%.1f MB", Double(size) / 1_048_576.0)
    }
    return String(format: "%.0f KB", Double(size) / 1024.0)
}

import AppKit
import PDFKit
import UniformTypeIdentifiers

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func makePageItems(document: PDFDocument) -> [PageItem] {
    (0..<document.pageCount).compactMap { index in
        guard let page = document.page(at: index) else { return nil }
        let thumbnail = page.thumbnail(of: NSSize(width: 220, height: 300), for: .mediaBox)
        return PageItem(index: index, thumbnail: thumbnail)
    }
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
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.writeObjects([image])
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
    for provider in providers {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            let pdfURL: URL?
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.pathExtension.lowercased() == "pdf" {
                pdfURL = url
            } else if let url = item as? URL, url.pathExtension.lowercased() == "pdf" {
                pdfURL = url
            } else {
                pdfURL = nil
            }
            if let pdfURL {
                lock.lock()
                urls.append(pdfURL)
                lock.unlock()
            }
        }
    }
    group.notify(queue: .main) { completion(urls) }
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

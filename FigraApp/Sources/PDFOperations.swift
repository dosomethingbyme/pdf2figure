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

func chooseBibFiles() -> [URL] {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [bibContentType()]
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

func chooseSaveBib(defaultName: String, defaultDirectory: URL? = nil) -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [bibContentType()]
    panel.nameFieldStringValue = defaultName
    panel.directoryURL = defaultDirectory
    return panel.runModal() == .OK ? panel.url : nil
}

func bibContentType() -> UTType {
    UTType(filenameExtension: "bib") ?? .plainText
}

func loadPDFURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    loadFileURLs(
        from: providers,
        allowedExtensions: ["pdf"],
        fileRepresentationType: .pdf,
        temporaryDirectoryName: "FigraDroppedPDFs",
        temporaryExtension: "pdf",
        completion: completion
    )
}

func loadFileURLs(
    from providers: [NSItemProvider],
    allowedExtensions: Set<String>,
    fileRepresentationType: UTType?,
    temporaryDirectoryName: String,
    temporaryExtension: String,
    completion: @escaping ([URL]) -> Void
) {
    var urls: [URL] = []
    let lock = NSLock()
    let group = DispatchGroup()

    func append(_ url: URL?) {
        guard let url, url.isFileURL, allowedExtensions.contains(url.pathExtension.lowercased()) else { return }
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
        } else if let fileRepresentationType, provider.hasItemConformingToTypeIdentifier(fileRepresentationType.identifier) {
            group.enter()
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: fileRepresentationType.identifier) { url, inPlace, _ in
                defer { group.leave() }
                guard let url else { return }

                if inPlace {
                    append(url)
                    return
                }

                if let temporaryURL = copyDroppedFileToTemporaryURL(url, directoryName: temporaryDirectoryName, fileExtension: temporaryExtension) {
                    append(temporaryURL)
                } else {
                    append(url)
                }
            }
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

private func copyDroppedPDFToTemporaryURL(_ url: URL) -> URL? {
    copyDroppedFileToTemporaryURL(url, directoryName: "FigraDroppedPDFs", fileExtension: "pdf")
}

private func copyDroppedFileToTemporaryURL(_ url: URL, directoryName: String, fileExtension pathExtension: String) -> URL? {
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(directoryName, isDirectory: true)
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(pathExtension)
    do {
        try FileManager.default.createDirectory(at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        try FileManager.default.copyItem(at: url, to: temporaryURL)
        return temporaryURL
    } catch {
        return nil
    }
}

@discardableResult
func writeProcessedBibFiles(_ urls: [URL], to outputURL: URL, options: BibProcessingOptions) throws -> BibProcessingSummary {
    let result = try buildBibPreview(from: urls, options: options)
    try result.outputText.write(to: outputURL, atomically: true, encoding: .utf8)
    return result.summary
}

func summarizeBibFiles(_ urls: [URL], options: BibProcessingOptions) throws -> BibProcessingSummary {
    try buildBibPreview(from: urls, options: options).summary
}

func previewBibFiles(_ urls: [URL], options: BibProcessingOptions) throws -> BibPreviewResult {
    try buildBibPreview(from: urls, options: options)
}

func countBibReferences(in url: URL) -> Int {
    guard let data = try? Data(contentsOf: url) else { return 0 }
    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return 0 }
    return countBibReferences(in: text)
}

func countBibReferences(in text: String) -> Int {
    parseBibBlocks(in: text).filter(\.isReference).count
}

private func buildBibPreview(from urls: [URL], options: BibProcessingOptions) throws -> BibPreviewResult {
    let chunks = try readBibChunks(from: urls)
    guard !chunks.isEmpty else {
        throw AppError("选中的 BibTeX 文件没有可合并内容。")
    }

    let sourceBlocks = chunks.flatMap { chunk in
        parseBibBlocks(in: chunk.text).enumerated().map { index, block in
            BibSourceBlock(url: chunk.url, sourceFileIndex: chunk.sourceFileIndex, entryIndex: index + 1, block: block)
        }
    }
    let blocks = sourceBlocks.map(\.block)
    guard blocks.contains(where: \.isReference) else {
        throw AppError("选中的 BibTeX 文件没有可合并参考文献。")
    }

    var seenKeys: [String: BibEntryPreview] = [:]
    var seenTitles: [String: BibEntryPreview] = [:]
    var seenDOIs: [String: BibEntryPreview] = [:]
    var seenArxivIDs: [String: BibEntryPreview] = [:]
    var duplicateBuckets: [String: (reason: BibDuplicateReason, candidates: [BibEntryPreview], autoRemoval: Bool)] = [:]
    var entries: [BibEntryPreview] = []
    var inputReferenceCount = 0
    var outputReferenceCount = 0
    var duplicateKeyMatchCount = 0
    var duplicateTitleMatchCount = 0
    var duplicateDOIMatchCount = 0
    var keyConflictCount = 0
    var suspiciousDuplicateCount = 0
    var parseWarningCount = 0
    var nonReferenceCount = 0

    for sourceBlock in sourceBlocks {
        let block = sourceBlock.block
        let cleaned = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { continue }
        let rendered = options.formatOutput ? formatBibBlock(block) : cleaned

        if !block.isReference {
            let decision: BibEntryDecision = block.type == nil ? .parseWarning : .keepNonReference
            if decision == .parseWarning { parseWarningCount += 1 } else { nonReferenceCount += 1 }
            let entry = makeBibEntryPreview(sourceBlock: sourceBlock, outputText: rendered, decision: decision)
            entries.append(entry)
            continue
        }

        inputReferenceCount += 1
        let normalizedKey = block.citationKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = block.normalizedTitle
        let normalizedDOI = normalizeBibDOI(bibFieldValue("doi", in: block))
        let normalizedArxivID = normalizeArxivID(from: block)
        let keyMatch = normalizedKey.flatMap { !$0.isEmpty ? seenKeys[$0] : nil }
        let titleMatch = normalizedTitle.flatMap { !$0.isEmpty ? seenTitles[$0] : nil }
        let doiMatch = normalizedDOI.flatMap { !$0.isEmpty ? seenDOIs[$0] : nil }
        let arxivMatch = normalizedArxivID.flatMap { !$0.isEmpty ? seenArxivIDs[$0] : nil }

        var matchedEntry: BibEntryPreview?
        var reason: BibDuplicateReason?
        var autoRemoval = false
        if doiMatch != nil {
            matchedEntry = doiMatch
            reason = .doi
            autoRemoval = true
            duplicateDOIMatchCount += 1
        } else if arxivMatch != nil {
            matchedEntry = arxivMatch
            reason = .arxiv
            autoRemoval = true
        } else if let keyMatch {
            matchedEntry = keyMatch
            if hasCitationKeyConflict(block: block, normalizedTitle: normalizedTitle, normalizedDOI: normalizedDOI, normalizedArxivID: normalizedArxivID, matchedEntry: keyMatch) {
                reason = .keyConflict
                keyConflictCount += 1
            } else {
                reason = titleMatch != nil ? .citationKeyAndTitle : .citationKey
                autoRemoval = true
                duplicateKeyMatchCount += 1
            }
        } else if titleMatch != nil {
            matchedEntry = titleMatch
            reason = .title
            autoRemoval = true
            duplicateTitleMatchCount += 1
        } else if let suspicious = suspiciousTitleMatch(for: normalizedTitle, in: seenTitles) {
            reason = .suspiciousTitle
            autoRemoval = false
            suspiciousDuplicateCount += 1
            let entry = makeBibEntryPreview(sourceBlock: sourceBlock, outputText: rendered, decision: .keep)
            let groupID = bibGroupID(reason: .suspiciousTitle, key: suspicious.key)
            entries.append(entry.withDuplicate(groupID: groupID, reason: .suspiciousTitle, keptEntryID: suspicious.entry.id, decision: .suspiciousDuplicate))
            appendBibDuplicateBucket(&duplicateBuckets, groupID: groupID, reason: .suspiciousTitle, candidates: [suspicious.entry, entry], autoRemoval: false)
            insertSeenBibEntry(entry, key: normalizedKey, title: normalizedTitle, doi: normalizedDOI, arxivID: normalizedArxivID, seenKeys: &seenKeys, seenTitles: &seenTitles, seenDOIs: &seenDOIs, seenArxivIDs: &seenArxivIDs)
            continue
        }

        let groupID = reason.map {
            bibGroupID(reason: $0, key: duplicateMatchKey(reason: $0, entry: sourceBlock, fallback: normalizedDOI ?? normalizedArxivID ?? normalizedTitle ?? normalizedKey ?? sourceBlock.id))
        }
        let entry = makeBibEntryPreview(
            sourceBlock: sourceBlock,
            outputText: rendered,
            decision: reason == .keyConflict ? .keyConflict : .keep,
            duplicateGroupID: groupID,
            duplicateReason: reason,
            keptEntryID: matchedEntry?.id
        )
        entries.append(entry)
        if let groupID, let reason, let matchedEntry {
            appendBibDuplicateBucket(&duplicateBuckets, groupID: groupID, reason: reason, candidates: [matchedEntry, entry], autoRemoval: autoRemoval)
        }
        insertSeenBibEntry(entry, key: normalizedKey, title: normalizedTitle, doi: normalizedDOI, arxivID: normalizedArxivID, seenKeys: &seenKeys, seenTitles: &seenTitles, seenDOIs: &seenDOIs, seenArxivIDs: &seenArxivIDs)
    }

    let resolved = applyBibOverrides(entries: entries, buckets: duplicateBuckets, options: options)
    entries = resolved.entries
    let outputEntries = resolved.outputEntries
    outputReferenceCount = outputEntries.filter(\.isReference).count

    let duplicateGroups = resolved.groups
        .sorted {
            if $0.keptEntry.sourceFileIndex == $1.keptEntry.sourceFileIndex {
                return $0.keptEntry.entryIndex < $1.keptEntry.entryIndex
            }
            return $0.keptEntry.sourceFileIndex < $1.keptEntry.sourceFileIndex
        }
    let summary = BibProcessingSummary(
        inputReferenceCount: inputReferenceCount,
        outputReferenceCount: outputReferenceCount,
        duplicateReferenceCount: resolved.removedEntries.count,
        duplicateKeyMatchCount: duplicateKeyMatchCount,
        duplicateTitleMatchCount: duplicateTitleMatchCount,
        duplicateDOIMatchCount: duplicateDOIMatchCount,
        keyConflictCount: keyConflictCount,
        suspiciousDuplicateCount: suspiciousDuplicateCount,
        parseWarningCount: parseWarningCount,
        nonReferenceCount: nonReferenceCount,
        manualOverrideCount: options.overrides.count
    )
    let outputText = outputEntries.map(\.outputText).joined(separator: "\n\n") + "\n"
    return BibPreviewResult(
        outputText: outputText,
        entries: entries,
        duplicateGroups: duplicateGroups,
        removedEntries: resolved.removedEntries,
        warningEntries: entries.filter { $0.decision == .keyConflict || $0.decision == .suspiciousDuplicate || $0.decision == .parseWarning },
        summary: summary
    )
}

private struct BibSourceChunk {
    let url: URL
    let sourceFileIndex: Int
    let text: String
}

private struct BibSourceBlock {
    let url: URL
    let sourceFileIndex: Int
    let entryIndex: Int
    let block: BibBlock

    var id: String { "\(sourceFileIndex + 1)-\(entryIndex)" }
}

private func readBibChunks(from urls: [URL]) throws -> [BibSourceChunk] {
    var chunks: [BibSourceChunk] = []
    for (index, url) in urls.enumerated() {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AppError("无法读取 BibTeX 文本：\(url.lastPathComponent)")
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            chunks.append(BibSourceChunk(url: url, sourceFileIndex: index, text: cleaned))
        }
    }
    return chunks
}

private func makeBibEntryPreview(
    sourceBlock: BibSourceBlock,
    outputText: String,
    decision: BibEntryDecision,
    duplicateGroupID: String? = nil,
    duplicateReason: BibDuplicateReason? = nil,
    keptEntryID: String? = nil
) -> BibEntryPreview {
    let block = sourceBlock.block
    return BibEntryPreview(
        id: sourceBlock.id,
        sourceFileName: sourceBlock.url.lastPathComponent,
        sourceURL: sourceBlock.url,
        sourceFileIndex: sourceBlock.sourceFileIndex,
        entryIndex: sourceBlock.entryIndex,
        type: block.type,
        citationKey: block.citationKey,
        title: bibFieldValue("title", in: block),
        author: bibFieldValue("author", in: block),
        year: bibFieldValue("year", in: block),
        doi: bibFieldValue("doi", in: block),
        arxivID: normalizeArxivID(from: block),
        journal: bibFieldValue("journal", in: block) ?? bibFieldValue("booktitle", in: block),
        rawText: block.text.trimmingCharacters(in: .whitespacesAndNewlines),
        outputText: outputText,
        decision: decision,
        duplicateGroupID: duplicateGroupID,
        duplicateReason: duplicateReason,
        keptEntryID: keptEntryID
    )
}

private extension BibEntryPreview {
    func withDuplicate(groupID: String?, reason: BibDuplicateReason?, keptEntryID: String?, decision: BibEntryDecision? = nil) -> BibEntryPreview {
        BibEntryPreview(
            id: id,
            sourceFileName: sourceFileName,
            sourceURL: sourceURL,
            sourceFileIndex: sourceFileIndex,
            entryIndex: entryIndex,
            type: type,
            citationKey: citationKey,
            title: title,
            author: author,
            year: year,
            doi: doi,
            arxivID: arxivID,
            journal: journal,
            rawText: rawText,
            outputText: outputText,
            decision: decision ?? self.decision,
            duplicateGroupID: groupID,
            duplicateReason: reason,
            keptEntryID: keptEntryID
        )
    }

    func withDecision(_ decision: BibEntryDecision, keptEntryID: String? = nil) -> BibEntryPreview {
        withDuplicate(groupID: duplicateGroupID, reason: duplicateReason, keptEntryID: keptEntryID ?? self.keptEntryID, decision: decision)
    }
}

private func normalizeBibDOI(_ value: String?) -> String? {
    guard var value else { return nil }
    value = normalizeBibFieldValue(value)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let prefixes = ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:"]
    for prefix in prefixes where value.hasPrefix(prefix) {
        value.removeFirst(prefix.count)
        break
    }
    value = value.trimmingCharacters(in: CharacterSet(charactersIn: " .,/"))
    return value.hasPrefix("10.") && value.count >= 6 ? value : nil
}

private func normalizeArxivID(from block: BibBlock) -> String? {
    let candidates = [
        bibFieldValue("eprint", in: block),
        bibFieldValue("arxivid", in: block),
        bibFieldValue("url", in: block),
        bibFieldValue("doi", in: block)
    ].compactMap { $0 }
    for candidate in candidates {
        if let id = extractArxivID(from: candidate) {
            return id
        }
    }
    return nil
}

private func extractArxivID(from value: String) -> String? {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let patterns = [
        #"arxiv[:/ ]+([a-z\-]+\/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)"#,
        #"abs/([a-z\-]+\/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)"#,
        #"^([a-z\-]+\/\d{7}|\d{4}\.\d{4,5}(?:v\d+)?)$"#
    ]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, range: range), match.numberOfRanges > 1, let idRange = Range(match.range(at: 1), in: lowered) else { continue }
        return String(lowered[idRange]).replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }
    return nil
}

private func titlesCompatible(_ normalizedTitle: String?, _ matchedTitle: String?) -> Bool {
    guard let normalizedTitle, let matchedNormalized = normalizeBibTitle(matchedTitle) else { return false }
    return normalizedTitle == matchedNormalized
}

private func hasCitationKeyConflict(
    block: BibBlock,
    normalizedTitle: String?,
    normalizedDOI: String?,
    normalizedArxivID: String?,
    matchedEntry: BibEntryPreview
) -> Bool {
    if !titlesCompatible(normalizedTitle, matchedEntry.title) {
        return true
    }
    if let normalizedDOI, let matchedDOI = normalizeBibDOI(matchedEntry.doi), normalizedDOI != matchedDOI {
        return true
    }
    if let normalizedArxivID, let matchedArxivID = matchedEntry.arxivID, normalizedArxivID != matchedArxivID {
        return true
    }
    if let year = bibFieldValue("year", in: block)?.trimmingCharacters(in: .whitespacesAndNewlines),
       let matchedYear = matchedEntry.year?.trimmingCharacters(in: .whitespacesAndNewlines),
       !year.isEmpty,
       !matchedYear.isEmpty,
       year != matchedYear {
        return true
    }
    return false
}

private func suspiciousTitleMatch(for normalizedTitle: String?, in seenTitles: [String: BibEntryPreview]) -> (key: String, entry: BibEntryPreview)? {
    guard let normalizedTitle, normalizedTitle.count >= 18 else { return nil }
    let tokens = Set(normalizedTitle.split(separator: " ").map(String.init).filter { $0.count > 2 })
    guard tokens.count >= 4 else { return nil }
    var best: (key: String, entry: BibEntryPreview, score: Double)?
    for (key, entry) in seenTitles {
        let otherTokens = Set(key.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard otherTokens.count >= 4 else { continue }
        let intersection = tokens.intersection(otherTokens).count
        let union = tokens.union(otherTokens).count
        let score = union == 0 ? 0 : Double(intersection) / Double(union)
        if score >= 0.82, score > (best?.score ?? 0) {
            best = (key, entry, score)
        }
    }
    return best.map { ($0.key, $0.entry) }
}

private func bibGroupID(reason: BibDuplicateReason, key: String) -> String {
    "\(reason.rawValue):\(key)"
}

private func duplicateMatchKey(reason: BibDuplicateReason, entry: BibSourceBlock, fallback: String) -> String {
    switch reason {
    case .doi:
        return normalizeBibDOI(bibFieldValue("doi", in: entry.block)) ?? fallback
    case .arxiv:
        return normalizeArxivID(from: entry.block) ?? fallback
    case .citationKey, .citationKeyAndTitle, .keyConflict:
        return entry.block.citationKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? fallback
    case .title, .suspiciousTitle:
        return entry.block.normalizedTitle ?? fallback
    }
}

private func appendBibDuplicateBucket(
    _ buckets: inout [String: (reason: BibDuplicateReason, candidates: [BibEntryPreview], autoRemoval: Bool)],
    groupID: String,
    reason: BibDuplicateReason,
    candidates: [BibEntryPreview],
    autoRemoval: Bool
) {
    var bucket = buckets[groupID] ?? (reason: reason, candidates: [], autoRemoval: autoRemoval)
    bucket.reason = mergeDuplicateReasons(bucket.reason, reason)
    bucket.autoRemoval = bucket.autoRemoval || autoRemoval
    for candidate in candidates where !bucket.candidates.contains(where: { $0.id == candidate.id }) {
        bucket.candidates.append(candidate)
    }
    buckets[groupID] = bucket
}

private func insertSeenBibEntry(
    _ entry: BibEntryPreview,
    key: String?,
    title: String?,
    doi: String?,
    arxivID: String?,
    seenKeys: inout [String: BibEntryPreview],
    seenTitles: inout [String: BibEntryPreview],
    seenDOIs: inout [String: BibEntryPreview],
    seenArxivIDs: inout [String: BibEntryPreview]
) {
    if let key, !key.isEmpty, seenKeys[key] == nil {
        seenKeys[key] = entry
    }
    if let title, !title.isEmpty, seenTitles[title] == nil {
        seenTitles[title] = entry
    }
    if let doi, !doi.isEmpty, seenDOIs[doi] == nil {
        seenDOIs[doi] = entry
    }
    if let arxivID, !arxivID.isEmpty, seenArxivIDs[arxivID] == nil {
        seenArxivIDs[arxivID] = entry
    }
}

private func applyBibOverrides(
    entries: [BibEntryPreview],
    buckets: [String: (reason: BibDuplicateReason, candidates: [BibEntryPreview], autoRemoval: Bool)],
    options: BibProcessingOptions
) -> (entries: [BibEntryPreview], outputEntries: [BibEntryPreview], removedEntries: [BibEntryPreview], groups: [BibDuplicateGroup]) {
    var updatedByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.withDuplicate(groupID: nil, reason: nil, keptEntryID: nil, decision: $0.decision == .parseWarning || $0.decision == .keepNonReference ? $0.decision : .keep)) })
    var removedIDs = Set<String>()
    var groups: [BibDuplicateGroup] = []

    for (groupID, bucket) in buckets {
        let candidates = bucket.candidates.sorted {
            if $0.sourceFileIndex == $1.sourceFileIndex {
                return $0.entryIndex < $1.entryIndex
            }
            return $0.sourceFileIndex < $1.sourceFileIndex
        }
        guard let defaultKept = candidates.first else { continue }
        let override = options.overrides[groupID]
        let keptEntry: BibEntryPreview
        switch override?.resolution {
        case .keepEntry(let id):
            keptEntry = candidates.first { $0.id == id } ?? defaultKept
        case .keepAll, .automatic, .none:
            keptEntry = defaultKept
        }

        let shouldRemove = options.removeDuplicates && bucket.autoRemoval && override?.resolution != .keepAll
        var removedEntries: [BibEntryPreview] = []

        for candidate in candidates {
            var decision: BibEntryDecision = .keep
            if bucket.reason == .keyConflict {
                decision = .keyConflict
            } else if bucket.reason == .suspiciousTitle {
                decision = .suspiciousDuplicate
            } else if shouldRemove && candidate.id != keptEntry.id {
                decision = .removeDuplicate
                removedIDs.insert(candidate.id)
            } else {
                removedIDs.remove(candidate.id)
            }

            let updated = candidate.withDuplicate(groupID: groupID, reason: bucket.reason, keptEntryID: keptEntry.id, decision: decision)
            updatedByID[candidate.id] = updated
            if decision == .removeDuplicate {
                removedEntries.append(updated)
            }
        }

        let resolvedKept = updatedByID[keptEntry.id] ?? keptEntry
        groups.append(BibDuplicateGroup(
            id: groupID,
            reason: bucket.reason,
            keptEntry: resolvedKept,
            removedEntries: removedEntries,
            candidateEntries: candidates.compactMap { updatedByID[$0.id] },
            isAutoRemoval: bucket.autoRemoval,
            isOverridden: override != nil
        ))
    }

    let updatedEntries = entries.compactMap { updatedByID[$0.id] }
    let outputEntries = updatedEntries.filter { !removedIDs.contains($0.id) }
    let removedEntries = updatedEntries.filter { removedIDs.contains($0.id) }
    return (updatedEntries, outputEntries, removedEntries, groups)
}

private func bibFieldValue(_ name: String, in block: BibBlock) -> String? {
    block.fields.first { $0.name.lowercased() == name }?.normalizedValue
}

private func mergeDuplicateReasons(_ lhs: BibDuplicateReason, _ rhs: BibDuplicateReason) -> BibDuplicateReason {
    if lhs == rhs { return lhs }
    if lhs == .keyConflict || rhs == .keyConflict { return .keyConflict }
    if lhs == .suspiciousTitle || rhs == .suspiciousTitle { return .suspiciousTitle }
    if lhs == .doi || rhs == .doi { return .doi }
    if lhs == .arxiv || rhs == .arxiv { return .arxiv }
    return .citationKeyAndTitle
}

private struct BibBlock {
    let text: String
    let type: String?
    let citationKey: String?
    let fields: [BibField]
    let normalizedTitle: String?

    var isReference: Bool {
        guard let type else { return false }
        return !["comment", "preamble", "string"].contains(type.lowercased())
    }
}

private struct BibField {
    let name: String
    let rawValue: String
    let normalizedValue: String
}

private func parseBibBlocks(in text: String) -> [BibBlock] {
    var blocks: [BibBlock] = []
    var cursor = text.startIndex

    while cursor < text.endIndex {
        guard let atIndex = text[cursor...].firstIndex(of: "@") else {
            appendBibTextBlock(String(text[cursor...]), to: &blocks)
            break
        }

        if cursor < atIndex {
            appendBibTextBlock(String(text[cursor..<atIndex]), to: &blocks)
        }

        guard let entry = parseBibEntry(in: text, at: atIndex) else {
            appendBibTextBlock(String(text[atIndex...atIndex]), to: &blocks)
            cursor = text.index(after: atIndex)
            continue
        }

        blocks.append(entry.block)
        cursor = entry.endIndex
    }

    return blocks
}

private func appendBibTextBlock(_ text: String, to blocks: inout [BibBlock]) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    blocks.append(BibBlock(text: text, type: nil, citationKey: nil, fields: [], normalizedTitle: nil))
}

private func parseBibEntry(in text: String, at atIndex: String.Index) -> (block: BibBlock, endIndex: String.Index)? {
    var cursor = text.index(after: atIndex)
    skipWhitespace(in: text, cursor: &cursor)
    let typeStart = cursor
    while cursor < text.endIndex, isBibIdentifierCharacter(text[cursor]) {
        cursor = text.index(after: cursor)
    }
    guard typeStart < cursor else { return nil }
    let type = String(text[typeStart..<cursor])
    skipWhitespace(in: text, cursor: &cursor)
    guard cursor < text.endIndex, text[cursor] == "{" || text[cursor] == "(" else { return nil }

    let openIndex = cursor
    let openCharacter = text[cursor]
    let closeCharacter: Character = openCharacter == "{" ? "}" : ")"
    var depth = 0

    while cursor < text.endIndex {
        let character = text[cursor]
        if character == openCharacter {
            depth += 1
        } else if character == closeCharacter {
            depth -= 1
            if depth == 0 {
                let endIndex = text.index(after: cursor)
                let entryText = String(text[atIndex..<endIndex])
                let lowercasedType = type.lowercased()
                let citationKey = ["comment", "preamble", "string"].contains(lowercasedType) ? nil : extractBibCitationKey(from: text, openIndex: openIndex, closeIndex: cursor)
                let fields = citationKey == nil ? [] : parseBibFields(in: text, openIndex: openIndex, closeIndex: cursor)
                let title = fields.first { $0.name.lowercased() == "title" }?.normalizedValue
                let block = BibBlock(text: entryText, type: type, citationKey: citationKey, fields: fields, normalizedTitle: normalizeBibTitle(title))
                return (block, endIndex)
            }
        }
        cursor = text.index(after: cursor)
    }

    let entryText = String(text[atIndex..<text.endIndex])
    let block = BibBlock(text: entryText, type: type, citationKey: nil, fields: [], normalizedTitle: nil)
    return (block, text.endIndex)
}

private func extractBibCitationKey(from text: String, openIndex: String.Index, closeIndex: String.Index) -> String? {
    var cursor = text.index(after: openIndex)
    skipWhitespace(in: text, cursor: &cursor)
    let keyStart = cursor
    while cursor < closeIndex, text[cursor] != "," {
        cursor = text.index(after: cursor)
    }
    guard cursor < closeIndex else { return nil }
    return String(text[keyStart..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func parseBibFields(in text: String, openIndex: String.Index, closeIndex: String.Index) -> [BibField] {
    var fields: [BibField] = []
    var cursor = text.index(after: openIndex)
    while cursor < closeIndex, text[cursor] != "," {
        cursor = text.index(after: cursor)
    }
    guard cursor < closeIndex else { return [] }
    cursor = text.index(after: cursor)

    while cursor < closeIndex {
        skipBibFieldSeparators(in: text, cursor: &cursor, endIndex: closeIndex)
        guard cursor < closeIndex else { break }

        let nameStart = cursor
        while cursor < closeIndex, isBibIdentifierCharacter(text[cursor]) {
            cursor = text.index(after: cursor)
        }
        guard nameStart < cursor else {
            cursor = text.index(after: cursor)
            continue
        }

        let name = String(text[nameStart..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
        skipWhitespace(in: text, cursor: &cursor)
        guard cursor < closeIndex, text[cursor] == "=" else { continue }
        cursor = text.index(after: cursor)
        skipWhitespace(in: text, cursor: &cursor)

        let rawValue = parseRawBibFieldValue(in: text, cursor: &cursor, endIndex: closeIndex)
        fields.append(BibField(name: name, rawValue: rawValue, normalizedValue: normalizeBibFieldValue(rawValue)))
    }

    return fields
}

private func parseRawBibFieldValue(in text: String, cursor: inout String.Index, endIndex: String.Index) -> String {
    let valueStart = cursor
    var braceDepth = 0
    var isQuoted = false
    var isEscaped = false

    while cursor < endIndex {
        let character = text[cursor]

        if isQuoted {
            if character == "\"" && !isEscaped {
                isQuoted = false
            }
            isEscaped = character == "\\" && !isEscaped
            if character != "\\" {
                isEscaped = false
            }
            cursor = text.index(after: cursor)
            continue
        }

        if character == "\"" {
            isQuoted = true
        } else if character == "{" {
            braceDepth += 1
        } else if character == "}" {
            braceDepth = max(0, braceDepth - 1)
        } else if character == ",", braceDepth == 0 {
            let rawValue = String(text[valueStart..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = text.index(after: cursor)
            return rawValue
        }

        cursor = text.index(after: cursor)
    }

    return String(text[valueStart..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func formatBibBlock(_ block: BibBlock) -> String {
    let cleaned = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard block.isReference, let type = block.type, let citationKey = block.citationKey, !block.fields.isEmpty else {
        return cleaned
    }

    let lines = block.fields.enumerated().map { index, field in
        let suffix = index == block.fields.count - 1 ? "" : ","
        return "  \(field.name.lowercased()) = \(field.rawValue)\(suffix)"
    }
    return "@\(type.lowercased()){\(citationKey.trimmingCharacters(in: .whitespacesAndNewlines)),\n\(lines.joined(separator: "\n"))\n}"
}

private func normalizeBibFieldValue(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while let stripped = stripOuterBibDelimiters(from: normalized) {
        normalized = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return normalized
}

private func stripOuterBibDelimiters(from value: String) -> String? {
    guard value.count >= 2, let first = value.first, let last = value.last else { return nil }
    if first == "{", last == "}", hasBalancedOuterDelimiters(value, open: "{", close: "}") {
        return String(value.dropFirst().dropLast())
    }
    if first == "\"", last == "\"" {
        return String(value.dropFirst().dropLast())
    }
    return nil
}

private func hasBalancedOuterDelimiters(_ value: String, open: Character, close: Character) -> Bool {
    var depth = 0
    var cursor = value.startIndex
    while cursor < value.endIndex {
        let character = value[cursor]
        if character == open {
            depth += 1
        } else if character == close {
            depth -= 1
            if depth == 0, value.index(after: cursor) < value.endIndex {
                return false
            }
        }
        cursor = value.index(after: cursor)
    }
    return depth == 0
}

private func normalizeBibTitle(_ title: String?) -> String? {
    guard let title else { return nil }
    let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    var scalars: [UnicodeScalar] = []
    var previousWasSpace = true

    for scalar in folded.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(scalar)
            previousWasSpace = false
        } else if !previousWasSpace {
            scalars.append(" ")
            previousWasSpace = true
        }
    }

    let normalized = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.count >= 6 ? normalized : nil
}

private func skipWhitespace(in text: String, cursor: inout String.Index) {
    while cursor < text.endIndex, text[cursor].isWhitespace {
        cursor = text.index(after: cursor)
    }
}

private func skipBibFieldSeparators(in text: String, cursor: inout String.Index, endIndex: String.Index) {
    while cursor < endIndex, text[cursor].isWhitespace || text[cursor] == "," {
        cursor = text.index(after: cursor)
    }
}

private func isBibIdentifierCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_" || character == "-"
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
